#!/usr/bin/env bash
# hard-stops-spec.sh: four of the five hard stops each refuse, and allow the right case. Nobody but
# the order's test author writes a frozen test. The implementer writes only its order's files. The
# build never lands on the trunk. Only the person's own prompt records an answer, and one answer
# serves one call. The fifth, a test newly broken at finish, is in finish-stop-spec.sh. The write rules hold through Bash, in the main checkout, and from a folder
# outside every code path. Each case sources the helper in a subshell, so it starts from fresh
# records, and its setup never takes the guarded step itself.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=records.bash
source "$HERE/records.bash"
TASK_ACTIONS="$PLUGIN/skills/task/scripts/task-actions.sh"

exists() { [ -e "$1" ] && echo yes || echo no; }

# guarded_case <role> <folder> <file or command> [remembered]: the hook's decision on <role>'s call
# from <folder>, with wo1's tests frozen and <role> dispatched for wo1. A refusal names the rule that
# refused it: frozen, owned or main. tests/a_test.sh is frozen and owned by wo1, so only the frozen
# rule can refuse it. In both arguments, @WT and @CODE stand for this case's worktree and main
# checkout. In the folder, @NOTES stands for a notes folder outside every code path. In the file or
# command, @ROOT stands for this case's folder. An argument with a space is a command. With
# remembered, the registry remembers project p for the notes folder.
guarded_case() (
  source "$HERE/records.bash"
  task_records branch
  order_records tests-frozen
  suite_records ""
  tests_record
  dispatch_record "$1"
  mkdir -p "$ROOT/notes"
  if [ "${4:-}" = remembered ]; then
    jq --arg d "$ROOT/notes" '.directoryChoices = [{directory: $d, project: "p", chosenAt: "2026-10-28"}]' \
      "$AIDA_REGISTRY_PATH" >"$ROOT/registry.new" && mv "$ROOT/registry.new" "$AIDA_REGISTRY_PATH"
  fi
  local arg input decision
  arg="${3//@WT/$WT}"; arg="${arg//@CODE/$CODE}"; arg="${arg//@ROOT/$ROOT}"
  case "$arg" in *' '*) input="$(jq -nc --arg c "$arg" '{command: $c}')" ;; *) input="$(file "$arg")" ;; esac
  HOOK_CWD="${2//@WT/$WT}"; HOOK_CWD="${HOOK_CWD//@CODE/$CODE}"; HOOK_CWD="${HOOK_CWD//@NOTES/$ROOT/notes}"
  decision="$(write_hook "$input" "aida:$1")"
  case "$decision:$(jq -r '.hookSpecificOutput.permissionDecisionReason // ""' "$ROOT/hook.json")" in
    deny:*"froze this test"*) decision="deny frozen" ;;
    deny:*"not a file"*) decision="deny owned" ;;
    deny:*"main checkout"*) decision="deny main" ;;
  esac
  printf '%s\n' "$decision"
)
frozen_case() { guarded_case "$1" @WT "@WT/$2"; }
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
expect "the implementer's write to a frozen test it owns is refused" "$(frozen_case implementer tests/a_test.sh)" "deny frozen"
expect "the test author of the order writes its frozen test" "$(frozen_case test-author tests/a_test.sh)" allow

echo "--- owned: the implementer writes its order's files and nothing else"
expect "an owned file is allowed" "$(frozen_case implementer a.php)" allow
expect "a file the order does not own is refused" "$(frozen_case implementer b.php)" "deny owned"

echo "--- bash: the frozen and the owned rules read a write through Bash"
expect "a redirect into the frozen test is refused" "$(guarded_case implementer @WT 'echo exit 0 > tests/a_test.sh')" "deny frozen"
expect "sed -i on the frozen test is refused" "$(guarded_case implementer @WT 'sed -i s/1/0/ tests/a_test.sh')" "deny frozen"
expect "a copy of the frozen test out to a scratch file is allowed" \
  "$(guarded_case implementer @WT 'cp tests/a_test.sh @ROOT/copy.sh')" allow
expect "a redirect into a file the order does not own is refused" "$(guarded_case implementer @WT 'echo b > b.php')" "deny owned"
expect "sed -i on an owned file is allowed" "$(guarded_case implementer @WT 'sed -i s/a/b/ a.php')" allow
expect "a redirect into an owned file, its errors piped to head, is allowed" \
  "$(guarded_case implementer @WT 'echo b > a.php 2>&1 | head -1')" allow

echo "--- main: a role does not write in the project's main checkout"
expect "the implementer's Write in the main checkout is refused" "$(guarded_case implementer @CODE @CODE/a.php)" "deny main"
expect "git -C the main checkout commit is refused" "$(guarded_case implementer @WT 'git -C @CODE commit -qam b')" "deny main"
expect "git -C the worktree commit is allowed" "$(guarded_case implementer @WT 'git -C @WT commit -qam b')" allow

echo "--- outside: from a folder outside every code path, the rules hold the same"
expect "the implementer's Write of the frozen test is refused" "$(guarded_case implementer @NOTES @WT/tests/a_test.sh)" "deny frozen"
expect "a redirect into a file the order does not own is refused" \
  "$(guarded_case implementer @NOTES 'echo b > @WT/b.php')" "deny owned"
expect "the implementer's Write in the main checkout is refused" "$(guarded_case implementer @NOTES @CODE/a.php)" "deny main"
expect "the implementer's Write of an owned file is allowed" "$(guarded_case implementer @NOTES @WT/a.php)" allow
expect "with the project remembered for the folder, the Write of the frozen test is refused" \
  "$(guarded_case implementer @NOTES @WT/tests/a_test.sh remembered)" "deny frozen"

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
