#!/usr/bin/env bash
# pre-compact-spec.sh: hooks/pre-compact.sh lets a manual compaction run when the task has unsaved
# stage work, and writes a warning into the task record that names the unsaved files. A saved task
# gets no warning.
set -u
# shellcheck source=records.bash
source "$(dirname "${BASH_SOURCE[0]}")/records.bash"
# compact: one manual compaction from the task's worktree. Sets RC to the hook's exit.
compact() {
  jq -nc --arg d "$WT" '{hook_event_name: "PreCompact", trigger: "manual", cwd: $d, session_id: "s1"}' \
    | CLAUDE_PLUGIN_ROOT="$PLUGIN" bash "$PLUGIN/hooks/pre-compact.sh" >/dev/null 2>&1
  RC=$?
}
task_records branch

compact
expect "a manual compaction with unsaved work runs" "$RC" 0
expect "the warning names an unsaved file" \
  "$(jq -r '[ (.warnings // [])[] | select(.step == "compact") | .words | contains("alignment.json") ] | any' "$TASK/task.json")" true

jq --arg t "$(date -u -v+1M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '+1 minute' +%Y-%m-%dT%H:%M:%SZ)" \
  '.savedAt = $t | del(.warnings)' "$TASK/task.json" >"$ROOT/task.new" && mv "$ROOT/task.new" "$TASK/task.json"
compact
expect "a saved task gets no warning" "$(jq -r '(.warnings // []) | length' "$TASK/task.json")" 0

finish
