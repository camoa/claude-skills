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
#                   v1.5 — v5.12.0 — adds `agentic-recipe`;
#                   v1.7 — v5.31.0 — adds `preconditions`)
#
# Behavior:
# - Accepts a bare gate_specific object and wraps it in the envelope, deriving
#   schema_version from gate_type and hoisting user_choice / bypass_reason
# - Stamps fired_at from this script's clock in both shapes; a caller-supplied
#   fired_at is discarded (see the normalize block for why)
# - Validates the JSON parses + has schema_version starting with "1." (1.0–1.7 accepted)
# - Validates gate_type is one of the 17 allowed values
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
  pre-analysis|coverage-mapping|skill-review|plugin-validate|phase-command-bypass|dev-guides-load|playbook-load|review|e2e|visual_regression|visual_parity|recipe-load|agentic-recipe|mechanism-challenge|spec|internal-prior-art|preconditions)
    ;;
  *)
    echo "gate-audit-write: invalid gate_type: $GATE_TYPE" >&2
    echo "  must be one of: pre-analysis, coverage-mapping, skill-review, plugin-validate, phase-command-bypass, dev-guides-load, playbook-load, review, e2e, visual_regression, visual_parity, recipe-load, agentic-recipe, mechanism-challenge, spec, internal-prior-art, preconditions" >&2
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
  preconditions)      DEFAULT_SV="1.7" ;;
  *) DEFAULT_SV="1.0" ;;
esac

FIRED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

if echo "$PAYLOAD" | jq -e 'has("gate_type")' >/dev/null 2>&1; then
  # Hoist here too. A full-envelope caller that tucked the answer inside gate_specific
  # has put it where section 4 does not look for it, and observed runs do exactly that:
  # `user_choice: "continue"` buried one level down, invisible to every envelope reader.
  # Only lift when the envelope slot is empty, so a caller that filled it in properly wins.
  PAYLOAD=$(echo "$PAYLOAD" | jq --arg sv "$DEFAULT_SV" --arg fa "$FIRED_AT" '
    .schema_version = (.schema_version // $sv)
    | .fired_at = $fa
    | if (.user_choice == null) and (.gate_specific.user_choice? != null)
      then .user_choice = .gate_specific.user_choice
         | .gate_specific |= del(.user_choice) else . end
    | if (.bypass_reason == null) and (.gate_specific.bypass_reason? != null)
      then .bypass_reason = .gate_specific.bypass_reason
         | .gate_specific |= del(.bypass_reason) else . end')
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
# v1.5 agentic-recipe gate, v1.6 internal-prior-art gate, v1.7 preconditions gate)
SV=$(echo "$PAYLOAD" | jq -r '.schema_version // empty')
case "$SV" in
  1.0|1.1|1.2|1.3|1.4|1.5|1.6|1.7) ;;
  *)
    echo "gate-audit-write: schema_version must be one of 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 (got \"$SV\")" >&2
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

# Warn on a gate_specific that is missing the keys its section of the schema names.
#
# The writer deliberately does not fail here. It cannot: the schema says outright that this
# script validates the envelope and not the payload, so a caller has never had to satisfy a
# payload contract and failing now would break runs mid-flight. But silence has a measured
# cost. On one observed research run, three separate records drifted — `user_choice` written
# one level below where consumers read it, a create-on-miss mirror missing half its documented
# keys, and a `recipe-load` whose `frameworks[]` was empty while its prose `notes` described
# the resolution in full. That last one is the shape of the problem: the record exists to make
# resolution machine-auditable, and the machine-readable half was the half left out. A
# consumer counting resolved frameworks reads zero.
#
# Keys listed here are ones the gate's own section states, not everything it may carry.
case "$GATE_TYPE" in
  pre-analysis)       REQUIRED_KEYS="decision confidence code_read" ;;
  recipe-load)        REQUIRED_KEYS="phase frameworks resolved_count" ;;
  dev-guides-load)    REQUIRED_KEYS="phase methodology_floor guides_actually_loaded" ;;
  playbook-load)      REQUIRED_KEYS="phase playbook_sets_loaded playbook_sets_source" ;;
  agentic-recipe)     REQUIRED_KEYS="recipes recipe_lookup_status" ;;
  internal-prior-art) REQUIRED_KEYS="sources" ;;
  # `verdict` and `declared` both required: a payload carrying only the summary counts cannot
  # distinguish a recipe that declared no preconditions from one whose preconditions all passed,
  # and those are the two facts this record exists to keep apart.
  preconditions)      REQUIRED_KEYS="phase declared verdict preconditions" ;;
  coverage-mapping)   REQUIRED_KEYS="verdict" ;;
  *)                  REQUIRED_KEYS="" ;;
esac

if [[ -n "$REQUIRED_KEYS" ]]; then
  MISSING=""
  for k in $REQUIRED_KEYS; do
    if ! echo "$PAYLOAD" | jq -e --arg k "$k" '.gate_specific | has($k)' >/dev/null 2>&1; then
      MISSING="$MISSING $k"
    fi
  done
  if [[ -n "$MISSING" ]]; then
    echo "gate-audit-write: WARNING — $GATE_TYPE gate_specific is missing documented key(s):$MISSING" >&2
    echo "  see references/gate-audit-schema.md for this gate's section. Written anyway." >&2
  fi
fi

# An empty required list is not the same as a missing key, and for recipe-load it is the
# case that actually occurred: `frameworks: []` beside a prose `notes` describing a
# resolution that did happen. The schema pairs an empty list with a `bypass` object naming
# the no-recipe outcome, so empty-and-unexplained is the drift worth naming.
if [[ "$GATE_TYPE" == "recipe-load" ]]; then
  if echo "$PAYLOAD" | jq -e '(.gate_specific.frameworks | type == "array" and length == 0)
                              and (.gate_specific.bypass // null) == null' >/dev/null 2>&1; then
    echo "gate-audit-write: WARNING — recipe-load recorded no frameworks and no bypass object." >&2
    echo "  An empty frameworks[] needs a bypass naming why (no_frameworks_defined etc.)." >&2
    echo "  Prose in notes[] is not a substitute: consumers count frameworks[]. Written anyway." >&2
  fi
fi

# A resolved recipe that did not suit the task must say so where a program can read it.
#
# Recipe routing keys on phase and framework and on nothing else. It never asks what kind of
# work the task is, so an environment task — three config values and a build — was handed a
# contrib-module prior-art method during research and a service-and-plugin architecture method
# during design. Both times the phase noticed, and both times it wrote a paragraph into a
# `notes` key that appears nowhere in this gate's schema and that no consumer reads. By the
# next phase the observation was gone, and the review that eventually judges the work has no
# way to learn the method was wrong for it.
#
# `method_fit` is where that goes: `{"verdict": "fits|partial|mismatch|undetermined",
# "reason": "<one line>"}` on each framework entry. `undetermined` is a real answer and the
# honest one when nobody looked; what must not happen is an unassessed recipe reading as a
# suitable one. Absent is warned rather than rejected, per this writer's payload posture.
if [[ "$GATE_TYPE" == "recipe-load" ]]; then
  # A jq failure here must not read as "no problems found". It is reported and the
  # write continues, the same posture as every other payload warning.
  if ! FIT_PROBLEMS=$(echo "$PAYLOAD" | jq -r '
    (.gate_specific.frameworks // [])
    | map(select(.available == true))
    | map(
        (.framework // "?") as $fw
        | (.method_fit // null) as $fit
        | if $fit == null then
            "\($fw): no method_fit, so an unassessed recipe reads as a suitable one"
          elif ($fit | type) != "object" then
            "\($fw): method_fit is a \($fit | type), not the {verdict, reason} object the schema requires"
          else
            ($fit.verdict // "") as $v
            | ($fit.reason // "") as $r
            | if (["fits","partial","mismatch","undetermined"] | index($v)) == null then
                "\($fw): method_fit.verdict \"\($v)\" is not fits|partial|mismatch|undetermined"
              elif (($v == "partial" or $v == "mismatch") and ($r | length) == 0) then
                "\($fw): method_fit is \($v) with no reason, so the next phase cannot act on it"
              else empty end
          end)
    | .[]' 2>&1); then
    echo "gate-audit-write: WARNING — could not check recipe-load method_fit: $FIT_PROBLEMS" >&2
    FIT_PROBLEMS=""
  fi
  if [[ -n "$FIT_PROBLEMS" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] && echo "gate-audit-write: WARNING — recipe-load $line" >&2
    done <<< "$FIT_PROBLEMS"
    echo "  See references/gate-audit-schema.md 5.12. Prose in notes[] is not a substitute." >&2
    echo "  Record fit= on the project_state recipe line too, or it is gone next phase. Written anyway." >&2
  fi
fi

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
