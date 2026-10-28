#!/usr/bin/env bash
# Fixture db: a redo reverts the order's own commits, read from its records' commit lists, and
# the tests brief then carries the person's words (live-run row 94, gap row 252, 6.1.0 batch 3a).
# Builds a project and two tasks, each with two work orders (wo1 proved by tests and owning
# a.php, wo2 a gate order owning b.php), freezes and builds wo1, changes wo1's design, which stops
# it, and redoes it. Runs under bash, which CI runs on Linux, from $HOME, with CLAUDE_PLUGIN_ROOT unset. Setup
# lives in functions, copied from run-cy-fixture.sh and run-cs-fixture.sh.
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
# pa <task folder> <step> <order or empty> <words>: records a person's answer through
# person-answer.sh. Since batch 2b (6.1.0) each person-only step reads it, in every run mode.
pa() {
  printf '%s' "$4" >"$ROOT/pa-words"
  if [ -n "$3" ]; then
    (cd "$HOME" && env -u CLAUDE_PLUGIN_ROOT bash "$PLUGIN/skills/task/scripts/person-answer.sh" --project "${1%/tasks/*}" \
      "${1##*/}" --step "$2" --order "$3" -- "@$ROOT/pa-words") >/dev/null 2>&1
  else
    (cd "$HOME" && env -u CLAUDE_PLUGIN_ROOT bash "$PLUGIN/skills/task/scripts/person-answer.sh" --project "${1%/tasks/*}" \
      "${1##*/}" --step "$2" -- "@$ROOT/pa-words") >/dev/null 2>&1
  fi
}
export AIDA_REGISTRY_PATH="$ROOT/aida/registry.json"
export AIDA_PROJECTS_HOME="$ROOT/aida/projects"
export AIDA_SETTINGS_PATH="$ROOT/aida/settings.json"
CODE="$ROOT/code"
PROJECT="$ROOT/aida/projects/dbfx"
RECIPES="$ROOT/recipes"
TEST_RECIPE_FLAG="fake=$RECIPES/test-execution.md"
SCOPE="$PLUGIN/skills/scope/scripts/scope-actions.sh"
RESEARCH="$PLUGIN/skills/research/scripts/research-actions.sh"
DESIGN="$PLUGIN/skills/design/scripts/design-actions.sh"
IMPLEMENT="$PLUGIN/skills/implement/scripts/implement-actions.sh"
LOG="$ROOT/log.txt"
# The task under test and its worktree; use_task sets both.
TASK=""
WT=""

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

make_code_repo() {
  mkdir -p "$CODE" && cd "$CODE" || exit 1
  git init -q -b main && git config user.email fx@example.invalid && git config user.name fx
  for f in a b c; do printf '%s\n' "$f" >"$f.php"; done
  git add -A && git commit -qm init && git checkout -q -b work
  cd "$HOME" || exit 1
}

make_project() {
  env -u CLAUDE_PLUGIN_ROOT "$SH" "$PLUGIN/skills/project/scripts/project-actions.sh" create \
    --name dbfx --path "$CODE" --projects-home "$AIDA_PROJECTS_HOME" --framework fake >>"$LOG" 2>&1 || exit 1
}

# use_task <name>: creates the task and points TASK and WT at it.
use_task() {
  env -u CLAUDE_PLUGIN_ROOT "$SH" "$PLUGIN/skills/task/scripts/task-actions.sh" create \
    --project "$PROJECT" --name "$1" -- change some files >>"$LOG" 2>&1 || exit 1
  TASK="$PROJECT/tasks/$1"
  WT="$(jq -r '.worktree.path' "$TASK/task.json")"
  [ -d "$WT" ] || { printf 'setup failed: no worktree for %s\n' "$1"; exit 1; }
}

# One machine-verified criterion and one a person verifies; the distill sidecar is an agent's
# record, so the fixture writes it.
scope_task() {
  must "$SCOPE" init "$TASK"
  must "$SCOPE" set-goal "$TASK" --goal "change files" --expected-result "files changed"
  must "$SCOPE" add "$TASK" --text "a.php changes" --verification "tests/ATest.sh" --verified-by machine
  must "$SCOPE" add "$TASK" --text "b.php changes" --verification "look" --verified-by person
  mkdir -p "$TASK/records"
  printf '{"schemaVersion":1,"stage":"scope","standsAlone":true,"decisions":["change files"],"gaps":[]}\n' \
    >"$TASK/records/scope-distill.json"
  must "$SCOPE" approve "$TASK"
}

research_task() {
  must "$RESEARCH" start "$TASK"
  must "$RESEARCH" record "$TASK" --search prior --searched-for "prior art" --text "none" \
    --source "the tree" --criteria-served c1,c2
  must "$RESEARCH" check "$TASK"
}

close_design() { must "$DESIGN" account "$TASK" --id wo1 --finding prior#1; must "$DESIGN" --run-mode interactive close "$TASK" --no-recipe; }

# wo1 is proved by tests and owns a.php; wo2 is a gate order owning b.php. Neither depends on
# the other, so a change to wo1 stops wo1 alone.
design_task() {
  must "$DESIGN" start "$TASK"
  must "$DESIGN" create "$TASK" --title "change a" --criteria-served c1 --criteria-owned c1 \
    --reasoning "the brief says so" --diff-budget small --interface none
  must "$DESIGN" add-owned-file "$TASK" --id wo1 --path a.php
  must "$DESIGN" add-owned-file "$TASK" --id wo1 --path tests/ATest.sh
  must "$DESIGN" add-done-when "$TASK" --id wo1 --text "change a"
  must "$DESIGN" add-test "$TASK" --id wo1 --level unit --description "ATest checks a"
  must "$DESIGN" create "$TASK" --title "change b" --criteria-served c2 --criteria-owned c2 \
    --reasoning "the brief says so" --diff-budget small --interface none --proof gate
  must "$DESIGN" add-owned-file "$TASK" --id wo2 --path b.php
  must "$DESIGN" add-done-when "$TASK" --id wo2 --text "change b"
  close_design
}

write_recipes() {
  mkdir -p "$RECIPES"
  printf -- '---\nname: fake_implement\ncapability: implement\nrecipe_class: process\nframework: fake\n---\n\n## Configuration gate\n\n```sh\ntrue\n```\n' \
    >"$RECIPES/implement.md"
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
    argv: ["true", "{paths}"]
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
    absent: >-
      None.
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
}

# build_task <name>: a task scoped, researched, designed and closed, ready for implement start.
build_task() {
  use_task "$1"
  scope_task
  research_task
  design_task
}

# The commits wo1 leaves on the branch; freeze_and_build_wo1 sets both.
FREEZE=""
BUILD=""
# freeze_and_build_wo1: start, preconditions, wo1's brief and freeze (one commit, the test file),
# then one commit to a.php recorded as wo1's build attempt from the freeze commit.
freeze_and_build_wo1() {
  must "$IMPLEMENT" start "$TASK"
  must "$IMPLEMENT" preconditions "$TASK" --recipe "$TEST_RECIPE_FLAG" --check-recipe "fake=$RECIPES/checks.md"
  must "$IMPLEMENT" tests-brief "$TASK" wo1
  mkdir -p "$WT/tests"
  printf 'exit 1\n' >"$WT/tests/ATest.sh"
  must "$IMPLEMENT" tests-freeze "$TASK" wo1 --test-recipe "$TEST_RECIPE_FLAG" --test-glob 'tests/*Test.sh' \
    --test "tests/ATest.sh::checks_c1=c1" --locks-in "checks_c1=tests/ATest.sh names the code" \
    --row "c1=confirmed::model::ok"
  FREEZE="$(git -C "$WT" rev-parse HEAD)"
  (cd "$WT" && printf 'a2\n' >a.php && git add a.php && git commit -qm "wo1 attempt")
  BUILD="$(git -C "$WT" rev-parse HEAD)"
  printf 'none\n' >"$ROOT/iface.md"; printf 'report\nStop: none\nDeviation: none\n' >"$ROOT/report.md"
  must "$IMPLEMENT" build-record "$TASK" wo1 --interface "$ROOT/iface.md" --report "$ROOT/report.md" \
    --started-at "$FREEZE" --test-recipe "$TEST_RECIPE_FLAG"
}

# stop_wo1: wo1's interface changes, design closes again, and the resumed start stops wo1. Since
# 6.1.0 batch 3b a change mid-build stops an order only unattended, so that start runs autonomous.
stop_wo1() {
  must "$DESIGN" update "$TASK" --id wo1 --interface "a new one"
  close_design
  pa "$TASK" "task set-run-mode" "" "autonomous"
  must "$PLUGIN/skills/task/scripts/task-actions.sh" set-run-mode --project "$PROJECT" "${TASK##*/}" autonomous
  must "$IMPLEMENT" start "$TASK"
  pa "$TASK" "task set-run-mode" "" "interactive"
  must "$PLUGIN/skills/task/scripts/task-actions.sh" set-run-mode --project "$PROJECT" "${TASK##*/}" interactive
  [ "$(ledger_stop wo1)" = "design drift: the design file for wo1 has changed since the snapshot was taken" ] \
    || { printf 'setup failed: wo1 did not stop for drift\n'; exit 1; }
}

# line <file> <key>: the summary line for one key, with its parenthesised order when any.
line() { grep "^$2[:(]" "$1" | head -1; }
# ledger_stop <unit>: the order's stop reasons from the ledger, joined by "; ", or none.
ledger_stop() { jq -r --arg id "$1" '.orders[] | select(.id == $id) | (.stopped // []) | if length == 0 then "none" else map(.reason) | join("; ") end' "$TASK/implementation/ledger.json"; }
# redone <jq filter>: one field of the order's newest redo entry in the ledger.
redone() { jq -r --arg id wo1 ".orders[] | select(.id == \$id) | .redos | last | $1" "$TASK/implementation/ledger.json"; }
# short <sha>: the first seven characters.
short() { printf '%s' "$1" | cut -c1-7; }

make_code_repo
make_project
write_recipes

echo "--- wo1 frozen and built, then stopped for drift: the redo reverts the build and the freeze"
build_task t1
freeze_and_build_wo1
stop_wo1
pa "$TASK" "implement redo" wo1 "wo1 interface changed"
rc="$(try "$ROOT/redo-t1.txt" "$IMPLEMENT" redo "$TASK" wo1 --because "wo1 interface changed")"
expect "redo exits 0" "$rc" "0"
REVERT_FREEZE="$(git -C "$WT" rev-parse HEAD)"
REVERT_BUILD="$(git -C "$WT" rev-parse HEAD~1)"
expect "the ledger lists the build and the freeze, newest first, with their reverts" \
  "$(redone '[.reverted[] | .commit + " " + .revert] | join(",")')" "$BUILD $REVERT_BUILD,$FREEZE $REVERT_FREEZE"
expect "the reverted: line names both" "$(grep '^reverted: ' "$ROOT/redo-t1.txt")" \
  "reverted: $(short "$BUILD") by $(short "$REVERT_BUILD"), $(short "$FREEZE") by $(short "$REVERT_FREEZE")"
expect "HEAD is the revert of the freeze" "$(git -C "$WT" log -1 --format=%B | grep -c "This reverts commit $FREEZE.")" "1"
expect "a.php is back, and the test file is gone" "$(cat "$WT/a.php") $([ -e "$WT/tests/ATest.sh" ] && echo held || echo gone)" "a gone"
expect "redone.json holds the person's words" "$(jq -r '.because' "$(redone '.movedTo')/redone.json")" "wo1 interface changed"

echo "--- start and tests-brief after the redo"
rc="$(try "$ROOT/start-t1.txt" "$IMPLEMENT" start "$TASK")"
expect "start exits 0" "$rc" "0"
rc="$(try "$ROOT/brief-t1.txt" "$IMPLEMENT" tests-brief "$TASK" wo1)"
expect "tests-brief exits 0" "$rc" "0"
expect "the brief carries the redo" "$(jq -r '.redo.because' "$TASK/implementation/brief-wo1-tests.json")" "wo1 interface changed"

echo "--- another order's commit follows wo1's: the redo reverts wo1's alone"
build_task t2
freeze_and_build_wo1
must "$IMPLEMENT" tests-freeze "$TASK" wo2 --test-recipe "$TEST_RECIPE_FLAG" --checklist "c2=look"
(cd "$WT" && printf 'b2\n' >b.php && git add b.php && git commit -qm "wo2 attempt")
must "$IMPLEMENT" build-record "$TASK" wo2 --interface "$ROOT/iface.md" --report "$ROOT/report.md" \
  --started-at "$BUILD" --test-recipe "$TEST_RECIPE_FLAG" \
  --implement-recipe "fake=$RECIPES/implement.md"
stop_wo1
pa "$TASK" "implement redo" wo1 "wo1 interface changed"
rc="$(try "$ROOT/redo-t2.txt" "$IMPLEMENT" redo "$TASK" wo1 --because "wo1 interface changed")"
expect "redo exits 0" "$rc" "0"
expect "the ledger lists wo1's build and freeze alone" "$(redone '[.reverted[] | .commit] | join(",")')" "$BUILD,$FREEZE"
expect "a.php is back and wo2's b.php stays" "$(cat "$WT/a.php") $(cat "$WT/b.php")" "a b2"

printf 'passed %s of %s\n' "$PASS" "$TOTAL"
[ "$PASS" -eq "$TOTAL" ]
