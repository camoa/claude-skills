#!/usr/bin/env bash
# read-hook-spec.sh: hooks/deny-prior-source.sh refuses a dispatched test author the source its
# record denies, through a Bash read in the task's worktree, also when the shell starts in the
# project's main checkout and a literal cd or git -C moves it there. With a second task's test
# author open too, the main checkout names no one record, so the cd target decides it.
set -u
# shellcheck source=records.bash
source "$(dirname "${BASH_SOURCE[0]}")/records.bash"
task_records branch
dispatch_record test-author
# read_hook <dir> <command>: the read hook's decision on a test author's Bash call from <dir>.
read_hook() {
  jq -nc --arg d "$1" --arg c "$2" \
    '{tool_name: "Bash", cwd: $d, agent_id: "a1", agent_type: "aida:test-author", session_id: "s1",
      permission_mode: "default", tool_input: {command: $c}}' \
    | CLAUDE_PLUGIN_ROOT="$PLUGIN" bash "$PLUGIN/hooks/deny-prior-source.sh" \
    | jq -r '.hookSpecificOutput.permissionDecision // "allow"'
}

expect "cat a.php in the worktree is refused" "$(read_hook "$WT" "cat a.php")" deny
expect "cd into the worktree from the main checkout, then cat a.php, is refused" \
  "$(read_hook "$CODE" "cd $WT && cat a.php")" deny
expect "git -C the worktree show of a.php, from the main checkout, is refused" \
  "$(read_hook "$CODE" "git -C $WT show HEAD:a.php")" deny
expect "cat of a file the record does not deny passes" "$(read_hook "$CODE" "cd $WT && cat tests/a_test.sh")" allow

# Task t2, its worktree $ROOT/wt2, and its own test author's record.
mkdir -p "$PROJECT/tasks/t2/implementation"
git -C "$CODE" worktree add -q -b feature/t2 "$ROOT/wt2" main
jq --arg w "$ROOT/wt2" '.id = "t2" | .worktree = {path: $w, branch: "feature/t2", base: "main"}' \
  "$TASK/task.json" >"$PROJECT/tasks/t2/task.json"
jq --arg w "$ROOT/wt2" '.task = "t2" | .codePath = $w' "$IMPL/dispatch.json" >"$PROJECT/tasks/t2/implementation/dispatch.json"
expect "with two records open, cd into one worktree from the main checkout, then cat a.php, is refused" \
  "$(read_hook "$CODE" "cd $WT && cat a.php")" deny

finish
