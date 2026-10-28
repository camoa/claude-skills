#!/usr/bin/env bash
# frozen-hook-note-spec.sh: hooks/deny-frozen-test-writes.sh says that it checked nothing only when
# the write lands in a task's worktree that no open dispatch record covers (gap row 466). A write
# outside every task's worktree is not the hook's business, so the hook says nothing.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=records.bash
source "$HERE/records.bash"

# second_task <with record>: task t2 with its own worktree $ROOT/wt2 on feature/t2. With yes, its
# implementer's dispatch record is open too.
second_task() {
  mkdir -p "$PROJECT/tasks/t2/implementation"
  git -C "$CODE" worktree add -q -b feature/t2 "$ROOT/wt2" main
  jq --arg w "$ROOT/wt2" '.id = "t2" | .worktree = {path: $w, branch: "feature/t2", base: "main"}' \
    "$TASK/task.json" >"$PROJECT/tasks/t2/task.json"
  [ "$1" = no ] \
    || jq --arg w "$ROOT/wt2" '.task = "t2" | .codePath = $w' "$IMPL/dispatch.json" >"$PROJECT/tasks/t2/implementation/dispatch.json"
}
# edit <dir> <file>: prints silent when the hook answers an ordinary subagent's Edit of <file>,
# run in <dir>, with no output, and note when it answers with a message.
edit() {
  jq -nc --arg d "$1" --arg f "$2" \
    '{tool_name: "Edit", cwd: $d, agent_id: "a1", agent_type: "general-purpose", session_id: "s1",
      permission_mode: "default", tool_input: {file_path: $f, old_string: "a", new_string: "b"}}' \
    | bash "$PLUGIN/hooks/deny-frozen-test-writes.sh" | jq -r 'if . == {} then "silent" elif .systemMessage then "note" else tostring end'
}
outside_case() (
  source "$HERE/records.bash"
  task_records branch
  dispatch_record implementer
  second_task yes
  edit "$CODE" "$CODE/a.php"
)
uncovered_case() (
  source "$HERE/records.bash"
  task_records branch
  dispatch_record implementer
  second_task no
  edit "$ROOT/wt2" "$ROOT/wt2/a.php"
)

echo "--- the note that nothing was checked"
expect "an edit outside every task's worktree, with two records open, prints nothing" "$(outside_case)" silent
expect "an edit in a task's worktree that no record covers prints the note" "$(uncovered_case)" note

finish
