#!/usr/bin/env bash
# Fixture du: research rows 122 and 123 from the newyorkcares run. Builds a
# project with one framework and one task with an approved contract, then proves what the scripts
# do: a recipe fit of `unsure` is stored as given with its reason (row 122), and a declined
# recipe is written to task.json by `task decline-recipe`, read back by `research read`, and
# refused when the framework is not declared, when it is repeated, and when the task does not
# exist (row 123). `read` lists inputs/ three levels deep, so an extracted prior-art tree is
# listed on a resumed run (row 125, fix round). Row 124 is prose in the agent and the skill. Runs under bash, which CI runs on Linux, from $HOME, with CLAUDE_PLUGIN_ROOT unset. Setup lives in
# functions, copied from run-dn-fixture.sh.
PLUGIN="${PLUGIN:-$(cd "$(dirname "$0")/../.." && pwd)}"
set -u

PASS=0; TOTAL=0
# expect <what> <actual> <wanted>: prints ok or BAD with both values, and counts.
expect() {
  TOTAL=$((TOTAL + 1))
  if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); printf 'ok: %s\n' "$1"
  else printf 'BAD: %s\n  actual: %s\n  wanted: %s\n' "$1" "$2" "$3"; fi
}

ROOT="$(mktemp -d)" || exit 1
trap 'rm -rf "$ROOT"' EXIT
export AIDA_REGISTRY_PATH="$ROOT/aida/registry.json"
export AIDA_PROJECTS_HOME="$ROOT/aida/projects"
export AIDA_SETTINGS_PATH="$ROOT/aida/settings.json"
CODE="$ROOT/code"
PROJECT="$ROOT/aida/projects/dufx"
TASK="$PROJECT/tasks/t1"
WT="$ROOT/code.worktrees/code-t1"
SCOPE="$PLUGIN/skills/scope/scripts/scope-actions.sh"
RESEARCH="$PLUGIN/skills/research/scripts/research-actions.sh"
TASKS="$PLUGIN/skills/task/scripts/task-actions.sh"
CHECK_TASK="$PLUGIN/scripts/check-task.sh"
LOG="$ROOT/log.txt"

# Every stage action runs from the task's worktree (exit 79 otherwise), under the shell this
# runner runs under. Output goes to the log.
SH=bash; [ -n "${ZSH_VERSION:-}" ] && SH=zsh
in_wt() { (cd "$WT" && env -u CLAUDE_PLUGIN_ROOT "$SH" "$@") >>"$LOG" 2>&1; }
must() { in_wt "$@" || { printf 'setup failed: %s\n' "$*"; tail -5 "$LOG"; exit 1; }; }
# try <out> <cmd>...: runs the action from the worktree, output to <out>, and prints the exit code.
try() {
  local out="$1"; shift
  (cd "$WT" && env -u CLAUDE_PLUGIN_ROOT "$SH" "$@") >"$out" 2>&1
  printf '%s' "$?"
}
# task_try <out> <args>...: task-actions.sh runs from anywhere; output to <out>, prints the exit code.
task_try() {
  local out="$1"; shift
  env -u CLAUDE_PLUGIN_ROOT "$SH" "$TASKS" "$@" >"$out" 2>&1
  printf '%s' "$?"
}

make_code_repo() {
  mkdir -p "$CODE" && cd "$CODE" || exit 1
  git init -q -b main && git config user.email fx@example.invalid && git config user.name fx
  printf 'a\n' >a.php
  git add -A && git commit -qm init && git checkout -q -b work
  cd "$HOME" || exit 1
}

make_project_and_task() {
  env -u CLAUDE_PLUGIN_ROOT "$SH" "$PLUGIN/skills/project/scripts/project-actions.sh" create \
    --name dufx --path "$CODE" --projects-home "$AIDA_PROJECTS_HOME" --framework fake >>"$LOG" 2>&1 || exit 1
  env -u CLAUDE_PLUGIN_ROOT "$SH" "$TASKS" create \
    --project "$PROJECT" --name t1 -- change some files >>"$LOG" 2>&1 || exit 1
}

# One person-verified criterion; the distill sidecar is an agent's record, so the fixture writes it.
scope_task() {
  must "$SCOPE" init "$TASK"
  must "$SCOPE" set-goal "$TASK" --goal "change files" --expected-result "files changed"
  must "$SCOPE" add "$TASK" --text "a.php changes" --verification "look" --verified-by person
  mkdir -p "$TASK/records"
  printf '{"schemaVersion":1,"stage":"scope","standsAlone":true,"decisions":["change files"],"gaps":[]}\n' \
    >"$TASK/records/scope-distill.json"
  must "$SCOPE" approve "$TASK"
}

# fit_field <jq expr>: one field of the recipeFit stored on the prior-art search.
fit_field() { jq -r ".recipeFit | $1" "$TASK/research/prior.json"; }
declined() { jq -c '.recipesDeclined // "absent"' "$TASK/task.json"; }

make_code_repo
make_project_and_task
scope_task
must "$RESEARCH" start "$TASK"

echo "--- row 122: a recipe fit of unsure is recorded as given, with the reason"
rc="$(try "$ROOT/out-unsure.txt" "$RESEARCH" record "$TASK" --search prior --searched-for "prior art" \
  --text "none" --source "the tree" --criteria-served c1 \
  --recipe-fit unsure --recipe-path "$ROOT/recipe.md" --recipe-reason "the recipe assumes a feature build and this task measures")"
expect "exit 0" "$rc" "0"
expect "fits is unsure" "$(fit_field .fits)" "unsure"
expect "the reason is stored" "$(fit_field .reason)" "the recipe assumes a feature build and this task measures"
expect "the path is stored" "$(fit_field .path)" "$ROOT/recipe.md"

echo "--- row 123: read before any decline prints none"
rc="$(try "$ROOT/out-read0.txt" "$RESEARCH" read "$TASK")"
expect "exit 0" "$rc" "0"
expect "recipes-declined: none" "$(grep '^recipes-declined:' "$ROOT/out-read0.txt")" "recipes-declined: none"
expect "task.json has no recipesDeclined" "$(declined)" '"absent"'

echo "--- row 123: decline-recipe with no framework: exit 3, nothing written"
rc="$(task_try "$ROOT/out-nofw.txt" decline-recipe --project "$PROJECT" t1)"
expect "exit 3" "$rc" "3"
expect "the message says a framework is required" "$(grep -c 'a framework is required' "$ROOT/out-nofw.txt")" "1"
expect "nothing written" "$(declined)" '"absent"'

echo "--- row 123: decline-recipe for a framework project.json does not declare: exit 3"
rc="$(task_try "$ROOT/out-undeclared.txt" decline-recipe --project "$PROJECT" t1 node)"
expect "exit 3" "$rc" "3"
expect "the message names the framework" "$(grep -c "does not declare the framework 'node'" "$ROOT/out-undeclared.txt")" "1"
expect "nothing written" "$(declined)" '"absent"'

echo "--- row 123: decline-recipe on a task that does not exist: exit 1"
rc="$(task_try "$ROOT/out-notask.txt" decline-recipe --project "$PROJECT" t9 fake)"
expect "exit 1" "$rc" "1"
expect "NOT FOUND named" "$(grep -c '^NOT FOUND: t9' "$ROOT/out-notask.txt")" "1"

echo "--- row 123: decline-recipe for the declared framework: written and committed"
rc="$(task_try "$ROOT/out-decline.txt" decline-recipe --project "$PROJECT" t1 fake)"
expect "exit 0" "$rc" "0"
expect "RECIPE DECLINED line" "$(grep '^RECIPE DECLINED:' "$ROOT/out-decline.txt")" "RECIPE DECLINED: fake"
expect "recipesDeclined line" "$(grep '^recipesDeclined:' "$ROOT/out-decline.txt")" "recipesDeclined: fake"
expect "task.json holds the framework" "$(declined)" '["fake"]'
expect "the project folder is committed" "$(git -C "$PROJECT" status --porcelain -- tasks/t1/task.json | wc -l | tr -d ' ')" "0"
expect "the commit subject names the decline" \
  "$(git -C "$PROJECT" log -1 --format=%s)" "Decline a process recipe for fake on t1"

echo "--- row 123: decline-recipe again for the same framework: exit 3, still one entry"
rc="$(task_try "$ROOT/out-repeat.txt" decline-recipe --project "$PROJECT" t1 fake)"
expect "exit 3" "$rc" "3"
expect "the message says it is already declined" "$(grep -c "already declines a recipe for 'fake'" "$ROOT/out-repeat.txt")" "1"
expect "still one entry" "$(declined)" '["fake"]'

echo "--- row 123: read after the decline prints the framework"
rc="$(try "$ROOT/out-read1.txt" "$RESEARCH" read "$TASK")"
expect "exit 0" "$rc" "0"
expect "recipes-declined: fake" "$(grep '^recipes-declined:' "$ROOT/out-read1.txt")" "recipes-declined: fake"

echo "--- row 125: read lists a file three levels deep under inputs/"
mkdir -p "$TASK/inputs/prior-art/old-branch" && printf 'x\n' >"$TASK/inputs/prior-art/old-branch/x.php"
rc="$(try "$ROOT/out-read2.txt" "$RESEARCH" read "$TASK")"
expect "exit 0" "$rc" "0"
expect "inputs: present" "$(grep '^inputs:' "$ROOT/out-read2.txt")" "inputs: present"
expect "the extracted file is listed" "$(grep '^input:' "$ROOT/out-read2.txt")" "input: $TASK/inputs/prior-art/old-branch/x.php"

echo "--- row 123: check-task accepts the field's shape"
rc="$(env -u CLAUDE_PLUGIN_ROOT "$SH" "$CHECK_TASK" "$TASK" >"$ROOT/out-check.txt" 2>&1; printf '%s' "$?")"
expect "exit 0" "$rc" "0"
expect "recipesDeclined is not reported unreadable" "$(grep -c 'recipesDeclined' "$ROOT/out-check.txt")" "0"

printf 'passed %s of %s\n' "$PASS" "$TOTAL"
[ "$PASS" -eq "$TOTAL" ]
