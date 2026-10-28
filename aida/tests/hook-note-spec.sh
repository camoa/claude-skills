#!/usr/bin/env bash
# hook-note-spec.sh: hooks/deny-frozen-test-writes.sh and hooks/deny-prior-source.sh say that they
# checked nothing only when the call lands in a task's worktree that no open dispatch record covers
# (gap row 466). A call outside every task's worktree is not their business, so they say nothing.
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
# call <hook> <dir> <tool> <tool_input>: prints silent when the hook answers an ordinary subagent's
# call, run in <dir>, with no output, and the message when it answers with one.
call() {
  jq -nc --arg d "$2" --arg t "$3" --argjson i "$4" \
    '{tool_name: $t, cwd: $d, agent_id: "a1", agent_type: "general-purpose", session_id: "s1",
      permission_mode: "default", tool_input: $i}' \
    | bash "$PLUGIN/hooks/$1.sh" | jq -r 'if . == {} then "silent" else .systemMessage // tostring end'
}
# note_case <hook> <t2 record> <dir> <tool> <tool_input>: t1's implementer record open, then task
# t2, then the call. Prints silent, the note, or "note naming wt2" when the note names that folder.
# In <dir> and <tool_input>, @ is this case's own temporary folder.
note_case() (
  source "$HERE/records.bash"
  task_records branch
  dispatch_record implementer
  second_task "$2"
  call "$1" "${3//@/$ROOT}" "$4" "${5//@/$ROOT}" | sed -e "s#.*not_enforced.*holding $ROOT/wt2,.*#note naming wt2#" -e 's#.*not_enforced.*#note#'
)
edit() { jq -nc --arg f "$1" '{file_path: $f, old_string: "a", new_string: "b"}'; }
cmd() { jq -nc --arg c "$1" '{command: $c}'; }
read_of() { jq -nc --arg f "$1" '{file_path: $f}'; }

echo "--- the frozen-test hook's note"
expect "an edit outside every task's worktree, with two records open, prints nothing" \
  "$(note_case deny-frozen-test-writes yes "@/code" Edit "$(edit "@/code/a.php")")" silent
expect "an edit in a task's worktree that no record covers prints the note" \
  "$(note_case deny-frozen-test-writes no "@/wt2" Edit "$(edit "@/wt2/a.php")")" "note naming wt2"
expect "an edit of a worktree file from the main checkout names the file's folder" \
  "$(note_case deny-frozen-test-writes no "@/code" Edit "$(edit "@/wt2/a.php")")" "note naming wt2"
expect "a write after a cd into a task's worktree, from the main checkout, prints the note" \
  "$(note_case deny-frozen-test-writes no "@/code" Bash "$(cmd "cd @/wt2 && echo x > a.php")")" "note naming wt2"
expect "a command that writes nothing, in a task's worktree, prints nothing" \
  "$(note_case deny-frozen-test-writes no "@/wt2" Bash "$(cmd ls)")" silent

echo "--- the prior-source hook's note"
expect "a read outside every task's worktree prints nothing" \
  "$(note_case deny-prior-source no "@/code" Read "$(read_of "@/code/a.php")")" silent
expect "a read in a task's worktree that no record covers prints the note" \
  "$(note_case deny-prior-source no "@/code" Read "$(read_of "@/wt2/a.php")")" "note naming wt2"

finish
