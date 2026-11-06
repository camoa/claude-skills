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
expect "go-on --owns, attended, still refuses with no answer and writes nothing" \
  "$(LOOK='.stopped | length' way_case go-on "give b.php" --continue build --owns b.php)" "68|same|1|b"
expect "go-on close, attended, still refuses with no answer and writes nothing" \
  "$(ALLOWS='["close"]' LOOK='.stopped | length' way_case go-on "close it" --continue close)" "68|same|1|b"

echo "--- redo: attended, the order is planned again and its commit reverted; unattended, it refuses"
expect "redo, attended" "$(ALLOWS='[]' LOOK='.lastStep' way_case redo "the test was wrong")" "0|changed|null|a"
expect "redo, autonomous" "$(AUTO=1 ALLOWS='[]' LOOK='.lastStep' way_case redo "the test was wrong")" "68|same|code-written|b"

echo "--- drop: attended, the order is dropped, reverted, and its dependent cannot start; unattended, it refuses"
expect "drop, attended" "$(ALLOWS='[]' WO2=1 AFTER=1 LOOK='.lastStep' way_case drop "not needed")" "0|changed|dropped|a|3:dependency:none"
expect "drop, autonomous" "$(AUTO=1 ALLOWS='[]' LOOK='.lastStep' way_case drop "not needed")" "68|same|code-written|b"

# after_case <action> <file>...: wo1 frozen, then one commit no record of it lists, changing each
# <file>. Runs <action> attended. With KEEP set, a person first reverts that commit and commits
# other.php again alone. Prints the exit, whether the ledger changed, a.php's text, whether other.php
# is there, and how many lines of the action's output name that commit.
after_case() (
  source "$HERE/records.bash"
  local action="$1" f c
  shift
  task_records branch
  order_records tests-frozen
  tests_record
  [ -z "${SHARED:-}" ] || edit "$TASK/design/wo1.json" '.sharedFiles = ["a.php"]'
  [ -z "${SHARED:-}" ] || { edit "$IMPL/snapshot.json" '.workOrders[0].sharedFiles = ["a.php"]'; close_design; }
  for f in "$@"; do printf 'b\n' >"$WT/$f"; done
  git -C "$WT" add "$@" && git -C "$WT" commit -qm "a commit before the record"
  c="$(git -C "$WT" rev-parse --short=7 HEAD)"
  if [ -n "${KEEP:-}" ]; then
    git -C "$WT" revert --no-edit HEAD >/dev/null
    printf 'b\n' >"$WT/other.php"
    git -C "$WT" add other.php && git -C "$WT" commit -qm "other.php stays"
  fi
  cp "$IMPL/ledger.json" "$ROOT/ledger.before"
  run "$IMPLEMENT" "$action" "$TASK" wo1 --because "the design changed"
  printf '%s|%s|%s|%s|%s\n' "$RC" "$(cmp -s "$IMPL/ledger.json" "$ROOT/ledger.before" && echo same || echo changed)" \
    "$(cat "$WT/a.php")" "$([ -e "$WT/other.php" ] && echo other || echo none)" "$(grep -c "$c" "$OUT")"
)

# after_listed: the refused commit a person reverted, then redo. Prints the commits unattributed
# names, so a commit and its revert leave no loose end.
after_listed() (
  source "$HERE/records.bash"
  task_records branch
  order_records tests-frozen
  tests_record
  printf 'b\n' >"$WT/a.php"; printf 'b\n' >"$WT/other.php"
  git -C "$WT" add a.php other.php && git -C "$WT" commit -qm "a commit before the record"
  git -C "$WT" revert --no-edit HEAD >/dev/null
  run "$IMPLEMENT" redo "$TASK" wo1 --because "the design changed"
  run "$IMPLEMENT" unattributed "$TASK"
  cat "$OUT"
)

# after_record_case: a record order, whose range lives in the project folder. After its freeze, one
# commit there changes its document and one changes only a record of the task, as AIDA's own writes
# do. Prints the exit, whether the document is there, and whether the task record kept its change.
after_record_case() (
  source "$HERE/records.bash"
  task_records branch
  edit "$TASK/design/wo1.json" '.proof = "record" | .tests = [] | .interface = "" | .ownedFiles = [$doc]' --arg doc "$PROJECT/notes/a.md"
  close_design
  order_records tests-frozen
  git -C "$PROJECT" add -A && git -C "$PROJECT" commit -qm "wo1 is a record order"
  jq -n --arg c "$(git -C "$PROJECT" rev-parse HEAD)" \
    '{schemaVersion: 1, takenAt: "2026-10-28", unit: "wo1", commit: $c, testGlobs: [], rows: [],
      proof: "record", support: [], freezeCommits: []}' >"$IMPL/tests-wo1.json"
  git -C "$PROJECT" add -A && git -C "$PROJECT" commit -qm "records"
  mkdir -p "$PROJECT/notes"
  printf 'b\n' >"$PROJECT/notes/a.md"
  git -C "$PROJECT" add notes && git -C "$PROJECT" commit -qm "a commit before the record"
  printf 'note\n' >"$TASK/note.md"
  git -C "$PROJECT" add -A && git -C "$PROJECT" commit -qm "a task note"
  run "$IMPLEMENT" redo "$TASK" wo1 --because "the design changed"
  printf '%s|%s|%s\n' "$RC" "$([ -e "$PROJECT/notes/a.md" ] && echo doc || echo none)" "$([ -e "$TASK/note.md" ] && echo note || echo none)"
)

echo "--- a commit after the last record: its own files are the order's, others refuse or stay"
expect "redo reverts a commit no record lists that changes only the order's files" "$(after_case redo a.php)" "0|changed|a|none|1"
expect "drop reverts it the same way" "$(after_case drop a.php)" "0|changed|a|none|1"
expect "redo refuses a commit that also changes another file, names it, and changes nothing" \
  "$(after_case redo a.php other.php)" "113|same|b|other|1"
expect "drop refuses it the same way" "$(after_case drop a.php other.php)" "113|same|b|other|1"
expect "a commit that changes no file of the order is left alone" "$(after_case redo other.php)" "0|changed|a|other|0"
expect "a person's revert of the refused commit lets redo through, and what they kept stays" \
  "$(KEEP=1 after_case redo a.php other.php)" "0|changed|a|other|1"
expect "the refused commit and its revert leave nothing unattributed" "$(after_listed)" "unattributed: none"
expect "a shared file alone never makes a commit the order's" "$(SHARED=1 after_case redo a.php)" "0|changed|b|none|0"
expect "a record order's commit is reverted, and a commit of AIDA's records stays" "$(after_record_case)" "0|none|note"

finish
