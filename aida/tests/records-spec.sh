#!/usr/bin/env bash
# records-spec.sh: tests/records.bash writes a task at each state a spec asks for, and the plugin's
# own readers take it as that state. Each case sources the helper in a subshell, so it starts from
# fresh records.
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
planned_case() (
  source "$HERE/records.bash"
  task_records branch
  order_records planned
  run "$IMPLEMENT" read "$TASK"
  line 'order(wo1)' | sed 's/ |.*//'
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
# Every record the helper writes, each against its schema: prints each fault, or nothing.
schema_case() (
  source "$HERE/records.bash"
  # shellcheck source=/dev/null
  source "$PLUGIN/scripts/lib/schema-check.sh"
  task_records branch
  order_records code-written '["fix"]'
  order_commit
  local pair
  for pair in project:"$PROJECT/project.json" registry:"$AIDA_REGISTRY_PATH" task:"$TASK/task.json" \
    alignment:"$TASK/alignment.json" design:"$TASK/design/wo1.json" design-closed:"$TASK/design-closed.json" \
    snapshot:"$IMPL/snapshot.json" ledger:"$IMPL/ledger.json"; do
    schema_check_compare "$PLUGIN/scripts/${pair%%:*}-schema.json" "${pair#*:}" \
      | jq -r --arg n "${pair%%:*}" '(.missing + .unreadable)[] | "\($n): \(.field)"' || echo "${pair%%:*}: not compared"
  done
)

echo "--- the task: the worktree holds the trunk unless the spec asks for the work branch"
expect "with no argument, the read sees the trunk and design closed" "$(trunk_case)" "main|start"
expect "with branch, the read sees the work branch" "$(branch_case)" "feature/t1"

echo "--- the order: the read sees the step the ledger names"
expect "planned, the read sees the order not started" "$(planned_case)" "not started"
expect "stopped, the read offers the ways out the stop allows" "$(stopped_case)" \
  "finish: wo1 is stopped, so offer the ways out: go-on with fix, redo or drop"
expect "the order's commit changes a.php and is listed on the order" "$(commit_case)" "listed|b"

echo "--- the answer and the schemas"
expect "the answer reader finds the person's answer" "$(answer_case)" "found"
expect "every record passes its schema" "$(schema_case)" ""

finish
