#!/usr/bin/env bash
# reopen-test-first-spec.sh: a failed task review that reopens an order proved by tests opens a
# test round before the fix round, and the repair's test freezes as a record of its own. An order
# proved another way goes straight to its fix round.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=records.bash
source "$HERE/records.bash"

# reopened <proof> [<fields JSON>]: wo1, proved by <proof> and owning README.md and tests/*_test.sh,
# closed with its tests frozen, and a failed task review of the finish whose one finding fails c1
# in a.php. The fields replace the finding's own. Then reopen.
reopened() {
  task_records branch
  jq --arg p "$1" '.proof = $p | .ownedFiles = ["a.php", "README.md", "tests/*_test.sh"]' \
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
  jq -n --arg r "$range" --argjson f "${2:-null}" '{verdict: "failed", reviewedRange: $r,
      findings: [{id: "f1", disposition: "criterion", severity: "high", file: "a.php", lines: "",
        linkedTo: "c1", lens: "correctness", evidence: "a.php still says a"} + $f]}' >"$TASK/review/review.json"
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

# A finding whose lens judges the shape of code, or whose file is a document, holds no logic for a
# test to prove, so its repair opens the fix round at once (row 479).
# shape_case <fields JSON>
shape_case() (
  source "$HERE/records.bash"
  reopened tests "$1"
  printf '%s|%s\n' "$(sed -n 's/^next: //p' "$OUT" | cut -d: -f1)" "$(ledger '[.repairs[] | has("testOwed")] | any')"
)
expect "a dry finding on a tests order owes no test" "$(shape_case '{"lens": "dry"}')" 'review wo1|false'
expect "a correctness finding in a document owes no test" "$(shape_case '{"file": "README.md"}')" 'review wo1|false'

# A finding reopen cannot write refuses, and finished.json stays, so nothing is lost.
broken_case() (
  source "$HERE/records.bash"
  reopened tests '{"evidence": 5}'
  printf '%s|%s\n' "$RC" "$([ -f "$IMPL/finished.json" ] && echo finished || echo removed)"
)
expect "reopen refuses when it cannot write a repair finding" "$(broken_case)" '3|finished'

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

# The repair's test author writes a new test file no order owns. A person adds it to wo1, with
# each owned file named, and closes design. The start that takes it in keeps that file in the tree
# and sets aside a stray one. With the test round closed, the file goes aside too (row 484). Prints
# start's exit, then where each file is.
# added_case [closed]
added_case() (
  source "$HERE/records.bash"
  reopened tests
  [ -z "${1:-}" ] || edit "$IMPL/ledger.json" '(.orders[] | select(.id == "wo1")).repairs |= map(del(.testOwed))'
  printf 'exit 1\n' >"$WT/tests/navigate_damaged.sh"
  printf 'x\n' >"$WT/stray.txt"
  edit "$TASK/design/wo1.json" '.ownedFiles = ["a.php", "README.md", "tests/a_test.sh", "tests/navigate_damaged.sh"]'
  edit "$TASK/design-closed.json" '.hash = $h' --arg h "$(records_hash_for "$TASK")"
  git -C "$PROJECT" commit -qam "wo1 owns the repair's new test"
  run "$IMPLEMENT" start "$TASK"
  printf '%s|%s|%s\n' "$RC" "$([ -f "$WT/tests/navigate_damaged.sh" ] && echo kept || echo aside)" \
    "$([ -f "$WT/stray.txt" ] && echo kept || echo aside)"
)
expect "start keeps the open repair's new test file and sets aside a stray one" "$(added_case)" '0|kept|aside'
expect "start sets aside an owned new file once the test round is closed" "$(added_case closed)" '0|aside|aside'

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
