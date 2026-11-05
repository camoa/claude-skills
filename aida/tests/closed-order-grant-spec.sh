#!/usr/bin/env bash
# closed-order-grant-spec.sh: a person's grant, at another order's fix round, of a file a closed
# order owns reopens that order for a repair round, and the granting order waits until it closes
# again (gap row 433). A builder's closed-order-defect stop gives a tests order its failing test
# first too.
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

# The failing test is owed by the granted file, not by the granting order's findings: a grant of a
# text file owes none, and the owner's fix round opens at once (gap row 493). The same holds for a
# builder's closed-order-defect stop.
text_case() (
  source "$HERE/records.bash"
  in_review closed
  edit "$IMPL/snapshot.json" '(.workOrders[] | select(.id == "wo1") | .ownedFiles) += ["services.yml"]'
  answer "implement fix-brief" wo2 "services.yml"
  run "$IMPLEMENT" fix-brief "$TASK" wo2 --allow services.yml
  printf '%s|%s\n' "$RC" "$(ledger '(.repairs[0].by // "norepair") + " " + (.repairs[0].testOwed // "none")')"
)
expect "a grant of a text file owes no failing test" "$(text_case)" '0|wo2 none'

# Attended at an interactive stage, the grant still needs the recorded answer: with none it
# refuses, and wo1 is not reopened.
unanswered_case() (
  source "$HERE/records.bash"
  in_review closed
  run "$IMPLEMENT" fix-brief "$TASK" wo2 --allow a.php
  printf '%s|%s\n' "$RC" "$(ledger '.lastStep')"
)
expect "an attended grant with no recorded answer refuses" "$(unanswered_case)" '100|closed'

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

# A dropped owner releases the order that granted it a file: its next fix round opens.
dropped_case() (
  source "$HERE/records.bash"
  in_review closed
  answer "implement fix-brief" wo2 "a.php"
  run "$IMPLEMENT" fix-brief "$TASK" wo2 --allow a.php
  edit "$IMPL/ledger.json" '(.orders[] | select(.id == "wo1")).lastStep = "dropped"'
  run "$IMPLEMENT" fix-brief "$TASK" wo2
  printf '%s|%s\n' "$RC" "$([ -f "$IMPL/brief-wo2-fix-1.json" ] && echo brief || echo none)"
)
expect "a dropped owner no longer holds the order that granted it a file" "$(dropped_case)" '0|brief'

# A builder's stop on a defect in the closed tests order's file reopens it the same way: its
# failing test comes first.
builder_case() (
  source "$HERE/records.bash"
  in_review closed
  edit "$IMPL/ledger.json" '(.orders[] | select(.id == "wo2")).lastStep = "tests-frozen"'
  sed 's/wo1/wo2/' "$IMPL/tests-wo1.json" >"$IMPL/tests-wo2.json"
  printf 'Stop: closed-order-defect: a.php: a.php is wrong\nDeviation: none\n' >"$IMPL/answers-wo2-attempt1.md"
  run "$IMPLEMENT" build-record "$TASK" wo2 --report "$IMPL/answers-wo2-attempt1.md" --interface "$IMPL/interface-wo2.md" --started-at "$(git -C "$WT" rev-parse HEAD)"
  printf '%s|%s|%s\n' "$RC" "$(ledger '.repairs[0].by + " " + (.repairs[0].testOwed | tostring)')" "$(sed -n 's/^next: //p' "$OUT" | cut -d: -f1)"
)
expect "a builder's closed-order-defect on a tests order owes the failing test first" "$(builder_case)" '0|wo2 true|tests wo1'

# The same file test applies to a builder's stop on a defect in a closed tests order's text file.
builder_text_case() (
  source "$HERE/records.bash"
  in_review closed
  edit "$IMPL/snapshot.json" '(.workOrders[] | select(.id == "wo1") | .ownedFiles) += ["services.yml"]'
  edit "$IMPL/ledger.json" '(.orders[] | select(.id == "wo2")).lastStep = "tests-frozen"'
  sed 's/wo1/wo2/' "$IMPL/tests-wo1.json" >"$IMPL/tests-wo2.json"
  printf 'Stop: closed-order-defect: services.yml: the key is wrong\nDeviation: none\n' >"$IMPL/answers-wo2-attempt1.md"
  run "$IMPLEMENT" build-record "$TASK" wo2 --report "$IMPL/answers-wo2-attempt1.md" --interface "$IMPL/interface-wo2.md" --started-at "$(git -C "$WT" rev-parse HEAD)"
  printf '%s|%s\n' "$RC" "$(ledger '(.repairs[0].by // "norepair") + " " + (.repairs[0].testOwed // "none")')"
)
expect "a builder's closed-order-defect in a text file owes no failing test" "$(builder_text_case)" '0|wo2 none'

# A person takes a row of an open order's review into that order's own fix (gap row 488).
# in_take <rows JSON>: wo1 closed, and wo2 reviewed with a review record holding only the given
# rows, {findings, information}.
in_take() {
  in_review closed
  jq -n --argjson r "$1" '{schemaVersion: 1, unit: "wo2", findings: []} + $r' >"$IMPL/review-wo2.json"
}
info() { jq -nc --arg f "$1" --argjson d "${2:-false}" '{information: [{id: "i1", summary: "out can overwrite its input", file: $f, lines: "3", departsFromDesign: $d}]}'; }
wo2() { jq -r ".orders[] | select(.id == \"wo2\") | $1" "$IMPL/ledger.json"; }
review2() { jq -r "$1" "$IMPL/review-wo2.json"; }

take_case() (
  source "$HERE/records.bash"
  in_take "$(info b.php)"
  run "$IMPLEMENT" fix-brief "$TASK" wo2 --take i1 --because "fix it here"
  printf '%s|%s|%s|%s|%s|%s\n' "$RC" "$(review2 '.information[0].takenAs')" \
    "$(review2 '.findings[-1] | "\(.id) \(.linkedTo) \(.fixScope | tojson) \(.origin)"')" "$(wo2 '.repairs[0].testOwed')" \
    "$(sed -n 's/^next: //p' "$OUT" | cut -d: -f1)" "$([ -f "$IMPL/brief-wo2-fix-1.json" ] && echo brief || echo none)"
)
expect "a taken information row becomes a repair finding that owes its test first" "$(take_case)" \
  '0|f1|f1 c2 ["b.php"] repair|true|tests wo2|none'

# A row on a text file owes no test: the round opens in the same call with one round more, and
# close waits for the fix.
take_text_case() (
  source "$HERE/records.bash"
  in_take "$(info README.md)"
  edit "$IMPL/snapshot.json" '(.workOrders[] | select(.id == "wo2") | .ownedFiles) += ["README.md"]'
  run "$IMPLEMENT" fix-brief "$TASK" wo2 --take i1 --because "fix it here"
  printf '%s|%s|%s|%s|' "$RC" "$(wo2 '.repairs[0].testOwed // "none"')" \
    "$(jq -c '[ .findings[].id ]' "$IMPL/brief-wo2-fix-1.json" 2>/dev/null)" "$(sed -n 's/^round: //p' "$OUT")"
  run "$IMPLEMENT" close "$TASK" wo2
  printf '%s\n' "$RC"
)
expect "a taken row on a text file opens the round at once, one round more, and close waits" "$(take_text_case)" \
  '0|none|["f1"]|1 of 3|59'

# A finding that cites nothing is taken the same way, and stays in the record as the reviewer wrote it.
take_uncited_case() (
  source "$HERE/records.bash"
  in_take '{"findings": [{"id": "f1", "severity": "medium", "file": "b.php", "lines": "", "linkedTo": "", "evidence": "b.php reads twice",
    "fixScope": ["b.php"], "actionable": false, "status": "open", "origin": "review"}]}'
  run "$IMPLEMENT" fix-brief "$TASK" wo2 --take f1 --because "fix it here"
  printf '%s|%s|%s\n' "$RC" "$(review2 '.findings[1] | "\(.id) \(.linkedTo) \(.actionable)"')" \
    "$(review2 '.findings[0] | "\(.actionable) \(.takenAs)"')"
)
expect "a finding that cites nothing is taken into a new repair finding" "$(take_uncited_case)" '0|f2 c2 true|false f2'

# take_refused_case <kind> <phrase>: the take refuses (exit 3) with the guard's own phrase, and the
# review record and the ledger stay as they were. The phrase is the output under test: an unknown
# flag also exits 3.
take_refused_case() (
  source "$HERE/records.bash"
  local args="--take i1" before
  case "$1" in
    open) in_review closed
      edit "$IMPL/review-wo2.json" '. + $i' --argjson i "$(info b.php)" ;;
    unknown) in_take "$(info b.php)"; args="--take i9" ;;
    taken) in_take "$(info b.php | jq -c '.information[0].takenAs = "f1"')" ;;
    departs) in_take "$(info b.php true)" ;;
    other) in_take "$(info a.php)" ;;
    frozen) in_take "$(info tests/b_test.sh)"
      edit "$IMPL/snapshot.json" '(.workOrders[] | select(.id == "wo2") | .ownedFiles) += ["tests/b_test.sh"]'
      jq '.unit = "wo2" | .rows[0].tests[0].path = "tests/b_test.sh"' "$IMPL/tests-wo1.json" >"$IMPL/tests-wo2.json" ;;
    allow) in_take "$(info b.php)"; args="--take i1 --allow b.php" ;;
  esac
  before="$(cat "$IMPL/review-wo2.json" "$IMPL/ledger.json" | cksum)"
  # shellcheck disable=SC2086 # the flags split on purpose
  run "$IMPLEMENT" fix-brief "$TASK" wo2 $args --because "fix it here"
  printf '%s|%s|%s\n' "$RC" "$([ "$(cat "$IMPL/review-wo2.json" "$IMPL/ledger.json" | cksum)" = "$before" ] && echo same || echo changed)" \
    "$(grep -qF -- "$2" "$OUT" && echo named || echo unnamed)"
)
while IFS='|' read -r kind phrase; do
  expect "a take refuses: $kind" "$(take_refused_case "$kind" "$phrase")" '3|same|named'
done <<'REFUSALS'
open|has an open actionable finding
unknown|names no information item
taken|was taken already
departs|departs from the design
other|does not own
frozen|a frozen test
allow|--take and --allow go in two calls
REFUSALS

# Unattended, the take needs the person's recorded answer: the take values one per line, then the
# words.
take_gate_case() (
  source "$HERE/records.bash"
  unset CLAUDE_CODE_SESSION_ATTENDED
  in_take "$(info b.php)"
  run "$IMPLEMENT" fix-brief "$TASK" wo2 --take i1 --because x
  printf '%s|%s|' "$RC" "$(review2 '.information[0].takenAs // "none"')"
  answer "implement fix-brief" wo2 "i1
x"
  run "$IMPLEMENT" fix-brief "$TASK" wo2 --take i1 --because x
  printf '%s\n' "$RC"
)
expect "an unattended take refuses without the recorded answer, and runs with it" "$(take_gate_case)" '100|none|0'

# An order that depends on one with a taken row sees that the row went to a fix.
take_dependent_case() (
  source "$HERE/records.bash"
  in_review closed
  edit "$IMPL/ledger.json" '(.orders[] | select(.id == "wo2")).lastStep = null'
  info a.php | jq '{schemaVersion: 1, unit: "wo1", findings: []} + . | .information[0].takenAs = "f1"' >"$IMPL/review-wo1.json"
  run "$IMPLEMENT" tests-brief "$TASK" wo2
  printf '%s|%s\n' "$RC" "$(jq -r '.dependencyInformation[0].takenAs' "$IMPL/brief-wo2-tests.json" 2>/dev/null)"
)
expect "a dependent order's brief carries the take" "$(take_dependent_case)" '0|f1'

finish
