#!/usr/bin/env bash
# records-spec.sh: tests/records.bash writes no step a spec guards, and every record it writes
# passes the plugin's own checks. Each case sources the helper in a subshell, so it starts from
# fresh records.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=records.bash
source "$HERE/records.bash"

# What setup leaves unwritten: no person's answer and no open dispatch.
unwritten_case() (
  source "$HERE/records.bash"
  task_records branch
  order_records code-written
  ls "$TASK/person-answers.json" "$IMPL/dispatch.json" 2>/dev/null
)
# Every record the helper writes, each against its schema, and the project check over the
# project: prints each fault, or nothing.
schema_case() (
  source "$HERE/records.bash"
  # shellcheck source=/dev/null
  source "$PLUGIN/scripts/lib/schema-check.sh"
  task_records branch
  bash "$PLUGIN/scripts/check-project.sh" "$PROJECT" >/dev/null 2>&1 || echo "project check: $?"
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

expect "setup writes no person's answer and no dispatch" "$(unwritten_case)" ""
expect "every record passes its schema, and the project passes the project check" "$(schema_case)" ""

finish
