#!/usr/bin/env bash
# review-completion-spec.sh: the task review records warnings and fails only on a criterion, the
# one unattended stop is completion's, and a person's ruling at close reaches its route. A wrong
# frozen test goes back to its order's test author through reopen, and a criterion with wrong
# wording is handed to scope as a follow-up. Each case sources the helper in a subshell, so it
# starts from fresh records.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=records.bash
source "$HERE/records.bash"

# closed_with <close arguments>...: the acceptance step with c1's row met, then close.
closed_with() {
  evidence "$(c1_row)"
  run "$REVIEW" acceptance "$TASK"
  run "$REVIEW" acceptance "$TASK" --evidence
  run "$REVIEW" close "$TASK" "$@"
}

# passed_record [<warnings JSON>]: a closed review that passed with these warnings, c1 met.
passed_record() {
  reviewed_record
  edit "$TASK/review/review.json" '.verdict = "passed" | .warnings = $w
    | .criteria = [{id: "c1", verifiedBy: "person", verdict: "met", answeredBy: "person"}]' --argjson w "${1:-[]}"
  edit "$TASK/alignment.json" '.criteria[0].verdict = "met"'
}

echo "--- review close: warnings, and the verdict"
verdict_case() (
  source "$HERE/records.bash"
  review_records
  reviewed_record
  edit "$TASK/review/review.json" '.checks += [{id: "security", verdict: "unmet", detail: "a finding"}]'
  closed_with --row c1=met
  jq -r '.verdict + "|" + ([ (.warnings // [])[].id ] | join(","))' "$TASK/review/review.json"
)
expect "a check reading unmet is a warning, and every criterion met passes" "$(verdict_case)" "passed|security"

unasked_case() (
  source "$HERE/records.bash"
  review_records
  reviewed_record
  closed_with --row c1=met --row c9=met
  printf '%s|%s|%s\n' "$RC" "$(jq -r '.verdict' "$TASK/review/review.json")" \
    "$(jq '[ (.warnings // [])[] | select(.step == "review close") ] | length' "$TASK/task.json")"
)
expect "an answer to a row nobody asked is ignored and named in the task record" "$(unasked_case)" "0|passed|1"

low_case() (
  source "$HERE/records.bash"
  review_records
  reviewed_record
  edit "$TASK/review/review.json" '.checks += [
    {id: "serves-a-criterion", verdict: "met", detail: "x", scriptHalf: {verdict: "met", detail: "x"}},
    {id: "test-and-mutation", verdict: "met", detail: "x", scriptHalf: {verdict: "met", detail: "x"}}]'
  jq -n '{findings: [{id: "f1", lens: "solid", severity: "low", file: "a.php", lines: "1", linkedTo: "", evidence: "a nit"}]}' >"$ROOT/findings.json"
  run "$REVIEW" findings "$TASK" --findings "$ROOT/findings.json"
  jq -r '.checks[] | select(.id == "solid") | .verdict + "|" + (has("answeredBy") | tostring)' "$TASK/review/review.json"
)
expect "a lens with low findings only reads met, and asks the person nothing" "$(low_case)" "met|false"

moved_case() (
  source "$HERE/records.bash"
  review_records
  reviewed_record
  edit "$TASK/review/review.json" '.checks += [
    {id: "serves-a-criterion", verdict: "met", detail: "x", scriptHalf: {verdict: "met", detail: "x"}},
    {id: "test-and-mutation", verdict: "met", detail: "x", scriptHalf: {verdict: "met", detail: "x"}}]'
  printf 'c\n' >"$WT/a.php" && git -C "$WT" commit -qam "moved"
  printf '{"findings": []}\n' >"$ROOT/findings.json"
  run "$REVIEW" findings "$TASK" --findings "$ROOT/findings.json"
  local attended
  attended="$RC|$(jq '[ (.warnings // [])[] | select(.step == "review findings") ] | length' "$TASK/task.json")"
  edit "$TASK/task.json" '.runMode = "autonomous"'
  run "$REVIEW" findings "$TASK" --findings "$ROOT/findings.json"
  printf '%s|%s\n' "$attended" "$RC"
)
expect "code moved since checks warns attended and stops unattended" "$(moved_case)" "0|1|51"

echo "--- the four rows from the 2026-10-28 scan"
# halves_record: the review record as checks leaves it, with checks 3 and 4 met on their script half.
halves_record() {
  reviewed_record
  edit "$TASK/review/review.json" '.checks += [
    {id: "serves-a-criterion", verdict: "met", detail: "x", scriptHalf: {verdict: "met", detail: "x"}},
    {id: "test-and-mutation", verdict: "met", detail: "x", scriptHalf: {verdict: "met", detail: "x"}}]'
}
env_case() (
  source "$HERE/records.bash"
  review_records
  mkdir -p "$WT/.ddev" && printf 'name: t1\n' >"$WT/.ddev/config.yaml"
  git -C "$WT" add .ddev/config.yaml && git -C "$WT" commit -qm "the site of t1"
  edit "$TASK/task.json" '.worktree.recipeChanges = [{path: ".ddev/config.yaml", blob: $b}]' \
    --arg b "$(git -C "$WT" rev-parse HEAD:.ddev/config.yaml)"
  edit "$IMPL/finished.json" '.commitRange = $r' --arg r "$(git -C "$WT" rev-parse HEAD~2)..$(git -C "$WT" rev-parse HEAD)"
  halves_record
  jq -n '{findings: [{id: "f1", lens: "purpose", severity: "high", file: ".ddev/config.yaml", lines: "1",
    linkedTo: "", evidence: "serves no criterion"}]}' >"$ROOT/findings.json"
  run "$REVIEW" findings "$TASK" --findings "$ROOT/findings.json"
  jq -r '([ .checks[] | select(.id == "serves-a-criterion") ][0].verdict) + "|" + (.findings | length | tostring)' "$TASK/review/review.json"
)
expect "a purpose finding on a file the environment wrote is not recorded (row 469)" "$(env_case)" "met|0"

nocriterion_case() (
  source "$HERE/records.bash"
  review_records
  reviewed_record
  edit "$TASK/review/review.json" '.findings = [{id: "f1", lens: "solid", severity: "high", file: "a.php", lines: "1",
    linkedTo: "", evidence: "a god class", disposition: "follow-up"}]
    | .checks = [{id: "solid", verdict: "unmet", detail: "f1"}]'
  closed_with --row c1=met
  printf '%s|' "$(jq -r '.verdict' "$TASK/review/review.json")"
  run "$COMPLETION" read "$TASK"
  grep -c '^followUp(f1): ' "$OUT"
)
expect "a finding that cites no criterion warns, and completion offers it as a task (row 470)" "$(nocriterion_case)" "passed|1"

# rebuild_case <listed|hand>: wo1's departure waits, and a later commit changes a.php. With listed,
# wo1's own fix record lists that commit; with hand, no record of wo1 does.
rebuild_case() (
  source "$HERE/records.bash"
  review_records "" closed
  jq -n --arg c "$(git -C "$WT" rev-parse HEAD)" '{schemaVersion: 1, unit: "wo1", reviewedAt: $c, findings: [], rounds: [],
    deviationPending: {departure: "a.php reads the old file", file: "report.md"}}' >"$IMPL/review-wo1.json"
  printf 'rebuilt\n' >"$WT/a.php" && git -C "$WT" commit -qam "rebuild wo1 to the design"
  [ "$1" != listed ] || jq -n --arg c "$(git -C "$WT" rev-parse HEAD)" '{unit: "wo1", commits: [$c]}' >"$IMPL/fix-wo1-1.json"
  edit "$IMPL/finished.json" '.commitRange = $r' --arg r "$(git -C "$WT" rev-parse HEAD~2)..$(git -C "$WT" rev-parse HEAD)"
  reviewed_record
  edit "$TASK/review/review.json" '.checks += [{id: "decision-wo1-departure", verdict: "unknown", answeredBy: "nobody",
    detail: "wo1 departs from the design"}]'
  closed_with --row c1=met --row decision-wo1-departure=rebuild
  jq -r '.checks[] | select(.id == "decision-wo1-departure") | .verdict' "$TASK/review/review.json"
)
expect "a commit the order's own fix record lists is no rebuild, so rebuild reads unmet (row 471)" "$(rebuild_case listed)" "unmet"
expect "a later commit no record of the order lists is no rebuild (row 471)" "$(rebuild_case hand)" "unmet"

stale_case() (
  source "$HERE/records.bash"
  review_records
  reviewed_record
  closed_with --row c1=met --row decision-wo1-f2=deferred
  printf '%s|%s\n' "$RC" "$(jq -r '.verdict' "$TASK/review/review.json")"
)
expect "a decision row from an earlier pass is named and dropped, and close goes on (row 472)" "$(stale_case)" "0|passed"

# ids_case: an earlier pass, archived, recorded the god-class finding as f2. The reviewer of this
# pass numbers it f1 and a new finding f2. Prints the id the god-class finding keeps, and the id
# the new one gets.
ids_case() (
  source "$HERE/records.bash"
  review_records
  halves_record
  jq '.verdict = "failed" | .findings = [
    {id: "f1", lens: "dry", severity: "medium", file: "b.php", lines: "2", linkedTo: "", evidence: "a copy", disposition: "follow-up"},
    {id: "f2", lens: "solid", severity: "high", file: "a.php", lines: "1", linkedTo: "", evidence: "a god class", disposition: "follow-up"}]' \
    "$TASK/review/review.json" >"$TASK/review/review-2026-10-27-abc1234.json"
  jq -n '{findings: [{id: "f1", lens: "solid", severity: "high", file: "a.php", lines: "1", linkedTo: "", evidence: "a god class"},
    {id: "f2", lens: "solid", severity: "low", file: "a.php", lines: "9", linkedTo: "", evidence: "a long name"}]}' >"$ROOT/findings.json"
  run "$REVIEW" findings "$TASK" --findings "$ROOT/findings.json"
  jq -r '[ (.findings[] | select(.evidence == "a god class") | .id), (.findings[] | select(.evidence == "a long name") | .id) ] | join("|")' \
    "$TASK/review/review.json"
)
expect "a finding keeps its id across passes while its content is the same, and a new one takes a fresh id (row 472)" \
  "$(ids_case)" "f2|f3"

echo "--- checks: the task's own change set (row 441)"
merge_case() (
  source "$HERE/records.bash"
  task_records branch
  order_records code-written
  order_commit
  git -C "$CODE" checkout -q main && printf 'c\n' >"$CODE/c.php" && git -C "$CODE" add c.php \
    && git -C "$CODE" commit -qm "trunk work" && git -C "$CODE" checkout -q --detach
  git -C "$WT" merge -q --no-edit main
  jq -n --arg r "$(jq -r '.startedFrom' "$IMPL/ledger.json")..$(git -C "$WT" rev-parse HEAD)" \
    '{schemaVersion: 1, commitRange: $r, criteria: [{id: "c1", verifiedBy: "machine"}], checklists: []}' >"$IMPL/finished.json"
  suite_records ""
  run "$REVIEW" checks "$TASK" --lookup-failed fake=no-recipe
  printf '%s|%s\n' "$(jq -r '.checks[] | select(.id == "serves-a-criterion") | .verdict' "$TASK/review/review.json")" \
    "$(sed -n 's/^changedFiles: //p' "$OUT")"
)
expect "a file trunk changed, merged into the branch, is not the task's change" "$(merge_case)" "met|1"

echo "--- a criterion's wording is wrong (row 450)"
contract_case() (
  source "$HERE/records.bash"
  review_records "" closed
  reviewed_record
  edit "$TASK/review/review.json" '.findings = [{id: "f1", lens: "solid", severity: "high", file: "a.php", lines: "1",
    linkedTo: "c1", evidence: "c1 names a block", disposition: "criterion"}]'
  closed_with --row c1=met --row "f1=contract-wrong:a.php says b or c"
  printf '%s|%s|%s|' "$RC" "$(jq -r '.findings[0] | .ruling + "|" + .correctedText' "$TASK/review/review.json")" \
    "$(jq -r '.criteria[0].verdict' "$TASK/review/review.json")"
  run "$COMPLETION" read "$TASK"
  grep -c '^followUp(f1): ' "$OUT"
)
expect "contract-wrong keeps the corrected text, clears the criterion, and is offered as a follow-up" "$(contract_case)" \
  "0|contract-wrong|a.php says b or c|met|1"

echo "--- a frozen test is wrong (row 449)"
test_wrong_case() (
  source "$HERE/records.bash"
  review_records "" closed
  tests_record
  printf '{"findings": []}\n' >"$IMPL/review-wo1.json"
  reviewed_record
  edit "$TASK/review/review.json" '.findings = [{id: "f1", lens: "solid", severity: "high", file: "tests/a_test.sh", lines: "1",
    linkedTo: "c1", evidence: "the test reads the wrong file", disposition: "criterion"}]'
  closed_with --row c1=met --row f1=test-wrong
  run "$IMPLEMENT" reopen "$TASK"
  printf '%s|%s|%s\n' "$RC" "$(ledger '(.repairs[0].retires // []) | join(",")')" "$(ledger '.repairs[0].testOwed')"
)
expect "reopen sends a test ruled wrong to its order, which owes the corrected test" "$(test_wrong_case)" \
  "0|tests/a_test.sh|true"

decision_wrong_case() (
  source "$HERE/records.bash"
  review_records "" closed
  tests_record
  jq -n '{schemaVersion: 1, unit: "wo1", findings: [{id: "f2", severity: "medium", file: "tests/a_test.sh", lines: "1",
    linkedTo: "c1", evidence: "the test reads the wrong file", status: "pending"}]}' >"$IMPL/review-wo1.json"
  reviewed_record
  edit "$TASK/review/review.json" '.verdict = "passed" | .checks += [{id: "decision-wo1-f2", verdict: "unmet",
    answeredBy: "person", answer: "test-wrong", detail: "wo1 finding f2 waits"}]'
  run "$IMPLEMENT" reopen "$TASK"
  printf '%s|%s|%s\n' "$RC" "$(ledger '(.repairs[0].retires // []) | join(",")')" "$(ledger '.repairs[0].testOwed')"
)
expect "a build's decision ruled test-wrong takes the same route to its order's test author" "$(decision_wrong_case)" \
  "0|tests/a_test.sh|true"

lens_wrong_case() (
  source "$HERE/records.bash"
  review_records "" closed
  tests_record
  printf '{"findings": []}\n' >"$IMPL/review-wo1.json"
  reviewed_record
  edit "$TASK/review/review.json" '.findings = [{id: "f1", lens: "solid", severity: "high", file: "tests/a_test.sh", lines: "1",
    linkedTo: "", evidence: "the test asserts an internal", disposition: "follow-up"}]'
  closed_with --row c1=met --row f1=test-wrong
  printf '%s|' "$(jq -r '[ .warnings[].id ] | join(",")' "$TASK/review/review.json")"
  run "$IMPLEMENT" reopen "$TASK"
  printf '%s|%s\n' "$RC" "$(ledger '(.repairs[0].retires // []) | join(",")')"
)
expect "a test ruled wrong on a finding with no criterion warns, and reopen routes it" "$(lens_wrong_case)" "f1|0|tests/a_test.sh"

no_text_case() (
  source "$HERE/records.bash"
  review_records "" closed
  reviewed_record
  edit "$TASK/review/review.json" '.findings = [{id: "f1", lens: "solid", severity: "high", file: "a.php", lines: "1",
    linkedTo: "c1", evidence: "c1 names a block", disposition: "criterion"}]'
  closed_with --row c1=met --row "f1=contract-wrong:"
  printf '%s|%s|%s\n' "$RC" "$(jq -r '.findings[0].ruling // "none"' "$TASK/review/review.json")" \
    "$(jq '[ (.warnings // [])[] | select(.step == "review close") ] | length' "$TASK/task.json")"
)
expect "contract-wrong with no corrected text is named and dropped" "$(no_text_case)" "0|none|1"

# owed_records: wo1 closed and reopened for a wrong test, tests/a_test.sh frozen and retired.
owed_records() {
  task_records branch
  order_records reviewed
  tests_record
  edit "$IMPL/ledger.json" '(.orders[] | select(.id == "wo1")).repairs = [{review: "r", reviewFindings: ["f1"], findings: ["f1"],
    at: "2026-10-28", testOwed: true, retires: ["tests/a_test.sh"]}]'
}
author_case() (
  source "$HERE/records.bash"
  owed_records
  dispatch_record test-author
  printf '%s|%s\n' "$(write_hook "$(file "$WT/tests/a_test.sh")" aida:test-author)" \
    "$(write_hook "$(file "$WT/tests/a_test.sh")" aida:implementer)"
)
expect "the repair's test author may rewrite the retired test, and the implementer may not" "$(author_case)" "allow|deny"

refreeze_case() (
  source "$HERE/records.bash"
  owed_records
  suite_records ""
  printf 'exit 0\n' >"$WT/tests/a_test.sh"
  run "$IMPLEMENT" tests-freeze "$TASK" wo1 --test-glob 'tests/*_test.sh' --test-recipe "fake=$RECIPE" \
    --test "tests/a_test.sh::a says b=c1" --locks-in "a says b=the built a.php says b" --row "c1=confirmed::model::reads a.php"
  printf '%s|%s|%s\n' "$RC" "$(jq -r '.rows[0].tests[0].path' "$IMPL/tests-wo1-repair-1.json" 2>/dev/null)" "$(ledger '.repairs[0] | has("testOwed")')"
)
expect "the corrected copy of a retired test freezes as the repair's own record" "$(refreeze_case)" "0|tests/a_test.sh|false"

# both_case <command>: the repair's test author runs <command> through Bash, with tests/a_test.sh
# retired and tests/b_test.sh frozen too.
both_case() (
  source "$HERE/records.bash"
  owed_records
  edit "$IMPL/tests-wo1.json" '.rows[0].tests += [{path: "tests/b_test.sh", name: "b", sha256: "0", red: "x", redSignal: "unchecked"}]'
  dispatch_record test-author
  write_hook "$(jq -nc --arg c "$1" '{command: $c}')" aida:test-author
)
expect "a Bash write to the retired test alone is allowed" "$(both_case 'echo x > tests/a_test.sh')" "allow"
expect "a Bash write to the retired test and another frozen test is refused" \
  "$(both_case 'echo x > tests/a_test.sh && echo y > tests/b_test.sh')" "deny"
expect "an in-place edit of the retired test and another frozen test is refused" \
  "$(both_case 'sed -i s/a/b/ tests/a_test.sh tests/b_test.sh')" "deny"

supersede_case() (
  source "$HERE/records.bash"
  owed_records
  printf 'exit 0\n' >"$WT/tests/a_test.sh" && git -C "$WT" commit -qam "the corrected test"
  jq --arg sha "$("${RECORDS_HASH_SHA256_CMD[@]}" "$WT/tests/a_test.sh" | cut -d' ' -f1)" --arg c "$(git -C "$WT" rev-parse HEAD)" \
    '.commit = $c | .freezeCommits = [$c] | .rows[0].tests[0].sha256 = $sha' "$IMPL/tests-wo1.json" >"$IMPL/tests-wo1-repair-1.json"
  jq -n --arg r "$(jq -r '.startedFrom' "$IMPL/ledger.json")..$(git -C "$WT" rev-parse HEAD)" \
    '{schemaVersion: 1, commitRange: $r, criteria: [{id: "c1", verifiedBy: "machine"}], checklists: []}' >"$IMPL/finished.json"
  suite_records ""
  run "$REVIEW" checks "$TASK" --lookup-failed fake=no-recipe
  printf '%s\n' "$RC"
)
expect "a repair's record holds a retired test to its new hash" "$(supersede_case)" "0"

# redo_rebuild_case <answer>: wo1 closed with one commit, finished, and a closed task review over
# that finish whose decision-wo1-departure the person answered <answer>. Then redo, with the
# person's answer. Prints wo1's lastStep, a.php's text, and whether finished.json stays.
redo_rebuild_case() (
  source "$HERE/records.bash"
  task_records branch
  order_records closed
  order_commit
  local range
  range="$(jq -r '.startedFrom' "$IMPL/ledger.json")..$(git -C "$WT" rev-parse HEAD)"
  jq -n --arg r "$range" '{schemaVersion: 1, commitRange: $r}' >"$IMPL/finished.json"
  mkdir -p "$TASK/review"
  jq -n --arg r "$range" --arg a "$1" '{verdict: "passed", reviewedRange: $r, findings: [],
    checks: [{id: "decision-wo1-departure", verdict: "unmet", answeredBy: "person", answer: $a, detail: "wo1 departs"}]}' \
    >"$TASK/review/review.json"
  answer "implement redo" wo1 "rebuild it to the design"
  run "$IMPLEMENT" redo "$TASK" wo1 --because "rebuild it to the design"
  printf '%s|%s|%s\n' "$(ledger '.lastStep')" "$(cat "$WT/a.php")" "$([ -f "$IMPL/finished.json" ] && echo finished || echo open)"
)
expect "redo takes a closed order whose departure the person ruled rebuild at the task review" \
  "$(redo_rebuild_case rebuild)" "null|a|open"
expect "a closed order with no rebuild ruling is still left as it is" "$(redo_rebuild_case keep)" "closed|b|finished"

echo "--- the fix verifier cites the files the fix rests on (row 445)"
# verified <verdict JSON>: wo1 fixed in one round over a.php, verify-brief run, and verify-record
# run on this one verdict for f1. Prints the brief's restsOn and f1's status.
verified() (
  source "$HERE/records.bash"
  task_records branch
  order_records fixed
  order_commit
  edit "$IMPL/ledger.json" '(.orders[] | select(.id == "wo1")) |= (.roundsUsed = 1 | del(.unrecordedCommits))'
  jq -n --arg h "$(git -C "$WT" rev-parse HEAD)" '{schemaVersion: 1, takenAt: "2026-10-28", unit: "wo1", reviewedAt: $h,
    findingsPath: "x", rounds: [], findings: [{id: "f1", severity: "high", file: "a.php", lines: "1", linkedTo: "c1",
    evidence: "a says a", actionable: true, status: "open", origin: "review", fixScope: ["a.php"]}]}' >"$IMPL/review-wo1.json"
  jq -n --arg h "$(git -C "$WT" rev-parse HEAD)" --arg s "$(git -C "$WT" rev-parse HEAD~1)" \
    '{schemaVersion: 1, unit: "wo1", round: 1, startedAt: $s, commit: $h}' >"$IMPL/fix-wo1-1.json"
  run "$IMPLEMENT" verify-brief "$TASK" wo1
  jq -n --argjson v "$1" '{verdicts: [$v]}' >"$ROOT/v.json"
  run "$IMPLEMENT" verify-record "$TASK" wo1 --verdicts "$ROOT/v.json"
  printf '%s|%s\n' "$(jq -r '(.restsOn // []) | join(",")' "$IMPL/brief-wo1-verify-1.json")" \
    "$(jq -r '.findings[] | select(.id == "f1") | .status' "$IMPL/review-wo1.json")"
)
expect "an addressed verdict citing a listed file closes the finding" \
  "$(verified '{"id": "f1", "verdict": "addressed", "file": "a.php", "lines": "1", "evidence": "a says b"}')" "a.php|addressed"
expect "an addressed verdict citing no listed file reads not addressed" \
  "$(verified '{"id": "f1", "verdict": "addressed", "file": "b.php", "lines": "1", "evidence": "fine"}')" "a.php|open"
expect "an addressed verdict naming a file it could not read reads not addressed" \
  "$(verified '{"id": "f1", "verdict": "addressed", "file": "a.php", "lines": "1", "couldNotRead": ["hooks/h.sh"], "evidence": "fine"}')" "a.php|open"

echo "--- completion: the one unattended stop"
stop_case() (
  source "$HERE/records.bash"
  review_records
  passed_record '[{"id": "security", "verdict": "unmet"}]'
  edit "$TASK/task.json" '.runMode = "autonomous"'
  run "$COMPLETION" close "$TASK" -- "done"
  printf '%s|%s\n' "$RC" "$([ -f "$TASK/completion/completed.json" ] && echo written || echo none)"
)
expect "unattended, a passed review with warnings stops completion and writes nothing" "$(stop_case)" "1|none"

child_case() (
  source "$HERE/records.bash"
  review_records
  passed_record
  mkdir -p "$PROJECT/tasks/t2" && jq -n '{schemaVersion: 1, id: "t2", state: "in_progress", parent: "t1", children: []}' >"$PROJECT/tasks/t2/task.json"
  edit "$TASK/task.json" '.children = ["t2"]'
  run "$COMPLETION" close "$TASK" -- "done"
  printf '%s|%s\n' "$RC" "$(jq '[ (.warnings // [])[] | select(.step == "completion close") ] | length' "$TASK/task.json")"
)
expect "an open child is a warning, and the parent closes" "$(child_case)" "0|1"

down_case() (
  source "$HERE/records.bash"
  review_records
  passed_record
  printf -- '---\nname: fake_environment\ncapability: environment\nframework: fake\n---\n\n## Tear down\n\n```sh\ntouch %s/down.txt\n```\n' "$ROOT" >"$ROOT/env.md"
  edit "$TASK/task.json" '.environment = {recipe: $r, address: "http://t1.test", upAt: "2026-10-28"}' --arg r "$ROOT/env.md"
  run "$COMPLETION" close "$TASK" -- "done"
  printf '%s|%s|%s\n' "$RC" "$([ -f "$ROOT/down.txt" ] && echo down || echo up)" "$(jq -r '.environment.recipe // "none"' "$TASK/task.json")"
)
expect "completion takes the task's own site down when the task closes" "$(down_case)" "0|down|none"

finish
