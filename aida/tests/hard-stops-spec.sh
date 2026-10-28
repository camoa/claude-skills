#!/usr/bin/env bash
# hard-stops-spec.sh: each of the four hard stops refuses, and allows the right case. Nobody but the
# order's test author writes a frozen test. The implementer writes only its order's files. The
# build never lands on the trunk. Only the person's own prompt records an answer, and one answer
# serves one call. Each case sources the helper in a subshell, so it starts from fresh records,
# and its setup never takes the guarded step itself.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=records.bash
source "$HERE/records.bash"
HOOK="$PLUGIN/hooks/deny-frozen-test-writes.sh"
TASK_ACTIONS="$PLUGIN/skills/task/scripts/task-actions.sh"

# write_hook <tool input> [<agent type>]: the write hook's decision on one call from the worktree,
# deny, ask or allow. A command in the input makes it a Bash call, else a Write. With no agent
# type, the call is the main session's.
write_hook() {
  local tool=Write
  [ "$(printf '%s' "$1" | jq 'has("command")')" = true ] && tool=Bash
  jq -nc --arg t "$tool" --argjson i "$1" --arg c "$WT" --arg a "${2:-}" \
    '{tool_name: $t, tool_input: $i, cwd: $c, permission_mode: "default", session_id: "s1"}
     + (if $a == "" then {} else {agent_type: $a, agent_id: "a1"} end)' \
    | CLAUDE_PLUGIN_ROOT="$PLUGIN" bash "$HOOK" | jq -r '.hookSpecificOutput.permissionDecision // "allow"'
}
file() { jq -nc --arg f "$1" '{file_path: $f}'; }
exists() { [ -e "$1" ] && echo yes || echo no; }

# frozen_case <role> <path>: the hook's decision on <role>'s write to <path>, with wo1's tests frozen
# and <role> dispatched for wo1. tests/a_test.sh is frozen and owned by wo1, so only the frozen
# rule can refuse it.
frozen_case() (
  source "$HERE/records.bash"
  task_records branch
  order_records tests-frozen
  suite_records ""
  tests_record
  dispatch_record "$1"
  write_hook "$(file "$WT/$2")" "aida:$1"
)
# build_case [branch]: build-brief's exit, and whether it wrote a brief, on wo1 with its tests frozen.
build_case() (
  source "$HERE/records.bash"
  task_records "$@"
  order_records tests-frozen
  suite_records ""
  tests_record
  run "$IMPLEMENT" build-brief "$TASK" wo1
  printf '%s|%s\n' "$RC" "$(exists "$IMPL/brief-wo1-build.json")"
)
# start_case [branch]: start's exit, and whether it wrote the ledger.
start_case() (
  source "$HERE/records.bash"
  task_records "$@"
  run "$IMPLEMENT" start "$TASK"
  printf '%s|%s\n' "$RC" "$(exists "$IMPL/ledger.json")"
)
# answer_hook_case <agent type>: the hook's decision on person-answer.sh and on a direct write of the
# answer record, from the main session or from a dispatched role.
answer_hook_case() (
  source "$HERE/records.bash"
  task_records branch
  order_records code-written
  local cmd
  cmd="$(jq -nc --arg c "$PLUGIN/skills/task/scripts/person-answer.sh --project $PROJECT t1 --step 'implement drop' --order wo1 -- 'not needed'" '{command: $c}')"
  [ -z "$1" ] || dispatch_record "${1#aida:}"
  printf '%s|%s\n' "$(write_hook "$cmd" "$1")" "$(write_hook "$(file "$TASK/person-answers.json")" "$1")"
)
# run_mode_case: set-run-mode with no answer, with one, and with the same answer once more. Prints
# each exit and the run mode it left.
run_mode_case() (
  source "$HERE/records.bash"
  task_records branch
  local out=""
  mode() { jq -r '.runMode // "interactive"' "$TASK/task.json"; }
  run "$TASK_ACTIONS" set-run-mode --project "$PROJECT" t1 autonomous
  out="$RC:$(mode)"
  answer "task set-run-mode" "" autonomous
  run "$TASK_ACTIONS" set-run-mode --project "$PROJECT" t1 autonomous
  out="$out|$RC:$(mode)"
  jq '.runMode = "light"' "$TASK/task.json" >"$TASK/task.new" && mv "$TASK/task.new" "$TASK/task.json"
  run "$TASK_ACTIONS" set-run-mode --project "$PROJECT" t1 autonomous
  printf '%s|%s:%s\n' "$out" "$RC" "$(mode)"
)

echo "--- frozen: an implementer cannot write a frozen test; the order's test author can"
expect "the implementer's write to a frozen test it owns is refused" "$(frozen_case implementer tests/a_test.sh)" deny
expect "the test author of the order writes its frozen test" "$(frozen_case test-author tests/a_test.sh)" allow

echo "--- owned: the implementer writes its order's files and nothing else"
expect "an owned file is allowed" "$(frozen_case implementer a.php)" allow
expect "a file the order does not own is refused" "$(frozen_case implementer b.php)" deny

echo "--- trunk: start and the build refuse on the trunk, and run on a work branch"
expect "on the trunk, start refuses and writes no ledger" "$(start_case)" "6|no"
expect "on feature/t1, start writes the ledger" "$(start_case branch)" "0|yes"
expect "on the trunk, build-brief refuses and writes no brief" "$(build_case)" "6|no"
expect "on feature/t1, build-brief writes the brief" "$(build_case branch)" "0|yes"

echo "--- answer: only the person's prompt records an answer, and one answer serves one call"
expect "from the main session, the person's script asks, and a direct write of the record is refused" \
  "$(answer_hook_case "")" "ask|deny"
expect "from a dispatched role, both are refused" "$(answer_hook_case aida:implementer)" "deny|deny"
expect "set-run-mode refuses with no answer, runs with one, and refuses when that one is used" \
  "$(run_mode_case)" "70:interactive|0:autonomous|70:light"

finish
