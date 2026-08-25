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
# The task-folder record first: it outlives the session file, which the SessionStart hook
# deletes, so a phase interrupted and resumed still knows what it declared.
TF_ACTIVE="$TASK_FOLDER/_phase-active.json"
if [[ -f "$TF_ACTIVE" ]]; then
  RAW=$(jq -r '.phase // empty' "$TF_ACTIVE" 2>/dev/null)
  [[ -n "$RAW" ]] && ACTIVE_PHASE="$RAW"
fi
# Fall back to the session file for a caller that declared without naming a task folder.
if [[ "$ACTIVE_PHASE" == "null" && -f "$SESS_FILE" ]]; then
  RAW=$(jq -r '.lastPhase // empty' "$SESS_FILE" 2>/dev/null)
  [[ -n "$RAW" ]] && ACTIVE_PHASE="$RAW"
fi

# Check match
if [[ "$ACTIVE_PHASE" == "$EXPECTED" ]]; then
  # Legitimate phase-command authoring; no bypass
  echo "{}"
  exit 0
fi

# UNKNOWABLE IS NOT A BYPASS. `lastPhase` unset means nobody declared a phase, which is the state
# of every session where the phase command has not called phase-active-write.sh — including, until
# that script existed, every session there has ever been. Reporting that as a bypass produced a
# finding on every phase artifact ever written and made the record worthless: a guardrail that
# always fires cannot tell a real bypass from a correct run.
#
# Assert a bypass only when a DIFFERENT phase is positively active. When nothing is declared, say
# so — `undetermined`, with the reason — so a reader can tell "we caught something" from "we could
# not look."
if [[ "$ACTIVE_PHASE" == "null" || -z "$ACTIVE_PHASE" ]]; then
  jq -nc --arg artifact "$ARTIFACT" --arg expected "$EXPECTED" \
     --arg task_folder "$TASK_FOLDER" --arg fired_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    '{schema_version: "1.0",
      gate_type: "phase-command-bypass",
      fired_at: $fired_at,
      task_folder: $task_folder,
      user_choice: null,
      bypass_reason: null,
      gate_specific: {
        artifact_written: $artifact,
        phase_command_active: null,
        expected_phase_command: $expected,
        verdict: "undetermined",
        reason: "no phase command declared itself active; scripts/phase-active-write.sh was not called, so a bypass can be neither confirmed nor ruled out"
      }}'
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
      expected_phase_command: $expected,
      verdict: "bypass",
      reason: "a different phase command was active when this artifact was written"
    }
  }'
