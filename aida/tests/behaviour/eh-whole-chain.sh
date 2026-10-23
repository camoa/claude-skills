#!/usr/bin/env bash
# Fixture eh: the tear-down the completion body promises and the folder the
# compact hook must not count (live-run rows 150 and 152). Builds one project on the framework
# `fake`. Four tasks carry the body's four shapes: a site up, `not-applicable`, no `environment`
# key, and no worktree at all. One more task drives hooks/pre-compact.sh through each of its three
# branches, with a file under `inputs/`, with one under `records/`, and then with a stage record
# on disk. Setup is copied from run-ec-fixture.sh and run-ds-fixture.sh. Runs under bash 3.2 and
# zsh, from $HOME, with CLAUDE_PLUGIN_ROOT unset.
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
PROJECT="$ROOT/aida/projects/ehfx"
RECIPES="$ROOT/recipes"
SCOPE="$PLUGIN/skills/scope/scripts/scope-actions.sh"
RESEARCH="$PLUGIN/skills/research/scripts/research-actions.sh"
DESIGN="$PLUGIN/skills/design/scripts/design-actions.sh"
IMPLEMENT="$PLUGIN/skills/implement/scripts/implement-actions.sh"
REVIEW="$PLUGIN/skills/review/scripts/review-actions.sh"
COMPLETION="$PLUGIN/skills/completion/scripts/completion-actions.sh"
PLAYBOOKS="$PLUGIN/skills/playbooks/scripts/playbook-actions.sh"
TASKS="$PLUGIN/skills/task/scripts/task-actions.sh"
HOOK="$PLUGIN/hooks/pre-compact.sh"
LOG="$ROOT/log.txt"
TEST_RECIPE_FLAG="fake=$RECIPES/test-execution.md"
CHECK_RECIPE_FLAG="fake=$RECIPES/checks.md"
ENV_RECIPE_FLAG="fake=$RECIPES/worktree-environment.md"

# Every stage action runs from the task's worktree (exit 79 otherwise), under the shell this
# runner runs under, so the zsh run proves the plugin script under zsh. Output goes to the log.
SH=bash; [ -n "${ZSH_VERSION:-}" ] && SH=zsh
in_wt() { wt="$1"; shift; (cd "$wt" && env -u CLAUDE_PLUGIN_ROOT "$SH" "$@") >>"$LOG" 2>&1; }
must() { in_wt "$@" || { printf 'setup failed: %s\n' "$*"; tail -12 "$LOG"; exit 1; }; }
# try <worktree> <out file> <args>: runs an action, keeps its output, prints the exit code.
try() {
  wt="$1"; out="$2"; shift 2
  (cd "$wt" && env -u CLAUDE_PLUGIN_ROOT "$SH" "$@") >"$out" 2>&1
  printf '%s' "$?"
}
holds() { grep -c -F -e "$2" "$1"; }
# compact <worktree> <out file>: the PreCompact hook on a manual compaction, from that worktree.
compact() {
  (cd "$1" && printf '{"trigger":"manual","cwd":"%s"}\n' "$1" \
    | env -u CLAUDE_PLUGIN_ROOT "$SH" "$HOOK") >"$2" 2>&1
  printf '%s' "$?"
}
wt_of() { printf '%s/code.worktrees/code-%s' "$ROOT" "$1"; }
# Waits for the clock to cross into the next second, so a write before a call and a write after it
# never share one second. No sleep: the loop asks the clock, which is enough for one second.
settle() {
  second="$(date -u +%S)"
  while [ "$(date -u +%S)" = "$second" ]; do :; done
}

make_code_repo() {
  mkdir -p "$CODE" && cd "$CODE" || exit 1
  git init -q -b main && git config user.email fx@example.invalid && git config user.name fx
  printf 'a\n' >a.php
  git add -A && git commit -qm init && git checkout -q -b work
  cd "$HOME" || exit 1
}

make_project() {
  env -u CLAUDE_PLUGIN_ROOT bash "$PLUGIN/skills/project/scripts/project-actions.sh" create \
    --name ehfx --path "$CODE" --projects-home "$AIDA_PROJECTS_HOME" --framework fake >>"$LOG" 2>&1 || exit 1
}

make_task() {
  env -u CLAUDE_PLUGIN_ROOT bash "$TASKS" create --project "$PROJECT" --name "$1" -- write one document \
    >>"$LOG" 2>&1 || exit 1
}

# The three recipes the stages ask for. The commands are `true`, because nothing here judges a
# stack; the address command prints the one line `environment up` reads.
write_recipes() {
  mkdir -p "$RECIPES"
  cat >"$RECIPES/test-execution.md" <<'EOF'
---
name: fake_test_execution
capability: test-execution
recipe_class: process
framework: fake
---

## Preconditions

```yaml
preconditions: []
```

## Test commands

```yaml
test_commands:
  - id: suite
    argv: ["true"]
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
    argv: ["true", "{paths}"]
    cost: every-attempt
```

```yaml
failure_signal:
  assertion: >-
    Exit 1.
```
EOF
  cat >"$RECIPES/checks.md" <<'EOF'
---
name: fake_review_checks
capability: review
recipe_class: process
framework: fake
---

## Check commands

```yaml
check_commands:
  - id: coding-standards
    argv: ["true", "{paths}"]
  - id: static-analysis
    absent: >-
      None.
  - id: security
    absent: >-
      None.
  - id: duplication
    absent: >-
      None.
  - id: design-metrics
    absent: >-
      None.
```

## Surface commands

```yaml
surface_commands:
  - id: e2e-preflight
    absent: >-
      None.
  - id: e2e
    absent: >-
      None.
  - id: visual-regression
    absent: >-
      None.
  - id: visual-regression-accept
    absent: >-
      None.
  - id: visual-parity
    absent: >-
      None.
  - id: visual-parity-accept
    absent: >-
      None.
```
EOF
  cat >"$RECIPES/worktree-environment.md" <<'EOF'
---
name: fake_worktree_environment
capability: worktree-environment
recipe_class: process
framework: fake
---

## Preconditions

```sh
true
```

## Bring up

```sh
true
```

## Address

```sh
echo address: http://ehfx.test
```

## Tear down

```sh
true
```
EOF
}

# scope_task <task> <wt>: one machine criterion, owned and judged by its order.
scope_task() {
  must "$2" "$SCOPE" init "$1"
  must "$2" "$SCOPE" set-goal "$1" --goal "do the work" --expected-result "work done"
  must "$2" "$SCOPE" add "$1" --text "first thing" --verification "the document says so" --verified-by machine
  mkdir -p "$1/records"
  printf '{"schemaVersion":1,"stage":"scope","standsAlone":true,"decisions":["do the work"],"gaps":[]}\n' \
    >"$1/records/scope-distill.json"
  must "$2" "$SCOPE" approve "$1"
}

research_task() {
  must "$2" "$RESEARCH" start "$1"
  must "$2" "$RESEARCH" record "$1" --search prior --searched-for "prior art" \
    --text "the framework guide says to write it down" --source "guides/writing.md" --criteria-served c1
  must "$2" "$RESEARCH" check "$1"
  must "$2" "$PLAYBOOKS" load "$1"
}

# carry <task> <wt>: the whole build for one record order, through review's close. The order owns
# one document in the task folder, so no commit lands in the code repository and no test runs.
carry() {
  task="$1"; wt="$2"; from=""
  scope_task "$task" "$wt"
  research_task "$task" "$wt"
  must "$wt" "$DESIGN" start "$task"
  must "$wt" "$DESIGN" create "$task" --title "write the document" --criteria-served c1 --criteria-owned c1 \
    --reasoning "the brief says so" --diff-budget small --interface none
  must "$wt" "$DESIGN" add-owned-file "$task" --id wo1 --path "$task/deliverables/a.md"
  must "$wt" "$DESIGN" add-done-when "$task" --id wo1 --text "write the document"
  must "$wt" "$DESIGN" account "$task" --id wo1 --finding prior#1
  must "$wt" "$DESIGN" --run-mode interactive close "$task" --no-recipe
  must "$wt" "$IMPLEMENT" start "$task"
  must "$wt" "$IMPLEMENT" preconditions "$task" --recipe "$TEST_RECIPE_FLAG" --check-recipe "$CHECK_RECIPE_FLAG"
  must "$wt" "$IMPLEMENT" tests-freeze "$task" wo1 --test-recipe "$TEST_RECIPE_FLAG" \
    --row "wo1=confirmed::person::reads from the document alone"
  from="$(git -C "$PROJECT" rev-parse HEAD)"
  mkdir -p "$task/deliverables" && printf 'written\n' >"$task/deliverables/a.md"
  git -C "$PROJECT" add -- "$task/deliverables/a.md" >>"$LOG" 2>&1
  git -C "$PROJECT" -c user.email=fx@example.invalid -c user.name=fx commit -qm "a.md" >>"$LOG" 2>&1
  must "$wt" "$IMPLEMENT" build-record "$task" wo1 --interface "$ROOT/iface.md" --report "$ROOT/report.md" \
    --started-at "$from" --test-recipe "$TEST_RECIPE_FLAG" --check-recipe "$CHECK_RECIPE_FLAG"
  must "$wt" "$IMPLEMENT" review-record "$task" wo1 --findings "$ROOT/no-findings.json"
  must "$wt" "$IMPLEMENT" close "$task" wo1
  must "$wt" "$IMPLEMENT" finish "$task"
  must "$wt" "$REVIEW" checks "$task" --recipe "$TEST_RECIPE_FLAG" --check-recipe "$CHECK_RECIPE_FLAG"
  must "$wt" "$REVIEW" brief "$task"
  must "$wt" "$REVIEW" findings "$task" --findings "$ROOT/no-findings.json"
  must "$wt" "$REVIEW" surfaces "$task"
  must "$wt" "$REVIEW" close "$task"
}

printf 'none\n' >"$ROOT/iface.md"; printf 'report\nStop: none\nDeviation: none\n' >"$ROOT/report.md"
printf '{ "findings": [] }\n' >"$ROOT/no-findings.json"
make_code_repo
make_project
write_recipes

# ------------------------------------------------------------------------------------------------
# Row 150: the commit-range section of the completion body, in four shapes.
# ------------------------------------------------------------------------------------------------
for id in t1 t2 t3; do make_task "$id"; done
T1="$PROJECT/tasks/t1"; W1="$(wt_of t1)"
T2="$PROJECT/tasks/t2"; W2="$(wt_of t2)"
T3="$PROJECT/tasks/t3"; W3="$(wt_of t3)"
carry "$T1" "$W1"
carry "$T2" "$W2"
carry "$T3" "$W3"

# The site of t1 comes up through the task skill against the fixture recipe, so `environment` is
# written by its own producer and never by hand.
RC="$(try "$W1" "$ROOT/out-up.txt" "$TASKS" environment --project "$PROJECT" t1 up --recipe "$ENV_RECIPE_FLAG")"
echo "--- a task whose site is up"
expect "environment up exits 0" "$RC" "0"
expect "the record holds the address" "$(jq -r '.environment.address' "$T1/task.json")" "http://ehfx.test"
RC="$(try "$W1" "$ROOT/out-close1.txt" "$COMPLETION" close "$T1")"
expect "completion close exits 0" "$RC" "0"
expect "the body names the tear-down" \
  "$(holds "$T1/completion/pr-body.md" "The site of this task is up. Run \`task environment t1 down\` before the worktree is removed, or the framework keeps an orphaned registry entry.")" "1"
expect "the prune line keeps its tear-down clause" \
  "$(holds "$T1/completion/pr-body.md" "After the merge: \`task prune t1\` from the main checkout tears the site down when one is up, then removes the tree and the merged branch.")" "1"
expect "the tear-down comes before the prune line" \
  "$(awk '/^The site of this task is up\./ { a = NR } /^After the merge: / { b = NR } END { print (a > 0 && a < b) ? "yes" : "no" }' "$T1/completion/pr-body.md")" "yes"
expect "the branch line is still there" \
  "$(holds "$T1/completion/pr-body.md" "in the worktree $W1. Push from there.")" "1"

echo "--- a task the person said needs no site"
RC="$(try "$W2" "$ROOT/out-na.txt" "$TASKS" environment --project "$PROJECT" t2 not-applicable -- the change is a code analysis)"
expect "not-applicable exits 0" "$RC" "0"
expect "the record holds not-applicable" "$(jq -r '.environment["not-applicable"]' "$T2/task.json")" "the change is a code analysis"
RC="$(try "$W2" "$ROOT/out-close2.txt" "$COMPLETION" close "$T2")"
expect "completion close exits 0" "$RC" "0"
expect "the body names no tear-down" "$(holds "$T2/completion/pr-body.md" "The site of this task is up.")" "0"
expect "the prune line drops its tear-down clause" \
  "$(holds "$T2/completion/pr-body.md" "After the merge: \`task prune t2\` from the main checkout removes the tree and the merged branch.")" "1"
expect "the branch line is still there" \
  "$(holds "$T2/completion/pr-body.md" "in the worktree $W2. Push from there.")" "1"

echo "--- a task with no environment key at all"
expect "the record holds no environment" "$(jq -r '.environment // "absent"' "$T3/task.json")" "absent"
RC="$(try "$W3" "$ROOT/out-close3.txt" "$COMPLETION" close "$T3")"
expect "completion close exits 0" "$RC" "0"
expect "the body names no tear-down" "$(holds "$T3/completion/pr-body.md" "The site of this task is up.")" "0"
expect "the prune line drops its tear-down clause" \
  "$(holds "$T3/completion/pr-body.md" "After the merge: \`task prune t3\` from the main checkout removes the tree and the merged branch.")" "1"

echo "--- a task with no worktree at all"
# A version 5 folder moved by `repair` is the one task shape that records no worktree, and no
# stage action has run to make one. It has no contract and no review, so the close takes a reason.
mkdir -p "$PROJECT/implementation_process/in_progress/t4"
printf '# t4\n\n## Goal\n\nthe goal of t4\n' >"$PROJECT/implementation_process/in_progress/t4/task.md"
git -C "$PROJECT" add -A -- implementation_process >>"$LOG" 2>&1
git -C "$PROJECT" -c user.email=fx@example.invalid -c user.name=fx commit -qm v5 >>"$LOG" 2>&1
T4="$PROJECT/tasks/t4"
RC="$(try "$HOME" "$ROOT/out-repair.txt" "$TASKS" repair --project "$PROJECT" "$PROJECT/implementation_process/in_progress/t4")"
expect "repair exits 0" "$RC" "0"
expect "the record holds no worktree" "$(jq -r '.worktree // "absent"' "$T4/task.json")" "absent"
RC="$(try "$HOME" "$ROOT/out-close4.txt" "$COMPLETION" close "$T4" --reason "the work was dropped")"
expect "completion close exits 0" "$RC" "0"
expect "the body names no branch" "$(holds "$T4/completion/pr-body.md" "Push from there.")" "0"
expect "the body names no prune" "$(holds "$T4/completion/pr-body.md" "After the merge: ")" "0"
expect "the body names no tear-down" "$(holds "$T4/completion/pr-body.md" "The site of this task is up.")" "0"

# ------------------------------------------------------------------------------------------------
# Row 152: the compact hook and the two folders a task's own stages do not write. Each branch is
# reached by what the hook itself reads: savedAt on task.json, else the newest note under notes/,
# else neither. One ordinary task carries all three, because each branch is a state of those two
# inputs, and the rows walk it forward through them.
# ------------------------------------------------------------------------------------------------
make_task h1
H1="$PROJECT/tasks/h1"; WH1="$(wt_of h1)"
must "$WH1" "$TASKS" start --project "$PROJECT" h1 -- the work starts

echo "--- the never-saved branch: a task just started holds no stage work"
expect "the task is in progress with neither savedAt nor a note" \
  "$(jq -r '.state + " " + (.savedAt // "absent")' "$H1/task.json")$([ -d "$H1/notes" ] && echo " notes" || echo " none")" \
  "in_progress absent none"
expect "start wrote the task check under records/" \
  "$([ -f "$H1/records/check-task.json" ] && echo yes || echo no)" "yes"
RC="$(compact "$WH1" "$ROOT/out-h1a.txt")"
expect "a manual compact exits 0" "$RC" "0"
expect "nothing was said" "$(wc -c <"$ROOT/out-h1a.txt" | tr -d ' ')" "0"

echo "--- the never-saved branch: a file under inputs/ is not stage work"
mkdir -p "$H1/inputs" && printf 'a pasted specification\n' >"$H1/inputs/spec.md"
RC="$(compact "$WH1" "$ROOT/out-h1b.txt")"
expect "a manual compact exits 0" "$RC" "0"
expect "nothing was said" "$(wc -c <"$ROOT/out-h1b.txt" | tr -d ' ')" "0"

echo "--- the never-saved branch: a stage record still refuses"
must "$WH1" "$SCOPE" init "$H1"
RC="$(compact "$WH1" "$ROOT/out-h1c.txt")"
expect "a manual compact exits 2" "$RC" "2"
expect "the refusal names the save" "$(holds "$ROOT/out-h1c.txt" "run \`/aida:task save h1\` before compacting")" "1"

echo "--- the savedAt branch: inputs/ and records/ newer than the save are not stage work"
# savedAt is a whole second, and the hook's reference file carries it with no fraction. So the
# save runs at the start of a second, and every later write lands in a later one.
settle
must "$WH1" "$TASKS" save --project "$PROJECT" h1 -- the contract was started
settle
expect "savedAt is on disk" "$(jq -r '.savedAt // "absent"' "$H1/task.json" | wc -c | tr -d ' ')" "21"
RC="$(compact "$WH1" "$ROOT/out-h1d.txt")"
expect "a manual compact exits 0 right after the save" "$RC" "0"
printf 'a page the work started from\n' >"$H1/inputs/spec.md"
RC="$(compact "$WH1" "$ROOT/out-h1e.txt")"
expect "a manual compact exits 0 with inputs/ newer" "$RC" "0"
# The task check is the producer of records/check-task.json, run again, so the folder holds a file
# newer than the save without any stage having written one.
must "$WH1" "$PLUGIN/scripts/check-task.sh" "$H1"
RC="$(compact "$WH1" "$ROOT/out-h1f.txt")"
expect "a manual compact exits 0 with records/ newer" "$RC" "0"
expect "nothing was said" "$(wc -c <"$ROOT/out-h1f.txt" | tr -d ' ')" "0"

echo "--- the savedAt branch: a stage record newer than the save still refuses"
must "$WH1" "$SCOPE" set-goal "$H1" --goal "do the work" --expected-result "work done"
RC="$(compact "$WH1" "$ROOT/out-h1g.txt")"
expect "a manual compact exits 2" "$RC" "2"
expect "the refusal names the save" "$(holds "$ROOT/out-h1g.txt" "run \`/aida:task save h1\` before compacting")" "1"

echo "--- the note branch: task.json written after the note is not stage work"
# The hook reads the newest note when task.json carries no savedAt. A second save clears the
# refusal above and appends to the same note, so the note is the newest thing a save wrote. Then
# savedAt alone is removed. Nothing is touched: the save writes task.json straight after the note,
# which is the shape this branch has to read past.
settle
must "$WH1" "$TASKS" save --project "$PROJECT" h1 -- the goal was agreed
settle
jq 'del(.savedAt)' "$H1/task.json" >"$ROOT/h1.json" && mv "$ROOT/h1.json" "$H1/task.json"
expect "a note is on disk and savedAt is not" \
  "$(jq -r '.savedAt // "absent"' "$H1/task.json") $(find "$H1/notes" -name '[0-9-]*.md' | wc -l | tr -d ' ')" "absent 1"
expect "task.json is newer than the note" \
  "$([ "$H1/task.json" -nt "$(find "$H1/notes" -name '[0-9-]*.md' | sort | tail -1)" ] && echo yes || echo no)" "yes"
RC="$(compact "$WH1" "$ROOT/out-h1h.txt")"
expect "a manual compact exits 0" "$RC" "0"
expect "nothing was said" "$(wc -c <"$ROOT/out-h1h.txt" | tr -d ' ')" "0"

echo "--- the note branch: a file under inputs/ newer than the note is not stage work"
printf 'a second page the work started from\n' >"$H1/inputs/spec2.md"
RC="$(compact "$WH1" "$ROOT/out-h1i.txt")"
expect "a manual compact exits 0" "$RC" "0"
expect "nothing was said" "$(wc -c <"$ROOT/out-h1i.txt" | tr -d ' ')" "0"

echo "--- the note branch: a stage record newer than the note still refuses"
must "$WH1" "$SCOPE" add "$H1" --text "first thing" --verification "the document says so" --verified-by machine
jq 'del(.savedAt)' "$H1/task.json" >"$ROOT/h1.json" && mv "$ROOT/h1.json" "$H1/task.json"
RC="$(compact "$WH1" "$ROOT/out-h1j.txt")"
expect "a manual compact exits 2" "$RC" "2"
expect "the refusal names the save" "$(holds "$ROOT/out-h1j.txt" "run \`/aida:task save h1\` before compacting")" "1"

printf 'passed %s of %s\n' "$PASS" "$TOTAL"
[ "$PASS" -eq "$TOTAL" ]
