#!/usr/bin/env bash
# Fixture kn: a project chooses where its task worktrees go (gap row 350). The
# project field worktreeBase names the base folder of the group, <base>/<slug repo>.worktrees. A
# person answers it once; create records the default, `..`, the parent of codePath, when none is
# given.
# The rows cover:
#   create   create with no --worktree-base records the parent of the code path, and the first
#            tree goes in <parent>/code.worktrees, as before. --worktree-base under the code path
#            exits 3 and leaves no project; a given folder is recorded.
#   missing  a project with no field, as an unattended create leaves it and as every project made
#            before this row is: the check names worktreeBase in a note
#            and exits 0, read-worktree-base exits 1 and prints the default, and task create
#            still uses it.
#   set      set-worktree-base records the base, read-worktree-base exits 0 and prints it, and a
#            new tree goes in <base>/code.worktrees.
#   kept     a tree task.json already records in the old group stays there.
#   refused  the code path, a folder under it, a new folder under it, a link into it, / and the
#            parent of the home directory are each refused at exit 3, and the field keeps its
#            value. A folder in another git repository, in a registered project folder or under
#            another registered code path is refused too. The home directory itself is recorded,
#            and so is a folder in a git repository whose top is the home directory.
#   hand     a base under the code path written by hand: the check names it at exit 1, and task
#            create refuses at 3 and makes nothing under the code path.
#   prune    the prune of each tree removes its own empty group folder, under either base, and
#            never the base itself.
#   default  set-worktree-base with no folder records the default again, and a new tree goes
#            beside the code path.
# Runs under bash and zsh, from $HOME, with CLAUDE_PLUGIN_ROOT unset.
PLUGIN="${PLUGIN:-$(cd "$(dirname "$0")/../.." && pwd)}"
set -u

PASS=0; TOTAL=0
# expect <what> <actual> <wanted>: prints ok or BAD with both values, and counts.
expect() {
  TOTAL=$((TOTAL + 1))
  if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); printf 'ok: %s\n' "$1"
  else printf 'BAD: %s\n  actual: %s\n  wanted: %s\n' "$1" "$2" "$3"; fi
}
is_dir() { if [ -d "$1" ]; then printf 'yes'; else printf 'no'; fi; }

ROOT="$(cd "$(mktemp -d)" && pwd -P)" || exit 1
trap 'rm -rf "$ROOT"' EXIT
export AIDA_REGISTRY_PATH="$ROOT/aida/registry.json"
export AIDA_PROJECTS_HOME="$ROOT/aida/projects"
export AIDA_SETTINGS_PATH="$ROOT/aida/settings.json"
CODE="$ROOT/code"
GROUP="$ROOT/code.worktrees"
BASE="$ROOT/trees"
PROJECT="$ROOT/aida/projects/knfx"
TASKS="$PLUGIN/skills/task/scripts/task-actions.sh"
ACTIONS="$PLUGIN/skills/project/scripts/project-actions.sh"
LOG="$ROOT/log.txt"

mkdir -p "$CODE/inner" && cd "$CODE" || exit 1
git init -q -b main && git config user.email fx@example.invalid && git config user.name fx
printf 'a\n' >inner/a.txt && git add -A && git commit -qm init
mkdir -p "$ROOT/code2" "$ROOT/code3" "$ROOT/other" "$ROOT/home" && cd "$HOME" || exit 1
git -C "$ROOT/other" init -q && git -C "$ROOT/home" init -q
# project_create <name> <code> [<create option>...]: prints the exit code of project create.
project_create() {
  local name="$1" code="$2"; shift 2
  env -u CLAUDE_PLUGIN_ROOT bash "$ACTIONS" create --name "$name" --path "$code" \
    --projects-home "$AIDA_PROJECTS_HOME" --framework fake "$@" >>"$LOG" 2>&1
  printf '%s' "$?"
}
project_create knfx "$CODE" >/dev/null
[ -f "$PROJECT/project.json" ] || { echo "setup failed: project"; tail -12 "$LOG"; exit 1; }

# create <id>: prints the exit code of task create.
create() {
  env -u CLAUDE_PLUGIN_ROOT bash "$TASKS" create --project "$PROJECT" --name "$1" -- keep the tree where the project says >>"$LOG" 2>&1
  printf '%s' "$?"
}
# base_set [<folder>]: prints the exit code of set-worktree-base.
base_set() {
  env -u CLAUDE_PLUGIN_ROOT bash "$ACTIONS" set-worktree-base knfx "$@" >>"$LOG" 2>&1
  printf '%s' "$?"
}
base_of() { jq -r '.worktreeBase // "none"' "$PROJECT/project.json"; }
recorded() { jq -r '.worktree.path // "none"' "$PROJECT/tasks/$1/task.json"; }
complete() {
  jq '.state = "complete"' "$PROJECT/tasks/$1/task.json" >"$ROOT/tj" && mv "$ROOT/tj" "$PROJECT/tasks/$1/task.json"
}
prune() { (cd "$HOME" && env -u CLAUDE_PLUGIN_ROOT bash "$TASKS" prune --project "$PROJECT" "$1") >>"$LOG" 2>&1; }
# tw <id>: runs task_worktree on the task, the way a stage action resolves its tree.
tw() {
  (cd "$HOME" && env -u CLAUDE_PLUGIN_ROOT PLUGIN_ROOT="$PLUGIN" bash -c '
    die() { shift; printf "%s\n" "$*" >&2; exit 3; }
    die3() { printf "%s\n" "$*" >&2; exit 3; }
    . "$PLUGIN_ROOT/scripts/lib/task-helpers.sh" 2>/dev/null
    . "$PLUGIN_ROOT/scripts/lib/recipes.sh"
    task_worktree "$1" fixture' _ "$PROJECT/tasks/$1") 2>>"$LOG"
}

echo "--- create"
expect "create: with no option nothing is recorded" "$(base_of)" "none"
expect "create: task create exits 0" "$(create t1)" "0"
expect "create: the tree is in the group beside the code path" "$(recorded t1)" "$GROUP/code-t1"
expect "create: a base under the code path exits 3" "$(project_create kn_in "$ROOT/code2" --worktree-base "$ROOT/code2/trees")" "3"
expect "create: no project is left" "$(is_dir "$AIDA_PROJECTS_HOME/kn_in")" "no"
expect "create: a given base exits 0" "$(project_create kn_given "$ROOT/code2" --worktree-base "$BASE")" "0"
expect "create: the given base is recorded" "$(jq -r '.worktreeBase' "$AIDA_PROJECTS_HOME/kn_given/project.json")" "$BASE"
expect "create: --worktree-base .. exits 0" "$(project_create kn_dot "$ROOT/code3" --worktree-base ..)" "0"
expect "create: the default is recorded as .." "$(jq -r '.worktreeBase' "$AIDA_PROJECTS_HOME/kn_dot/project.json")" ".."

echo "--- missing"
env -u CLAUDE_PLUGIN_ROOT bash "$PLUGIN/scripts/check-project.sh" "$PROJECT" >"$ROOT/check-missing.txt" 2>&1
expect "missing: the check exits 0, the note raises nothing" "$?" "0"
expect "missing: the record notes the field" "$(jq -r '.worktreeBaseUnset' "$PROJECT/records/check-project.json")" "true"
expect "missing: the note names the producer" "$(grep -c 'Producer: project-actions.sh set-worktree-base' "$ROOT/check-missing.txt")" "1"
out="$(env -u CLAUDE_PLUGIN_ROOT bash "$ACTIONS" read-worktree-base knfx 2>>"$LOG")"
expect "missing: read-worktree-base exits 1" "$?" "1"
expect "missing: it prints the default" "$out" "$ROOT"
expect "missing: task create exits 0" "$(create t0)" "0"
expect "missing: the tree uses the default" "$(recorded t0)" "$GROUP/code-t0"

echo "--- set"
mkdir -p "$BASE"
expect "set: set-worktree-base exits 0" "$(base_set "$BASE")" "0"
expect "set: project.json records the base" "$(base_of)" "$BASE"
expect "set: the change is committed" "$(git -C "$PROJECT" status --porcelain project.json | wc -l | tr -d ' ')" "0"
out="$(env -u CLAUDE_PLUGIN_ROOT bash "$ACTIONS" read-worktree-base knfx 2>>"$LOG")"
expect "set: read-worktree-base exits 0" "$?" "0"
expect "set: it prints the base" "$out" "$BASE"
expect "set: create exits 0" "$(create t2)" "0"
expect "set: the tree is in the group under the base" "$(recorded t2)" "$BASE/code.worktrees/code-t2"
expect "set: nothing new beside the code path" "$(is_dir "$GROUP/code-t2")" "no"

echo "--- kept"
expect "kept: the recorded tree is printed" "$(tw t1)" "$GROUP/code-t1"
expect "kept: the record is unchanged" "$(recorded t1)" "$GROUP/code-t1"

echo "--- refused"
ln -s "$CODE/inner" "$ROOT/link"
for p in "$CODE" "$CODE/inner" "$CODE/new" "$ROOT/link" / "$(dirname -- "$HOME")"; do
  expect "refused: $p exits 3" "$(base_set "$p")" "3"
done
expect "refused: the field keeps its value" "$(base_of)" "$BASE"
expect "refused: the refusal names the cause" "$(grep -c 'set-worktree-base: .* is refused (inside-code-path)' "$LOG")" "4"
expect "refused: / is a system root" "$(grep -c 'set-worktree-base: / is refused (refused-system-root)' "$LOG")" "1"
for p in "$ROOT/other/trees" "$PROJECT/trees" "$ROOT/code2/trees"; do
  expect "refused: $p exits 3" "$(base_set "$p")" "3"
done
expect "refused: the other repository is named" "$(grep -c 'is refused (inside-git-repository)' "$LOG")" "1"
expect "refused: the registered project and code path are named" "$(grep -c 'is refused (inside-registered-project)' "$LOG")" "2"
expect "allowed: a folder in a repository at home exits 0" \
  "$(HOME="$ROOT/home" GIT_AUTHOR_NAME=fx GIT_AUTHOR_EMAIL=fx@example.invalid GIT_COMMITTER_NAME=fx GIT_COMMITTER_EMAIL=fx@example.invalid base_set "$ROOT/home/trees")" "0"
expect "allowed: that folder is recorded" "$(base_of)" "$ROOT/home/trees"
expect "allowed: the home directory exits 0" "$(base_set "$HOME")" "0"
expect "allowed: the home directory is recorded" "$(base_of)" "$(cd "$HOME" && pwd -P)"
base_set "$BASE" >/dev/null

echo "--- hand"
jq --arg b "$CODE/inner/trees" '.worktreeBase = $b' "$PROJECT/project.json" >"$ROOT/pj" && mv "$ROOT/pj" "$PROJECT/project.json"
env -u CLAUDE_PLUGIN_ROOT bash "$PLUGIN/scripts/check-project.sh" "$PROJECT" >"$ROOT/check.txt" 2>&1
expect "hand: the check exits 1" "$?" "1"
expect "hand: the check names worktreeBase" \
  "$(jq -r '[.crossFieldIssues[] | select(.field == "worktreeBase")] | length' "$PROJECT/records/check-project.json")" "1"
expect "hand: create refuses 3" "$(create t3)" "3"
expect "hand: nothing is made under the code path" "$(is_dir "$CODE/inner/trees")" "no"
expect "hand: the refusal names the base" "$(grep -c "worktreeBase $CODE/inner/trees is refused" "$LOG")" "1"
jq --arg b "$BASE" '.worktreeBase = $b' "$PROJECT/project.json" >"$ROOT/pj" && mv "$ROOT/pj" "$PROJECT/project.json"

echo "--- prune"
complete t2
prune t2
expect "prune: the tree under the base is gone" "$(is_dir "$BASE/code.worktrees/code-t2")" "no"
expect "prune: its empty group folder is removed" "$(is_dir "$BASE/code.worktrees")" "no"
expect "prune: the base itself stays" "$(is_dir "$BASE")" "yes"
complete t1
prune t1
expect "prune: the tree in the old group is gone" "$(is_dir "$GROUP/code-t1")" "no"
expect "prune: the old group folder that still holds a tree stays" "$(is_dir "$GROUP/code-t0")" "yes"
complete t0
prune t0
expect "prune: the old empty group folder is removed" "$(is_dir "$GROUP")" "no"

echo "--- default"
expect "default: set-worktree-base with no folder exits 0" "$(base_set)" "0"
expect "default: the default is recorded as .." "$(base_of)" ".."
expect "default: create exits 0" "$(create t4)" "0"
expect "default: the tree is beside the code path again" "$(recorded t4)" "$GROUP/code-t4"

printf 'passed %s of %s\n' "$PASS" "$TOTAL"
[ "$PASS" -eq "$TOTAL" ]
