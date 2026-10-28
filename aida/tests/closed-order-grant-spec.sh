#!/usr/bin/env bash
# closed-order-grant-spec.sh: a person's grant, at another order's fix round, of a file a closed
# order owns reopens that order for a repair round, and the granting order waits until it closes
# again (gap row 433).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=records.bash
source "$HERE/records.bash"

# in_review <wo1 step>: wo1 at that step with its tests frozen, and wo2 in review with one open
# finding whose fix scope is its own b.php.
in_review() {
  task_records branch wo2
  order_records closed
  test_recipe
  tests_record
  edit "$IMPL/ledger.json" '.orders |= map(if .id == "wo2" then .lastStep = "reviewed" else .lastStep = $s end)' --arg s "$1"
  jq -n '{schemaVersion: 1, unit: "wo1", findings: []}' >"$IMPL/review-wo1.json"
  jq -n '{schemaVersion: 1, unit: "wo2", findings: [{id: "f1", severity: "high", file: "b.php", lines: "",
      linkedTo: "c2", evidence: "b.php fails because a.php is wrong", fixScope: ["b.php"],
      actionable: true, status: "open", origin: "review"}]}' >"$IMPL/review-wo2.json"
  jq -n --arg c "$(git -C "$WT" rev-parse HEAD)" '{schemaVersion: 1, unit: "wo2", commit: $c, commits: []}' >"$IMPL/build-wo2.json"
}

# The grant reopens wo1 with a repair finding on a.php that owes a failing test first, and writes
# no brief for wo2. wo2's next fix-brief waits for wo1.
grant_case() (
  source "$HERE/records.bash"
  in_review closed
  answer "implement fix-brief" wo2 "a.php"
  run "$IMPLEMENT" fix-brief "$TASK" wo2 --allow a.php
  printf '%s|%s|%s|%s|%s|' "$RC" "$(ledger '.lastStep')" "$(ledger '.repairs[0].by + " " + (.repairs[0].testOwed | tostring)')" \
    "$(jq -c '.findings[-1].fixScope' "$IMPL/review-wo1.json")" "$([ -f "$IMPL/brief-wo2-fix-1.json" ] && echo brief || echo none)"
  printf '%s|' "$(sed -n 's/^next: //p' "$OUT" | cut -d: -f1)"
  run "$IMPLEMENT" fix-brief "$TASK" wo2
  printf '%s\n' "$RC"
)
expect "a grant of a closed order's file reopens it, and the granting order waits" "$(grant_case)" \
  '0|reviewed|wo2 true|["a.php"]|none|tests wo1|40'

# An owner that is not closed is not reopened: the grant refuses as before.
open_case() (
  source "$HERE/records.bash"
  in_review code-written
  answer "implement fix-brief" wo2 "a.php"
  run "$IMPLEMENT" fix-brief "$TASK" wo2 --allow a.php
  printf '%s|%s\n' "$RC" "$(ledger '.repairs // [] | length')"
)
expect "a grant of a file an open order owns still refuses" "$(open_case)" '3|0'

# A frozen test of the closed order is never granted.
frozen_case() (
  source "$HERE/records.bash"
  in_review closed
  answer "implement fix-brief" wo2 "tests/a_test.sh"
  run "$IMPLEMENT" fix-brief "$TASK" wo2 --allow tests/a_test.sh
  printf '%s|%s\n' "$RC" "$(ledger '.lastStep')"
)
expect "a grant of the closed order's frozen test refuses" "$(frozen_case)" '3|closed'

finish
