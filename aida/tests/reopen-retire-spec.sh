#!/usr/bin/env bash
# reopen-retire-spec.sh: a person rules a frozen test wrong before the task review (gap row 475).
# reopen --test sends the ruling to the closed order whose merged record holds the test, with the
# person's answer and no review. The repair freeze removes the named tests and nothing else, and
# its record names what it retires, so review stops counting them. Each case sources the helper in
# a subshell, so it starts from fresh records.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=records.bash
source "$HERE/records.bash"

RULING="tests/a_test.sh::a says b"
BECAUSE="the test reads the wrong file"

# closed_records [wo2]: wo1 closed over its build, with tests/a_test.sh frozen holding "a says b",
# and no finish. With wo2, wo2 is closed too.
closed_records() {
  task_records branch "$@"
  order_records closed
  suite_records ""
  tests_record
  edit "$IMPL/ledger.json" '(.orders[] | select(.id == "wo1")).commitRange = $r' \
    --arg r "$(jq -r '.startedFrom' "$IMPL/ledger.json")..$(git -C "$WT" rev-parse HEAD)"
  printf '{"schemaVersion": 1, "unit": "wo1", "findings": []}\n' >"$IMPL/review-wo1.json"
}

# finished_records: finish recorded over the worktree's commits.
finished_records() {
  jq -n --arg r "$(jq -r '.startedFrom' "$IMPL/ledger.json")..$(git -C "$WT" rev-parse HEAD)" \
    '{schemaVersion: 1, commitRange: $r, criteria: [{id: "c1", verifiedBy: "machine"}], checklists: []}' >"$IMPL/finished.json"
}

# retire [<ruling>]: reopen with the person's ruling on one frozen test.
retire() { run "$IMPLEMENT" reopen "$TASK" --test "${1:-$RULING}" --because "$BECAUSE"; }
answered() { answer "implement reopen" "" "${1:-$RULING}
$BECAUSE"; }

echo "--- reopen takes a person's ruling"
unanswered_case() (
  source "$HERE/records.bash"
  closed_records
  retire
  printf '%s|%s\n' "$RC" "$(ledger '.repairs // [] | length')"
)
expect "reopen --test with no answer refuses and writes no repair" "$(unanswered_case)" "68|0"

answered_case() (
  source "$HERE/records.bash"
  closed_records
  answered
  retire
  printf '%s|%s|%s|%s|%s|%s\n' "$RC" "$(ledger '.repairs[0].retires | join(",")')" \
    "$(ledger '.repairs[0].retiredTests | map(.path + "::" + .name) | join(",")')" "$(ledger '.repairs[0].testOwed')" \
    "$(ledger '.lastStep')" "$(jq -r '[ .findings[] | .file ] | join(",")' "$IMPL/review-wo1.json")"
)
expect "reopen --test with the answer sends the ruling to the closed order" "$(answered_case)" \
  "0|tests/a_test.sh|tests/a_test.sh::a says b|true|reviewed|tests/a_test.sh"

# open_owner_case <step>: the owner at <step>, with the answer.
open_owner_case() (
  source "$HERE/records.bash"
  closed_records
  edit "$IMPL/ledger.json" '(.orders[] | select(.id == "wo1")).lastStep = $s' --arg s "$1"
  answered
  local before
  before="$(cksum <"$IMPL/ledger.json")"
  retire
  printf '%s|%s\n' "$RC" "$([ "$(cksum <"$IMPL/ledger.json")" = "$before" ] && echo unchanged)"
)
expect "an owner at checks-passed closes first" "$(open_owner_case checks-passed)" "119|unchanged"
expect "an owner at tests-frozen takes the retake or redo" "$(open_owner_case tests-frozen)" "119|unchanged"

open_review_case() (
  source "$HERE/records.bash"
  closed_records
  finished_records
  mkdir -p "$TASK/review"
  jq -n --arg r "$(jq -r '.commitRange' "$IMPL/finished.json")" '{reviewedRange: $r, findings: []}' >"$TASK/review/review.json"
  answered
  retire
  printf '%s|%s\n' "$RC" "$([ -f "$IMPL/finished.json" ] && echo kept)"
)
expect "an open task review of the finish refuses until it closes" "$(open_review_case)" "119|kept"

both_sources_case() (
  source "$HERE/records.bash"
  closed_records wo2
  printf '{"schemaVersion": 1, "unit": "wo2", "findings": []}\n' >"$IMPL/review-wo2.json"
  finished_records
  mkdir -p "$TASK/review"
  jq -n --arg r "$(jq -r '.commitRange' "$IMPL/finished.json")" '{verdict: "failed", reviewedRange: $r,
      findings: [{id: "f1", disposition: "criterion", severity: "high", file: "b.php", lines: "",
        linkedTo: "c2", lens: "correctness", evidence: "b.php is missing"}]}' >"$TASK/review/review.json"
  answered
  retire
  printf '%s|%s|%s\n' "$RC" "$(jq '[ .orders[] | select((.repairs // []) != []) ] | length' "$IMPL/ledger.json")" \
    "$([ -f "$IMPL/finished.json" ] && echo kept || echo removed)"
)
expect "a closed review's findings and the person's ruling route in one call" "$(both_sources_case)" "0|2|removed"

no_review_case() (
  source "$HERE/records.bash"
  closed_records
  finished_records
  answered
  retire
  printf '%s|%s|%s\n' "$RC" "$(ledger '.repairs | length')" "$([ -f "$IMPL/finished.json" ] && echo kept || echo removed)"
)
expect "a finish with no task review routes the ruling" "$(no_review_case)" "0|1|removed"

unknown_name_case() (
  source "$HERE/records.bash"
  closed_records
  answered "tests/a_test.sh::a says c"
  retire "tests/a_test.sh::a says c"
  printf '%s\n' "$RC"
)
expect "a test name the frozen record does not hold is an argument fault" "$(unknown_name_case)" "3"

echo "--- the repair freeze removes the named tests and nothing else"
# three_records: wo1 owes the test round for the person's ruling on "a says b", in a file of three
# frozen tests, one line each.
three_records() {
  owed_records
  printf 'short() { :; }\nsays_b() { :; }\nlower() { :; }\n' >"$WT/tests/a_test.sh"
  git -C "$WT" commit -qam "three tests"
  edit "$IMPL/tests-wo1.json" '.commit = $c | .freezeCommits = [$c]
    | .rows[0].tests = [ "a is short", "a says b", "a is lower" | {path: "tests/a_test.sh", name: ., sha256: $sha, red: "x", redSignal: "unchecked"} ]' \
    --arg c "$(git -C "$WT" rev-parse HEAD)" --arg sha "$("${RECORDS_HASH_SHA256_CMD[@]}" "$WT/tests/a_test.sh" | cut -d' ' -f1)"
  edit "$IMPL/ledger.json" '(.orders[] | select(.id == "wo1")).repairs[0].retiredTests = [{path: "tests/a_test.sh", name: "a says b"}]'
  suite_records ""
}
# refreeze <test name>...: the repair freeze of tests/a_test.sh with these tests, each locked in.
refreeze() {
  local n args=()
  for n in "$@"; do args+=(--test "tests/a_test.sh::$n=c1" --locks-in "$n=the built a.php"); done
  run "$IMPLEMENT" tests-freeze "$TASK" wo1 --test-glob 'tests/*_test.sh' --test-recipe "fake=$RECIPE" "${args[@]}" \
    --row "c1=confirmed::model::reads a.php"
}

kept_case() (
  source "$HERE/records.bash"
  three_records
  sed -i '/says_b/d' "$WT/tests/a_test.sh"
  refreeze "a is short" "a is lower"
  printf '%s|%s|' "$RC" "$(jq -r '.retires | join(",")' "$IMPL/tests-wo1-repair-1.json" 2>/dev/null)"
  finished_records
  run "$REVIEW" checks "$TASK" --lookup-failed fake=no-recipe
  printf '%s\n' "$RC"
)
expect "a kept file with the named test's lines deleted freezes, and review reads it" "$(kept_case)" "0|tests/a_test.sh|0"

lost_case() (
  source "$HERE/records.bash"
  three_records
  sed -i '/says_b/d; /lower/d' "$WT/tests/a_test.sh"
  refreeze "a is short"
  printf '%s|%s\n' "$RC" "$([ -f "$IMPL/tests-wo1-repair-1.json" ] && echo written || echo none)"
)
expect "a kept file that also lost a test nobody named is refused" "$(lost_case)" "27|none"

edited_case() (
  source "$HERE/records.bash"
  three_records
  sed -i '/says_b/d; s/short() { :; }/short() { true; }/' "$WT/tests/a_test.sh"
  refreeze "a is short" "a is lower"
  printf '%s|%s\n' "$RC" "$([ -f "$IMPL/tests-wo1-repair-1.json" ] && echo written || echo none)"
)
expect "a kept file with a kept test changed is refused" "$(edited_case)" "27|none"

# deleted_records: wo1 owes the test round for the person's ruling on its one frozen test, and the
# test author deleted the file. Then the repair freeze, with no --test.
deleted_records() {
  owed_records
  edit "$IMPL/ledger.json" '(.orders[] | select(.id == "wo1")).repairs[0].retiredTests = [{path: "tests/a_test.sh", name: "a says b"}]'
  suite_records ""
  rm "$WT/tests/a_test.sh"
  run "$IMPLEMENT" tests-freeze "$TASK" wo1 --test-glob 'tests/*_test.sh'
}
deleted_case() (
  source "$HERE/records.bash"
  deleted_records
  printf '%s|%s|%s|%s|' "$RC" "$(jq -c '[.rows, .retires]' "$IMPL/tests-wo1-repair-1.json" 2>/dev/null)" \
    "$(git -C "$WT" cat-file -e HEAD:tests/a_test.sh 2>/dev/null && echo held || echo absent)" \
    "$([ "$(jq -r '.freezeCommits | join(",")' "$IMPL/tests-wo1-repair-1.json" 2>/dev/null)" = "$(git -C "$WT" rev-parse HEAD)" ] && echo head)"
  finished_records
  run "$REVIEW" checks "$TASK" --lookup-failed fake=no-recipe
  printf '%s\n' "$RC"
)
expect "a file whose every test is named is deleted in the freeze commit, and review reads it" "$(deleted_case)" \
  '0|[[],["tests/a_test.sh"]]|absent|head|0'

already_correct_case() (
  source "$HERE/records.bash"
  deleted_records
  jq -n --arg c "$(git -C "$WT" rev-parse HEAD~1)" '{schemaVersion: 1, unit: "wo1", reviewedAt: $c,
      findings: [{id: "f1", severity: "high", actionable: true, status: "open", file: "tests/a_test.sh", lines: "",
        linkedTo: "c1", evidence: "a person ruled a says b wrong", fixScope: ["tests/a_test.sh"]}]}' >"$IMPL/review-wo1.json"
  jq -n --arg r "$ROOT/fix-report.md" '{schemaVersion: 1, unit: "wo1", round: 1, reportPath: $r}' >"$IMPL/brief-wo1-fix-1.json"
  printf 'Outcome: f1: already-correct\n' >"$ROOT/fix-report.md"
  run "$IMPLEMENT" fix-record "$TASK" wo1 --report "$ROOT/fix-report.md" --started-at "$(git -C "$WT" rev-parse HEAD)"
  printf '%s\n' "$RC"
)
expect "the fix round takes already-correct on the deleted retired file" "$(already_correct_case)" "0"

echo "--- a criterion left with no test"
judged_case() (
  source "$HERE/records.bash"
  owed_records
  edit "$IMPL/ledger.json" '.criteria[0].judgements = [{unit: "wo1", verdict: "confirmed", judgedBy: "model", note: "n"}]
    | .criteria[0].rowState = "confirmed"'
  edit "$IMPL/ledger.json" '(.orders[] | select(.id == "wo1")).repairs[0].retiredTests = [{path: "tests/a_test.sh", name: "a says b"}]'
  suite_records ""
  rm "$WT/tests/a_test.sh"
  run "$IMPLEMENT" tests-freeze "$TASK" wo1 --test-glob 'tests/*_test.sh'
  printf '%s|%s|' "$(jq '[ .warnings[] | select(.step == "tests-freeze" and .order == "wo1") ] | length' "$TASK/task.json")" \
    "$(jq '[ .criteria[0].judgements[]? | select(.unit == "wo1") ] | length' "$IMPL/ledger.json")"
  finished_records
  run "$REVIEW" checks "$TASK" --lookup-failed fake=no-recipe
  jq -r '[ .checks[] | select(.id == "test-and-mutation") ][0].verdict' "$TASK/review/review.json"
)
expect "a freeze that leaves c1 with no test warns once, takes back the judgement, and review reads it unmet" \
  "$(judged_case)" "1|0|unmet"

run_line_case() (
  source "$HERE/records.bash"
  owed_records
  edit "$IMPL/snapshot.json" '(.workOrders[] | select(.id == "wo1")).verify = [{run: "true", pass: "exit 0", binding: true, criterion: "c1"}]'
  edit "$IMPL/ledger.json" '(.orders[] | select(.id == "wo1")).repairs[0].retiredTests = [{path: "tests/a_test.sh", name: "a says b"}]'
  suite_records ""
  rm "$WT/tests/a_test.sh"
  run "$IMPLEMENT" tests-freeze "$TASK" wo1 --test-glob 'tests/*_test.sh'
  printf '%s\n' "$RC"
)
expect "a repair freeze does not ask again for the row a verify run line proves" "$(run_line_case)" "0"

finish
