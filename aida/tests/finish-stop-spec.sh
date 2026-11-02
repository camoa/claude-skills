#!/usr/bin/env bash
# finish-stop-spec.sh: the fifth hard stop. At finish, a test that did not fail in the
# implement-start baseline and fails at the final commit stops completion. A failure already in the
# baseline is a warning. A regression no order takes is recorded as not caused by this task only by
# the person.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=records.bash
source "$HERE/records.bash"

# closed_task <baseline failures> <failures now>: wo1 closed with its test tests/a_test.sh frozen,
# and the suite's two runs. The records finish reads and nothing more.
closed_task() {
  task_records branch
  order_records closed
  suite_records "$1" "$2"
  tests_record
  jq -n '{schemaVersion: 1, unit: "wo1", findings: []}' >"$IMPL/review-wo1.json"
}

# A test the baseline passed fails now, and its file is wo1's frozen test: finish stops wo1 for a
# fix round and writes no finished.json.
broken_case() (
  source "$HERE/records.bash"
  closed_task "" "FAIL tests/a_test.sh"
  run "$IMPLEMENT" finish "$TASK"
  printf '%s|%s|%s\n' "$RC" "$(ledger '[.stopped[]? | .step + " " + (.allows | join(","))] | join(";")')" \
    "$([ -f "$IMPL/finished.json" ] && echo written || echo none)"
)
expect "a newly broken test stops finish on the order that owns it" "$(broken_case)" '66|finish fix|none'

# The same test failed in the baseline too: finish writes finished.json and a warning.
baseline_case() (
  source "$HERE/records.bash"
  closed_task "FAIL tests/a_test.sh" "FAIL tests/a_test.sh"
  run "$IMPLEMENT" finish "$TASK"
  printf '%s|%s|%s\n' "$RC" "$([ -f "$IMPL/finished.json" ] && echo written || echo none)" \
    "$(jq '[ (.warnings // [])[] | select(.step == "finish" and (.words | contains("baseline"))) ] | length' "$TASK/task.json")"
)
expect "a baseline failure is a warning, and finish writes finished.json" "$(baseline_case)" '0|written|1'

# A newly broken test in a file no order owns, recorded as not caused by this task with no
# person's answer: the answer guard refuses, and nothing is written.
refused_case() (
  source "$HERE/records.bash"
  closed_task "" "FAIL tests/old_test.sh"
  local before
  before="$(cksum <"$IMPL/ledger.json")"
  run "$IMPLEMENT" finish "$TASK" --regression "not-caused=FAIL tests/old_test.sh" --because "a flaky test"
  printf '%s|%s|%s\n' "$RC" "$([ "$(cksum <"$IMPL/ledger.json")" = "$before" ] && echo unchanged)" \
    "$([ -f "$IMPL/finished.json" ] && echo written || echo none)"
)
expect "not caused by this task refuses without the person's answer, and writes nothing" "$(refused_case)" '68|unchanged|none'

# With the person's answer, it is a warning that holds the person's words, and finish writes
# finished.json.
answered_case() (
  source "$HERE/records.bash"
  closed_task "" "FAIL tests/old_test.sh"
  answer "implement finish regression" "" "a flaky test"
  run "$IMPLEMENT" finish "$TASK" --regression "not-caused=FAIL tests/old_test.sh" --because "a flaky test"
  printf '%s|%s|%s\n' "$RC" "$([ -f "$IMPL/finished.json" ] && echo written || echo none)" \
    "$(jq '[ (.warnings // [])[] | select(.step == "finish" and (.words | contains("a flaky test"))) ] | length' "$TASK/task.json")"
)
expect "with the answer, not caused by this task is a warning with the person's words" "$(answered_case)" '0|written|1'

# stopped_on <failures now>: finish over a green baseline, then the exit and wo1's stops.
stopped_on() {
  closed_task "" "$1"
  [ -z "${2:-}" ] || { printf '%s\n' "$2" >>"$WT/tests/a_test.sh"; git -C "$WT" commit -qam "a test function"; }
  run "$IMPLEMENT" finish "$TASK"
  printf '%s|%s\n' "$RC" "$(ledger '[.stopped[]? | .step + " " + (.allows | join(","))] | join(";")')"
}

# A PHPUnit failure line names the test class, not its file. The frozen test file of that name is wo1's.
phpunit_case() ( source "$HERE/records.bash"; stopped_on '1) Drupal\Tests\x\a_test::testB' )
expect "a PHPUnit failure line goes to the order whose frozen test file the class names" "$(phpunit_case)" '66|finish fix'

# A Go failure line names the test function, which wo1's frozen test file defines.
go_case() ( source "$HERE/records.bash"; stopped_on '--- FAIL: TestA (0.00s)' '# func TestA(t *testing.T) {' )
expect "a Go failure line goes to the order whose frozen test file defines the function" "$(go_case)" '66|finish fix'

# A suite row with no failure_line: the run's banner and counts are no tests, so the whole run is
# one item for the person, and not caused by this task folds that run to met.
run_item_case() (
  source "$HERE/records.bash"
  closed_task "" "$(printf 'fake runner\nFAIL tests/old_test.sh\ntests failed')"
  answer "implement finish regression" "" "the environment"
  run "$IMPLEMENT" finish "$TASK" --regression "not-caused=the suite on fake" --because "the environment"
  printf '%s|%s\n' "$RC" "$(jq -r '.suite.verdict + " " + (.suite.runs | map(.verdict) | join(","))' "$IMPL/finished.json" 2>/dev/null)"
)
expect "a run with no failure_line is one item, and not caused by this task makes it met" "$(run_item_case)" '0|met met'

# The person gives a regression no rule assigns to wo1: wo1 stops for fix, and go-on fix opens its round.
assign_case() (
  source "$HERE/records.bash"
  closed_task "" "FAIL tests/old_test.sh"
  answer "implement finish regression" "" "wo1 broke it"
  run "$IMPLEMENT" finish "$TASK" --regression "wo1=the suite on fake" --because "wo1 broke it"
  printf '%s|%s|' "$RC" "$(ledger '[.stopped[]? | .step + " " + (.allows | join(","))] | join(";")')"
  answer "implement go-on fix" wo1 "fix it"
  run "$IMPLEMENT" go-on "$TASK" wo1 --continue fix --because "fix it"
  sed -n 's/^next: //p' "$OUT" | cut -d: -f1
)
expect "a regression the person gives to an order stops it, and go-on fix opens the round" "$(assign_case)" '66|finish fix|review wo1'

# Twenty-one new lines, the first twenty recorded not caused by this task: the twenty-first still stops finish.
many_case() (
  source "$HERE/records.bash"
  closed_task "" "$(printf 'FAIL %s\n' a b c d e f g h i j k l m n o p q r s t u)"
  jq '.notCaused = [ ("abcdefghijklmnopqrst" | split(""))[] | {line: ("FAIL " + .), because: "flaky", at: "2026-10-28"} ]' \
    "$IMPL/ledger.json" >"$ROOT/l.json" && mv "$ROOT/l.json" "$IMPL/ledger.json"
  run "$IMPLEMENT" finish "$TASK"
  printf '%s|%s\n' "$RC" "$([ -f "$IMPL/finished.json" ] && echo written || echo none)"
)
expect "a new line past the first twenty still stops finish" "$(many_case)" '66|none'

# A second framework whose suite crashed and printed nothing is an item of its own, beside the
# first framework's new line.
crash_case() (
  source "$HERE/records.bash"
  closed_task "" "FAIL tests/a_test.sh"
  printf 'exit 1\n' >"$ROOT/crash.sh"
  sed -e 's/^framework: fake$/framework: fake2/' -e "s#$ROOT/suite.sh#$ROOT/crash.sh#" "$RECIPE" >"$ROOT/recipe2.md"
  jq --arg r "$ROOT/recipe2.md" '.frameworks += [.frameworks[0] | .framework = "fake2" | .recipePath = $r]' \
    "$IMPL/preconditions.json" >"$ROOT/p.json" && mv "$ROOT/p.json" "$IMPL/preconditions.json"
  jq '.suite += [{framework: "fake2", verdict: "met", exitCode: 0, output: ""}]' "$IMPL/baseline.json" >"$ROOT/b.json" \
    && mv "$ROOT/b.json" "$IMPL/baseline.json"
  answer "implement finish regression" "" "the runner crashed"
  run "$IMPLEMENT" finish "$TASK" --regression "not-caused=the suite on fake2" --because "the runner crashed"
  printf '%s|%s\n' "$RC" "$(jq -r '[ (.notCaused // [])[] | .line ] | join(",")' "$IMPL/ledger.json")"
)
expect "a crashed framework stays an item beside another framework's new line" "$(crash_case)" '66|the suite on fake2'

finish
