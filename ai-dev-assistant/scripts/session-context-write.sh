#!/usr/bin/env bash
# session-context-write.sh — persist per-workspace session context for hooks.
#
# Verbatim lift (v4.16.0) of the jq merge block that used to live in the
# session-context-writer SKILL body. Extracted so lifecycle commands can write
# session context via a Bash call with ZERO model context, instead of invoking
# an inline skill whose model: pin overflowed in large sessions (BUG-1).
#
# Usage:
#   session-context-write.sh <project_name> <project_path> <task|null> <taskPath|null> [<currentEpic>|null|{CURRENT_EPIC_OR_NULL}]
#
# Args (mirror the former SKILL placeholders 1:1):
#   $1  project_name      resolved project name (e.g. wasatch_update)
#   $2  project_path      absolute project path
#   $3  task              task name, or the literal string "null" / "" for none
#   $4  taskPath          absolute task path, or the literal string "null" / "" for none
#   $5  currentEpic       (optional) epic folder name; the literal "null"/"" to clear;
#                         or the preserve-sentinel {CURRENT_EPIC_OR_NULL} (the default
#                         when omitted) to keep whatever is already on disk.
#
# Merges the new core fields over any existing session file, seeding
# loadedGuides: [] and lastPhase: null only when the file is first created.
# loadedGuides, lastPhase, and currentEpic are managed by other components
# (guide-integrator, task-frontmatter-reader, the context-reminder hook) — this
# script must not clobber them.
#
# The session file path is resolved by the shared session-paths.sh helper
# (ddf_session_file): keyed by md5($PWD) and, when CLAUDE_CODE_SESSION_ID is set,
# additionally by the session ID. Silent — emits nothing to stdout.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=./session-paths.sh
. "$SCRIPT_DIR/session-paths.sh"

PROJECT_NAME="${1:-}"
PROJECT_PATH="${2:-}"
TASK_ARG="${3:-null}"
TASK_PATH_ARG="${4:-null}"
# NOTE: do not fold the brace default into ${5:-...} — a literal "}" inside the
# expansion closes it at the first brace and appends a stray "}" to the value.
if [ "$#" -ge 5 ]; then
  NEW_EPIC_ARG="$5"
else
  NEW_EPIC_ARG='{CURRENT_EPIC_OR_NULL}'
fi

SESS_FILE=$(ddf_session_file)
mkdir -p "$(dirname "$SESS_FILE")"

NEW_CORE=$(jq -n \
  --arg workspace "$PWD" \
  --arg project "$PROJECT_NAME" \
  --arg projectPath "$PROJECT_PATH" \
  --arg task "$TASK_ARG" \
  --arg taskPath "$TASK_PATH_ARG" \
  --arg updatedAt "$(date -I)" \
  '{
    workspace: $workspace,
    project: $project,
    projectPath: $projectPath,
    task: (if $task == "null" or $task == "" then null else $task end),
    taskPath: (if $taskPath == "null" or $taskPath == "" then null else $taskPath end),
    updatedAt: $updatedAt
  }')

if [ -s "$SESS_FILE" ] && jq -e . "$SESS_FILE" >/dev/null 2>&1; then
  # Preserve loadedGuides, lastPhase, and currentEpic; overwrite core fields.
  # currentEpic behavior: if the caller passed an explicit value (not the literal
  # "{CURRENT_EPIC_OR_NULL}" preserve-sentinel), use it; otherwise preserve existing.
  jq --argjson new "$NEW_CORE" --arg epic "$NEW_EPIC_ARG" \
    '. * $new
     | .loadedGuides = (.loadedGuides // [])
     | .lastPhase = (.lastPhase // null)
     | .currentEpic = (
         if $epic == "{CURRENT_EPIC_OR_NULL}" then (.currentEpic // null)
         elif $epic == "null" or $epic == "" then null
         else $epic
         end
       )' \
    "$SESS_FILE" > "$SESS_FILE.tmp" && mv "$SESS_FILE.tmp" "$SESS_FILE"
else
  # First write, empty, or corrupt JSON — reseed from scratch with fresh core +
  # preserved-field defaults.
  echo "$NEW_CORE" | jq --arg epic "$NEW_EPIC_ARG" '. + {
    loadedGuides: [],
    lastPhase: null,
    currentEpic: (if $epic == "{CURRENT_EPIC_OR_NULL}" or $epic == "null" or $epic == "" then null else $epic end)
  }' > "$SESS_FILE"
fi
