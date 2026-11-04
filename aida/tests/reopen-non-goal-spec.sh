#!/usr/bin/env bash
# reopen-non-goal-spec.sh: a task review finding that cites a non-goal routes back to its order when
# a person rules it fix, and takes the owner's first criterion, as a finding that cites none does
# (gap row 482). A finding reopen leaves out is named with a reason.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=records.bash
source "$HERE/records.bash"

# reopened <findings JSON> [criteria JSON]: wo1 closed over its build, proved by tests, under a
# contract with non-goal n1, and a failed task review of the finish that holds <findings> and the
# criterion rows. Then reopen.
reopened() {
  task_records branch
  jq '.nonGoals = [{id: "n1", text: "no map is refused"}] | .nextNonGoalId = 2' "$TASK/alignment.json" >"$ROOT/a.json" \
    && mv "$ROOT/a.json" "$TASK/alignment.json"
  jq '.proof = "tests" | .ownedFiles = ["a.php", "tests/*_test.sh"]' "$TASK/design/wo1.json" >"$ROOT/w.json" && mv "$ROOT/w.json" "$TASK/design/wo1.json"
  jq --arg h "$(records_hash_for "$TASK")" '.hash = $h' "$TASK/design-closed.json" >"$ROOT/d.json" \
    && mv "$ROOT/d.json" "$TASK/design-closed.json"
  git -C "$PROJECT" commit -qam "a non-goal, and wo1 owns its tests folder"
  order_records closed
  suite_records ""
  tests_record
  local range
  range="$(jq -r '.startedFrom' "$IMPL/ledger.json")..$(git -C "$WT" rev-parse HEAD)"
  jq -n '{schemaVersion: 1, unit: "wo1", findings: []}' >"$IMPL/review-wo1.json"
  jq -n --arg r "$range" '{schemaVersion: 1, commitRange: $r}' >"$IMPL/finished.json"
  mkdir -p "$TASK/review"
  jq -n --arg r "$range" --argjson f "$1" --argjson c "${2:-[]}" '{verdict: "failed", reviewedRange: $r, criteria: $c,
      findings: [ $f[] | {severity: "medium", file: "a.php", lines: "", lens: "correctness", evidence: "a valid map is refused"} + . ]}' \
    >"$TASK/review/review.json"
  run "$IMPLEMENT" reopen "$TASK"
}

# A logic finding a person ruled fix that cites n1 reopens wo1, and wo1 owes a test of it. The
# test brief's repair cites c1, a criterion wo1 serves, so the repair test can freeze under it,
# and its evidence keeps the n1 link.
fixed_case() (
  source "$HERE/records.bash"
  reopened '[{"id": "f1", "linkedTo": "n1", "disposition": "criterion", "ruling": "fix"}]'
  run "$IMPLEMENT" tests-brief "$TASK" wo1
  printf '%s|%s\n' "$RC" "$(jq -r '[ .repair.findings[] | .linkedTo, (.evidence | endswith("citing n1")) ] | join(",")' \
    "$IMPL/brief-wo1-tests.json" 2>/dev/null)"
)
expect "a fix ruling on a non-goal finding reopens its order under the order's first criterion" "$(fixed_case)" '0|c1,true'

# Beside a routed finding, an unruled one that cites n1 is named among the findings left. One a
# person ruled deferred has its route already, so it is not named.
# left_ids: the finding ids the notRouted line names.
left_ids() { sed -n 's/^notRouted: //p' "$OUT" | grep -o '\bf[0-9][0-9]* (' | tr -d ' (' | paste -sd, -; }
left_case() (
  source "$HERE/records.bash"
  reopened '[{"id": "f1", "linkedTo": "c1", "disposition": "criterion"},
             {"id": "f2", "linkedTo": "n1", "disposition": "non-goal"},
             {"id": "f3", "linkedTo": "n1", "disposition": "follow-up", "ruling": "deferred"}]'
  printf '%s|%s\n' "$RC" "$(left_ids)"
)
expect "reopen names an unruled finding it leaves out, and not a deferred one" "$(left_case)" '0|f2'

# A finding a person ruled wrong fails no criterion, so the refusal names it with that ruling
# (gap row 490). Its unruled acceptance copy still routes, and the routed line names f1.
wrong_case() (
  source "$HERE/records.bash"
  reopened '[{"id": "f1", "linkedTo": "c1", "disposition": "criterion", "ruling": "wrong"}]'
  printf '%s|%s\n' "$RC" "$(grep -c 'f1 (a person ruled it wrong' "$OUT")"
)
expect "reopen refuses a finding ruled wrong and names the ruling" "$(wrong_case)" '119|1'
# The person answered c1 unmet, and its only finding is ruled wrong. No finding reaches an order,
# so the refusal names c1 and the answer it failed through.
answer_case() (
  source "$HERE/records.bash"
  reopened '[{"id": "f1", "linkedTo": "c1", "disposition": "criterion", "ruling": "wrong"}]' \
    '[{"id": "c1", "verifiedBy": "person", "verdict": "unmet", "answeredBy": "person"}]'
  printf '%s|%s\n' "$RC" "$(grep -o "c1 reads unmet through the person's answer" "$OUT" | wc -l | tr -d ' ')"
)
expect "reopen names a criterion that failed through the person's answer" "$(answer_case)" '119|1'
copy_case() (
  source "$HERE/records.bash"
  reopened '[{"id": "f1", "linkedTo": "c1", "disposition": "criterion", "ruling": "wrong"},
             {"id": "f9", "linkedTo": "c1", "disposition": "criterion", "lens": "acceptance"}]'
  printf '%s|%s|%s\n' "$RC" "$(jq -r '[ .findings[].evidence | test("as its finding f9,") ] | any' "$IMPL/review-wo1.json")" "$(left_ids)"
)
expect "an unruled copy of a finding ruled wrong reopens its order" "$(copy_case)" '0|true|f1'

finish
