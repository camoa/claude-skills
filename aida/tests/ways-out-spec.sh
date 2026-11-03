#!/usr/bin/env bash
# ways-out-spec.sh: a stopped order refuses tests, build and review until a person takes one of the
# three ways out. Attended at an interactive stage, a way out takes the person's answer from the
# chat. Unattended, it refuses without the recorded answer and writes nothing. go-on close needs the
# recorded answer in every mode. Each case sources the helper in a subshell, so it starts from fresh
# records.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=records.bash
source "$HERE/records.bash"

# stopped_case <action> <step>: the exit of <action> on wo1, stopped at <step>, and whether it wrote
# its brief.
stopped_case() (
  source "$HERE/records.bash"
  task_records branch
  order_records "$2" '["build"]'
  suite_records ""
  [ "$2" = planned ] || tests_record
  run "$IMPLEMENT" "$1" "$TASK" wo1
  printf '%s|%s\n' "$RC" "$(ls "$IMPL"/brief-wo1-* 2>/dev/null | wc -l | tr -d ' ')"
)

# read_case: the read's next line on wo1, stopped for one reason that allows fix.
read_case() (
  source "$HERE/records.bash"
  task_records branch
  order_records code-written '["fix"]'
  run "$IMPLEMENT" read "$TASK"
  sed -n 's/^next: //p' "$OUT"
)

# way_case <action> <words> [<args>...]: runs the way out on wo1, stopped for a build with one commit
# of its builder, with no person's answer. With AUTO set, implement runs autonomous. Prints the exit
# and whether the run left the ledger as it was. Then the jq filter in $LOOK runs over wo1's ledger
# entry, a.php's text follows, and $AFTER, when set, runs last.
way_case() (
  source "$HERE/records.bash"
  local action="$1" words="$2" same
  shift 2
  task_records branch ${WO2:+wo2}
  order_records code-written "${ALLOWS:-[\"build\"]}"
  order_commit
  [ -z "${AUTO:-}" ] || edit "$TASK/task.json" '.runMode = "autonomous"'
  cp "$IMPL/ledger.json" "$ROOT/ledger.before"
  run "$IMPLEMENT" "$action" "$TASK" wo1 "$@" --because "$words"
  same="$(cmp -s "$IMPL/ledger.json" "$ROOT/ledger.before" && echo same || echo changed)"
  printf '%s|%s|%s|%s' "$RC" "$same" "$(ledger "$LOOK")" "$(cat "$WT/a.php")"
  # Exit 3 is shared by many refusals and no field names this one, so its phrase identifies it.
  [ -z "${AFTER:-}" ] || { run "$IMPLEMENT" tests-brief "$TASK" wo2; printf '|%s:%s:%s' "$RC" "$(grep -q 'depends on wo1, which has no completion record' "$OUT" && echo dependency || echo other)" "$([ -e "$IMPL/brief-wo2-tests.json" ] && echo brief || echo none)"; }
  echo
)

echo "--- stopped: a stopped order refuses tests, build and review, and the read offers the ways out"
expect "tests-brief on a stopped order refuses and writes no brief" "$(stopped_case tests-brief planned)" "49|0"
expect "build-brief on a stopped order refuses and writes no brief" "$(stopped_case build-brief tests-frozen)" "49|0"
expect "review-brief on a stopped order refuses and writes no brief" "$(stopped_case review-brief checks-passed)" "49|0"
expect "stopped, the read offers the ways out the stop allows" "$(read_case)" \
  "finish: wo1 is stopped, so offer the ways out: go-on with fix, redo or drop"

echo "--- go-on: attended, a choice the stop allows clears it with no recorded answer; unattended, it refuses"
expect "go-on fix on a stop that allows build refuses, and writes nothing" \
  "$(LOOK='.stopped | length' way_case go-on "fix it" --continue fix)" "67|same|1|b"
expect "go-on build, attended, clears the stop with no recorded answer" \
  "$(LOOK='.stopped // "none"' way_case go-on "one more attempt" --continue build)" "0|changed|none|b"
expect "go-on build, autonomous, refuses with no answer and writes nothing" \
  "$(AUTO=1 LOOK='.stopped | length' way_case go-on "one more attempt" --continue build)" "68|same|1|b"
expect "go-on close, attended, still refuses with no answer and writes nothing" \
  "$(ALLOWS='["close"]' LOOK='.stopped | length' way_case go-on "close it" --continue close)" "68|same|1|b"

echo "--- redo: attended, the order is planned again and its commit reverted; unattended, it refuses"
expect "redo, attended" "$(ALLOWS='[]' LOOK='.lastStep' way_case redo "the test was wrong")" "0|changed|null|a"
expect "redo, autonomous" "$(AUTO=1 ALLOWS='[]' LOOK='.lastStep' way_case redo "the test was wrong")" "68|same|code-written|b"

echo "--- drop: attended, the order is dropped, reverted, and its dependent cannot start; unattended, it refuses"
expect "drop, attended" "$(ALLOWS='[]' WO2=1 AFTER=1 LOOK='.lastStep' way_case drop "not needed")" "0|changed|dropped|a|3:dependency:none"
expect "drop, autonomous" "$(AUTO=1 ALLOWS='[]' LOOK='.lastStep' way_case drop "not needed")" "68|same|code-written|b"

finish
