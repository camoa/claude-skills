#!/usr/bin/env bash
# reopen-test-first-spec.sh: a failed task review that reopens an order proved by tests opens a
# test round before the fix round, and the repair's test freezes as a record of its own. An order
# proved another way goes straight to its fix round.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=records.bash
source "$HERE/records.bash"

# reopened <proof>: wo1, proved by <proof> and owning tests/*_test.sh, closed with its tests
# frozen, and a failed task review of the finish whose one finding fails c1 in a.php. Then reopen.
reopened() {
  task_records branch
  jq --arg p "$1" '.proof = $p | .ownedFiles = ["a.php", "tests/*_test.sh"]' \
    "$TASK/design/wo1.json" >"$ROOT/w.json" && mv "$ROOT/w.json" "$TASK/design/wo1.json"
  jq --arg h "$(records_hash_for "$TASK")" '.hash = $h' "$TASK/design-closed.json" >"$ROOT/d.json" \
    && mv "$ROOT/d.json" "$TASK/design-closed.json"
  git -C "$PROJECT" commit -qam "wo1 owns its tests folder"
  order_records closed
  suite_records ""
  tests_record
  local range
  range="$(jq -r '.startedFrom' "$IMPL/ledger.json")..$(git -C "$WT" rev-parse HEAD)"
  jq -n '{schemaVersion: 1, unit: "wo1", findings: []}' >"$IMPL/review-wo1.json"
  jq -n --arg r "$range" '{schemaVersion: 1, commitRange: $r}' >"$IMPL/finished.json"
  mkdir -p "$TASK/review"
  jq -n --arg r "$range" '{verdict: "failed", reviewedRange: $r,
      findings: [{id: "f1", disposition: "criterion", severity: "high", file: "a.php", lines: "",
        linkedTo: "c1", lens: "correctness", evidence: "a.php still says a"}]}' >"$TASK/review/review.json"
  run "$IMPLEMENT" reopen "$TASK"
}

# The next step names the test round, and fix-brief refuses until the repair's test is frozen.
tests_case() (
  source "$HERE/records.bash"
  reopened tests
  printf '%s|' "$(sed -n 's/^next: //p' "$OUT" | cut -d: -f1)"
  run "$IMPLEMENT" fix-brief "$TASK" wo1
  printf '%s\n' "$RC"
)
expect "reopen on a tests order opens a test round before the fix round" "$(tests_case)" 'tests wo1|121'

# The repair's failing test freezes as a new record. The original record is the same file, and
# the order stays in its fix step.
freeze_case() (
  source "$HERE/records.bash"
  reopened tests
  local before
  before="$(cksum <"$IMPL/tests-wo1.json")"
  printf 'echo a still says a\nexit 1\n' >"$WT/tests/a_bug_test.sh"
  printf 'a still says a\n' >"$IMPL/red-bug.txt"
  run "$IMPLEMENT" tests-freeze "$TASK" wo1 --test-glob 'tests/*_test.sh' --test-recipe "fake=$RECIPE" \
    --test "tests/a_bug_test.sh::bug=c1" --red "bug=$IMPL/red-bug.txt" --row "c1=confirmed::model::observes the bug"
  printf '%s|%s|%s|%s\n' "$RC" "$(jq -r '.unit + " " + .rows[0].tests[0].path' "$IMPL/tests-wo1-repair-1.json" 2>/dev/null)" \
    "$([ "$(cksum <"$IMPL/tests-wo1.json")" = "$before" ] && echo unchanged)" "$(ledger '.lastStep')"
)
expect "the repair's test freezes as a new record, and the original record is unchanged" "$(freeze_case)" \
  '0|wo1 tests/a_bug_test.sh|unchanged|reviewed'

# An order proved by observation has no test author, so its fix round opens at once.
observe_case() (
  source "$HERE/records.bash"
  reopened observe
  printf '%s|%s\n' "$(sed -n 's/^next: //p' "$OUT" | cut -d: -f1)" "$(ledger '[.repairs[] | has("testOwed")] | any')"
)
expect "reopen on an observe order opens the fix round directly" "$(observe_case)" 'review wo1|false'

# The repair's test author writes its new test file, and the hook refuses its write, by Write or by
# Bash, to the order's first frozen test.
author_case() (
  source "$HERE/records.bash"
  reopened tests
  dispatch_record test-author
  printf '%s|%s|%s\n' "$(write_hook "$(file "$WT/tests/a_test.sh")" aida:test-author)" \
    "$(write_hook "$(jq -nc '{command: "printf x > tests/a_test.sh"}')" aida:test-author)" \
    "$(write_hook "$(file "$WT/tests/a_bug_test.sh")" aida:test-author)"
)
expect "the repair's test author may write only its new test file" "$(author_case)" 'deny|deny|allow'

# A repair's record names the order it repairs, so design and start read no other order from it.
started_case() (
  source "$HERE/records.bash"
  task_records branch
  order_records planned
  jq -n '{unit: "wo1", rows: []}' >"$IMPL/tests-wo1-repair-1.json"
  # shellcheck source=/dev/null
  PLUGIN_ROOT="$PLUGIN" source "$PLUGIN/scripts/lib/task-helpers.sh"
  started_orders_json "$TASK"
)
expect "a repair's record adds no order to the started list" "$(started_case)" '["wo1"]'

finish
