#!/usr/bin/env bash
# ways-out-spec.sh: a stopped order refuses tests, build and review until a person takes one of the
# three ways out. Each way out refuses without the person's answer and writes nothing, and works
# with it. Each case sources the helper in a subshell, so it starts from fresh records.
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

# way_case <action> <answer step> <words> [<args>...]: runs the way out on wo1, stopped for a build
# with one commit of its builder, first with no answer and then with one. Prints the first exit,
# whether that run left the ledger as it was, and the second exit. Then the jq filter in $LOOK runs
# over wo1's ledger entry, a.php's text follows, and $AFTER, when set, runs last.
way_case() (
  source "$HERE/records.bash"
  local action="$1" step="$2" words="$3" first same
  shift 3
  task_records branch ${WO2:+wo2}
  order_records code-written "${ALLOWS:-[\"build\"]}"
  order_commit
  cp "$IMPL/ledger.json" "$ROOT/ledger.before"
  run "$IMPLEMENT" "$action" "$TASK" wo1 "$@" --because "$words"
  first="$RC"
  same="$(cmp -s "$IMPL/ledger.json" "$ROOT/ledger.before" && echo same || echo changed)"
  answer "$step" wo1 "$words"
  run "$IMPLEMENT" "$action" "$TASK" wo1 "$@" --because "$words"
  printf '%s|%s|%s|%s|%s' "$first" "$same" "$RC" "$(ledger "$LOOK")" "$(cat "$WT/a.php")"
  # Exit 3 is shared by many refusals and no field names this one, so its phrase identifies it.
  [ -z "${AFTER:-}" ] || { run "$IMPLEMENT" tests-brief "$TASK" wo2; printf '|%s:%s:%s' "$RC" "$(grep -q 'depends on wo1, which has no completion record' "$OUT" && echo dependency || echo other)" "$([ -e "$IMPL/brief-wo2-tests.json" ] && echo brief || echo none)"; }
  echo
)

echo "--- stopped: a stopped order refuses tests, build and review"
expect "tests-brief on a stopped order refuses and writes no brief" "$(stopped_case tests-brief planned)" "49|0"
expect "build-brief on a stopped order refuses and writes no brief" "$(stopped_case build-brief tests-frozen)" "49|0"
expect "review-brief on a stopped order refuses and writes no brief" "$(stopped_case review-brief checks-passed)" "49|0"

echo "--- go-on: a choice the stop does not allow refuses; an allowed one clears the stop"
expect "go-on fix on a stop that allows build refuses with the answer, and writes nothing" \
  "$(LOOK='.stopped | length' way_case go-on "implement go-on fix" "fix it" --continue fix)" "68|same|67|1|b"
expect "go-on build refuses with no answer and writes nothing, and with the answer clears the stop" \
  "$(LOOK='.stopped // "none"' way_case go-on "implement go-on build" "one more attempt" --continue build)" "68|same|0|none|b"

echo "--- redo: refuses with no answer; with it, the order is planned again and its commit reverted"
expect "redo" "$(ALLOWS='[]' LOOK='.lastStep' way_case redo "implement redo" "the test was wrong")" "68|same|0|null|a"

echo "--- drop: refuses with no answer; with it, the order is dropped, reverted, and its dependent cannot start"
expect "drop" "$(ALLOWS='[]' WO2=1 AFTER=1 LOOK='.lastStep' way_case drop "implement drop" "not needed")" "68|same|0|dropped|a|3:dependency:none"

finish
