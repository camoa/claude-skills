#!/usr/bin/env bash
# reopen-non-goal-spec.sh: a task review finding that cites a non-goal routes back to its order when
# a person rules it fix, and takes the owner's first criterion, as a finding that cites none does
# (gap row 482). A finding reopen leaves out is named with a reason.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=records.bash
source "$HERE/records.bash"

# reopened <findings JSON>: wo1 closed over its build, proved by observation, under a contract with
# non-goal n1, and a failed task review of the finish that holds <findings>. Then reopen.
reopened() {
  task_records branch
  jq '.nonGoals = [{id: "n1", text: "no map is refused"}] | .nextNonGoalId = 2' "$TASK/alignment.json" >"$ROOT/a.json" \
    && mv "$ROOT/a.json" "$TASK/alignment.json"
  jq '.proof = "observe"' "$TASK/design/wo1.json" >"$ROOT/w.json" && mv "$ROOT/w.json" "$TASK/design/wo1.json"
  jq --arg h "$(records_hash_for "$TASK")" '.hash = $h' "$TASK/design-closed.json" >"$ROOT/d.json" \
    && mv "$ROOT/d.json" "$TASK/design-closed.json"
  git -C "$PROJECT" commit -qam "a non-goal, and wo1 proved by observation"
  order_records closed
  local range
  range="$(jq -r '.startedFrom' "$IMPL/ledger.json")..$(git -C "$WT" rev-parse HEAD)"
  jq -n '{schemaVersion: 1, unit: "wo1", findings: []}' >"$IMPL/review-wo1.json"
  jq -n --arg r "$range" '{schemaVersion: 1, commitRange: $r}' >"$IMPL/finished.json"
  mkdir -p "$TASK/review"
  jq -n --arg r "$range" --argjson f "$1" '{verdict: "failed", reviewedRange: $r,
      findings: [ $f[] | {severity: "medium", file: "a.php", lines: "", lens: "correctness", evidence: "a valid map is refused"} + . ]}' \
    >"$TASK/review/review.json"
  run "$IMPLEMENT" reopen "$TASK"
}

# A finding a person ruled fix that cites n1 reopens wo1, and its repair cites c1, wo1's first
# criterion, so a repair freeze can key a test to it.
fixed_case() (
  source "$HERE/records.bash"
  reopened '[{"id": "f1", "linkedTo": "n1", "disposition": "criterion", "ruling": "fix"}]'
  printf '%s|%s\n' "$RC" "$(jq -r '[ .findings[] | .linkedTo ] | join(",")' "$IMPL/review-wo1.json")"
)
expect "a fix ruling on a non-goal finding reopens its order under the order's first criterion" "$(fixed_case)" '0|c1'

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

finish
