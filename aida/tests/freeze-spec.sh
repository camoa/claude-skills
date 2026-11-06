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

# changed_records: wo1 also owns tests/c_test.sh, which holds no test of wo1, and tests/e_test.sh.
# The test author changes c_test.sh, tests/d_test.sh that no order owns, and a.php, stages a new
# e_test.sh, and writes a failing tests/a_test.sh (gap row 480). HEAD is read into $HEAD0.
changed_records() {
  task_records branch "$@"
  mkdir -p "$WT/tests"
  printf 'exit 0\n' >"$WT/tests/c_test.sh"
  printf 'exit 0\n' >"$WT/tests/d_test.sh"
  git -C "$WT" add tests && git -C "$WT" commit -qm "two tests"
  order_records planned
  edit "$IMPL/snapshot.json" '(.workOrders[] | select(.id == "wo1")).ownedFiles += ["tests/c_test.sh", "tests/e_test.sh"]'
  test_recipe
  HEAD0="$(git -C "$WT" rev-parse HEAD)"
  printf '. ./tests/helper\nexit 0\n' >"$WT/tests/c_test.sh"
  printf 'exit 1\n' >"$WT/tests/d_test.sh"
  printf 'b\n' >"$WT/a.php"
  printf 'exit 0\n' >"$WT/tests/e_test.sh"
  git -C "$WT" add tests/e_test.sh
  printf 'echo a does not say b\nexit 1\n' >"$WT/tests/a_test.sh"
  (cd "$WT" && sh tests/a_test.sh) >"$ROOT/red.txt" 2>&1
}
# freeze_a: freezes tests/a_test.sh for c1.
freeze_a() {
  run "$IMPLEMENT" tests-freeze "$TASK" wo1 --test "tests/a_test.sh::a says b=c1" --red "a says b=$ROOT/red.txt" \
    --test-glob 'tests/*_test.sh' --test-recipe "fake=$RECIPE" --row "c1=confirmed::model::it proves c1"
}

# Prints the freeze's exit, the files of the freeze commit, and what stays uncommitted.
changed_case() (
  source "$HERE/records.bash"
  changed_records
  freeze_a
  printf '%s|%s|%s\n' "$RC" "$(git -C "$WT" diff --name-only "$HEAD0" HEAD | tr '\n' ' ')" \
    "$(git -C "$WT" status --porcelain | cut -c4- | tr '\n' ' ')"
)
expect "an owned test file the author changed or staged rides in the freeze commit, and nothing else does" \
  "$(changed_case)" "0|tests/a_test.sh tests/c_test.sh tests/e_test.sh |a.php tests/d_test.sh "

# wo2's frozen record holds a test in tests/c_test.sh, which wo1 shares.
held_case() (
  source "$HERE/records.bash"
  changed_records wo2
  jq -n '{schemaVersion: 1, unit: "wo2", commit: "x", testGlobs: ["tests/*_test.sh"],
      rows: [{criterion: "c2", kind: "machine", tests: [{path: "tests/c_test.sh", name: "c", sha256: "0"}]}], support: []}' \
    >"$IMPL/tests-wo2.json"
  freeze_a
  printf '%s|%s|%s\n' "$RC" "$([ -f "$IMPL/tests-wo1.json" ] && echo record || echo none)" \
    "$([ "$(git -C "$WT" rev-parse HEAD)" = "$HEAD0" ] && echo no-commit)"
)
expect "a changed test file another order froze tests in is refused, and nothing is frozen" "$(held_case)" "27|none|no-commit"

# The same freeze again, after another commit and a second change to tests/c_test.sh.
refreeze_case() (
  source "$HERE/records.bash"
  changed_records
  freeze_a
  printf 'a note\n' >"$WT/notes.txt"
  git -C "$WT" add notes.txt && git -C "$WT" commit -qm "a note"
  printf 'exit 0\n' >"$WT/tests/c_test.sh"
  freeze_a
  printf '%s|%s|%s\n' "$RC" "$(jq '.freezeCommits | length' "$IMPL/tests-wo1.json")" \
    "$([ "$(jq -r '.freezeCommits[-1]' "$IMPL/tests-wo1.json")" = "$(git -C "$WT" rev-parse HEAD)" ] && echo head)"
)
expect "an unchanged re-freeze that commits a changed test file records the commit" "$(refreeze_case)" "0|2|head"

# person_records: wo1 serves c1, which a person verifies, and wo1 owns tests/a_test.sh, which fails
# until a.php says b. Its red run is in $ROOT/red.txt, and HEAD is read into $HEAD0 (gap row 499).
person_records() {
  task_records branch
  order_records planned
  edit "$IMPL/snapshot.json" '.alignment.criteria[0].verifiedBy = "person"'
  suite_records ""
  mkdir -p "$WT/tests"
  printf 'grep -q b a.php && exit 0\necho a does not say b\nexit 1\n' >"$WT/tests/a_test.sh"
  (cd "$WT" && sh tests/a_test.sh) >"$ROOT/red.txt" 2>&1
  HEAD0="$(git -C "$WT" rev-parse HEAD)"
}
# freeze_person <claim> [<flag>]...: freezes tests/a_test.sh with the claim, and c1's checklist.
freeze_person() {
  local claim="$1"
  shift
  run "$IMPLEMENT" tests-freeze "$TASK" wo1 --test "tests/a_test.sh::a says b=$claim" --red "a says b=$ROOT/red.txt" \
    --test-glob 'tests/*_test.sh' --test-recipe "fake=$RECIPE" --checklist "c1=read a.php" "$@"
}
# Prints the freeze's exit, whether the record exists, and whether HEAD moved.
unrecorded_case() (
  source "$HERE/records.bash"
  person_records
  freeze_person "$@"
  printf '%s|%s|%s\n' "$RC" "$([ -f "$IMPL/tests-wo1.json" ] && echo record || echo none)" \
    "$([ "$(git -C "$WT" rev-parse HEAD)" = "$HEAD0" ] && echo no-commit || echo committed)"
)
expect "a test that claims only a person's criterion is refused, and nothing is frozen" "$(unrecorded_case c1)" "3|none|no-commit"
expect "a test that claims only a criterion the order does not hold is refused, and nothing is frozen" "$(unrecorded_case c9)" "3|none|no-commit"

# The checker rejected the order row, because no test claims wo1. That rejection reaches the
# ledger, and nothing is committed (gap row 491).
rejected_case() (
  source "$HERE/records.bash"
  person_records
  freeze_person c1 --row "wo1=rejected::model::no test pins the order"
  printf '%s|%s|%s\n' "$RC" "$(ledger '[.rowsRejected[].criterion] | join(",")')" \
    "$([ "$(git -C "$WT" rev-parse HEAD)" = "$HEAD0" ] && echo no-commit || echo committed)"
)
expect "a rejected order row beside an unrecorded test is recorded, and nothing is committed" "$(rejected_case)" "65|wo1|no-commit"

# wo1 also owns c2, a machine criterion with its own test in tests/b_test.sh, so the record has a
# row and only tests/a_test.sh would drop from it.
mixed_case() (
  source "$HERE/records.bash"
  person_records
  edit "$IMPL/snapshot.json" '.alignment.criteria += [.alignment.criteria[0] + {id: "c2", verifiedBy: "machine"}]
    | (.workOrders[] | select(.id == "wo1")) |= (.criteriaServed += ["c2"] | .criteriaOwned = ["c2"] | .ownedFiles += ["tests/b_test.sh"])'
  printf 'echo b is missing\nexit 1\n' >"$WT/tests/b_test.sh"
  (cd "$WT" && sh tests/b_test.sh) >"$ROOT/red-b.txt" 2>&1
  freeze_person c1 --test "tests/b_test.sh::b exists=c2" --red "b exists=$ROOT/red-b.txt" --row "c2=confirmed::model::it proves c2"
  printf '%s|%s\n' "$RC" "$([ "$(git -C "$WT" rev-parse HEAD)" = "$HEAD0" ] && echo no-commit || echo committed)"
)
expect "a test no row would hold is refused beside a test a row holds" "$(mixed_case)" "3|no-commit"

# The test claims the order id instead. The record holds it, and build-record runs and guards it.
# Prints the freeze's exit, the frozen path, then the build's exit and its two check verdicts.
order_claim_case() (
  source "$HERE/records.bash"
  person_records
  freeze_person wo1 --row "wo1=confirmed::model::it proves the done-when"
  printf '%s|%s|' "$RC" "$(jq -r '[ .rows[] | (.tests // [])[] | .path ] | join(" ")' "$IMPL/tests-wo1.json" 2>/dev/null)"
  local start
  start="$(git -C "$WT" rev-parse HEAD)"
  printf 'b\n' >"$WT/a.php"
  git -C "$WT" commit -qam "build wo1"
  printf 'Stop: none\nDeviation: none\n' >"$IMPL/answers-wo1-attempt1.md"
  printf 'none\n' >"$IMPL/interface-wo1.md"
  run "$IMPLEMENT" build-record "$TASK" wo1 --report "$IMPL/answers-wo1-attempt1.md" --interface "$IMPL/interface-wo1.md" \
    --started-at "$start"
  printf '%s|%s\n' "$RC" "$(jq -r '[ .checks[] | select(.id == "order-tests" or .id == "frozen-tests") | .id + "=" + .verdict ] | sort | join(" ")' "$IMPL/build-wo1.json" 2>/dev/null)"
)
expect "a test that claims the order id on a person's order is recorded, run and guarded" "$(order_claim_case)" \
  "0|tests/a_test.sh|0|frozen-tests=met order-tests=met"

finish
