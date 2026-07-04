#!/usr/bin/env bash
# orchestration-policy-read.sh — defensive reader for the orchestration-policy slot.
#
# Usage: orchestration-policy-read.sh <project_folder>
#
# Reads <project_folder>/orchestration-policy.json — the durable, project-scoped
# structured home for run_mode (mirror), active_checkpoints, cross_task_decisions,
# and conditional_routing. Sibling of project_state.md; NOT the workspace-hashed
# session file.
#
# Contract (mirrors project-state-read.sh / fm-read.sh): ALWAYS emit a single-line
# JSON superset to stdout and exit 0, regardless of input. Warnings surface via
# warnings[]. No writes, no side effects, no eval/source of the JSON (jq-parse only).
#
# The **Run Mode:** dial in project_state.md is AUTHORITATIVE. This reader
# cross-reads it (via project-state-read.sh) and emits the DIAL's run_mode. If the
# on-disk policy disagrees, the dial wins and a run_mode_dial_mismatch warning is
# appended — the mismatch is surfaced, never silently resolved.
#
# Output superset:
#   {
#     "schema_version": "1.0",
#     "run_mode": "interactive" | "autonomous",   # always the dial value
#     "active_checkpoints":   [ ... ],
#     "cross_task_decisions": [ ... ],
#     "conditional_routing":  [ ... ],
#     "folder": "<abs path>",
#     "warnings": [{"code": "...", "detail": "..."}]
#   }
#
# Warning codes:
#   missing_arg                   — called without $1
#   orchestration_policy_missing  — policy file absent (default superset from dial)
#   orchestration_policy_corrupt  — policy file is not valid JSON (default superset)
#   run_mode_dial_mismatch        — policy run_mode != dial; dial wins

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PSR="$SCRIPT_DIR/project-state-read.sh"

PROJECT_DIR="${1:-}"

# emit_superset <schema_version> <run_mode> <checkpoints json> <decisions json>
#               <routing json> <folder> <warnings json>
emit_superset() {
  jq -nc \
    --arg sv "$1" --arg rm "$2" \
    --argjson cp "$3" --argjson cd "$4" --argjson cr "$5" \
    --arg folder "$6" --argjson w "$7" '
    {
      schema_version: $sv,
      run_mode: $rm,
      active_checkpoints: $cp,
      cross_task_decisions: $cd,
      conditional_routing: $cr,
      folder: $folder,
      warnings: $w
    }'
}

if [ -z "$PROJECT_DIR" ]; then
  emit_superset "1.0" "interactive" "[]" "[]" "[]" "" \
    '[{"code":"missing_arg","detail":"path to project folder required as $1"}]'
  exit 0
fi

# Cross-read the AUTHORITATIVE dial. project-state-read.sh is itself defensive
# (emit JSON + exit 0 on any input), so this never fails the reader.
DIAL="interactive"
if [ -f "$PSR" ]; then
  DIAL=$(bash "$PSR" "$PROJECT_DIR" 2>/dev/null | jq -r '.runMode // "interactive"' 2>/dev/null)
  case "$DIAL" in
    interactive|autonomous) ;;
    *) DIAL="interactive" ;;
  esac
fi

POLICY="$PROJECT_DIR/orchestration-policy.json"

# File absent → default superset seeded from the dial.
if [ ! -f "$POLICY" ]; then
  emit_superset "1.0" "$DIAL" "[]" "[]" "[]" "$PROJECT_DIR" \
    '[{"code":"orchestration_policy_missing","detail":"orchestration-policy.json not found beside project_state.md"}]'
  exit 0
fi

# File present but not valid JSON → default superset (NEVER eval/source it).
if ! jq -e . "$POLICY" >/dev/null 2>&1; then
  emit_superset "1.0" "$DIAL" "[]" "[]" "[]" "$PROJECT_DIR" \
    '[{"code":"orchestration_policy_corrupt","detail":"orchestration-policy.json is not valid JSON; using default superset"}]'
  exit 0
fi

# File present + valid: defensively default any missing superset key, then apply
# the dial-wins authority rule for run_mode.
jq -c --arg dial "$DIAL" --arg folder "$PROJECT_DIR" '
  {
    schema_version:       (.schema_version // "1.0"),
    active_checkpoints:   (.active_checkpoints // []),
    cross_task_decisions: (.cross_task_decisions // []),
    conditional_routing:  (.conditional_routing // []),
    folder:               $folder,
    warnings:             (.warnings // [])
  }
  + { run_mode: $dial }
  + ( if ((.run_mode // $dial) != $dial)
      then { warnings: ((.warnings // []) + [{
              code: "run_mode_dial_mismatch",
              detail: ("policy=" + (.run_mode | tostring) + " dial=" + $dial + "; dial wins")
            }]) }
      else {} end )
' "$POLICY" 2>/dev/null || \
  emit_superset "1.0" "$DIAL" "[]" "[]" "[]" "$PROJECT_DIR" \
    '[{"code":"orchestration_policy_corrupt","detail":"jq projection failed; using default superset"}]'
