#!/usr/bin/env bash
# freeze-spec.sh: tests-freeze refuses a test that passes before the build, and a test the order
# does not own. It freezes one that fails: the record is written and the commit holds the test
# alone. The recipe's file command runs the test file with sh, so the test's own exit decides. Each
# case sources the helper in a subshell, so it starts from fresh records.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=records.bash
source "$HERE/records.bash"

# freeze_case <path> <exit>: writes <path>, a test that exits <exit>, and an untracked notes.txt
# beside it that no order owns, keeps what the test printed as its red run, and freezes it for c1.
# Prints the freeze's exit, whether the tests record exists, and the files of the commit HEAD moved to.
freeze_case() (
  source "$HERE/records.bash"
  task_records branch
  order_records planned
  test_recipe
  local head
  head="$(git -C "$WT" rev-parse HEAD)"
  mkdir -p "$WT/$(dirname "$1")"
  printf 'echo a does not say b\nexit %s\n' "$2" >"$WT/$1"
  printf 'a note\n' >"$WT/notes.txt"
  (cd "$WT" && sh "$1") >"$ROOT/red.txt" 2>&1
  run "$IMPLEMENT" tests-freeze "$TASK" wo1 --test "$1::a says b=c1" --red "a says b=$ROOT/red.txt" \
    --test-glob 'tests/*_test.sh' --test-recipe "fake=$RECIPE" --row "c1=confirmed::model::it proves c1"
  printf '%s|%s|%s\n' "$RC" "$([ -f "$IMPL/tests-wo1.json" ] && echo record || echo none)" \
    "$(git -C "$WT" diff --name-only "$head" HEAD | tr '\n' ' ')"
)

expect "a test that passes before the build is refused, and nothing is frozen" "$(freeze_case tests/a_test.sh 0)" "80|none|"
expect "a test the order does not own is refused, and nothing is frozen" "$(freeze_case tests/b_test.sh 1)" "27|none|"
expect "a test that fails is frozen, and the commit holds the test alone" "$(freeze_case tests/a_test.sh 1)" "0|record|tests/a_test.sh "

finish
