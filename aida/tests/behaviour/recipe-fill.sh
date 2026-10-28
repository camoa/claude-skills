#!/usr/bin/env bash
# Fixture recipe-fill: build-record and fix-record take a left-out recipe flag from the records
# (gap rows 397 and 399). preconditions.json holds the test recipe and baseline.json
# the check recipe, so neither step needs --test-recipe, and neither reads a check recipe. One task, one order,
# a stub runner (`true`) for the tests and the coding-standards tool. The rows:
#   build    build-record with no recipe flag: exit 0, order-tests reads met.
#   fix      one finding and one fix round, fix-record with no recipe flag: exit 0, order-tests
#            reads met.
#   none     the same round with no check recipe in baseline.json exits 0. With no test recipe
#            in preconditions.json, build-record refuses at 3 and spends no attempt.
# The record steps run no tool row since 6.1.0, so no coding-standards verdict is read here.
# Runs under bash, which CI runs on Linux, from $HOME, with CLAUDE_PLUGIN_ROOT unset.
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
PROJECT="$ROOT/aida/projects/rffx"
TASK="$PROJECT/tasks/t1"
IMPL="$TASK/implementation"
WT="$ROOT/code.worktrees/code-t1"
RECIPES="$ROOT/recipes"
SCOPE="$PLUGIN/skills/scope/scripts/scope-actions.sh"
RESEARCH="$PLUGIN/skills/research/scripts/research-actions.sh"
DESIGN="$PLUGIN/skills/design/scripts/design-actions.sh"
IMPLEMENT="$PLUGIN/skills/implement/scripts/implement-actions.sh"
TASKS="$PLUGIN/skills/task/scripts/task-actions.sh"
LOG="$ROOT/log.txt"
OUT="$ROOT/out.txt"

in_wt() { (cd "$WT" && env -u CLAUDE_PLUGIN_ROOT bash "$@") >>"$LOG" 2>&1; }
must() { in_wt "$@" || { printf 'setup failed: %s\n' "$*"; tail -5 "$LOG"; exit 1; }; }
# try <out> <cmd>...: runs the action from the worktree, output to <out>, and prints the exit code.
try() {
  local out="$1"; shift
  (cd "$WT" && env -u CLAUDE_PLUGIN_ROOT bash "$@") >"$out" 2>&1
  printf '%s' "$?"
}
# verdict <record> <check id>
verdict() { jq -r --arg id "$2" '.checks[] | select(.id == $id) | .verdict' "$1" 2>/dev/null; }
order() { jq -r ".orders[] | select(.id == \"wo1\") | $1" "$IMPL/ledger.json"; }

mkdir -p "$CODE" "$RECIPES" && cd "$CODE" || exit 1
git init -q -b main && git config user.email fx@example.invalid && git config user.name fx
printf 'a\n' >a.php
git add -A && git commit -qm init && git checkout -q -b work
cd "$HOME" || exit 1
env -u CLAUDE_PLUGIN_ROOT bash "$PLUGIN/skills/project/scripts/project-actions.sh" create \
  --name rffx --path "$CODE" --projects-home "$AIDA_PROJECTS_HOME" --framework fake >>"$LOG" 2>&1 || exit 1
env -u CLAUDE_PLUGIN_ROOT bash "$TASKS" create --project "$PROJECT" --name t1 -- change a file >>"$LOG" 2>&1 || exit 1

must "$SCOPE" init "$TASK"
must "$SCOPE" set-goal "$TASK" --goal "change a" --expected-result "a changed"
must "$SCOPE" add "$TASK" --text "a.php changes" --verification "look" --verified-by person
mkdir -p "$TASK/records"
printf '{"schemaVersion":1,"stage":"scope","standsAlone":true,"decisions":["change a"],"gaps":[]}\n' \
  >"$TASK/records/scope-distill.json"
must "$SCOPE" approve "$TASK"
must "$RESEARCH" start "$TASK"
must "$RESEARCH" record "$TASK" --search prior --searched-for "prior art" --text "none" \
  --source "the tree" --criteria-served c1
must "$RESEARCH" check "$TASK"
must "$DESIGN" start "$TASK"
must "$DESIGN" create "$TASK" --title "change a" --criteria-served c1 --criteria-owned c1 \
  --reasoning "the brief says so" --diff-budget small --interface none
must "$DESIGN" add-owned-file "$TASK" --id wo1 --path a.php
must "$DESIGN" add-done-when "$TASK" --id wo1 --text "change a"
must "$DESIGN" account "$TASK" --id wo1 --finding prior#1
must "$DESIGN" --run-mode interactive close "$TASK" --no-recipe

cat >"$RECIPES/test-execution.md" <<'EOR'
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
EOR
cat >"$RECIPES/checks.md" <<'EOR'
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
EOR

must "$IMPLEMENT" start "$TASK"
must "$IMPLEMENT" preconditions "$TASK" \
  --recipe "fake=$RECIPES/test-execution.md" --check-recipe "fake=$RECIPES/checks.md"
must "$IMPLEMENT" tests-freeze "$TASK" wo1 --test-recipe "fake=$RECIPES/test-execution.md" --checklist "c1=look"
must "$IMPLEMENT" build-brief "$TASK" wo1
FROM="$(git -C "$WT" rev-parse HEAD)"
(cd "$WT" && printf 'a built\n' >a.php && git add a.php && git commit -qm "wo1 built")
printf 'none\n' >"$IMPL/interface-wo1.md"
printf 'the five answers\nStop: none\nDeviation: none\n' >"$IMPL/answers-wo1-attempt1.md"
cp -p "$IMPL/ledger.json" "$ROOT/built-ledger.json"
cp -p "$IMPL/preconditions.json" "$ROOT/preconditions.json"

echo "--- build: build-record with no recipe flag"
expect "build: build-record exits 0" "$(try "$OUT" "$IMPLEMENT" build-record "$TASK" wo1 \
  --interface "$IMPL/interface-wo1.md" --report "$IMPL/answers-wo1-attempt1.md" --started-at "$FROM")" "0"
expect "build: order-tests reads met" "$(verdict "$IMPL/build-wo1.json" order-tests)" "met"

echo "--- fix: one finding and one fix round, fix-record with no recipe flag"
jq -n '{findings: [{id: "f1", severity: "medium", file: "a.php", lines: "1", linkedTo: "c1",
    evidence: "the line says built", fixScope: ["a.php"]}], recipes: []}' >"$ROOT/findings.json"
must "$IMPLEMENT" review-record "$TASK" wo1 --findings "$ROOT/findings.json"
must "$IMPLEMENT" fix-brief "$TASK" wo1
FIX_FROM="$(git -C "$WT" rev-parse HEAD)"
FIX_REPORT="$(jq -r '.reportPath' "$IMPL/brief-wo1-fix-1.json")"
(cd "$WT" && printf 'a fixed\n' >a.php && git commit -qam "fix round 1")
printf 'fixed it\nStop: none\nDeviation: none\n' >"$FIX_REPORT"
cp -p "$IMPL/ledger.json" "$ROOT/reviewed-ledger.json"
expect "fix: fix-record exits 0" "$(try "$OUT" "$IMPLEMENT" fix-record "$TASK" wo1 \
  --report "$FIX_REPORT" --started-at "$FIX_FROM")" "0"
expect "fix: order-tests reads met" "$(verdict "$IMPL/fix-wo1-1.json" order-tests)" "met"
expect "fix: roundsUsed is 1" "$(order .roundsUsed)" "1"

echo "--- none: nothing on record to take"
rm -f "$IMPL/fix-wo1-1.json"; cp -p "$ROOT/reviewed-ledger.json" "$IMPL/ledger.json"
jq '.checkRecipes = []' "$IMPL/baseline.json" >"$ROOT/b" && mv "$ROOT/b" "$IMPL/baseline.json"
expect "none: fix-record with no check recipe exits 0" "$(try "$OUT" "$IMPLEMENT" fix-record "$TASK" wo1 \
  --report "$FIX_REPORT" --started-at "$FIX_FROM")" "0"
cp -p "$ROOT/built-ledger.json" "$IMPL/ledger.json"; rm -f "$IMPL/build-wo1.json"
jq '.frameworks = [ .frameworks[] | del(.recipePath) ]' "$ROOT/preconditions.json" >"$IMPL/preconditions.json"
expect "none: build-record with no test recipe refuses 3" "$(try "$OUT" "$IMPLEMENT" build-record "$TASK" wo1 \
  --interface "$IMPL/interface-wo1.md" --report "$IMPL/answers-wo1-attempt1.md" --started-at "$FROM")" "3"
expect "none: no attempt was spent" "$(order '.attemptsUsed // 0')" "0"

printf 'passed %s of %s\n' "$PASS" "$TOTAL"
[ "$PASS" -eq "$TOTAL" ]
