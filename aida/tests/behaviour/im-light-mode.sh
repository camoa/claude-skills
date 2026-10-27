#!/usr/bin/env bash
# Fixture im: a light order's fix-round cap is the one its round was recorded
# under, and a light run leaves a finding still open after that round for the review (gap row 296).
# Before this build, a light task at one of one rounds with a finding still open halted (exit 56).
# A person who then set the task interactive to rule was refused: "wo1 has used 1 of 2, so another
# round is still available" (exit 3), and the order took a second round light does not allow.
# The rows:
#   ruled     light, round one recorded, then the task set interactive: the round is spent, and
#             a ruling on the leftover is taken at once (exit 0). Since gap row 339, a leftover
#             read not-addressed with a person present is offered the repair round instead of
#             a 57 (run-kc-fixture.sh); the person here rules it rather than open that round.
#   pending   light, unattended: a low finding with a fix scope, still open after the one round, goes
#             pending (exit 0), the order closes and its close logs the skipped rounds, and finish
#             carries the finding as a pending decision. Low only: a medium or high finding still
#             waits for a person.
#   high      light, a high finding still open after the one round stops the order (56). The person
#             sets the task interactive and goes on with close, which rules the finding deferred,
#             and close logs the skipped rounds.
# Runs under bash, which CI runs on Linux, from $HOME, with CLAUDE_PLUGIN_ROOT unset. Setup is copied from
# run-fe-fixture.sh.
# fix_report <unit>: the report the newest fix brief of that unit pins, the one path fix-record
# takes (gap row 250), or a file under $ROOT when no brief pins one.
fix_report() {
  local b p=""
  b="$(ls -t "$TASK"/implementation/brief-"$1"-fix-*.json 2>/dev/null | head -n 1)"
  [ -z "$b" ] || p="$(jq -r '.reportPath // empty' "$b")"
  printf '%s' "${p:-$ROOT/fix-report-$1.md}"
}
PLUGIN="${PLUGIN:-$(cd "$(dirname "$0")/../.." && pwd)}"
set -u

PASS=0; TOTAL=0
# expect <what> <actual> <wanted>: prints ok or BAD with both values, and counts.
expect() {
  TOTAL=$((TOTAL + 1))
  if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); printf 'ok: %s\n' "$1"
  else printf 'BAD: %s\n  actual: %s\n  wanted: %s\n' "$1" "$2" "$3"; fi
}
# saw <file> <literal>: yes when the file holds that text, no when it does not.
saw() { if [ -f "$1" ] && grep -Fq -e "$2" "$1"; then printf 'yes'; else printf 'no'; fi; }
# rows <file> <literal>: how many lines of the file hold that text.
rows() { if [ -f "$1" ]; then grep -Fc -e "$2" "$1"; else printf '0'; fi; }

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
PROJECT="$ROOT/aida/projects/imfx"
RECIPES="$ROOT/recipes"
TEST_RECIPE_FLAG="fake=$RECIPES/test-execution.md"
CHECK_RECIPE_FLAG="fake=$RECIPES/checks.md"
TASKS="$PLUGIN/skills/task/scripts/task-actions.sh"
SCOPE="$PLUGIN/skills/scope/scripts/scope-actions.sh"
RESEARCH="$PLUGIN/skills/research/scripts/research-actions.sh"
DESIGN="$PLUGIN/skills/design/scripts/design-actions.sh"
IMPLEMENT="$PLUGIN/skills/implement/scripts/implement-actions.sh"
LOG="$ROOT/log.txt"
OUT="$ROOT/out.txt"
TASK=""; IMPL=""; WT=""; RC=""; CLOG=""

SH=bash; [ -n "${ZSH_VERSION:-}" ] && SH=zsh
in_wt() { (cd "$WT" && env -u CLAUDE_PLUGIN_ROOT "$SH" "$@") >>"$LOG" 2>&1; }
# A setup step that fails ends the run, with the count so far.
must() {
  in_wt "$@" || { printf 'setup failed: %s\n' "$*"; tail -5 "$LOG"; printf 'passed %s of %s\n' "$PASS" "$TOTAL"; exit 1; }
}
# try <out> <cmd>...: runs the action from the worktree, output to <out>, and prints the exit code.
try() {
  local out="$1"; shift
  (cd "$WT" && env -u CLAUDE_PLUGIN_ROOT "$SH" "$@") >"$out" 2>&1
  printf '%s' "$?"
}
line_of() { grep "^$2:" "$1" | head -1 | sed "s/^$2: //"; }

make_code_repo() {
  mkdir -p "$CODE" && cd "$CODE" || exit 1
  git init -q -b main && git config user.email fx@example.invalid && git config user.name fx
  for f in a b; do printf '%s\n' "$f" >"$f.php"; done
  git add -A && git commit -qm init && git checkout -q -b work
  cd "$HOME" || exit 1
}

use_task() {
  env -u CLAUDE_PLUGIN_ROOT "$SH" "$TASKS" create \
    --project "$PROJECT" --name "$1" -- change a file >>"$LOG" 2>&1 || exit 1
  TASK="$PROJECT/tasks/$1"
  IMPL="$TASK/implementation"
  WT="$(jq -r '.worktree.path' "$TASK/task.json")"
  CLOG="$TASK/COMPROMISES.md"
  [ -d "$WT" ] || { printf 'setup failed: no worktree for %s\n' "$1"; exit 1; }
}

# scope_task: one machine-verified criterion, approved. A light task needs no set-tests call; any
# other task is given no automated tests, so every task here builds through confirm.
scope_task() {
  must "$SCOPE" init "$TASK"
  must "$SCOPE" set-goal "$TASK" --goal "greet" --expected-result "a greeting"
  must "$SCOPE" add "$TASK" --text "a.php greets" --verification "a.php prints hello" --verified-by machine
  must "$SCOPE" add "$TASK" --text "b.php names" --verification "b.php prints the name" --verified-by machine
  [ "$(jq -r 'if has("automatedTests") then (.automatedTests | tostring) else "absent" end' "$TASK/alignment.json")" = "false" ] \
    || must "$SCOPE" set-tests "$TASK" --automated no
  mkdir -p "$TASK/records"
  printf '{"schemaVersion":1,"stage":"scope","standsAlone":true,"decisions":["greet"],"gaps":[]}\n' \
    >"$TASK/records/scope-distill.json"
  must "$SCOPE" approve "$TASK"
}

research_task() {
  must "$RESEARCH" start "$TASK"
  must "$RESEARCH" record "$TASK" --search prior --searched-for "prior art" --text "none" \
    --source "the tree" --criteria-served c1,c2
  [ -f "$TASK/records/test-runner.json" ] || { mkdir -p "$TASK/records" && printf '{"verdict":"unmet"}\n' >"$TASK/records/test-runner.json"; } # gap row 366
  must "$RESEARCH" check "$TASK"
}

# design_two: wo1 owns a.php and c1, wo2 owns b.php and c2. No dependency between them.
design_two() {
  must "$DESIGN" start "$TASK"
  must "$DESIGN" create "$TASK" --title "skeleton" --criteria-served c1 --criteria-owned c1 \
    --reasoning "the brief says so" --diff-budget small --interface none
  must "$DESIGN" add-owned-file "$TASK" --id wo1 --path a.php
  must "$DESIGN" add-done-when "$TASK" --id wo1 --text "a.php prints the greeting"
  must "$DESIGN" create "$TASK" --title "name" --criteria-served c2 --criteria-owned c2 \
    --reasoning "the brief says so" --diff-budget small --interface none
  must "$DESIGN" add-owned-file "$TASK" --id wo2 --path b.php
  must "$DESIGN" add-done-when "$TASK" --id wo2 --text "b.php prints the name"
}

# build_order <id> <file> <text>: freezes nothing, builds the order in one commit, and records it.
BUILD=""
build_order() {
  must "$IMPLEMENT" tests-freeze "$TASK" "$1" --test-recipe "$TEST_RECIPE_FLAG"
  local freeze
  freeze="$(git -C "$WT" rev-parse HEAD)"
  must "$IMPLEMENT" build-brief "$TASK" "$1"
  (cd "$WT" && printf '%s\n' "$3" >"$2" && git add "$2" && git commit -qm "$1 attempt" >/dev/null 2>&1)
  must "$IMPLEMENT" build-record "$TASK" "$1" --interface "$ROOT/iface.md" --report "$ROOT/report.md" \
    --started-at "$freeze" --test-recipe "$TEST_RECIPE_FLAG" --check-recipe "$CHECK_RECIPE_FLAG"
  BUILD="$(git -C "$WT" rev-parse HEAD)"
}

# fix_round <id> <file> <verdict> [severity]: one review finding on the order's own criterion, one fix round,
# one verification.
fix_round() {
  printf '{ "findings": [{"id":"f1","severity":"%s","file":"%s","lines":"1-1","linkedTo":"c%s","evidence":"the text is wrong","fixScope":["%s"]}] }\n' \
    "${4:-high}" "$2" "${1#wo}" "$2" >"$ROOT/findings-$1.json"
  must "$IMPLEMENT" review-record "$TASK" "$1" --findings "$ROOT/findings-$1.json"
  RC="$(try "$OUT" "$IMPLEMENT" fix-brief "$TASK" "$1")"
  (cd "$WT" && printf 'fixed\n' >>"$2" && git add "$2" && git commit -qm "$1 fixed" >/dev/null 2>&1)
  printf 'fixed it\n' >"$(fix_report "$1")"
  must "$IMPLEMENT" fix-record "$TASK" "$1" --report "$(fix_report "$1")" --started-at "$BUILD" \
    --test-recipe "$TEST_RECIPE_FLAG" --check-recipe "$CHECK_RECIPE_FLAG"
  must "$IMPLEMENT" verify-brief "$TASK" "$1"
  printf '{ "verdicts": [{"id":"f1","verdict":"%s"}] }\n' "$3" >"$IMPL/verify-$1-1.json"
}

write_recipes() {
  mkdir -p "$RECIPES"
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
    argv: ["no-such-runner"]
    cost: every-attempt
  - id: file
    argv: ["no-such-runner", "{paths}"]
    cost: every-attempt
  - id: test
    absent: >-
      No single-test form.
  - id: changed
    absent: >-
      No changed form.
  - id: smoke
    argv: ["no-such-runner"]
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
}

make_code_repo
write_recipes
env -u CLAUDE_PLUGIN_ROOT "$SH" "$PLUGIN/skills/project/scripts/project-actions.sh" create \
  --name imfx --path "$CODE" --projects-home "$AIDA_PROJECTS_HOME" --framework fake >>"$LOG" 2>&1 || exit 1
printf 'none\n' >"$ROOT/iface.md"; printf 'report\nStop: none\nDeviation: none\n' >"$ROOT/report.md"
printf '{ "findings": [] }\n' >"$ROOT/rv-none.json"


# light_task <name>: a light task through design, with wo2 after wo1, and the build started.
light_task() {
  use_task "$1"
  pa "$PROJECT/tasks/$1" "task set-run-mode" "" "light"
  must "$TASKS" set-run-mode --project "$PROJECT" "$1" light
  scope_task
  research_task
  design_two
  must "$DESIGN" update "$TASK" --id wo2 --depends-on wo1
  must "$DESIGN" account "$TASK" --id wo1 --finding prior#1
  must "$DESIGN" --run-mode autonomous close "$TASK" --no-recipe
  must "$IMPLEMENT" start "$TASK"
  must "$IMPLEMENT" preconditions "$TASK" --recipe "$TEST_RECIPE_FLAG" --check-recipe "$CHECK_RECIPE_FLAG"
}
status_of() { jq -r --arg id "$1" '[ .findings[] | select(.id == $id) ][0] | .status // "none"' "$IMPL/review-wo1.json"; }

# --------------------------------------------------------------------------------------------
# ruled: round one recorded on a light task, then the task set interactive to rule.
# --------------------------------------------------------------------------------------------
echo "--- ruled: a person who sets the light task interactive rules at once"
light_task lb
build_order wo1 a.php "hello"
fix_round wo1 a.php not-addressed low
pa "$PROJECT/tasks/lb" "task set-run-mode" "" "interactive"
must "$TASKS" set-run-mode --project "$PROJECT" lb interactive
RC="$(try "$OUT" "$IMPLEMENT" verify-record "$TASK" wo1 --verdicts "$IMPL/verify-wo1-1.json")"
expect "the round is spent, and the leftover read not-addressed waits for the person (0)" "$RC $(status_of f1)" "0 open"
expect "the summary offers the one repair round" "$(saw "$OUT" "one repair round may take f1")" "yes"
pa "$TASK" "implement verify-record" wo1 "f1=deferred::low, a later task takes it"
RC="$(try "$OUT" "$IMPLEMENT" verify-record "$TASK" wo1 --ruling "f1=deferred::low, a later task takes it")"
expect "the ruling is taken at once" "$RC" "0"
expect "the leftover is ruled deferred" "$(jq -r '[ .findings[] | select(.id == "f1") ][0].ruling // "none"' "$IMPL/review-wo1.json")" "deferred"
RC="$(try "$OUT" "$IMPLEMENT" close "$TASK" wo1)"
expect "wo1 closes after one round" "$RC" "0"
expect "the order used one round" "$(jq -r '.orders[0].roundsUsed' "$IMPL/ledger.json")" "1"

# --------------------------------------------------------------------------------------------
# pending: light, unattended, a finding with a fix scope is still open after the one round.
# --------------------------------------------------------------------------------------------
echo "--- pending: a light run leaves the open low finding for the review"
light_task la
build_order wo1 a.php "hello"
fix_round wo1 a.php not-addressed low
RC="$(try "$OUT" "$IMPLEMENT" verify-record "$TASK" wo1 --verdicts "$IMPL/verify-wo1-1.json")"
expect "verify-record does not halt the light order" "$RC" "0"
expect "the low finding with a fix scope is pending" "$(status_of f1)" "pending"
expect "the order is not stopped" "$(jq -r '.orders[0].stopped // "none"' "$IMPL/ledger.json")" "none"
expect "the ledger marks the round as light" "$(jq -r '.orders[0].lightRounds // "absent"' "$IMPL/ledger.json")" "true"
RC="$(try "$OUT" "$IMPLEMENT" close "$TASK" wo1)"
expect "wo1 closes" "$RC" "0"
expect "close logs the skipped rounds" "$(saw "$CLOG" "| la | implement | fix rounds after the first on wo1, which left f1 to a ruling")" "yes"
expect "the code tree holds no log" "$([ -e "$WT/COMPROMISES.md" ] && echo yes || echo no)" "no"
build_order wo2 b.php "name"
must "$IMPLEMENT" review-record "$TASK" wo2 --findings "$ROOT/rv-none.json"
must "$IMPLEMENT" close "$TASK" wo2
RC="$(try "$OUT" "$IMPLEMENT" finish "$TASK")"
expect "finish exits 0" "$RC" "0"
expect "finish puts the finding to the person" \
  "$(jq -r '[ (.pendingDecisions // [])[] | "\(.unit)-\(.finding)-\(.kind)" ] | join(",")' "$IMPL/finished.json" 2>/dev/null)" "wo1-f1-ruling"

# --------------------------------------------------------------------------------------------
# high: a high finding still halts a light order, and the person rules it through interactive.
# --------------------------------------------------------------------------------------------
echo "--- high: a light order halts on a high finding, and the person rules at once"
light_task lc
build_order wo1 a.php "hello"
fix_round wo1 a.php not-addressed high
RC="$(try "$OUT" "$IMPLEMENT" verify-record "$TASK" wo1 --verdicts "$IMPL/verify-wo1-1.json")"
expect "a high finding halts the light order (56)" "$RC" "56"
expect "the high finding stays open" "$(status_of f1)" "open"
pa "$PROJECT/tasks/lc" "task set-run-mode" "" "interactive"
must "$TASKS" set-run-mode --project "$PROJECT" lc interactive
pa "$TASK" "implement go-on close" wo1 "a later task fixes it"
RC="$(try "$OUT" "$IMPLEMENT" go-on "$TASK" wo1 --continue close --because "a later task fixes it")"
expect "go-on close rules the finding deferred with no second round" "$RC $(status_of f1)" "0 ruled"
RC="$(try "$OUT" "$IMPLEMENT" close "$TASK" wo1)"
expect "wo1 closes" "$RC" "0"
expect "close logs the skipped rounds on the interactive task" "$(saw "$CLOG" "| lc | implement | fix rounds after the first on wo1, which left f1 to a ruling")" "yes"
expect "the code tree holds no log" "$([ -e "$WT/COMPROMISES.md" ] && echo yes || echo no)" "no"

printf 'passed %s of %s\n' "$PASS" "$TOTAL"
[ "$PASS" -eq "$TOTAL" ]
