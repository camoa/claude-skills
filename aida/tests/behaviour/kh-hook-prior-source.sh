#!/usr/bin/env bash
# Fixture kh: a build brief names each path its text names and the dispatch
# denies, and a record an order depends on is not denied (gap row 344, periplus gap 35). Before
# this build, a brief whose reasoning said "Read deliverables/probe-record.md (wo1) first" carried
# that line, dispatch-open denied the file, and neither said so. Four orders: wo1 owns a
# task-folder record and a probe output; wo2 owns code and depends on wo1; wo3 owns a code folder
# and a file named config and depends on wo2 alone; wo4 owns a second task-folder record and
# depends on wo3. The rows:
#   none     wo1's brief names no path another order owns, so it has no deniedReads key.
#   brief    wo2's reasoning names wo1's record, wo4's record, a file under wo3's folder and the
#            word configuration: deniedReads holds wo4's record and the folder only, and the
#            summary's next asks a person to rule before the dispatch.
#   deny     dispatch-open implementer wo2 denies wo3's and wo4's paths, not wo1's two records;
#            the read hook refuses wo4's record and wo3's folder, and allows wo1's record.
#   chain    wo3 depends on wo1 through wo2: its brief names wo1's record and has no deniedReads,
#            next says dispatch, and its dispatch denies wo2's code and wo4's record, not wo1's.
# Runs under bash, which CI runs on Linux, from $HOME, with CLAUDE_PLUGIN_ROOT unset. Setup is copied from
# run-kq-fixture.sh.
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
PROJECT="$ROOT/aida/projects/khfx"
RECIPES="$ROOT/recipes"
TEST_RECIPE_FLAG="fake=$RECIPES/test-execution.md"
CHECK_FLAG="fake=$RECIPES/checks.md"
TASKS="$PLUGIN/skills/task/scripts/task-actions.sh"
SCOPE="$PLUGIN/skills/scope/scripts/scope-actions.sh"
RESEARCH="$PLUGIN/skills/research/scripts/research-actions.sh"
DESIGN="$PLUGIN/skills/design/scripts/design-actions.sh"
IMPLEMENT="$PLUGIN/skills/implement/scripts/implement-actions.sh"
READ_HOOK="$PLUGIN/hooks/deny-prior-source.sh"
LOG="$ROOT/log.txt"
OUT="$ROOT/out.txt"

SH=bash; [ -n "${ZSH_VERSION:-}" ] && SH=zsh
in_wt() { (cd "$WT" && env -u CLAUDE_PLUGIN_ROOT "$SH" "$@") >>"$LOG" 2>&1; }
# A setup step that fails ends the run, with the count so far.
must() {
  in_wt "$@" || { printf 'setup failed: %s\n' "$*"; tail -5 "$LOG"; printf 'passed %s of %s\n' "$PASS" "$TOTAL"; exit 1; }
}

mkdir -p "$CODE" && cd "$CODE" || exit 1
git init -q -b main && git config user.email fx@example.invalid && git config user.name fx
printf 'base\n' >README
git add -A && git commit -qm init && git checkout -q -b work
cd "$HOME" || exit 1

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
{
  printf -- '---\nname: fake_review_checks\ncapability: review\nrecipe_class: process\nframework: fake\n---\n\n'
  printf '## Check commands\n\n```yaml\ncheck_commands:\n'
  for id in coding-standards static-analysis security; do printf '  - id: %s\n    absent: >-\n      None.\n' "$id"; done
  printf '```\n'
} >"$RECIPES/checks.md"

env -u CLAUDE_PLUGIN_ROOT "$SH" "$PLUGIN/skills/project/scripts/project-actions.sh" create \
  --name khfx --path "$CODE" --projects-home "$AIDA_PROJECTS_HOME" --framework fake >>"$LOG" 2>&1 || exit 1
env -u CLAUDE_PLUGIN_ROOT "$SH" "$TASKS" create --project "$PROJECT" --name t1 -- probe and rules >>"$LOG" 2>&1 || exit 1
TASK="$PROJECT/tasks/t1"
IMPL="$TASK/implementation"
WT="$(jq -r '.worktree.path' "$TASK/task.json")"
[ -d "$WT" ] || { printf 'setup failed: no worktree\n'; exit 1; }
pa "$PROJECT/tasks/t1" "task set-run-mode" "" "light"
env -u CLAUDE_PLUGIN_ROOT "$SH" "$TASKS" set-run-mode --project "$PROJECT" t1 light >>"$LOG" 2>&1 || exit 1
RECORD="$TASK/deliverables/probe-record.md"
SCRIPT="$TASK/deliverables/probe/counts.txt"
EVIDENCE="$TASK/deliverables/site-evidence.md"

must "$SCOPE" init "$TASK"
must "$SCOPE" set-goal "$TASK" --goal "ship" --expected-result "the probe and the rules"
for c in probe rules engine evidence; do
  must "$SCOPE" add "$TASK" --text "the $c is there" --verification "the $c is there" --verified-by machine
done
mkdir -p "$TASK/records"
printf '{"schemaVersion":1,"stage":"scope","standsAlone":true,"decisions":["ship"],"gaps":[]}\n' \
  >"$TASK/records/scope-distill.json"
must "$SCOPE" approve "$TASK"
must "$RESEARCH" start "$TASK"
must "$RESEARCH" record "$TASK" --search prior --searched-for "prior art" --text "none" \
  --source "the tree" --criteria-served c1,c2,c3,c4
[ -f "$TASK/records/test-runner.json" ] || { mkdir -p "$TASK/records" && printf '{"verdict":"unmet"}\n' >"$TASK/records/test-runner.json"; } # gap row 366
must "$RESEARCH" check "$TASK"
must "$DESIGN" start "$TASK"
# order <id> <criterion> <depends on, or ""> <reasoning> <owned file>...: one order, fully drawn.
order() {
  local id="$1" c="$2" dep="$3" why="$4" f
  shift 4
  if [ -n "$dep" ]; then
    must "$DESIGN" create "$TASK" --title "$id" --criteria-served "$c" --criteria-owned "$c" --depends-on "$dep" \
      --reasoning "$why" --diff-budget small --interface none
  else
    must "$DESIGN" create "$TASK" --title "$id" --criteria-served "$c" --criteria-owned "$c" \
      --reasoning "$why" --diff-budget small --interface none
  fi
  for f in "$@"; do must "$DESIGN" add-owned-file "$TASK" --id "$id" --path "$f"; done
  must "$DESIGN" add-done-when "$TASK" --id "$id" --text "the $id files are there"
  must "$DESIGN" account "$TASK" --id "$id" --finding prior#1
}
order wo1 c1 "" "the brief says so" "$RECORD" "$SCRIPT"
order wo2 c2 wo1 "Read deliverables/probe-record.md (wo1) first: its counts say which sources matter. Call src/engine/run.sh from src/rules.sh. Do not edit deliverables/site-evidence.md. The configuration stays as it is." \
  src/rules.sh docs/guide.md
order wo3 c3 wo2 "Read deliverables/probe-record.md first." src/engine config
order wo4 c4 wo3 "the brief says so" "$EVIDENCE"
must "$DESIGN" check "$TASK"
must "$DESIGN" --run-mode autonomous close "$TASK" --no-recipe
must "$IMPLEMENT" start "$TASK"
must "$IMPLEMENT" preconditions "$TASK" --recipe "$TEST_RECIPE_FLAG" --check-recipe "$CHECK_FLAG"
printf 'none\n' >"$ROOT/iface.md"; printf 'report\nStop: none\nDeviation: none\n' >"$ROOT/report.md"
printf '{ "findings": [] }\n' >"$ROOT/rv-none.json"
# hook_on <path>: the read hook's answer to the open implementer's Read of the path.
hook_on() {
  jq -nc --arg c "$WT" --arg f "$1" \
    '{tool_name: "Read", agent_type: "aida:implementer", cwd: $c, tool_input: {file_path: $f}}' \
    | env -u CLAUDE_PLUGIN_ROOT "$SH" "$READ_HOOK" 2>>"$LOG" | jq -r '.hookSpecificOutput.permissionDecision // "allow"'
}
RULE="a person rules first: the order text names a path in deniedReads, which its dispatch denies."

echo "--- none: wo1's brief names no path another order owns"
must "$IMPLEMENT" dispatch-open "$TASK" row-checker wo1 --test-glob 'tests/*'
printf '{"rows":[{"criterion":"wo1:1","verdict":"confirmed","note":"checked wo1:1"}]}\n' >"$IMPL/row-check-wo1.json"
must "$IMPLEMENT" dispatch-close "$TASK"
must "$IMPLEMENT" tests-freeze "$TASK" wo1 --test-recipe "$TEST_RECIPE_FLAG" \
  --row "wo1=confirmed::model::reads from the record alone" --checklist "c1=read it"
freeze="$(git -C "$PROJECT" rev-parse HEAD)"
must "$IMPLEMENT" build-brief "$TASK" wo1
expect "wo1's brief has no deniedReads" "$(jq 'has("deniedReads")' "$IMPL/brief-wo1-build.json")" "false"
mkdir -p "$TASK/deliverables/probe"
printf 'counts\n' >"$RECORD"; printf 'x\n' >"$SCRIPT"
git -C "$PROJECT" add -- "$RECORD" "$SCRIPT" && git -C "$PROJECT" commit -qm "wo1 attempt"
must "$IMPLEMENT" build-record "$TASK" wo1 --interface "$ROOT/iface.md" --report "$ROOT/report.md" \
  --started-at "$freeze" --test-recipe "$TEST_RECIPE_FLAG" --check-recipe "$CHECK_FLAG"
must "$IMPLEMENT" review-record "$TASK" wo1 --findings "$ROOT/rv-none.json"
must "$IMPLEMENT" close "$TASK" wo1

echo "--- brief: wo2's brief lists the denied paths its reasoning names"
must "$IMPLEMENT" tests-freeze "$TASK" wo2 --test-recipe "$TEST_RECIPE_FLAG"
(cd "$WT" && env -u CLAUDE_PLUGIN_ROOT "$SH" "$IMPLEMENT" build-brief "$TASK" wo2) >"$OUT" 2>&1
expect "build-brief wo2 passes" "$?" "0"
expect "deniedReads holds wo4's record and the folder" \
  "$(jq -c '.deniedReads' "$IMPL/brief-wo2-build.json")" "$(jq -nc --arg e "$EVIDENCE" '[$e, "src/engine"]')"
expect "the reasoning still carries the read" \
  "$(jq -r '.unit.reasoning' "$IMPL/brief-wo2-build.json" | grep -c 'Read deliverables/probe-record.md')" "1"
expect "the summary names both" \
  "$(grep -cxF "deniedReads: $EVIDENCE, src/engine" "$OUT")" "1"
expect "next asks a person to rule first" "$(grep -cF "next: $RULE" "$OUT")" "1"
expect "next names the design route" \
  "$(grep -c 'To change it, design update on wo2, close design, start, then restart$' "$OUT")" "1"

echo "--- deny: wo1's records are readable to wo2, the rest stays denied"
(cd "$WT" && env -u CLAUDE_PLUGIN_ROOT "$SH" "$IMPLEMENT" dispatch-open "$TASK" implementer wo2) >"$OUT" 2>&1
expect "dispatch-open implementer wo2 passes" "$?" "0"
expect "denyRead holds wo3's and wo4's paths" "$(jq -c '.denyRead | sort' "$IMPL/dispatch.json")" \
  "$(jq -nc --arg e "$EVIDENCE" '[$e, "config", "src/engine"] | sort')"
expect "the read hook refuses wo4's record" "$(hook_on "$EVIDENCE")" "deny"
expect "the read hook refuses wo3's folder" "$(hook_on "$WT/src/engine/run.sh")" "deny"
expect "the read hook allows wo1's record" "$(hook_on "$RECORD")" "allow"
must "$IMPLEMENT" dispatch-close "$TASK" --not-sent

echo "--- chain: wo3 reads wo1's record through wo2"
freeze="$(git -C "$WT" rev-parse HEAD)"
(cd "$WT" && mkdir -p src docs && printf 'x\n' >src/rules.sh && printf 'x\n' >docs/guide.md \
  && git add src/rules.sh docs/guide.md && git commit -qm "wo2 attempt" >/dev/null 2>&1)
must "$IMPLEMENT" build-record "$TASK" wo2 --interface "$ROOT/iface.md" --report "$ROOT/report.md" \
  --started-at "$freeze" --test-recipe "$TEST_RECIPE_FLAG" --check-recipe "$CHECK_FLAG"
must "$IMPLEMENT" review-record "$TASK" wo2 --findings "$ROOT/rv-none.json"
must "$IMPLEMENT" close "$TASK" wo2
must "$IMPLEMENT" tests-freeze "$TASK" wo3 --test-recipe "$TEST_RECIPE_FLAG"
(cd "$WT" && env -u CLAUDE_PLUGIN_ROOT "$SH" "$IMPLEMENT" build-brief "$TASK" wo3) >"$OUT" 2>&1
expect "build-brief wo3 passes" "$?" "0"
expect "wo3's brief has no deniedReads" "$(jq 'has("deniedReads")' "$IMPL/brief-wo3-build.json")" "false"
expect "next says dispatch" "$(grep -c '^next: dispatch implementer' "$OUT")" "1"
(cd "$WT" && env -u CLAUDE_PLUGIN_ROOT "$SH" "$IMPLEMENT" dispatch-open "$TASK" implementer wo3) >"$OUT" 2>&1
expect "dispatch-open implementer wo3 passes" "$?" "0"
expect "denyRead holds wo2's code and wo4's record" "$(jq -c '.denyRead | sort' "$IMPL/dispatch.json")" \
  "$(jq -nc --arg e "$EVIDENCE" '[$e, "docs/guide.md", "src/rules.sh"] | sort')"

printf 'passed %s of %s\n' "$PASS" "$TOTAL"
[ "$PASS" -eq "$TOTAL" ]
