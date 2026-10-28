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

# redo on wo1, after wo1 and then wo2 each committed: wo1's change is reverted, wo2's stays, and
# no revert names wo2's commit.
redo_case() (
  source "$HERE/records.bash"
  task_records branch wo2
  order_records code-written '["build"]'
  order_commit
  printf 'b\n' >"$WT/b.php"
  git -C "$WT" add b.php && git -C "$WT" commit -qm "build wo2"
  local wo2_commit
  wo2_commit="$(git -C "$WT" rev-parse HEAD)"
  jq --arg c "$wo2_commit" '(.orders[] | select(.id == "wo2")).unrecordedCommits = [$c]' \
    "$IMPL/ledger.json" >"$IMPL/ledger.new" && mv "$IMPL/ledger.new" "$IMPL/ledger.json"
  answer "implement redo" wo1 "start again"
  run "$IMPLEMENT" redo "$TASK" wo1 --because "start again"
  printf '%s|%s|%s|%s\n' "$RC" "$(cat "$WT/a.php")" "$(cat "$WT/b.php" 2>/dev/null)" \
    "$(git -C "$WT" log --format=%B | grep -c "This reverts commit $wo2_commit")"
)
expect "redo reverts its own order's commit and leaves another order's" "$(redo_case)" '0|a|b|0'

# build-record on a record order, whose own check reads deferred: the floor accepts it.
record_build_case() (
  source "$HERE/records.bash"
  task_records branch
  jq --arg doc "$PROJECT/notes/a.md" '.proof = "record" | .tests = [] | .interface = "" | .ownedFiles = [$doc]' \
    "$TASK/design/wo1.json" >"$ROOT/w.json" && mv "$ROOT/w.json" "$TASK/design/wo1.json"
  jq '.criteria[0].verifiedBy = "person"' "$TASK/alignment.json" >"$ROOT/a.json" && mv "$ROOT/a.json" "$TASK/alignment.json"
  git -C "$PROJECT" commit -qam "wo1 is a record order"
  order_records tests-frozen
  jq -n --arg c "$(git -C "$WT" rev-parse HEAD)" \
    '{schemaVersion: 1, takenAt: "2026-10-28", unit: "wo1", commit: $c, testGlobs: [], rows: [],
      proof: "record", support: [], freezeCommits: []}' >"$IMPL/tests-wo1.json"
  local start
  start="$(git -C "$PROJECT" rev-parse HEAD)"
  mkdir -p "$PROJECT/notes" && printf 'a note\n' >"$PROJECT/notes/a.md"
  git -C "$PROJECT" add notes/a.md && git -C "$PROJECT" commit -qm "build wo1"
  printf 'Stop: none\nDeviation: none\n' >"$IMPL/answers-wo1-attempt1.md"
  run "$IMPLEMENT" build-record "$TASK" wo1 --report "$IMPL/answers-wo1-attempt1.md" --interface "$IMPL/interface-wo1.md" \
    --started-at "$start"
  printf '%s|%s|%s\n' "$RC" "$(ledger '.lastStep')" "$(jq -r '[ .checks[] | select(.id == "done-when") | .verdict ][0]' "$IMPL/build-wo1.json" 2>/dev/null)"
)
expect "build-record passes a record order at deferred" "$(record_build_case)" '0|checks-passed|deferred'

# A repair's test freeze, with an earlier repair record of wo1 that does not parse: the freeze
# cannot tell which files an earlier freeze holds, so it refuses and freezes nothing.
repair_case() (
  source "$HERE/records.bash"
  task_records branch
  jq '.ownedFiles = ["a.php", "tests/*_test.sh"]' "$TASK/design/wo1.json" >"$ROOT/w.json" && mv "$ROOT/w.json" "$TASK/design/wo1.json"
  jq --arg h "$(records_hash_for "$TASK")" '.hash = $h' "$TASK/design-closed.json" >"$ROOT/d.json" \
    && mv "$ROOT/d.json" "$TASK/design-closed.json"
  git -C "$PROJECT" commit -qam "wo1 owns its tests folder"
  order_records closed
  suite_records ""
  tests_record
  local range
  range="$(jq -r '.startedFrom' "$IMPL/ledger.json")..$(git -C "$WT" rev-parse HEAD)"
  jq -n '{schemaVersion: 1, unit: "wo1", findings: []}' >"$IMPL/review-wo1.json"
  jq -n --arg r "$range" '{schemaVersion: 1, commitRange: $r}' >"$IMPL/finished.json"
  mkdir -p "$TASK/review"
  jq -n --arg r "$range" '{verdict: "failed", reviewedRange: $r,
      findings: [{id: "f1", disposition: "criterion", severity: "high", file: "a.php", lines: "",
        linkedTo: "c1", lens: "correctness", evidence: "a.php still says a"}]}' >"$TASK/review/review.json"
  run "$IMPLEMENT" reopen "$TASK"
  printf 'not json\n' >"$IMPL/tests-wo1-repair-9.json"
  printf 'echo a still says a\nexit 1\n' >"$WT/tests/a_bug_test.sh"
  printf 'a still says a\n' >"$IMPL/red-bug.txt"
  run "$IMPLEMENT" tests-freeze "$TASK" wo1 --test-glob 'tests/*_test.sh' --test-recipe "fake=$RECIPE" \
    --test "tests/a_bug_test.sh::bug=c1" --red "bug=$IMPL/red-bug.txt" --row "c1=confirmed::model::observes the bug"
  printf '%s|%s\n' "$RC" "$(ls "$IMPL"/tests-wo1-repair-*.json | wc -l | tr -d ' ')"
)
expect "a repair freeze refuses on an earlier repair record that does not parse" "$(repair_case)" '3|1'

# observe_build <jq filter on wo1>: wo1 proved by a look at surface home, changed by the filter,
# after one look whose row judges "the page shows b". Prints build-record's exit and whether it
# wrote a build record.
observe_build() {
  task_records branch
  jq '.proof = "observe" | .surfaces = ["home"] | .tests = [] | .interface = "" | .doneWhen = ["the page shows b"]' \
    "$TASK/design/wo1.json" | jq "$1" >"$ROOT/w.json" && mv "$ROOT/w.json" "$TASK/design/wo1.json"
  jq '.criteria[0].verifiedBy = "person"' "$TASK/alignment.json" >"$ROOT/a.json" && mv "$ROOT/a.json" "$TASK/alignment.json"
  order_records tests-frozen
  jq -n --arg c "$(git -C "$WT" rev-parse HEAD)" \
    '{schemaVersion: 1, takenAt: "2026-10-28", unit: "wo1", commit: $c, testGlobs: [], rows: [],
      proof: "observe", support: [], freezeCommits: []}' >"$IMPL/tests-wo1.json"
  printf 'b\n' >"$WT/a.php" && git -C "$WT" commit -qam "build wo1"
  mkdir -p "$IMPL/observed-wo1"
  : >"$IMPL/observed-wo1/home-wide.png"
  jq -n --arg s "$IMPL/observed-wo1/home-wide.png" '{order: "wo1", observedAt: "2026-10-28", judgedBy: "model",
      rows: [{doneWhen: "the page shows b", surface: "home", viewport: "wide", screenshot: $s, verdict: "met", note: "b shows"}]}' \
    >"$IMPL/observed-wo1.json"
  printf 'Stop: none\nDeviation: none\n' >"$IMPL/answers-wo1-attempt1.md"
  run "$IMPLEMENT" build-record "$TASK" wo1 --report "$IMPL/answers-wo1-attempt1.md" --interface "$IMPL/interface-wo1.md" \
    --started-at "$(git -C "$WT" rev-parse HEAD~1)" --observed "$IMPL/observed-wo1.json"
  printf '%s|%s\n' "$RC" "$([ -f "$IMPL/build-wo1.json" ] && echo written || echo none)"
}

# The surfaces the order names cannot be read as a list, so the surface rows cannot be compared.
surfaces_case() ( source "$HERE/records.bash"; observe_build '.surfaces = 5' )
expect "a failure to compare the look's surfaces refuses, and records no attempt" "$(surfaces_case)" '3|none'
# The done-when rows cannot be joined with the verify checks, so the sentences cannot be compared.
done_when_case() ( source "$HERE/records.bash"; observe_build '.doneWhen = {first: "the page shows b"}' )
expect "a failure to compare the look's sentences refuses, and records no attempt" "$(done_when_case)" '3|none'

# run_proved <record|observe>: wo1 proved by its record or by a look, owning the machine criterion
# c1 that a run line proves. build-record and close run on it, finish's record is written from the
# ledger, and review closes with the suite met. The look's record is gone by then, so only the run
# line can answer c1. Prints close's exit, c1's row state and review's verdict on c1.
run_proved() {
  task_records branch
  local run='[{run: "true", pass: "exit 0", cites: "a finding", binding: true, criterion: "c1"}]'
  if [ "$1" = record ]; then
    jq --arg doc "$PROJECT/notes/a.md" ".proof = \"record\" | .tests = [] | .interface = \"\" | .ownedFiles = [\$doc] | .verify = $run" \
      "$TASK/design/wo1.json" >"$ROOT/w.json" && mv "$ROOT/w.json" "$TASK/design/wo1.json"
    git -C "$PROJECT" commit -qam "wo1 is a record order"
  else
    jq ".proof = \"observe\" | .surfaces = [\"home\"] | .tests = [] | .interface = \"\" | .doneWhen = [\"the page shows b\"] | .verify = $run" \
      "$TASK/design/wo1.json" >"$ROOT/w.json" && mv "$ROOT/w.json" "$TASK/design/wo1.json"
  fi
  order_records tests-frozen
  jq -n --arg c "$(git -C "$WT" rev-parse HEAD)" --arg p "$1" \
    '{schemaVersion: 1, takenAt: "2026-10-28", unit: "wo1", commit: $c, testGlobs: [], rows: [],
      proof: $p, support: [], freezeCommits: []}' >"$IMPL/tests-wo1.json"
  printf 'Stop: none\nDeviation: none\n' >"$IMPL/answers-wo1-attempt1.md"
  local start observed=""
  if [ "$1" = record ]; then
    start="$(git -C "$PROJECT" rev-parse HEAD)"
    mkdir -p "$PROJECT/notes" && printf 'a note\n' >"$PROJECT/notes/a.md"
    git -C "$PROJECT" add notes/a.md && git -C "$PROJECT" commit -qm "build wo1"
  else
    start="$(git -C "$WT" rev-parse HEAD)"
    printf 'b\n' >"$WT/a.php" && git -C "$WT" commit -qam "build wo1"
    mkdir -p "$IMPL/observed-wo1" && : >"$IMPL/observed-wo1/home-wide.png"
    jq -n --arg s "$IMPL/observed-wo1/home-wide.png" '{order: "wo1", observedAt: "2026-10-28", judgedBy: "model",
        rows: [{doneWhen: "the page shows b", surface: "home", viewport: "wide", screenshot: $s, verdict: "met", note: "b shows"}]}' \
      >"$IMPL/observed-wo1.json"
    observed="$IMPL/observed-wo1.json"
  fi
  run "$IMPLEMENT" build-record "$TASK" wo1 --report "$IMPL/answers-wo1-attempt1.md" --interface "$IMPL/interface-wo1.md" \
    --started-at "$start" ${observed:+--observed "$observed"}
  jq '(.orders[] | select(.id == "wo1")).lastStep = "reviewed"' "$IMPL/ledger.json" >"$ROOT/l.json" && mv "$ROOT/l.json" "$IMPL/ledger.json"
  jq -n '{schemaVersion: 1, unit: "wo1", findings: []}' >"$IMPL/review-wo1.json"
  run "$IMPLEMENT" close "$TASK" wo1
  printf '%s|%s|' "$RC" "$(jq -r '.criteria[0].rowState' "$IMPL/ledger.json")"
  rm -f "$IMPL/observed-wo1.json"
  jq -n --arg r "$start..$(git -C "$WT" rev-parse HEAD)" --slurpfile l "$IMPL/ledger.json" '
    {schemaVersion: 1, commitRange: $r, checklists: [],
     criteria: [ $l[0].criteria[] | {id, verifiedBy: "machine", rowState} ]}' >"$IMPL/finished.json"
  mkdir -p "$TASK/review"
  jq -n --arg at "$(git -C "$WT" rev-parse HEAD)" --arg r "$(jq -r '.commitRange' "$IMPL/finished.json")" '
    {schemaVersion: 1, takenAt: "2026-10-28", task: "t1", reviewedRange: $r, reviewedAt: $at, hasUpstream: false,
     runMode: "interactive", recipes: [], criteria: [], findings: [], surfaces: [], catalogNotes: [],
     mutation: {verdict: "undeclared", detail: "no row", survivors: []},
     checks: [{id: "suite", verdict: "met", detail: "finish ran it"}, {id: "solid", verdict: "met", detail: "none"}]}' >"$TASK/review/review.json"
  mkdir -p "$TASK/records" "$TASK/review/evidence"
  jq -n '{rows: [{criterion: "c1", sentence: "the run line passes", path: "", verdict: "met", note: "finish ran the suite"}]}' \
    >"$TASK/records/evidence.json"
  run "$PLUGIN/skills/review/scripts/review-actions.sh" acceptance "$TASK"
  run "$PLUGIN/skills/review/scripts/review-actions.sh" acceptance "$TASK" --evidence
  run "$PLUGIN/skills/review/scripts/review-actions.sh" close "$TASK"
  jq -r '.criteria[0].verdict' "$TASK/alignment.json"
}
record_run_case() ( source "$HERE/records.bash"; run_proved record )
expect "a record order's run-line criterion is confirmed at close and met at review" "$(record_run_case)" '0|confirmed|met'
observe_run_case() ( source "$HERE/records.bash"; run_proved observe )
expect "an observe order's run-line criterion is confirmed at close and met at review" "$(observe_run_case)" '0|confirmed|met'

# broken_repair <action> <args>...: wo1 reviewed, with an open finding, a frozen test record and an
# earlier repair record that does not parse. Prints the exit and whether the message names the
# broken repair record.
broken_repair() {
  task_records branch
  order_records reviewed
  suite_records ""
  tests_record
  jq -n --arg c "$(git -C "$WT" rev-parse HEAD)" '{schemaVersion: 1, unit: "wo1", reviewedAt: $c,
      findings: [{id: "f1", severity: "high", actionable: true, status: "open", file: "a.php", lines: "",
        linkedTo: "c1", evidence: "a.php says a", fixScope: ["a.php"]}]}' >"$IMPL/review-wo1.json"
  jq -n --arg c "$(git -C "$WT" rev-parse HEAD)" '{schemaVersion: 1, unit: "wo1", attempt: 1, startedAt: $c, commit: $c, checks: []}' \
    >"$IMPL/build-wo1.json"
  printf 'not json\n' >"$IMPL/tests-wo1-repair-1.json"
  run "$IMPLEMENT" "$@"
  printf '%s|%s\n' "$RC" "$(grep -c 'tests-wo1-repair-1.json' "$OUT")"
}
fix_brief_case() ( source "$HERE/records.bash"; broken_repair fix-brief "$TASK" wo1 )
expect "fix-brief refuses on a repair record that does not parse, and names it" "$(fix_brief_case)" '3|1'
fix_record_case() (
  source "$HERE/records.bash"
  printf 'Outcome: f1: fixed\n' >"$ROOT/fix-report.md"
  broken_repair fix-record "$TASK" wo1 --report "$ROOT/fix-report.md" --started-at HEAD
)
expect "fix-record refuses on a repair record that does not parse, and names it" "$(fix_record_case)" '3|1'

finish
