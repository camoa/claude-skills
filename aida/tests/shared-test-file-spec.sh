#!/usr/bin/env bash
# shared-test-file-spec.sh: a test file belongs to one order's freeze (gap row 489). A later
# order's freeze that names a file an earlier order froze is refused, and nothing is frozen. A new
# file freezes. Review still stops at 124 on a frozen file that changed after its freeze. Each case
# sources the helper in a subshell, so it starts from fresh records.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=records.bash
source "$HERE/records.bash"

# later_records: wo1 froze tests/a_test.sh and is closed. wo2 owns tests/a_test.sh and
# tests/b_test.sh too, and is planned. HEAD is read into $HEAD0.
later_records() {
  task_records branch wo2
  order_records planned
  edit "$IMPL/ledger.json" '(.orders[] | select(.id == "wo1")).lastStep = "closed"'
  edit "$IMPL/snapshot.json" '(.workOrders[] | select(.id == "wo2")).ownedFiles += ["tests/a_test.sh", "tests/b_test.sh"]'
  test_recipe
  tests_record
  HEAD0="$(git -C "$WT" rev-parse HEAD)"
}
# freeze_wo2 <path>: a failing test of c2 at the end of <path>, and wo2's freeze of it. Prints the
# freeze's exit, whether wo2's record exists, and whether HEAD moved.
freeze_wo2() {
  printf 'echo b is missing\nexit 1\n' >>"$WT/$1"
  (cd "$WT" && sh "$1") >"$ROOT/red.txt" 2>&1
  run "$IMPLEMENT" tests-freeze "$TASK" wo2 --test "$1::b exists=c2" --red "b exists=$ROOT/red.txt" \
    --test-glob 'tests/*_test.sh' --test-recipe "fake=$RECIPE" --row "c2=confirmed::model::it proves c2"
  printf '%s|%s|%s\n' "$RC" "$([ -f "$IMPL/tests-wo2.json" ] && echo record || echo none)" \
    "$([ "$(git -C "$WT" rev-parse HEAD)" = "$HEAD0" ] && echo still || echo moved)"
}

shared_case() (
  source "$HERE/records.bash"
  later_records
  freeze_wo2 tests/a_test.sh
)
expect "a later freeze naming a file an earlier order froze is refused, and nothing is frozen" "$(shared_case)" "27|none|still"

new_case() (
  source "$HERE/records.bash"
  later_records
  freeze_wo2 tests/b_test.sh
)
expect "a later freeze in a new file freezes" "$(new_case)" "0|record|moved"

# A file wo1 froze gains lines after its freeze, and wo2's hand-written record holds the new hash.
edited_case() (
  source "$HERE/records.bash"
  task_records branch wo2
  order_records reviewed
  suite_records ""
  tests_record
  printf 'test -f b.php || exit 1\n' >>"$WT/tests/a_test.sh"
  git -C "$WT" commit -qam "after the freeze"
  jq --arg sha "$("${RECORDS_HASH_SHA256_CMD[@]}" "$WT/tests/a_test.sh" | cut -d' ' -f1)" '
    .unit = "wo2" | .rows = [{criterion: "c2", kind: "machine", tests: [{path: "tests/a_test.sh", name: "b exists", sha256: $sha,
      red: "b is missing", redSignal: "unchecked"}]}]' "$IMPL/tests-wo1.json" >"$IMPL/tests-wo2.json"
  jq -n --arg r "$(jq -r '.startedFrom' "$IMPL/ledger.json")..$(git -C "$WT" rev-parse HEAD)" \
    '{schemaVersion: 1, commitRange: $r, criteria: [{id: "c1", verifiedBy: "machine"}, {id: "c2", verifiedBy: "machine"}], checklists: []}' \
    >"$IMPL/finished.json"
  run "$REVIEW" checks "$TASK" --lookup-failed fake=no-recipe
  printf '%s\n' "$RC"
)
expect "review stops on a shared frozen file that changed after its freeze" "$(edited_case)" "124"

finish
