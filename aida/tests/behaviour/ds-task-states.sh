#!/usr/bin/env bash
# Fixture ds: the task skill, six rows from the newyorkcares run (117, 118,
# 119, 120, 140, 141). Builds a project and four tasks with the setup of run-ct-fixture.sh, then
# proves: a stage action from outside the tree with `cd` in the same command runs, and without it
# refuses at 79 naming `cd`; `start` unattended on a task with no environment says the offer waits
# and writes nothing, and the person's no is recorded through `environment not-applicable`;
# `save` on a new task writes the note and names the stage with no record; a task action's commit
# leaves another task's uncommitted file alone; `repair` on a version 5 parent moves its nested
# child too, with parent and children set, and a child it left behind is repaired from where it
# sits; `repair` reads `## Problem` and refuses neither heading naming both. From the fix round:
# `split` commits its children, and the stage stays scope until records/scope-distill.json
# exists. Runs under bash, which CI runs on Linux, from $HOME, with CLAUDE_PLUGIN_ROOT unset.
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
PROJECT="$ROOT/aida/projects/dsfx"
SCOPE="$PLUGIN/skills/scope/scripts/scope-actions.sh"
NEXT="$PLUGIN/skills/next/scripts/next-actions.sh"
TASKS="$PLUGIN/skills/task/scripts/task-actions.sh"
LOG="$ROOT/log.txt"

# The shell every plugin script runs under: the one this runner runs under.
if [ -n "${ZSH_VERSION:-}" ]; then SH=zsh; else SH=bash; fi

# try <outfile> <cmd>...: runs the command from $HOME under $SH with both streams in the file, and
# prints its exit code.
try() {
  local out="$1"; shift
  (cd "$HOME" && env -u CLAUDE_PLUGIN_ROOT "$SH" "$@") >"$out" 2>&1
  printf '%s' "$?"
}
holds() { grep -c -F -e "$2" "$1"; }
task_field() { jq -r "$2" "$PROJECT/tasks/$1/task.json"; }

make_code_repo() {
  mkdir -p "$CODE" && cd "$CODE" || exit 1
  git init -q -b main && git config user.email fx@example.invalid && git config user.name fx
  printf 'a\n' >a.php
  git add -A && git commit -qm init
  cd "$HOME" || exit 1
}

make_project() {
  env -u CLAUDE_PLUGIN_ROOT bash "$PLUGIN/skills/project/scripts/project-actions.sh" create \
    --name dsfx --path "$CODE" --projects-home "$AIDA_PROJECTS_HOME" --framework fake >>"$LOG" 2>&1 || exit 1
}

# make_task <name>: one task in state new, with its worktree.
make_task() {
  env -u CLAUDE_PLUGIN_ROOT "$SH" "$TASKS" create --project "$PROJECT" --name "$1" -- a goal for "$1" \
    >>"$LOG" 2>&1 || { printf 'setup failed: create %s\n' "$1"; tail -5 "$LOG"; exit 1; }
}

# v5_task <old-folder> <heading> [<frontmatter file>]: one version 5 task folder with task.md.
v5_task() {
  mkdir -p "$1"
  {
    [ -z "${3:-}" ] || cat "$3"
    printf '# %s\n\n' "$(basename -- "$1")"
    [ -z "$2" ] || printf '## %s\n\nthe goal of %s\n' "$2" "$(basename -- "$1")"
  } >"$1/task.md"
}

# project_commit: commits the project folder as it stands, the way a version 5 layout would sit.
project_commit() {
  git -C "$PROJECT" add -A -- implementation_process >>"$LOG" 2>&1
  git -C "$PROJECT" -c user.email=fx@example.invalid -c user.name=fx commit -qm "$1" >>"$LOG" 2>&1
}

make_code_repo
make_project
for t in t1 t2 t3 t4; do make_task "$t"; done
WT1="$ROOT/code.worktrees/code-t1"

echo "--- row 117: a stage action from outside the tree, without cd: exit 79 naming cd"
expect "scope init from \$HOME exits 79" "$(try "$ROOT/out-79.txt" "$SCOPE" init "$PROJECT/tasks/t1")" "79"
expect "the message names the cd form" "$(holds "$ROOT/out-79.txt" "start the call with: cd $WT1 &&")" "1"
expect "nothing was written" "$([ -f "$PROJECT/tasks/t1/alignment.json" ] && echo yes || echo no)" "no"

echo "--- row 117: the same action with cd at the front of the same command: exit 0"
expect "cd <tree> && scope init exits 0" "$(try "$ROOT/out-cd.txt" -c "cd '$WT1' && '$SCOPE' init '$PROJECT/tasks/t1'")" "0"
expect "alignment.json was written" "$([ -f "$PROJECT/tasks/t1/alignment.json" ] && echo yes || echo no)" "yes"

echo "--- row 118: start reached through scope's init shows the site offer line"
expect "t1 is in progress" "$(task_field t1 .state)" "in_progress"
expect "init's output holds the environment line" "$(holds "$ROOT/out-cd.txt" "environment: none. Run the task skill's site offer now, create step 5.")" "1"

echo "--- fix 5: the stage is scope until records/scope-distill.json exists"
expect "next open mid-scope says scope" "$(try "$ROOT/out-next1.txt" -c "cd '$CODE' && '$NEXT' open t1" >/dev/null; sed -n 's/^stage: //p' "$ROOT/out-next1.txt")" "scope"
expect "save mid-scope prints no distill line" "$(try "$ROOT/out-save0.txt" "$TASKS" save --project "$PROJECT" t1 -- mid scope)" "0"
expect "no distill line" "$(holds "$ROOT/out-save0.txt" "distill:")" "0"
mkdir -p "$PROJECT/tasks/t1/records"
printf '{"schemaVersion":1,"stage":"scope","standsAlone":true,"decisions":[],"gaps":[]}\n' >"$PROJECT/tasks/t1/records/scope-distill.json"
expect "next open with the sidecar says research" "$(try "$ROOT/out-next2.txt" -c "cd '$CODE' && '$NEXT' open t1" >/dev/null; sed -n 's/^stage: //p' "$ROOT/out-next2.txt")" "research"
expect "save then names research as recordless" "$(try "$ROOT/out-save00.txt" "$TASKS" save --project "$PROJECT" t1 -- after)" "0"
expect "distill: none, research" "$(holds "$ROOT/out-save00.txt" "distill: none, research has no record yet")" "1"

echo "--- row 118: start unattended on a task with no environment: the offer waits, nothing written"
expect "start exits 0" "$(try "$ROOT/out-start.txt" "$TASKS" --run-mode autonomous start --project "$PROJECT" t2 -- why)" "0"
expect "it says the offer waits" "$(holds "$ROOT/out-start.txt" "environment: none, the site offer waits for a person")" "1"
expect "task.json has no environment" "$(task_field t2 '.environment // "absent"')" "absent"
expect "start again, in progress, still says so" "$(try "$ROOT/out-start2.txt" "$TASKS" --run-mode autonomous start --project "$PROJECT" t2 -- why)" "0"
expect "the line is printed after UNCHANGED" "$(holds "$ROOT/out-start2.txt" "environment: none, the site offer waits for a person")" "1"

echo "--- row 118: the person's no is recorded as not-applicable with the reason"
expect "not-applicable unattended exits 70" "$(try "$ROOT/out-na70.txt" "$TASKS" --run-mode autonomous environment --project "$PROJECT" t2 not-applicable -- no site needed)" "70"
expect "nothing written unattended" "$(task_field t2 '.environment // "absent"')" "absent"
expect "not-applicable with no reason exits 3" "$(try "$ROOT/out-na3.txt" "$TASKS" environment --project "$PROJECT" t2 not-applicable --)" "3"
expect "not-applicable exits 0" "$(try "$ROOT/out-na.txt" "$TASKS" environment --project "$PROJECT" t2 not-applicable -- the change is a code analysis)" "0"
expect "it prints not-applicable" "$(holds "$ROOT/out-na.txt" "environment: not-applicable")" "1"
expect "the reason is recorded" "$(task_field t2 '.environment["not-applicable"]')" "the change is a code analysis"
expect "it was committed" "$(git -C "$PROJECT" status --porcelain -- tasks/t2 | wc -l | tr -d ' ')" "0"
expect "start after it prints no environment line" "$(try "$ROOT/out-start3.txt" "$TASKS" start --project "$PROJECT" t2 -- why)" "0"
expect "no environment line" "$(holds "$ROOT/out-start3.txt" "environment:")" "0"
expect "down with it recorded says nothing was up" "$(try "$ROOT/out-down.txt" "$TASKS" environment --project "$PROJECT" t2 down)" "0"
expect "and keeps the record" "$(task_field t2 '.environment["not-applicable"]')" "the change is a code analysis"

echo "--- row 119: save on a new task: exit 0, note written, no distiller named as required"
expect "save exits 0" "$(try "$ROOT/out-save.txt" "$TASKS" save --project "$PROJECT" t3 -- decided the thing)" "0"
NOTE="$PROJECT/tasks/t3/notes/$(date -u +%Y-%m-%d).md"
expect "the note was written" "$(grep -c 'decided the thing' "$NOTE")" "1"
expect "it names the stage with no record" "$(holds "$ROOT/out-save.txt" "distill: none, scope has no record yet")" "1"
expect "it does not name the distiller as required" "$(grep -ci 'distiller' "$ROOT/out-save.txt")" "0"
expect "t3 stays new" "$(task_field t3 .state)" "new"

echo "--- row 120: two tasks, one with an uncommitted file, start on the other leaves it alone"
mkdir -p "$PROJECT/tasks/t1/inputs" && printf 'surface\n' >"$PROJECT/tasks/t1/inputs/code-surface.md"
expect "start t4 exits 0" "$(try "$ROOT/out-start4.txt" "$TASKS" start --project "$PROJECT" t4 -- why)" "0"
expect "t1's file stays uncommitted" "$(git -C "$PROJECT" status --porcelain -- tasks/t1/inputs | cut -c1-2)" "??"
expect "the commit holds t4 alone" "$(git -C "$PROJECT" show --stat --format= HEAD | grep -c 'tasks/t1')" "0"
expect "and holds t4" "$(git -C "$PROJECT" show --stat --format= HEAD | grep -c 'tasks/t4/task.json')" "1"
expect "save on t3 leaves it alone too" "$(try "$ROOT/out-save2.txt" "$TASKS" save --project "$PROJECT" t3 -- another)" "0"
expect "t1's file still uncommitted" "$(git -C "$PROJECT" status --porcelain -- tasks/t1/inputs | cut -c1-2)" "??"

echo "--- break: split commits the parent's folder and every child's"
expect "split t4 exits 0" "$(try "$ROOT/out-split.txt" "$TASKS" split --project "$PROJECT" t4 --child k1 --goal one --child k2 --goal two)" "0"
expect "no child stays untracked" "$(git -C "$PROJECT" status --porcelain -- tasks/k1 tasks/k2 tasks/t4 | wc -l | tr -d ' ')" "0"
expect "the commit holds both children" "$(git -C "$PROJECT" show --stat --format= HEAD | grep -c 'tasks/k[12]/task.json')" "2"
expect "t1's file still uncommitted" "$(git -C "$PROJECT" status --porcelain -- tasks/t1/inputs | cut -c1-2)" "??"

echo "--- row 140: a version 5 parent with one nested in_progress child: repair moves both"
OLD="$PROJECT/implementation_process/in_progress"
printf -- '---\nparent: null\nchildren:\n- child5\n---\n' >"$ROOT/fm.txt"
v5_task "$OLD/epic5" Goal "$ROOT/fm.txt"
v5_task "$OLD/epic5/in_progress/child5" Goal
v5_task "$OLD/epic5/completed/left5" ""
printf 'old contract\n' >"$OLD/epic5/in_progress/child5/alignment.md"
project_commit "version 5 layout"
expect "repair exits 0" "$(try "$ROOT/out-repair.txt" "$TASKS" repair --project "$PROJECT" "$OLD/epic5")" "0"
expect "the parent moved" "$([ -f "$PROJECT/tasks/epic5/task.json" ] && echo yes || echo no)" "yes"
expect "the child moved to its own folder" "$([ -f "$PROJECT/tasks/child5/task.json" ] && echo yes || echo no)" "yes"
expect "the nested folder is gone" "$([ -e "$PROJECT/tasks/epic5/in_progress" ] && echo yes || echo no)" "no"
expect "the child has parent" "$(task_field child5 .parent)" "epic5"
expect "the child is in progress" "$(task_field child5 .state)" "in_progress"
expect "the parent has children" "$(task_field epic5 '.children | join(",")')" "child5"
expect "one MOVED line" "$(holds "$ROOT/out-repair.txt" "MOVED: child5 to $PROJECT/tasks/child5, parent epic5")" "1"
expect "the child's old contract was kept" "$([ -f "$PROJECT/tasks/child5/alignment.v5.md" ] && echo yes || echo no)" "yes"
expect "the parent's goal-heading line" "$(holds "$ROOT/out-repair.txt" "goal-heading: Goal")" "1"
expect "the move was committed whole" "$(git -C "$PROJECT" status --porcelain -- tasks/epic5 tasks/child5 implementation_process | wc -l | tr -d ' ')" "0"
expect "t1's file still uncommitted" "$(git -C "$PROJECT" status --porcelain -- tasks/t1/inputs | cut -c1-2)" "??"
expect "the child with no heading is left with the route" "$(holds "$ROOT/out-repair.txt" "LEFT: $PROJECT/tasks/epic5/completed/left5: $PROJECT/tasks/epic5/completed/left5/task.md has no Goal section and no Problem section. Refusing to move a task whose goal cannot be verified. Fix it there, then run repair on that path")" "1"
expect "it sits where it was left" "$([ -f "$PROJECT/tasks/epic5/completed/left5/task.md" ] && echo yes || echo no)" "yes"

echo "--- fix 1: the left child, fixed where it sits, is repaired from that path"
printf '\n## Goal\n\nthe goal of left5\n' >>"$PROJECT/tasks/epic5/completed/left5/task.md"
expect "repair from tasks/<parent>/completed exits 0" "$(try "$ROOT/out-left.txt" "$TASKS" repair --project "$PROJECT" "$PROJECT/tasks/epic5/completed/left5")" "0"
expect "it moved to its own folder" "$([ -f "$PROJECT/tasks/left5/task.json" ] && echo yes || echo no)" "yes"
expect "state from the folder it sat in" "$(task_field left5 .state)" "complete"
expect "parent from the folder it sat in" "$(task_field left5 .parent)" "epic5"
expect "the parent lists it" "$(task_field epic5 '.children | join(",")')" "child5,left5"
expect "the PARENT line" "$(holds "$ROOT/out-left.txt" "PARENT: epic5 now lists left5")" "1"
expect "the emptied folder is gone" "$([ -e "$PROJECT/tasks/epic5/completed" ] && echo yes || echo no)" "no"
expect "the commit holds child, parent and the old path" "$(git -C "$PROJECT" status --porcelain -- tasks/epic5 tasks/left5 | wc -l | tr -d ' ')" "0"
expect "t1's file still uncommitted" "$(git -C "$PROJECT" status --porcelain -- tasks/t1/inputs | cut -c1-2)" "??"

echo "--- row 141: a version 5 record headed ## Problem: repair accepts and records the heading"
v5_task "$OLD/prob5" Problem
expect "repair exits 0" "$(try "$ROOT/out-prob.txt" "$TASKS" repair --project "$PROJECT" "$OLD/prob5")" "0"
expect "it records the heading" "$(holds "$ROOT/out-prob.txt" "goal-heading: Problem")" "1"
expect "the goal read back" "$(grep -c 'the goal of prob5' "$PROJECT/tasks/prob5/task.md")" "1"

echo "--- row 141: neither heading: refused naming both"
v5_task "$OLD/none5" ""
expect "repair exits 3" "$(try "$ROOT/out-none.txt" "$TASKS" repair --project "$PROJECT" "$OLD/none5")" "3"
expect "the refusal names both headings" "$(holds "$ROOT/out-none.txt" "has no Goal section and no Problem section")" "1"
expect "nothing moved" "$([ -d "$OLD/none5" ] && [ ! -e "$PROJECT/tasks/none5" ] && echo yes || echo no)" "yes"

printf 'passed %s of %s\n' "$PASS" "$TOTAL"
[ "$PASS" -eq "$TOTAL" ]
