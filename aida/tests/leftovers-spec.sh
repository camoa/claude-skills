#!/usr/bin/env bash
# leftovers-spec.sh: the design check refuses a machine criterion that an observe or a record order
# owns with no run line proving it. finish takes no --accept-warnings. reopen, finish and
# fix-record run on a fresh task, whose review records hold a departure with no finding list.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=records.bash
source "$HERE/records.bash"

# design_as <proof> [run]: wo1 proved by <proof>, owning the machine criterion c1. An observe order
# names a surface. A record order owns a script in the project folder, which is not text only. With
# run, a run line proves c1. Prints the check's exit and the orders on the new list.
design_as() {
  task_records branch
  jq --arg p "$1" --arg doc "$PROJECT/tools/a.sh" --argjson run "$([ "${2:-}" = run ] && echo true || echo false)" '
    .proof = $p | .tests = []
    | (if $p == "observe" then .surfaces = ["home"] else . end)
    | (if $p == "record" then .ownedFiles = [$doc] else . end)
    | (if $run then .verify = [{run: "true", pass: "exit 0", cites: "a finding", binding: true, criterion: "c1"}] else . end)' \
    "$TASK/design/wo1.json" >"$ROOT/w.json" && mv "$ROOT/w.json" "$TASK/design/wo1.json"
  bash "$PLUGIN/scripts/check-design.sh" "$TASK" >"$ROOT/check.json" 2>/dev/null
  printf '%s|%s\n' "$?" "$(jq -r '[ (.coverage.machineCriteriaOnLookOrRecordOrders // [])[] | .id + " " + .criterionId ] | join(",")' "$ROOT/check.json")"
}

observe_refused() ( source "$HERE/records.bash"; design_as observe )
expect "the check refuses a machine criterion an observe order owns" "$(observe_refused)" '4|wo1 c1'
observe_run() ( source "$HERE/records.bash"; design_as observe run )
expect "a run line that proves it lets an observe order own it" "$(observe_run)" '0|'
record_refused() ( source "$HERE/records.bash"; design_as record )
expect "the check refuses a machine criterion a record order owns" "$(record_refused)" '4|wo1 c1'
record_run() ( source "$HERE/records.bash"; design_as record run )
expect "a run line that proves it lets a record order own it" "$(record_run)" '0|'

# closed_task: wo1 closed with its frozen test, a green suite, and a review record that holds a
# pending finding and a departure, as review-record writes them in 6.1.0.
closed_task() {
  task_records branch
  order_records closed
  suite_records ""
  tests_record
  jq -n '{schemaVersion: 1, unit: "wo1",
      findings: [{id: "f1", severity: "medium", status: "pending", evidence: "a person decides", fixScope: ["a.php"]}],
      deviationPending: {departure: "a.php says c", file: "report.md"}}' >"$IMPL/review-wo1.json"
}

# finish takes no --accept-warnings, even with a person's answer on the step it used: an
# unrecognized argument, and nothing is written.
accept_case() (
  source "$HERE/records.bash"
  closed_task
  answer "implement finish" "" "the warnings are fine"
  run "$IMPLEMENT" finish "$TASK" --accept-warnings "the warnings are fine"
  printf '%s|%s\n' "$RC" "$([ -f "$IMPL/finished.json" ] && echo written || echo none)"
)
expect "finish refuses --accept-warnings as an unknown argument and writes nothing" "$(accept_case)" '3|none'

# finish on that task names the pending finding and the departure, each once.
finish_case() (
  source "$HERE/records.bash"
  closed_task
  run "$IMPLEMENT" finish "$TASK"
  printf '%s|%s\n' "$RC" "$(jq -r '[ .pendingDecisions[] | .unit + "/" + (.finding // .kind) ] | join(",")' "$IMPL/finished.json" 2>/dev/null)"
)
expect "finish carries a pending finding and a departure to review" "$(finish_case)" '0|wo1/f1,wo1/departure'

# reopen on that task, after a failed task review of the finish, takes the finding to wo1.
reopen_case() (
  source "$HERE/records.bash"
  closed_task
  local range
  range="$(jq -r '.startedFrom' "$IMPL/ledger.json")..$(git -C "$WT" rev-parse HEAD)"
  jq -n --arg r "$range" '{schemaVersion: 1, commitRange: $r}' >"$IMPL/finished.json"
  mkdir -p "$TASK/review"
  jq -n --arg r "$range" '{verdict: "failed", reviewedRange: $r,
      findings: [{id: "f1", disposition: "criterion", severity: "high", file: "a.php", lines: "",
        linkedTo: "c1", lens: "correctness", evidence: "a.php still says a"}]}' >"$TASK/review/review.json"
  run "$IMPLEMENT" reopen "$TASK"
  printf '%s|%s\n' "$RC" "$(jq -r '[ .findings[] | .id ] | join(",")' "$IMPL/review-wo1.json")"
)
expect "reopen takes the review's finding to wo1" "$(reopen_case)" '0|f1,f2'

# fix-record on a fresh task: wo1 reviewed with one open finding, its fix brief, and a fixer that
# changed a.php. The round is recorded, and the summary's stopped line reads none.
fix_case() (
  source "$HERE/records.bash"
  task_records branch
  order_records reviewed
  suite_records ""
  tests_record
  local start
  start="$(git -C "$WT" rev-parse HEAD)"
  jq -n --arg c "$start" '{schemaVersion: 1, unit: "wo1", reviewedAt: $c,
      findings: [{id: "f1", severity: "high", actionable: true, status: "open", file: "a.php", lines: "",
        linkedTo: "c1", evidence: "a.php says a", fixScope: ["a.php"]}]}' >"$IMPL/review-wo1.json"
  jq -n --arg r "$ROOT/fix-report.md" '{schemaVersion: 1, unit: "wo1", round: 1, reportPath: $r}' >"$IMPL/brief-wo1-fix-1.json"
  printf 'Outcome: f1: fixed\n' >"$ROOT/fix-report.md"
  printf 'b\n' >"$WT/a.php"
  git -C "$WT" commit -qam "fix wo1"
  run "$IMPLEMENT" fix-record "$TASK" wo1 --report "$ROOT/fix-report.md" --started-at "$start"
  printf '%s|%s|%s\n' "$RC" "$(ledger '.lastStep')" "$(sed -n 's/^stopped: //p' "$OUT")"
)
expect "fix-record records the round, and nothing stops the order" "$(fix_case)" '0|fixed|none'

finish
