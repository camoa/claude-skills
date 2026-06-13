#!/usr/bin/env bash
# phase-command-bypass-detect.sh — detect Write-tool-bypass of phase commands.
#
# Usage: phase-command-bypass-detect.sh <task_folder> <artifact_name>
#
#   <task_folder>: absolute path to the task folder
#   <artifact_name>: research.md | architecture.md | implementation.md
#
# Behavior:
# - Reads session_context.json for the current workspace
# - Determines if a phase command is currently active (lastPhase field)
# - Checks if the artifact's expected phase command matches the active one
# - If mismatch (or no phase command active), emits a phase-command-bypass
#   audit JSON to stdout for the caller (a PreToolUse hook) to write via
#   gate-audit-write.sh
# - If match, emits empty JSON `{}` (no bypass; legitimate phase-command authoring)
#
# Notes:
# - Non-blocking. Returns the audit JSON; caller decides whether to write it.
# - The hook that invokes this script does NOT abort the Write tool. The
#   bypass is recorded but the Write proceeds. This is soft-nudge: we audit,
#   we don't block.

set -uo pipefail

TASK_FOLDER="${1:?task folder required}"
ARTIFACT="${2:?artifact name required}"

# Map artifact → expected phase command
EXPECTED=""
case "$ARTIFACT" in
  research.md) EXPECTED="research" ;;
  architecture.md) EXPECTED="design" ;;
  implementation.md) EXPECTED="implement" ;;
  *)
    # Unknown artifact; treat as no-op
    echo "{}"
    exit 0
    ;;
esac

# Read session_context for current workspace
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/session-paths.sh"
SESS_FILE=$(ddf_session_file)

ACTIVE_PHASE="null"
if [[ -f "$SESS_FILE" ]]; then
  RAW=$(jq -r '.lastPhase // empty' "$SESS_FILE" 2>/dev/null)
  [[ -n "$RAW" ]] && ACTIVE_PHASE="$RAW"
fi

# Check match
if [[ "$ACTIVE_PHASE" == "$EXPECTED" ]]; then
  # Legitimate phase-command authoring; no bypass
  echo "{}"
  exit 0
fi

# Bypass detected — emit audit JSON
FIRED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

jq -nc \
  --arg artifact "$ARTIFACT" \
  --arg active "$ACTIVE_PHASE" \
  --arg expected "$EXPECTED" \
  --arg task_folder "$TASK_FOLDER" \
  --arg fired_at "$FIRED_AT" '
  {
    schema_version: "1.0",
    gate_type: "phase-command-bypass",
    fired_at: $fired_at,
    task_folder: $task_folder,
    user_choice: null,
    bypass_reason: null,
    gate_specific: {
      artifact_written: $artifact,
      phase_command_active: (if $active == "null" or $active == "" then null else $active end),
      expected_phase_command: $expected
    }
  }'
