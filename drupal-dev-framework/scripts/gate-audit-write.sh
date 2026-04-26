#!/usr/bin/env bash
# gate-audit-write.sh — atomic gate audit file writer.
#
# Usage: gate-audit-write.sh <task_folder> <gate_type> <json_payload>
#
#   <task_folder>: absolute path to task folder
#   <gate_type>: one of pre-analysis | coverage-mapping | skill-review |
#                plugin-validate | phase-command-bypass | dev-guides-load |
#                playbook-load | review
#   <json_payload>: complete audit JSON object conforming to
#                   references/gate-audit-schema.md (v1.0 for the original 7
#                   gate types; v1.1+ adds `review` — sibling plumbing_docs_tests
#                   bumps the schema doc itself)
#
# Behavior:
# - Validates the JSON parses + has schema_version starting with "1." (1.0, 1.1+ accepted)
# - Validates gate_type is one of the 8 allowed values
# - Validates required top-level fields (gate_type, fired_at, task_folder, gate_specific)
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
  pre-analysis|coverage-mapping|skill-review|plugin-validate|phase-command-bypass|dev-guides-load|playbook-load|review)
    ;;
  *)
    echo "gate-audit-write: invalid gate_type: $GATE_TYPE" >&2
    echo "  must be one of: pre-analysis, coverage-mapping, skill-review, plugin-validate, phase-command-bypass, dev-guides-load, playbook-load, review" >&2
    exit 2
    ;;
esac

# Validate JSON parses
if ! echo "$PAYLOAD" | jq empty >/dev/null 2>&1; then
  echo "gate-audit-write: invalid JSON payload" >&2
  exit 2
fi

# Validate schema_version (accept any 1.x — backward-compat for v1.1 review gate)
SV=$(echo "$PAYLOAD" | jq -r '.schema_version // empty')
case "$SV" in
  1.0|1.1) ;;
  *)
    echo "gate-audit-write: schema_version must be \"1.0\" or \"1.1\" (got \"$SV\")" >&2
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
