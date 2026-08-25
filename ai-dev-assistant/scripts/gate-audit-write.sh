#!/usr/bin/env bash
# gate-audit-write.sh — atomic gate audit file writer.
#
# Usage: gate-audit-write.sh <task_folder> <gate_type> <json_payload>
#
#   <task_folder>: absolute path to task folder
#   <gate_type>: one of pre-analysis | coverage-mapping | skill-review |
#                plugin-validate | phase-command-bypass | dev-guides-load |
#                playbook-load | review | e2e | visual_regression | visual_parity |
#                recipe-load | agentic-recipe | internal-prior-art
#   <json_payload>: EITHER the gate_specific object on its own (preferred — this
#                   script builds the envelope around it), OR a complete audit JSON
#                   object conforming to
#                   references/gate-audit-schema.md (v1.0 for the original 7
#                   gate types; v1.1 adds `review`; v1.2 — v4.11.0 — adds `e2e`
#                   + `visual_regression`; v1.3 — v4.14.0 — adds `visual_parity`;
#                   v1.4 — v5.11.0 — adds `recipe-load`;
#                   v1.5 — v5.12.0 — adds `agentic-recipe`)
#
# Behavior:
# - Accepts a bare gate_specific object and wraps it in the envelope, deriving
#   schema_version from gate_type and hoisting user_choice / bypass_reason
# - Stamps fired_at from this script's clock in both shapes; a caller-supplied
#   fired_at is discarded (see the normalize block for why)
# - Validates the JSON parses + has schema_version starting with "1." (1.0–1.6 accepted)
# - Validates gate_type is one of the 14 allowed values
# - Validates required top-level fields (gate_type, task_folder, gate_specific)
# - Writes to <task_folder>/_<gate_type>.json (overwrite-on-fire)
# - Atomic via temp + rename
#
# Exit codes:
#   0 — written successfully
#   1 — bash-level write failure (permissions, disk, missing folder)
#   2 — invalid input (bad JSON, schema mismatch, missing fields, bad gate_type)

set -uo pipefail

TASK_FOLDER="${1:?task folder required}"
GATE_TYPE="${2:?gate type required}"
PAYLOAD="${3:?JSON payload required}"

# Validate gate_type
case "$GATE_TYPE" in
  pre-analysis|coverage-mapping|skill-review|plugin-validate|phase-command-bypass|dev-guides-load|playbook-load|review|e2e|visual_regression|visual_parity|recipe-load|agentic-recipe|mechanism-challenge|spec|internal-prior-art)
    ;;
  *)
    echo "gate-audit-write: invalid gate_type: $GATE_TYPE" >&2
    echo "  must be one of: pre-analysis, coverage-mapping, skill-review, plugin-validate, phase-command-bypass, dev-guides-load, playbook-load, review, e2e, visual_regression, visual_parity, recipe-load, agentic-recipe, mechanism-challenge, spec, internal-prior-art" >&2
    exit 2
    ;;
esac

# Validate JSON parses
if ! echo "$PAYLOAD" | jq empty >/dev/null 2>&1; then
  echo "gate-audit-write: invalid JSON payload" >&2
  exit 2
fi

# Normalize the payload into a complete envelope.
#
# Two accepted shapes:
#   full envelope  — has a top-level `gate_type`; used as-is (v4.0.0 contract)
#   bare payload   — no top-level `gate_type`; treated as `gate_specific` and wrapped here
#
# The bare shape exists because it is what a caller reaches for naturally, and because
# an envelope hand-authored per call is an envelope that drifts: every audit written
# before v5.30.0 carried a model-authored `fired_at`, and every one of them said
# midnight. The clock lives here now. `fired_at` is stamped by this script in BOTH
# shapes and a caller-supplied value is discarded — a caller that cannot read a clock
# cannot stamp a time, and a wrong time is worse than no time because it reads as
# evidence. `user_choice` and `bypass_reason` are envelope-level per
# references/gate-audit-schema.md section 4; when a bare payload carries them they are
# hoisted rather than left buried where no consumer looks for them.
if ! echo "$PAYLOAD" | jq -e 'type == "object"' >/dev/null 2>&1; then
  echo "gate-audit-write: payload must be a JSON object" >&2
  exit 2
fi

# schema_version each gate type was introduced at (schema section 3).
case "$GATE_TYPE" in
  review) DEFAULT_SV="1.2" ;;
  e2e|visual_regression) DEFAULT_SV="1.2" ;;
  visual_parity) DEFAULT_SV="1.3" ;;
  recipe-load) DEFAULT_SV="1.4" ;;
  agentic-recipe) DEFAULT_SV="1.5" ;;
  internal-prior-art) DEFAULT_SV="1.6" ;;
  *) DEFAULT_SV="1.0" ;;
esac

FIRED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

if echo "$PAYLOAD" | jq -e 'has("gate_type")' >/dev/null 2>&1; then
  PAYLOAD=$(echo "$PAYLOAD" | jq --arg sv "$DEFAULT_SV" --arg fa "$FIRED_AT" \
    '.schema_version = (.schema_version // $sv) | .fired_at = $fa')
else
  PAYLOAD=$(echo "$PAYLOAD" | jq \
    --arg sv "$DEFAULT_SV" --arg gt "$GATE_TYPE" \
    --arg fa "$FIRED_AT" --arg tf "$TASK_FOLDER" \
    '{schema_version: $sv, gate_type: $gt, fired_at: $fa, task_folder: $tf,
      user_choice: (.user_choice // null), bypass_reason: (.bypass_reason // null),
      gate_specific: (del(.user_choice) | del(.bypass_reason))}')
fi

# Validate schema_version (accept any 1.x — backward-compat for v1.1 review gate,
# v1.2 e2e / visual_regression gates, v1.3 visual_parity gate, v1.4 recipe-load gate,
# v1.5 agentic-recipe gate, v1.6 internal-prior-art gate)
SV=$(echo "$PAYLOAD" | jq -r '.schema_version // empty')
case "$SV" in
  1.0|1.1|1.2|1.3|1.4|1.5|1.6) ;;
  *)
    echo "gate-audit-write: schema_version must be one of 1.0 1.1 1.2 1.3 1.4 1.5 1.6 (got \"$SV\")" >&2
    exit 2
    ;;
esac

# Validate gate_type matches argument
PAYLOAD_GT=$(echo "$PAYLOAD" | jq -r '.gate_type // empty')
if [[ "$PAYLOAD_GT" != "$GATE_TYPE" ]]; then
  echo "gate-audit-write: payload gate_type ($PAYLOAD_GT) does not match argument ($GATE_TYPE)" >&2
  exit 2
fi

# Validate required fields
for field in fired_at task_folder gate_specific; do
  if ! echo "$PAYLOAD" | jq -e "has(\"$field\")" >/dev/null 2>&1; then
    echo "gate-audit-write: missing required field: $field" >&2
    exit 2
  fi
done

# Validate task folder exists
if [[ ! -d "$TASK_FOLDER" ]]; then
  echo "gate-audit-write: task folder does not exist: $TASK_FOLDER" >&2
  exit 1
fi

OUT_FILE="$TASK_FOLDER/_${GATE_TYPE}.json"
TMP_FILE="$OUT_FILE.tmp.$$"

# Atomic write: temp + rename
if ! echo "$PAYLOAD" | jq . > "$TMP_FILE" 2>/dev/null; then
  echo "gate-audit-write: failed to write temp file" >&2
  rm -f "$TMP_FILE"
  exit 1
fi

if ! mv "$TMP_FILE" "$OUT_FILE"; then
  echo "gate-audit-write: failed to rename temp to $OUT_FILE" >&2
  rm -f "$TMP_FILE"
  exit 1
fi

echo "gate-audit-write: wrote $OUT_FILE"
exit 0
