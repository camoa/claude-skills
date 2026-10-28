#!/usr/bin/env bash
# row-checkpoint-spec.sh: a rejection puts back to the row checker only the rows it rejected, and
# the next freeze carries a confirmed row whose test file only the repair edited.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=records.bash
source "$HERE/records.bash"

# two_rows: wo1 owns c1 and c2, each proved by one test in tests/a_test.sh, and is planned.
two_rows() {
  task_records branch
  jq '.criteria += [.criteria[0] + {id: "c2", text: "a.php says c"}] | .nextCriterionId = 3' \
    "$TASK/alignment.json" >"$ROOT/a.json" && mv "$ROOT/a.json" "$TASK/alignment.json"
  jq '.criteriaServed = ["c1", "c2"] | .criteriaOwned = ["c1", "c2"]' \
    "$TASK/design/wo1.json" >"$ROOT/w.json" && mv "$ROOT/w.json" "$TASK/design/wo1.json"
  jq --arg h "$(records_hash_for "$TASK")" '.hash = $h' "$TASK/design-closed.json" >"$ROOT/d.json" \
    && mv "$ROOT/d.json" "$TASK/design-closed.json"
  git -C "$PROJECT" commit -qam "wo1 owns c2"
  order_records planned
  suite_records ""
  mkdir -p "$WT/tests"
  printf 'echo a does not say b\necho a does not say c\nexit 1\n' >"$WT/tests/a_test.sh"
  git -C "$WT" add tests/a_test.sh && git -C "$WT" commit -qm "tests of wo1"
  printf 'a does not say b\n' >"$IMPL/red-one.txt"
  printf 'a does not say c\n' >"$IMPL/red-two.txt"
}

# freeze <row>...: tests-freeze of wo1's two tests with the given --row values.
freeze() {
  local rows=() r
  for r in "$@"; do rows+=(--row "$r"); done
  run "$IMPLEMENT" tests-freeze "$TASK" wo1 --test-glob 'tests/*_test.sh' --test-recipe "fake=$RECIPE" \
    --test "tests/a_test.sh::one=c1" --test "tests/a_test.sh::two=c2" \
    --red "one=$IMPL/red-one.txt" --red "two=$IMPL/red-two.txt" "${rows[@]}"
}

# A rejection of c1 names c1 alone on checkAgain, though c2's test shares its file.
check_again_case() (
  source "$HERE/records.bash"
  two_rows
  jq -n '{rows: [{criterion: "c1", verdict: "rejected", repair: "tests", note: "misses b"},
                 {criterion: "c2", verdict: "confirmed", note: "observes c"}]}' >"$IMPL/row-check-wo1.json"
  freeze "c1=rejected::model::misses b" "c2=confirmed::model::observes c"
  printf '%s|%s|%s\n' "$RC" "$(sed -n 's/^checkAgain: //p' "$OUT")" "$(ledger '[.rowsConfirmed[].criterion] | join(",")')"
)
expect "a rejection puts back the rejected row alone, and records the confirmed one" "$(check_again_case)" '65|["c1"]|c2'

# The repair edited tests/a_test.sh after c2 was confirmed. Only the repair touched the file, so
# the freeze carries c2 and judges c1 from its new --row.
carry_case() (
  source "$HERE/records.bash"
  two_rows
  jq '(.orders[] | select(.id == "wo1")) += {
        rowsConfirmed: [{criterion: "c2", judgedBy: "model", note: "observes c", recordedAt: "2026-10-28T00:00:00Z"}],
        rowsRejected: [{criterion: "c1", checkerNote: "misses b", redAgain: ["one", "two"]}],
        checkAgain: [{criterion: "c1", verdict: "rejected"}]}' "$IMPL/ledger.json" >"$ROOT/l.json" \
    && mv "$ROOT/l.json" "$IMPL/ledger.json"
  jq -n '{rows: [{criterion: "c1", verdict: "confirmed", note: "observes b"}]}' >"$IMPL/row-check-wo1.json"
  freeze "c1=confirmed::model::observes b"
  printf '%s|%s\n' "$(sed -n 's/^rowsCarried: //p' "$OUT")" \
    "$(jq -r '[.rows[] | select(.criterion == "c2") | .criterion] | join(",")' "$IMPL/tests-wo1.json" 2>/dev/null)"
)
expect "a confirmed row in a file only the repair edited is carried into the frozen record" "$(carry_case)" 'c2|c2'

finish
