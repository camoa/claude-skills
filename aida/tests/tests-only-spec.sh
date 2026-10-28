#!/usr/bin/env bash
# tests-only-spec.sh: an order that deletes whole test files of one approved cleanup run (gap row
# 467). The design check accepts it as a confirm order, bounded by the run, its done-when rows,
# the tests orders it follows and the tests another open task froze. Its build may delete only.
# Each case sources the helper in a subshell, so it starts from fresh records.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=records.bash
source "$HERE/records.bash"

# cleanup_records: the goal names run-1, whose groups.json lists three tests. wo1 is a tests order
# that keeps tests/k_test.sh, frozen by this task. wo2 is confirmed by a person, deletes
# tests/a_test.sh and tests/b_test.sh, names each in a done-when row, and depends on wo1. Task t0
# is complete, and its freeze holds tests/a_test.sh under the glob tests/*_test.sh.
cleanup_records() {
  task_records branch wo2
  mkdir -p "$PROJECT/test-cleanup/run-1" "$PROJECT/tasks/t0/implementation"
  jq -n '[{id: "g1", files: ["tests/a_test.sh", "tests/b_test.sh", "tests/k_test.sh"], lines: 30}]' \
    >"$PROJECT/test-cleanup/run-1/groups.json"
  jq --arg g "Apply the test cleanup the person approved in $PROJECT/test-cleanup/run-1/decisions.md." \
    '.goal = $g | .criteria[1].verifiedBy = "person"' "$TASK/alignment.json" >"$ROOT/a.json" && mv "$ROOT/a.json" "$TASK/alignment.json"
  jq '.ownedFiles = ["tests/k_test.sh"] | .doneWhen = ["tests/k_test.sh checks a"]' "$TASK/design/wo1.json" >"$ROOT/w.json" \
    && mv "$ROOT/w.json" "$TASK/design/wo1.json"
  jq '.proof = "confirm" | .tests = [] | .ownedFiles = ["tests/a_test.sh", "tests/b_test.sh"]
      | .doneWhen = ["tests/a_test.sh is deleted", "tests/b_test.sh is deleted"]' "$TASK/design/wo2.json" >"$ROOT/w.json" \
    && mv "$ROOT/w.json" "$TASK/design/wo2.json"
  jq -n '{schemaVersion: 1, id: "t0", state: "complete", parent: null, children: []}' >"$PROJECT/tasks/t0/task.json"
  frozen_record t0 tests/a_test.sh
  frozen_record t1 tests/k_test.sh
}

# frozen_record <task> <path>: that task's freeze of wo1, holding one test at <path>.
frozen_record() {
  jq -n --arg p "$2" '{schemaVersion: 1, takenAt: "2026-10-28", unit: "wo1", commit: "0000000", testGlobs: ["tests/*_test.sh"],
    rows: [{criterion: "c1", kind: "machine", tests: [{path: $p, name: "a test", sha256: ("0" * 64)}]}], support: []}' \
    >"$PROJECT/tasks/$1/implementation/tests-wo1.json"
}

# edit <jq filter> <file>: applies the filter to one record in place.
edit() { jq "$1" "$2" >"$ROOT/e.json" && mv "$ROOT/e.json" "$2"; }

# design_case <jq filter on the report> [<setup>]: the design check over the cleanup records,
# after the setup command. Prints the check's exit, then what the filter reads.
design_case() (
  source "$HERE/records.bash"
  cleanup_records
  eval "${2:-:}"
  bash "$PLUGIN/scripts/check-design.sh" "$TASK" >"$OUT" 2>/dev/null
  printf '%s|%s\n' "$?" "$(jq -c "$1" "$OUT")"
)

# deletion_records: wo1 deletes tests/a_test.sh, the one test of run-1, and is at tests-frozen.
deletion_records() {
  task_records branch
  mkdir -p "$PROJECT/test-cleanup/run-1" "$WT/tests"
  jq -n '[{id: "g1", files: ["tests/a_test.sh"], lines: 2}]' >"$PROJECT/test-cleanup/run-1/groups.json"
  jq --arg g "Apply $PROJECT/test-cleanup/run-1/decisions.md." '.goal = $g | .criteria[0].verifiedBy = "person"' \
    "$TASK/alignment.json" >"$ROOT/a.json" && mv "$ROOT/a.json" "$TASK/alignment.json"
  edit '.proof = "confirm" | .tests = [] | .interface = "" | .ownedFiles = ["tests/a_test.sh"] | .doneWhen = ["tests/a_test.sh is deleted"]' \
    "$TASK/design/wo1.json"
  printf 'exit 0\n' >"$WT/tests/a_test.sh"
  git -C "$WT" add tests/a_test.sh && git -C "$WT" commit -qm "the test the cleanup deletes"
  order_records tests-frozen
  jq -n --arg c "$(git -C "$WT" rev-parse HEAD)" \
    '{schemaVersion: 1, takenAt: "2026-10-28", unit: "wo1", commit: $c, testGlobs: [], rows: [],
      proof: "confirm", support: [], freezeCommits: []}' >"$IMPL/tests-wo1.json"
}

# build_case <change>: build-record on wo1 after one commit that makes <change> to its test: edit,
# delete, or delete-env, which also adds .env.local, a file `task environment up` recorded.
# Prints the owned-files verdict.
build_case() (
  source "$HERE/records.bash"
  deletion_records
  if [ "$1" = edit ]; then printf 'exit 1\n' >"$WT/tests/a_test.sh"; git -C "$WT" add tests/a_test.sh
  else git -C "$WT" rm -q tests/a_test.sh; fi
  if [ "$1" = delete-env ]; then
    printf 'X=1\n' >"$WT/.env.local" && git -C "$WT" add .env.local
    blob="$(git -C "$WT" hash-object .env.local)"
    edit ".worktree.recipeChanges = [{path: \".env.local\", blob: \"$blob\"}]" "$TASK/task.json"
  fi
  git -C "$WT" commit -qm "build wo1"
  printf 'Stop: none\nDeviation: none\n' >"$IMPL/answers-wo1-attempt1.md"
  run "$IMPLEMENT" build-record "$TASK" wo1 --report "$IMPL/answers-wo1-attempt1.md" --interface "$IMPL/interface-wo1.md" \
    --started-at "$(git -C "$WT" rev-parse HEAD~1)"
  jq -r '.checks[] | select(.id == "owned-files") | .verdict' "$IMPL/build-wo1.json" 2>/dev/null || { echo "exit $RC"; cat "$OUT"; }
)

# dispatch_case <role>: dispatch-open of that role on wo1, on a task whose one order deletes a
# test. Prints the exit.
dispatch_case() (
  source "$HERE/records.bash"
  deletion_records
  run "$IMPLEMENT" dispatch-open "$TASK" "aida:$1" wo1 --test-glob 'tests/*_test.sh'
  echo "$RC"
)

CONFIRM='[.coverage.confirmOrdersOnTaskWithTests[].id, .coverage.confirmOrdersOwningTestFiles[].id] | unique'

echo "--- design: an order that deletes the run's tests"
expect "an order deleting files the named run lists is accepted" "$(design_case "$CONFIRM")" '0|[]'
expect "an order also owning a file the run does not list is still refused as code with no test" \
  "$(design_case "$CONFIRM" 'edit ".ownedFiles += [\"src/x.php\"] | .doneWhen += [\"src/x.php is deleted\"]" "$TASK/design/wo2.json"')" \
  '4|["wo2"]'
expect "with a goal that names no run, the order is refused as before" \
  "$(design_case "$CONFIRM" 'edit ".goal = \"clean up the tests\"" "$TASK/alignment.json"')" '4|["wo2"]'
expect "an owned file that no done-when row names is refused" \
  "$(design_case '.coverage.testsOnlyRowsUnmatched' 'edit ".doneWhen = [\"tests/a_test.sh is deleted\"]" "$TASK/design/wo2.json"')" \
  '4|[{"id":"wo2","item":"tests/b_test.sh","problem":"owned file named in no done-when row"}]'
expect "a done-when row that names no owned file is refused" \
  "$(design_case '.coverage.testsOnlyRowsUnmatched' 'edit ".doneWhen += [\"the suite is smaller\"]" "$TASK/design/wo2.json"')" \
  '4|[{"id":"wo2","item":"the suite is smaller","problem":"done-when row names no owned file"}]'
expect "an order that does not come after every tests order of its task is refused" \
  "$(design_case '.graph.testsOnlyOrdersBeforeTests' 'edit ".dependsOn = []" "$TASK/design/wo2.json"')" \
  '4|[{"id":"wo2","testsOrder":"wo1"}]'
expect "a test that another open task froze is refused, and this task's own freeze is not" \
  "$(design_case '.graph.ordersOwningFrozenPaths' 'edit ".state = \"in_progress\"" "$PROJECT/tasks/t0/task.json"')" \
  '4|[{"id":"wo2","path":"tests/a_test.sh","task":"t0"}]'
expect "a tests order that owns only a test another open task froze is refused" \
  "$(design_case '.graph.ordersOwningFrozenPaths' 'edit ".state = \"in_progress\"" "$PROJECT/tasks/t0/task.json"; frozen_record t0 tests/k_test.sh')" \
  '4|[{"id":"wo1","path":"tests/k_test.sh","task":"t0"}]'
expect "an order that also builds code may own a test another open task froze" \
  "$(design_case '.graph.ordersOwningFrozenPaths' 'edit ".state = \"in_progress\"" "$PROJECT/tasks/t0/task.json"; frozen_record t0 tests/k_test.sh; edit ".ownedFiles += [\"a.php\"]" "$TASK/design/wo1.json"')" \
  '0|[]'

echo "--- design: each refusal prints its line, naming the order and the file"
STOP='[.open.stop[] | select(startswith("order wo2"))]'
expect "an owned file no row names" \
  "$(design_case "$STOP" 'edit ".doneWhen = [\"tests/a_test.sh is deleted\"]" "$TASK/design/wo2.json"')" \
  '4|["order wo2 deletes the tests of a cleanup run, and no done-when row names its file tests/b_test.sh: add-done-when"]'
expect "a row that names no owned file" \
  "$(design_case "$STOP" 'edit ".doneWhen += [\"the suite is smaller\"]" "$TASK/design/wo2.json"')" \
  '4|["order wo2 deletes the tests of a cleanup run, and its done-when row \"the suite is smaller\" names no file it owns: remove-done-when, or name the file in it"]'
expect "an order before a tests order" \
  "$(design_case "$STOP" 'edit ".dependsOn = []" "$TASK/design/wo2.json"')" \
  '4|["order wo2 deletes the tests of a cleanup run and does not come after the tests order wo1: add wo1 to its dependsOn"]'
expect "a test another open task froze" \
  "$(design_case "$STOP" 'edit ".state = \"in_progress\"" "$PROJECT/tasks/t0/task.json"')" \
  '4|["order wo2 owns tests/a_test.sh, a test that task t0 froze and has not completed: remove-owned-file, or wait until t0 is complete"]'

echo "--- build: the order deletes, and never edits"
expect "a commit that edits the owned test reads owned-files unmet" "$(build_case edit)" "unmet"
expect "a commit that deletes the owned test reads owned-files met" "$(build_case delete)" "met"
expect "a file task environment up recorded is set aside, not read as an edit" "$(build_case delete-env)" "met"

echo "--- dispatch: a cleanup task with no file outside the test tree"
expect "the row-checker of a deletion order is dispatched" "$(dispatch_case row-checker)" "0"

finish
