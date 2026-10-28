#!/usr/bin/env bash
# Fixture kg: a dispatch record opened and never sent has a route back, and a
# fresh open keeps a fixer's finished report (gap row 343). Live, a fixer record was opened, the
# session ended before the Agent call, and the only close counted a resume no role spent. Later a
# fresh open removed a finished fixer report before fix-record read it. The rows:
#   notsent   --not-sent on an unsent record removes it, spends no resume, leaves the ledger alone;
#             a second open names --not-sent (37).
#   written   --not-sent with the role's report written refuses (3); the record stays open.
#   resumed   --not-sent on a record that counts a resume refuses (3).
#   reopen    --not-sent on a record reopened with --resume removes it and keeps the report.
#   finished  a fresh open refuses (3) while a finished report is newer than its brief, and keeps
#             it; after fix-brief writes the brief again, the open succeeds and removes it.
#   halt      a fixer cut off at its turn cap with a complete report is sent to fix-record (a
#             halt, 110, until 6.1.0 batch 3b; a warning now).
#   commit    --not-sent after a commit in the code path refuses (3).
#   record    --not-sent after a commit to a record order's owned file in the project folder
#             refuses (3).
# Runs under bash, which CI runs on Linux, from $HOME, with CLAUDE_PLUGIN_ROOT unset. Setup is copied from
# run-iz-fixture.sh.
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
PROJECT="$ROOT/aida/projects/kgfx"
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
TEST_RECIPE_FLAG="fake=$RECIPES/test-execution.md"
CHECK_RECIPE_FLAG="fake=$RECIPES/checks.md"

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

make_project_and_task() {
  env -u CLAUDE_PLUGIN_ROOT "$SH" "$PLUGIN/skills/project/scripts/project-actions.sh" create \
    --name kgfx --path "$CODE" --projects-home "$AIDA_PROJECTS_HOME" --framework fake >>"$LOG" 2>&1 || exit 1
  env -u CLAUDE_PLUGIN_ROOT "$SH" "$TASKS" create \
    --project "$PROJECT" --name t1 -- change some files >>"$LOG" 2>&1 || exit 1
}

# One machine-verified criterion and one person-verified; the distill sidecar is an agent's
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

# design_order <woId> <criterion> <title> <path>: one order, proved by tests, owning the path.
# `p`, never `path`: zsh ties a variable named path to PATH, and a local one empties it.
design_order() {
  local id="$1" crit="$2" title="$3" p="$4"
  must "$DESIGN" create "$TASK" --title "$title" --criteria-served "$crit" --criteria-owned "$crit" \
    --reasoning "the brief says so" --diff-budget small --interface none
  must "$DESIGN" add-owned-file "$TASK" --id "$id" --path "$p"
  must "$DESIGN" add-done-when "$TASK" --id "$id" --text "$title"
}

design_task() {
  must "$DESIGN" start "$TASK"
  design_order wo1 c1 "change a" a.php
  must "$DESIGN" add-owned-file "$TASK" --id wo1 --path tests/ATest.sh
  must "$DESIGN" add-test "$TASK" --id wo1 --level unit --description "ATest checks a"
  design_order wo2 c2 "change b" b.php
  must "$DESIGN" account "$TASK" --id wo1 --finding prior#1
  must "$DESIGN" --run-mode interactive close "$TASK" --no-recipe
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
}

# wo1 freezes one test file, committed so the tree is clean at the build; wo2 freezes its
# person-verified row.
implement_to_freeze() {
  must "$IMPLEMENT" start "$TASK"
  must "$IMPLEMENT" preconditions "$TASK" --recipe "$TEST_RECIPE_FLAG" --check-recipe "$CHECK_RECIPE_FLAG"
  mkdir -p "$WT/tests"
  printf 'exit 1\n' >"$WT/tests/ATest.sh"
  must "$IMPLEMENT" tests-freeze "$TASK" wo1 \
    --test-recipe "$TEST_RECIPE_FLAG" --test-glob 'tests/*Test.sh' \
    --test "tests/ATest.sh::checks_c1=c1" --locks-in "checks_c1=tests/ATest.sh names the code" \
    --row "c1=confirmed::model::ok"
  (cd "$WT" && git add tests/ATest.sh && git commit -qm "wo1 test")
  must "$IMPLEMENT" tests-freeze "$TASK" wo2 --test-recipe "$TEST_RECIPE_FLAG" --checklist "c2=look"
}

# commit_change <file> <text>: one commit in the worktree changing the file. SEQ keeps every
# write different, so each call makes a commit.
SEQ=0
commit_change() {
  SEQ=$((SEQ + 1))
  (cd "$WT" && printf '%s %s\n' "$2" "$SEQ" >"$1" && git add "$1" && git commit -qm "$2")
}

# build_order <unit> <file>: one commit changing the file, then the attempt recorded from the
# worktree's previous commit to its head. The ledger then reads checks-passed for the order.
build_order() {
  local unit="$1" file="$2" from
  commit_change "$file" "$unit built"
  from="$(git -C "$WT" rev-parse HEAD~1)"
  printf 'none\n' >"$ROOT/iface.md"; printf 'report\nStop: none\nDeviation: none\n' >"$ROOT/report.md"
  must "$IMPLEMENT" build-record "$TASK" "$unit" \
    --interface "$ROOT/iface.md" --report "$ROOT/report.md" --started-at "$from" \
    --test-recipe "$TEST_RECIPE_FLAG" --check-recipe "$CHECK_RECIPE_FLAG"
}

# fix_brief <out> [--allow <path>]...: fix-brief for wo1, output to <out>, prints the exit code.
# pinned_report: the report the newest fix brief pins, the one path fix-record and
# dispatch-close accept (gap row 250).
pinned_report() { jq -r '.reportPath' "$(ls -t "$IMPL"/brief-wo1-fix-*.json | head -n 1)"; }
fix_brief() { local out="$1"; shift; try "$out" "$IMPLEMENT" fix-brief "$TASK" wo1 "$@"; }


# order_field <unit> <jq expr>: one field of the order's ledger entry.
order_field() { jq -r --arg id "$1" ".orders[] | select(.id == \$id) | $2" "$IMPL/ledger.json"; }

FINDINGS='[{"id":"f1","severity":"high","file":"a.php","lines":"1","linkedTo":"c1","evidence":"a is wrong","fixScope":["a.php"]}]'

make_code_repo
make_project_and_task
scope_task
research_task
design_task
write_recipes
implement_to_freeze
build_order wo1 a.php
printf '{ "findings": %s }\n' "$FINDINGS" >"$ROOT/findings.json"
must "$IMPLEMENT" review-record "$TASK" wo1 --findings "$ROOT/findings.json"
rc="$(fix_brief "$ROOT/out-brief.txt")"
expect "setup: the fix brief: exit 0" "$rc" "0"
DISPATCH="$IMPL/dispatch.json"
# commit_at <stamp>: one commit changing a.php, committed at that time.
commit_at() {
  SEQ=$((SEQ + 1))
  (cd "$WT" && printf 'fixed %s\n' "$SEQ" >a.php && git add a.php \
    && GIT_COMMITTER_DATE="$1" GIT_AUTHOR_DATE="$1" git commit -qm "fix $SEQ")
}

reset() { rm -f "$DISPATCH"; }

echo "--- notsent: a fixer record opened and never sent is withdrawn, and no resume is spent"
must "$IMPLEMENT" dispatch-open "$TASK" fixer wo1
rc="$(try "$ROOT/do-twice.txt" "$IMPLEMENT" dispatch-open "$TASK" fixer wo1)"
expect "a second open refuses: exit 37" "$rc" "37"
expect "the refusal names --not-sent" "$(grep -c -- "--not-sent" "$ROOT/do-twice.txt")" "1"
LEDGER_BEFORE="$(jq -S -c . "$IMPL/ledger.json")"
rc="$(try "$ROOT/dc-notsent.txt" "$IMPLEMENT" dispatch-close "$TASK" --not-sent)"
expect "--not-sent on an unsent record: exit 0" "$rc" "0"
expect "the record is removed" "$([ -f "$DISPATCH" ] && echo open || echo removed)" "removed"
expect "the close says no resume was spent" "$(grep -c "never sent. No resume was spent" "$ROOT/dc-notsent.txt")" "1"
expect "the ledger is unchanged" "$(jq -S -c . "$IMPL/ledger.json")" "$LEDGER_BEFORE"
rc="$(try "$ROOT/do-again.txt" "$IMPLEMENT" dispatch-open "$TASK" fixer wo1)"
expect "the round opens again: exit 0" "$rc" "0"
expect "the reopened record counts no resume" "$(jq -r '.resumes // 0' "$DISPATCH")" "0"

reset

echo "--- written: a record whose role wrote its report refuses --not-sent and stays open"
must "$IMPLEMENT" dispatch-open "$TASK" fixer wo1
printf 'half done\n' >"$(pinned_report)"
rc="$(try "$ROOT/dc-written.txt" "$IMPLEMENT" dispatch-close "$TASK" --not-sent)"
expect "--not-sent with a report written: exit 3" "$rc" "3"
expect "the refusal names the report" "$(grep -c "answers-wo1-fix1.md exists, and dispatch-open removed it" "$ROOT/dc-written.txt")" "1"
expect "the record stays open" "$([ -f "$DISPATCH" ] && echo open || echo removed)" "open"
rm -f "$(pinned_report)"

reset

echo "--- resumed: a record that counts a resume refuses --not-sent"
must "$IMPLEMENT" dispatch-open "$TASK" fixer wo1
must "$IMPLEMENT" dispatch-close "$TASK" --no-report
rc="$(try "$ROOT/dc-resumed.txt" "$IMPLEMENT" dispatch-close "$TASK" --not-sent)"
expect "--not-sent on a resumed record: exit 3" "$rc" "3"
expect "the refusal names the resume" "$(grep -c "it counts a resume" "$ROOT/dc-resumed.txt")" "1"
expect "the record keeps resume 1" "$(jq -r '.resumes' "$DISPATCH")" "1"

reset

echo "--- reopen: a record reopened with --resume and never sent is withdrawn, and keeps the report"
# The record was closed and the role left a report; --resume keeps that report.
must "$IMPLEMENT" dispatch-open "$TASK" fixer wo1
printf 'half done\n' >"$(pinned_report)"
rm -f "$DISPATCH"
touch -t 200001010000 "$(pinned_report)"
must "$IMPLEMENT" dispatch-open "$TASK" fixer wo1 --resume
rc="$(try "$ROOT/dc-reopen.txt" "$IMPLEMENT" dispatch-close "$TASK" --not-sent)"
expect "--not-sent on a reopened record: exit 0" "$rc" "0"
expect "the record is removed" "$([ -f "$DISPATCH" ] && echo open || echo removed)" "removed"
expect "the earlier report is kept" "$([ -f "$(pinned_report)" ] && echo kept || echo removed)" "kept"
must "$IMPLEMENT" dispatch-open "$TASK" fixer wo1 --resume
expect "the next reopen carries one resume, as before" "$(jq -r 'has("resumedAt")' "$DISPATCH")" "true"
rm -f "$(pinned_report)"

reset

echo "--- finished: a fresh open keeps a finished fixer report that fix-record has not read"
# The live second measurement: the round's report was complete and the next open removed it.
must "$IMPLEMENT" dispatch-open "$TASK" fixer wo1
BRIEF="$IMPL/brief-wo1-fix-1.json"
touch -t 202001010000 "$BRIEF"
printf 'Outcome: f1: fixed\nRan: f1: true\n```\nok\n```\nReport: complete\n' >"$(pinned_report)"
touch -t 202001010001 "$(pinned_report)"
must "$IMPLEMENT" dispatch-close "$TASK"
rc="$(try "$ROOT/do-finished.txt" "$IMPLEMENT" dispatch-open "$TASK" fixer wo1)"
expect "the open refuses: exit 3" "$rc" "3"
expect "the refusal names fix-record" "$(grep -c "Run fix-record on it" "$ROOT/do-finished.txt")" "1"
expect "the report is kept" "$([ -f "$(pinned_report)" ] && echo kept || echo removed)" "kept"
expect "no record opened" "$([ -f "$DISPATCH" ] && echo open || echo none)" "none"
rc="$(fix_brief "$ROOT/out-brief2.txt")"
expect "fix-brief writes the round's brief again: exit 0" "$rc" "0"
rc="$(try "$ROOT/do-newbrief.txt" "$IMPLEMENT" dispatch-open "$TASK" fixer wo1)"
expect "after the new brief the open succeeds: exit 0" "$rc" "0"
expect "the earlier report is removed" "$([ -f "$(pinned_report)" ] && echo kept || echo removed)" "removed"

reset

echo "--- halt: a fixer halted with a complete report is sent to fix-record, not to a fresh dispatch"
must "$IMPLEMENT" dispatch-open "$TASK" fixer wo1
printf 'Outcome: f1: fixed\nRan: f1: true\n```\nok\n```\nReport: complete\n' >"$(pinned_report)"
printf 'half\n' >"$WT/a.php"
rc="$(try "$ROOT/dc-halt1.txt" "$IMPLEMENT" dispatch-close "$TASK")"
expect "the first close with the fix uncommitted: exit 112" "$rc" "112"
rc="$(try "$ROOT/dc-halt2.txt" "$IMPLEMENT" dispatch-close "$TASK")"
expect "the second close is a turn-cap warning: exit 0" "$rc" "0"
expect "the next line names fix-record" "$(grep -c "^next: run fix-record on .*answers-wo1-fix1.md, which is complete" "$ROOT/dc-halt2.txt")" "1"
(cd "$WT" && git add a.php && git commit -qm "the rest of the fix")
rm -f "$(pinned_report)"

reset

echo "--- commit: a commit after the record opened refuses --not-sent"
must "$IMPLEMENT" dispatch-open "$TASK" fixer wo1
commit_at "2031-01-01T00:00:00Z"
rc="$(try "$ROOT/dc-commit.txt" "$IMPLEMENT" dispatch-close "$TASK" --not-sent)"
expect "--not-sent after a commit: exit 3" "$rc" "3"
expect "the refusal names the commit" "$(grep -c "its code path has a commit at 2031-01-01T00:00:00Z" "$ROOT/dc-commit.txt")" "1"
expect "the record stays open" "$([ -f "$DISPATCH" ] && echo open || echo removed)" "open"

reset

echo "--- record: a record order's commit to its owned file in the project folder refuses --not-sent"
# A second task, t2, with one order proved by its record. Setup is copied from run-jc-fixture.sh.
env -u CLAUDE_PLUGIN_ROOT "$SH" "$TASKS" create --project "$PROJECT" --name t2 -- write a report >>"$LOG" 2>&1 \
  || { echo "setup failed: task t2"; exit 1; }
TASK="$PROJECT/tasks/t2"; IMPL="$TASK/implementation"; DISPATCH="$IMPL/dispatch.json"
WT="$(jq -r '.worktree.path' "$TASK/task.json")"
REPORT_FILE="$PROJECT/reports/t2.md"
must "$SCOPE" init "$TASK"
must "$SCOPE" set-goal "$TASK" --goal "write a report" --expected-result "a report"
must "$SCOPE" add "$TASK" --text "the report is written" --verification "read it" --verified-by person
mkdir -p "$TASK/records"
printf '{"schemaVersion":1,"stage":"scope","standsAlone":true,"decisions":["write a report"],"gaps":[]}\n' \
  >"$TASK/records/scope-distill.json"
must "$SCOPE" approve "$TASK"
must "$RESEARCH" start "$TASK"
must "$RESEARCH" record "$TASK" --search prior --searched-for "prior art" --text "none" --source "the tree" --criteria-served c1
must "$RESEARCH" check "$TASK"
must "$DESIGN" start "$TASK"
must "$DESIGN" create "$TASK" --title "write the report" --criteria-served c1 --criteria-owned c1 \
  --reasoning "the brief says so" --diff-budget small --interface none
must "$DESIGN" add-owned-file "$TASK" --id wo1 --path "$REPORT_FILE"
must "$DESIGN" update "$TASK" --id wo1 --proof record
must "$DESIGN" add-done-when "$TASK" --id wo1 --text "the report reads alone"
must "$DESIGN" account "$TASK" --id wo1 --finding prior#1
must "$DESIGN" --run-mode interactive close "$TASK" --no-recipe
must "$IMPLEMENT" start "$TASK"
must "$IMPLEMENT" preconditions "$TASK" --recipe "$TEST_RECIPE_FLAG" --check-recipe "$CHECK_RECIPE_FLAG"
pa "$TASK" "implement tests-freeze" wo1 "wo1=confirmed::person::reads from the document alone"
must "$IMPLEMENT" tests-freeze "$TASK" wo1 --test-recipe "$TEST_RECIPE_FLAG" \
  --row "wo1=confirmed::person::reads from the document alone" --checklist "c1=read it"
must "$IMPLEMENT" build-brief "$TASK" wo1
FROM="$(git -C "$PROJECT" rev-parse HEAD)"
mkdir -p "$PROJECT/reports" && printf 'the report\n' >"$REPORT_FILE"
git -C "$PROJECT" add -- reports/t2.md && git -C "$PROJECT" commit -qm "the report"
must "$IMPLEMENT" build-record "$TASK" wo1 --interface "$ROOT/iface.md" --report "$ROOT/report.md" \
  --started-at "$FROM" --test-recipe "$TEST_RECIPE_FLAG" --check-recipe "$CHECK_RECIPE_FLAG"
printf '{ "findings": [{"id":"f1","severity":"high","file":"%s","lines":"1","linkedTo":"c1","evidence":"the report is thin","fixScope":["%s"]}] }\n' \
  "$REPORT_FILE" "$REPORT_FILE" >"$ROOT/findings-t2.json"
must "$IMPLEMENT" review-record "$TASK" wo1 --findings "$ROOT/findings-t2.json"
must "$IMPLEMENT" fix-brief "$TASK" wo1
must "$IMPLEMENT" dispatch-open "$TASK" fixer wo1
rc="$(try "$ROOT/dc-rec0.txt" "$IMPLEMENT" dispatch-close "$TASK" --not-sent)"
expect "--not-sent on an unsent record order's record: exit 0" "$rc" "0"
must "$IMPLEMENT" dispatch-open "$TASK" fixer wo1
printf 'the report, fuller\n' >"$REPORT_FILE"
git -C "$PROJECT" add -- reports/t2.md
GIT_COMMITTER_DATE="2031-01-01T00:00:00Z" GIT_AUTHOR_DATE="2031-01-01T00:00:00Z" \
  git -C "$PROJECT" commit -qm "the fuller report"
rc="$(try "$ROOT/dc-rec1.txt" "$IMPLEMENT" dispatch-close "$TASK" --not-sent)"
expect "--not-sent after a commit to the owned file in the project folder: exit 3" "$rc" "3"
expect "the refusal names the project folder" \
  "$(grep -c "the order's files in the project folder have a commit at 2031-01-01T00:00:00Z" "$ROOT/dc-rec1.txt")" "1"
expect "the record stays open" "$([ -f "$DISPATCH" ] && echo open || echo removed)" "open"

printf 'passed %s of %s\n' "$PASS" "$TOTAL"
[ "$PASS" -eq "$TOTAL" ]
