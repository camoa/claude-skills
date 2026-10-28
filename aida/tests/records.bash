# shellcheck shell=bash disable=SC2034 # the spec that sources this file reads IMPLEMENT, OUT and RC
# records.bash: the one setup the plugin's own specs share. A spec sources it and is never run by
# it. Each function writes the few records one step reads, straight to disk. None runs a stage
# action, so no setup performs the step a spec guards: the branch stays where the spec puts it,
# and no answer is written until the spec writes one.
# Everything lives under one temporary folder, removed on exit. The registry and the settings file
# are kept there too, so a run reads nothing from the machine it runs on. bash 3.2 and later.
PLUGIN="${PLUGIN:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
IMPLEMENT="$PLUGIN/skills/implement/scripts/implement-actions.sh"
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

# task_records [branch]: a code repository whose trunk is main, a registered project, task t1 with
# its worktree, a contract with one machine-verified criterion, and work order wo1 that owns a.php
# and tests/a_test.sh. Design is closed over those files. The worktree holds the trunk, or the
# work branch feature/t1 when the argument is branch.
task_records() {
  mkdir -p "$CODE" "$TASK/design" "$IMPL" || exit 1
  git -C "$CODE" init -q -b main
  printf 'a\n' >"$CODE/a.php"
  git -C "$CODE" add a.php && git -C "$CODE" commit -qm init
  git -C "$CODE" remote add origin "$CODE"
  git -C "$CODE" update-ref refs/remotes/origin/main main
  git -C "$CODE" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  git -C "$CODE" checkout -q -b work
  local branch=main
  if [ "${1:-}" = branch ]; then branch=feature/t1; git -C "$CODE" worktree add -q -b "$branch" "$WT"
  else git -C "$CODE" worktree add -q "$WT" main; fi
  jq -n --arg c "$CODE" '{schemaVersion: 1, codePath: $c, name: "p", frameworks: ["fake"], state: "active"}' \
    >"$PROJECT/project.json"
  jq -n --arg c "$CODE" --arg p "$PROJECT" \
    '{version: 1, projects: [{codePath: $c, path: $p, name: "p", state: "active"}], declinedOffers: [], directoryChoices: []}' \
    >"$AIDA_REGISTRY_PATH"
  jq -n --arg w "$WT" --arg b "$branch" \
    '{schemaVersion: 1, id: "t1", state: "in_progress", parent: null, children: [], worktree: {path: $w, branch: $b, base: "work"}}' \
    >"$TASK/task.json"
  jq -n '{schemaVersion: 1, goal: "change a", expectedResult: "a changed",
      criteria: [{id: "c1", text: "a.php says b", verification: "run the test", verifiedBy: "machine",
        author: "owner", verdict: "unanswered"}],
      nonGoals: [], nextCriterionId: 2, nextNonGoalId: 1, decidedWithoutAPerson: []}' >"$TASK/alignment.json"
  jq -n '{schemaVersion: 1, id: "wo1", title: "change a", criteriaServed: ["c1"], criteriaOwned: ["c1"],
      nonGoals: [], dependsOn: [], ownedFiles: ["a.php", "tests/a_test.sh"], surfaces: [], interface: "none",
      tests: [{description: "a.php says b"}], doneWhen: ["a.php says b"], reasoning: "the contract asks it",
      diffBudget: "small", findings: []}' >"$TASK/design/wo1.json"
  # shellcheck source=/dev/null
  source "$PLUGIN/scripts/lib/records-hash.sh" || exit 1
  jq -n --arg h "$(records_hash_for "$TASK")" \
    '{schemaVersion: 1, closedAt: "2026-10-28", runMode: "interactive", closedBy: "person", hash: $h}' \
    >"$TASK/design-closed.json"
}

# order_records <step> [<allows>]: the snapshot of the closed design and a ledger with wo1 at
# <step>, such as planned or built. With <allows>, a JSON array of go-on choices, wo1 is stopped for
# one reason that allows them.
order_records() {
  local hash
  hash="$(jq -r '.hash' "$TASK/design-closed.json")"
  jq -n --arg h "$hash" --slurpfile a "$TASK/alignment.json" --slurpfile w "$TASK/design/wo1.json" \
    '{schemaVersion: 1, takenAt: "2026-10-28", hash: $h, alignment: $a[0], workOrders: $w}' >"$IMPL/snapshot.json"
  jq -n --arg h "$hash" --arg from "$(git -C "$WT" rev-parse HEAD)" --arg step "$1" --argjson allows "${2:-null}" '
    {schemaVersion: 1, startedFrom: $from, startedAt: "2026-10-28T00:00:00Z", runMode: "interactive",
     snapshotHash: $h,
     orders: [{id: "wo1", lastStep: (if $step == "planned" then null else $step end), attemptsUsed: 0, roundsUsed: 0}
       + (if $allows == null then {} else {stopped: [{step: "build-record", reason: "a stop", allows: $allows}]} end)],
     criteria: [{id: "c1", rowState: "not-judged"}]}' >"$IMPL/ledger.json"
}

# order_commit: one commit of wo1's builder in the worktree that changes a.php, listed on wo1's
# ledger entry the way a stopped builder's commits are.
order_commit() {
  printf 'b\n' >"$WT/a.php"
  git -C "$WT" commit -qam "build wo1"
  jq --arg c "$(git -C "$WT" rev-parse HEAD)" '.orders[0].unrecordedCommits = [$c]' "$IMPL/ledger.json" >"$IMPL/ledger.new" \
    && mv "$IMPL/ledger.new" "$IMPL/ledger.json"
}

# answer <step> <order> <words>: the person's answer, as person-answer.sh appends it.
answer() {
  local file="$TASK/person-answers.json"
  [ -f "$file" ] || printf '[]\n' >"$file"
  jq --arg s "$1" --arg o "$2" --arg w "$3" '. + [{step: $s, order: $o, words: $w, answeredAt: "2026-10-28T00:00:00Z"}]' \
    "$file" >"$file.new" && mv "$file.new" "$file"
}

# ledger <jq filter>: reads wo1's ledger entry.
ledger() { jq -r ".orders[] | select(.id == \"wo1\") | $1" "$IMPL/ledger.json"; }
