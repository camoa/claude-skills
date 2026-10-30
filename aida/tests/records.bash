# shellcheck shell=bash disable=SC2034 # the spec that sources this file reads IMPLEMENT, OUT and RC
# records.bash: the one setup the plugin's own specs share. A spec sources it and is never run by
# it. Each function writes the few records one step reads, straight to disk, and runs no stage
# action. So no setup performs the step a spec guards. The branch stays where the spec puts it.
# No answer is written until the spec writes one.
# Everything lives under one temporary folder, removed on exit. The registry and the settings file
# are kept there too, so a run reads nothing from the machine it runs on. bash 3.2 and later.
PLUGIN="${PLUGIN:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
IMPLEMENT="$PLUGIN/skills/implement/scripts/implement-actions.sh"
REVIEW="$PLUGIN/skills/review/scripts/review-actions.sh"
COMPLETION="$PLUGIN/skills/completion/scripts/completion-actions.sh"
ROOT="$(mktemp -d)" || exit 1
ROOT="$(cd "$ROOT" && pwd -P)"
trap 'rm -rf "$ROOT"' EXIT
export AIDA_REGISTRY_PATH="$ROOT/registry.json" AIDA_PROJECTS_HOME="$ROOT/projects"
export AIDA_SETTINGS_PATH="$ROOT/settings.json" GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=aida-test GIT_AUTHOR_EMAIL=aida-test@example.invalid
export GIT_COMMITTER_NAME=aida-test GIT_COMMITTER_EMAIL=aida-test@example.invalid
unset AIDA_SESSION_PLUGIN_VERSION AIDA_SESSION_CHECKED CLAUDE_PLUGIN_ROOT
CODE="$ROOT/code"
PROJECT="$ROOT/projects/p"
TASK="$PROJECT/tasks/t1"
IMPL="$TASK/implementation"
WT="$ROOT/wt"
OUT="$ROOT/out.txt"
RECIPE="$ROOT/test-recipe.md"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

PASS=0; TOTAL=0
# expect <what> <actual> <wanted>: prints ok or BAD with both values, and counts.
expect() {
  TOTAL=$((TOTAL + 1))
  if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); printf 'ok: %s\n' "$1"
  else printf 'BAD: %s\n  actual: %s\n  wanted: %s\n' "$1" "$2" "$3"; fi
}
# The last line of every spec, and its exit.
finish() {
  printf 'passed %s of %s\n' "$PASS" "$TOTAL"
  [ "$PASS" -eq "$TOTAL" ]
}

# run <script> <args>...: runs a plugin script from the task's worktree, where every stage action
# runs. Output goes to $OUT. Sets RC.
run() {
  (cd "$WT" && bash "$@") >"$OUT" 2>&1
  RC=$?
}

# task_records [branch] [wo2]: a code repository whose trunk is main, a registered project folder
# that is a git repository, task t1 with its worktree, a contract with one machine-verified
# criterion, and work order wo1 that owns a.php and tests/a_test.sh. With wo2, a second order
# owns b.php and criterion c2, and depends on wo1. Design is closed over the orders. The worktree holds the trunk,
# or the work branch feature/t1 when an argument is branch. The task's base is the trunk.
task_records() {
  local arg branch=main second=false
  for arg in "$@"; do
    case "$arg" in
      branch) branch=feature/t1 ;;
      wo2) second=true ;;
    esac
  done
  mkdir -p "$CODE" "$TASK/design" "$IMPL" || exit 1
  git -C "$CODE" init -q -b main
  printf 'a\n' >"$CODE/a.php"
  git -C "$CODE" add a.php && git -C "$CODE" commit -qm init
  git -C "$CODE" remote add origin "$CODE"
  git -C "$CODE" update-ref refs/remotes/origin/main main
  git -C "$CODE" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  git -C "$CODE" checkout -q --detach
  if [ "$branch" = main ]; then git -C "$CODE" worktree add -q "$WT" main
  else git -C "$CODE" worktree add -q -b "$branch" "$WT" main; fi
  jq -n --arg c "$CODE" '{schemaVersion: 1, codePath: $c, name: "p", frameworks: ["fake"], state: "active"}' \
    >"$PROJECT/project.json"
  jq -n --arg c "$CODE" --arg p "$PROJECT" \
    '{version: 1, projects: [{codePath: $c, path: $p, name: "p", state: "active"}], declinedOffers: [], directoryChoices: []}' \
    >"$AIDA_REGISTRY_PATH"
  jq -n --arg w "$WT" --arg b "$branch" \
    '{schemaVersion: 1, id: "t1", state: "in_progress", parent: null, children: [], worktree: {path: $w, branch: $b, base: "main"}}' \
    >"$TASK/task.json"
  jq -n --argjson second "$second" '
    [{id: "c1", text: "a.php says b"}] + (if $second then [{id: "c2", text: "b.php exists"}] else [] end)
    | {schemaVersion: 1, goal: "change a", expectedResult: "a changed",
       criteria: map(. + {verification: "run the test", verifiedBy: "machine", author: "owner", verdict: "unanswered"}),
       nonGoals: [], nextCriterionId: (length + 1), nextNonGoalId: 1, decidedWithoutAPerson: []}' >"$TASK/alignment.json"
  jq -n '{schemaVersion: 1, id: "wo1", title: "change a", criteriaServed: ["c1"], criteriaOwned: ["c1"],
      nonGoals: [], dependsOn: [], ownedFiles: ["a.php", "tests/a_test.sh"], surfaces: [], interface: "none",
      tests: [{description: "a.php says b"}], doneWhen: ["a.php says b"], reasoning: "the contract asks it",
      diffBudget: "small", findings: []}' >"$TASK/design/wo1.json"
  [ "$second" = false ] \
    || jq '.id = "wo2" | .title = "add b" | .criteriaServed = ["c2"] | .criteriaOwned = ["c2"] | .dependsOn = ["wo1"] | .ownedFiles = ["b.php"]' \
      "$TASK/design/wo1.json" >"$TASK/design/wo2.json"
  # shellcheck source=/dev/null
  source "$PLUGIN/scripts/lib/records-hash.sh" || exit 1
  jq -n --arg h "$(records_hash_for "$TASK")" \
    '{schemaVersion: 1, closedAt: "2026-10-28", runMode: "interactive", closedBy: "person", hash: $h}' \
    >"$TASK/design-closed.json"
  git -C "$PROJECT" init -q && git -C "$PROJECT" add -A && git -C "$PROJECT" commit -qm "task t1, design closed"
}

# order_records <step> [<allows>]: the snapshot of the closed design and a ledger with every order
# at <step>, such as planned, tests-frozen or code-written. With <allows>, a JSON array of go-on
# choices, wo1 is stopped for one reason that allows them.
order_records() {
  local hash
  hash="$(jq -r '.hash' "$TASK/design-closed.json")"
  jq -n --arg h "$hash" --slurpfile a "$TASK/alignment.json" --slurpfile w <(cat "$TASK"/design/wo*.json) \
    '{schemaVersion: 1, takenAt: "2026-10-28", hash: $h, alignment: $a[0], workOrders: $w}' >"$IMPL/snapshot.json"
  jq -n --arg h "$hash" --arg from "$(git -C "$WT" rev-parse HEAD)" --arg step "$1" --argjson allows "${2:-null}" \
    --slurpfile a "$TASK/alignment.json" --slurpfile w <(cat "$TASK"/design/wo*.json) '
    {schemaVersion: 1, startedFrom: $from, startedAt: "2026-10-28T00:00:00Z", runMode: "interactive",
     snapshotHash: $h,
     orders: [ $w[] | {id, lastStep: (if $step == "planned" then null else $step end), attemptsUsed: 0, roundsUsed: 0}
       + (if $allows == null or .id != "wo1" then {} else {stopped: [{step: "build-record", reason: "a stop", allows: $allows}]} end) ],
     criteria: [ $a[0].criteria[] | {id, rowState: "not-judged"} ]}' >"$IMPL/ledger.json"
}

# order_commit: one commit of wo1's builder in the worktree that changes a.php, listed on wo1's
# ledger entry the way a stopped builder's commits are.
order_commit() {
  printf 'b\n' >"$WT/a.php"
  git -C "$WT" commit -qam "build wo1"
  jq --arg c "$(git -C "$WT" rev-parse HEAD)" '(.orders[] | select(.id == "wo1")).unrecordedCommits = [$c]' \
    "$IMPL/ledger.json" >"$IMPL/ledger.new" && mv "$IMPL/ledger.new" "$IMPL/ledger.json"
}

# test_recipe: the fake framework's test recipe at $RECIPE. Its suite row runs $ROOT/suite.sh,
# which prints the lines of $ROOT/suite-now.txt and fails when there is one. Its file row runs the
# given test files with sh, so a test's own exit decides.
test_recipe() {
  printf 'cat "%s/suite-now.txt" 2>/dev/null\n[ ! -s "%s/suite-now.txt" ]\n' "$ROOT" "$ROOT" >"$ROOT/suite.sh"
  cat >"$RECIPE" <<EOR
---
name: fake_test_execution
capability: test-execution
recipe_class: process
framework: fake
---

## Test commands

\`\`\`yaml
test_commands:
  - id: suite
    argv: ["sh", "$ROOT/suite.sh"]
    cost: every-attempt
  - id: file
    argv: ["sh", "{paths}"]
    cost: every-attempt
  - id: test
    absent: >-
      No single-test form.
  - id: changed
    absent: >-
      No changed form.
  - id: smoke
    argv: ["true"]
    cost: every-attempt
  - id: mutation
    absent: >-
      No mutation tool.
\`\`\`
EOR
}

# suite_records <baseline failures> [<failures now>]: preconditions.json naming $RECIPE for fake,
# and baseline.json taken at the ledger's startedFrom. Each argument holds failure lines, one per
# line. The baseline suite printed the first and failed when it holds one. The suite run at the
# final commit prints the second and fails the same way. Run after order_records.
suite_records() {
  test_recipe
  printf '%s' "${2:-}" >"$ROOT/suite-now.txt"
  mkdir -p "$IMPL/baseline-output"
  printf '%s' "$1" >"$IMPL/baseline-output/suite-fake.txt"
  jq -n --arg r "$RECIPE" --arg s "$ROOT/suite.sh" '
    {schemaVersion: 1, takenAt: "2026-10-28", verdict: "undeclared",
     frameworks: [{framework: "fake", lookup: "resolved", verdict: "undeclared", entries: [],
       testCommands: {state: "ok", rows: [
         {id: "suite", argv: ["sh", $s], cost: "every-attempt"}, {id: "file", argv: ["sh", "{paths}"], cost: "every-attempt"},
         {id: "test", absent: true}, {id: "changed", absent: true},
         {id: "smoke", argv: ["true"], cost: "every-attempt"}, {id: "mutation", absent: true}]},
       smoke: {verdict: "met", exitCode: 0}, implementLookup: "no-recipe", reviewLookup: "no-recipe", recipePath: $r}]}' \
    >"$IMPL/preconditions.json"
  local undeclared='{verdict: "undeclared", reason: "no resolved check recipe carries a row for this tool"}'
  jq -n --arg c "$(jq -r '.startedFrom' "$IMPL/ledger.json")" --arg out "$1" --slurpfile s "$IMPL/snapshot.json" "
    {schemaVersion: 1, takenAt: \"2026-10-28\", commit: \$c, scope: [ \$s[0].workOrders[].ownedFiles[] ],
     suite: [{framework: \"fake\", verdict: (if \$out == \"\" then \"met\" else \"unmet\" end),
       exitCode: (if \$out == \"\" then 0 else 1 end), output: \$out, outputFile: \"baseline-output/suite-fake.txt\"}],
     codingStandards: $undeclared, staticAnalysis: $undeclared, security: $undeclared,
     toolRows: {}, checkRecipes: [], tree: {head: \$c, uncommitted: []}}" >"$IMPL/baseline.json"
}

# tests_record: wo1's test tests/a_test.sh, which fails, committed in the worktree, and its frozen
# record, as tests-freeze writes them. The ledger step stays the one order_records wrote.
tests_record() {
  mkdir -p "$WT/tests"
  printf 'echo a does not say b\nexit 1\n' >"$WT/tests/a_test.sh"
  git -C "$WT" add tests/a_test.sh && git -C "$WT" commit -qm "freeze wo1"
  records_hash__resolve_sha256_cmd || exit 1
  jq -n --arg c "$(git -C "$WT" rev-parse HEAD)" --arg sha "$("${RECORDS_HASH_SHA256_CMD[@]}" "$WT/tests/a_test.sh" | cut -d' ' -f1)" \
    --arg r "$RECIPE" '
    {schemaVersion: 1, takenAt: "2026-10-28", unit: "wo1", commit: $c, testGlobs: ["tests/*_test.sh"],
     rows: [{criterion: "c1", kind: "machine", tests: [{path: "tests/a_test.sh", name: "a says b", sha256: $sha,
       red: "a does not say b", redSignal: "unchecked"}]}],
     proof: "tests", support: [], freezeCommits: [$c], testRecipePath: {fake: $r}}' >"$IMPL/tests-wo1.json"
}

# dispatch_record <role>: the open dispatch of aida:<role> for wo1, as dispatch-open writes it. A
# test author may not read a.php. An implementer's or a fixer's record names the files wo1 owns.
dispatch_record() {
  jq -n --arg r "aida:$1" --arg w "$WT" --arg at "$NOW" --slurpfile o "$TASK/design/wo1.json" '
    {schemaVersion: 1, role: $r, task: "t1", unit: "wo1", codePath: $w, openedAt: $at,
     denyRead: (if $r == "aida:test-author" then ["a.php"] else [] end),
     allowWrite: (if $r == "aida:test-author" then ["tests/a_test.sh"] else ["a.php"] end)}
    + (if $r == "aida:implementer" or $r == "aida:fixer" then {ownedFiles: $o[0].ownedFiles} else {} end)' \
    >"$IMPL/dispatch.json"
}

# answer <step> <order> <words>: the person's answer, through person-answer.sh. An empty <order> is
# a step for the whole task.
answer() {
  bash "$PLUGIN/skills/task/scripts/person-answer.sh" --project "$PROJECT" t1 --step "$1" ${2:+--order "$2"} -- "$3" \
    >/dev/null || exit 1
}

# write_hook <tool input> [<agent type>]: the write hook's decision on one call from $HOOK_CWD, else
# the worktree, deny, ask or allow. A command in the input makes it a Bash call, else a Write. With
# no agent type, the call is the main session's. The hook's output stays in $ROOT/hook.json.
write_hook() {
  local tool=Write
  [ "$(printf '%s' "$1" | jq 'has("command")')" = true ] && tool=Bash
  jq -nc --arg t "$tool" --argjson i "$1" --arg c "${HOOK_CWD:-$WT}" --arg a "${2:-}" \
    '{tool_name: $t, tool_input: $i, cwd: $c, permission_mode: "default", session_id: "s1"}
     + (if $a == "" then {} else {agent_type: $a, agent_id: "a1"} end)' \
    | CLAUDE_PLUGIN_ROOT="$PLUGIN" bash "$PLUGIN/hooks/deny-frozen-test-writes.sh" | tee "$ROOT/hook.json" | jq -r '.hookSpecificOutput.permissionDecision // "allow"'
}
file() { jq -nc --arg f "$1" '{file_path: $f}'; }

# ledger <jq filter>: reads wo1's ledger entry.
ledger() { jq -r ".orders[] | select(.id == \"wo1\") | $1" "$IMPL/ledger.json"; }

# review_records [light] [<step>]: task t1 built on its branch, every order at <step>, default
# code-written, finish recorded over the one build commit, and c1 a person's criterion. With
# light, the task runs light.
review_records() {
  task_records branch
  jq '.criteria[0].verifiedBy = "person"' "$TASK/alignment.json" >"$ROOT/a.json" && mv "$ROOT/a.json" "$TASK/alignment.json"
  [ "${1:-}" != light ] || { jq '.runMode = "light"' "$TASK/task.json" >"$ROOT/t.json" && mv "$ROOT/t.json" "$TASK/task.json"; }
  order_records "${2:-code-written}"
  order_commit
  jq -n --arg r "$(git -C "$WT" rev-parse HEAD~1)..$(git -C "$WT" rev-parse HEAD)" \
    '{schemaVersion: 1, commitRange: $r, criteria: [{id: "c1", verifiedBy: "person"}], checklists: []}' >"$IMPL/finished.json"
  mkdir -p "$TASK/review/evidence" "$TASK/records"
}

# reviewed_record [<recipes JSON>]: the review record as findings leaves it, at the worktree's head.
reviewed_record() {
  jq -n --arg at "$(git -C "$WT" rev-parse HEAD)" --arg r "$(jq -r '.commitRange' "$IMPL/finished.json")" --argjson rc "${1:-[]}" '
    {schemaVersion: 1, takenAt: "2026-10-28", task: "t1", reviewedRange: $r, reviewedAt: $at, hasUpstream: false,
     runMode: "interactive", recipes: $rc, criteria: [], findings: [], surfaces: [], catalogNotes: [],
     mutation: {verdict: "undeclared", detail: "no row", survivors: []},
     checks: [{id: "solid", verdict: "met", detail: "none"}]}' >"$TASK/review/review.json"
}

# evidence <row JSON>...: the verifier's file with these rows.
evidence() { jq -n '{rows: [$ARGS.positional[] | fromjson]}' --args "$@" >"$TASK/records/evidence.json"; }
c1_row() { jq -nc --arg p "${2:-}" --arg v "${1:-met}" '{criterion: "c1", sentence: "the export holds three rows", path: $p, verdict: $v, note: "three rows came out"}'; }

# edit <file> <jq filter> [<jq argument>]...: rewrites one JSON record through the filter.
edit() {
  local f="$1" filter="$2"
  shift 2
  jq "$@" "$filter" "$f" >"$ROOT/edit.json" && mv "$ROOT/edit.json" "$f"
}

# owed_records: wo1 closed and reopened for a wrong test, tests/a_test.sh frozen and retired.
owed_records() {
  task_records branch
  order_records reviewed
  tests_record
  edit "$IMPL/ledger.json" '(.orders[] | select(.id == "wo1")).repairs = [{review: "r", reviewFindings: ["f1"], findings: ["f1"],
    at: "2026-10-28", testOwed: true, retires: ["tests/a_test.sh"]}]'
}
