#!/usr/bin/env bash
# finish-stop-spec.sh: the fifth hard stop. At finish, a test that passed in the implement-start
# baseline and fails at the final commit stops completion. A failure already in the baseline is a
# warning. A regression no order takes is recorded as not caused by this task only by the person.
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

finish
