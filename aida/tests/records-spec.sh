#!/usr/bin/env bash
# records-spec.sh: tests/records.bash writes a task at each state a spec asks for, and the plugin's
# own readers and checks take it as that state. Each case sources the helper in a subshell, so it
# starts from fresh records.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=records.bash
source "$HERE/records.bash"

# line <name>: the value of the read's line <name>.
line() { sed -n "s/^$1: //p" "$OUT"; }

trunk_case() (
  source "$HERE/records.bash"
  task_records
  run "$IMPLEMENT" read "$TASK"
  printf '%s|%s\n' "$(line branch)" "$(line next)"
)
branch_case() (
  source "$HERE/records.bash"
  task_records branch
  run "$IMPLEMENT" read "$TASK"
  line branch
)
project_case() (
  source "$HERE/records.bash"
  task_records branch
  bash "$PLUGIN/scripts/check-project.sh" "$PROJECT" >/dev/null 2>&1
  echo "$?"
)
# What setup leaves unwritten: no person's answer and no open dispatch.
unwritten_case() (
  source "$HERE/records.bash"
  task_records branch
  order_records code-written
  ls "$TASK/person-answers.json" "$IMPL/dispatch.json" 2>/dev/null
)
planned_case() (
  source "$HERE/records.bash"
  task_records branch
  order_records planned
  run "$IMPLEMENT" read "$TASK"
  line 'order(wo1)' | sed 's/ |.*//'
)
second_case() (
  source "$HERE/records.bash"
  task_records branch wo2
  order_records planned
  run "$IMPLEMENT" read "$TASK"
  bash "$PLUGIN/scripts/check-design.sh" "$TASK" >/dev/null 2>&1
  printf '%s|%s\n' "$?" "$(line 'order(wo2)' | sed 's/ |.*//')"
)
stopped_case() (
  source "$HERE/records.bash"
  task_records branch
  order_records code-written '["fix"]'
  run "$IMPLEMENT" read "$TASK"
  line next
)
commit_case() (
  source "$HERE/records.bash"
  task_records branch
  order_records code-written
  order_commit
  printf '%s|%s\n' "$([ "$(ledger '.unrecordedCommits[0]')" = "$(git -C "$WT" rev-parse HEAD)" ] && echo listed)" \
    "$(git -C "$WT" show HEAD:a.php)"
)
answer_case() (
  source "$HERE/records.bash"
  task_records branch
  answer "implement redo" wo1 "redo it"
  export PLUGIN_ROOT="$PLUGIN"
  # shellcheck source=/dev/null
  source "$PLUGIN/scripts/lib/task-helpers.sh"
  task_answer_find "$TASK" "implement redo" wo1 "redo it" && echo found
)
# suite_case <failures now>: the suite verdict finish records over a baseline that failed on t_old.
suite_case() (
  source "$HERE/records.bash"
  task_records branch
  order_records closed
  suite_records "FAIL: t_old" "$1"
  run "$IMPLEMENT" finish "$TASK"
  jq -r '.suite.verdict' "$IMPL/finished.json"
)
# Every record the helper writes, each against its schema: prints each fault, or nothing.
schema_case() (
  source "$HERE/records.bash"
  # shellcheck source=/dev/null
  source "$PLUGIN/scripts/lib/schema-check.sh"
  task_records branch
  order_records code-written '["fix"]'
  order_commit
  suite_records "FAIL: t_old"
  tests_record
  local pair role
  for role in test-author implementer; do
    dispatch_record "$role"
    schema_check_compare "$PLUGIN/scripts/dispatch-schema.json" "$IMPL/dispatch.json" \
      | jq -r --arg n "dispatch $role" '(.missing + .unreadable)[] | "\($n): \(.field)"' || echo "dispatch $role: not compared"
  done
  for pair in project:"$PROJECT/project.json" registry:"$AIDA_REGISTRY_PATH" task:"$TASK/task.json" \
    alignment:"$TASK/alignment.json" design:"$TASK/design/wo1.json" design-closed:"$TASK/design-closed.json" \
    snapshot:"$IMPL/snapshot.json" ledger:"$IMPL/ledger.json" preconditions:"$IMPL/preconditions.json" \
    baseline:"$IMPL/baseline.json" tests-frozen:"$IMPL/tests-wo1.json"; do
    schema_check_compare "$PLUGIN/scripts/${pair%%:*}-schema.json" "${pair#*:}" \
      | jq -r --arg n "${pair%%:*}" '(.missing + .unreadable)[] | "\($n): \(.field)"' || echo "${pair%%:*}: not compared"
  done
)

echo "--- the task: the worktree holds the trunk unless the spec asks for the work branch"
expect "with no argument, the read sees the trunk and design closed" "$(trunk_case)" "main|start"
expect "with branch, the read sees the work branch" "$(branch_case)" "feature/t1"
expect "the project check passes the project, its registry row and its git repository" "$(project_case)" 0
expect "setup writes no person's answer and no dispatch" "$(unwritten_case)" ""

echo "--- the order: the read sees the step the ledger names"
expect "planned, the read sees the order not started" "$(planned_case)" "not started"
expect "with wo2, the design check passes and the read sees wo2" "$(second_case)" "0|not started"
expect "stopped, the read offers the ways out the stop allows" "$(stopped_case)" \
  "finish: wo1 is stopped, so offer the ways out: go-on with fix, redo or drop"
expect "the order's commit changes a.php and is listed on the order" "$(commit_case)" "listed|b"

echo "--- the answer, the suite and the schemas"
expect "the answer reader finds the person's answer" "$(answer_case)" "found"
expect "finish reads a failure the baseline holds as met" "$(suite_case "FAIL: t_old")" "met"
expect "finish reads a failure the baseline lacks as unmet" "$(suite_case "FAIL: t_old
FAIL: t_new")" "unmet"
expect "every record passes its schema" "$(schema_case)" ""

finish
