#!/usr/bin/env bash
# Fixture mk: review never runs a mutation command that takes no changed-file path
# (gap row 400, periplus item 51). Such a command runs over the tool's own default scope on every
# review: `mutmut run` on ci-js-extra mutated the whole package, 17,693 mutants, three hours for
# 7,853 before the owner stopped it. One task changes the four files ci-js-extra changed. Review
# runs again per row, each time with a different mutation row. The rows:
#   replay  the python-cli catalog row verbatim, `["mutmut", "run"]` (python_cli_test_execution
#           0.2.3, dev-guides-store blob 3e5ebc45, copied 2026-10-22), with a stub mutmut on PATH:
#           the stub never runs, the row reads undeclared, the detail names the recipe and the
#           command, a catalog note names the recipe, and check 4 still reads met. Before the fix,
#           the stub ran and the row read met.
#   scoped  the same stub with a {paths} placeholder still runs over the changed files and reads met.
# Runs under bash, which CI runs on Linux, from $HOME, with CLAUDE_PLUGIN_ROOT unset. Setup is copied from
# run-md-fixture.sh.
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
PROJECT="$ROOT/aida/projects/mkfx"
TASK="$PROJECT/tasks/t1"
WT="$ROOT/code.worktrees/code-t1"
SCOPE="$PLUGIN/skills/scope/scripts/scope-actions.sh"
RESEARCH="$PLUGIN/skills/research/scripts/research-actions.sh"
DESIGN="$PLUGIN/skills/design/scripts/design-actions.sh"
IMPLEMENT="$PLUGIN/skills/implement/scripts/implement-actions.sh"
REVIEW="$PLUGIN/skills/review/scripts/review-actions.sh"
PLAYBOOKS="$PLUGIN/skills/playbooks/scripts/playbook-actions.sh"
TASKS="$PLUGIN/skills/task/scripts/task-actions.sh"
PROJECTS="$PLUGIN/skills/project/scripts/project-actions.sh"
LOG="$ROOT/log.txt"
FW=python-cli
CHECK_RECIPE_FLAG="$FW=$ROOT/recipes/checks.md"
# The four files ci-js-extra changed, from its review/diff.patch.
LIVE_FILES=(.github/workflows/checks.yml README.md pyproject.toml tests/test_ci_extras.py)
MARK="$ROOT/mutmut-ran"

SH=bash; [ -n "${ZSH_VERSION:-}" ] && SH=zsh
in_wt() { local wt="$1"; shift; (cd "$wt" && env -u CLAUDE_PLUGIN_ROOT "$SH" "$@") >>"$LOG" 2>&1; }
must() { in_wt "$@" || { printf 'setup failed: %s\n' "$*"; tail -8 "$LOG"; exit 1; }; }
# run_to <wt> <out> <err> <args...>: runs one step with the stub first on PATH; prints the exit code.
run_to() {
  local wt="$1" out="$2" err="$3"; shift 3
  (cd "$wt" && PATH="$ROOT/bin:$PATH" env -u CLAUDE_PLUGIN_ROOT "$SH" "$@") >"$out" 2>"$err"
  printf '%s' "$?"
}

make_code_repo() {
  local f
  mkdir -p "$CODE" && cd "$CODE" || exit 1
  git init -q -b main && git config user.email fx@example.invalid && git config user.name fx
  for f in "${LIVE_FILES[@]}"; do mkdir -p "$(dirname "$f")"; printf 'a\n' >"$f"; done
  git add -A && git commit -qm init && git checkout -q -b work
  cd "$HOME" || exit 1
}

# write_test_recipe <file> <mutation argv>: the test-execution recipe, its mutation row as given.
write_test_recipe() {
  mkdir -p "$(dirname "$1")"
  cat >"$1" <<EOF
---
name: python_cli_test_execution
capability: test-execution
recipe_class: process
framework: $FW
---

## Preconditions

\`\`\`yaml
preconditions: []
\`\`\`

## Test commands

\`\`\`yaml
test_commands:
  - id: suite
    argv: ["true"]
    cost: end-of-task
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
    argv: $2
    cost: end-of-task
\`\`\`

\`\`\`yaml
failure_signal:
  assertion: >-
    Exit 1.
\`\`\`
EOF
}

write_check_recipe() {
  mkdir -p "$ROOT/recipes"
  cat >"$ROOT/recipes/checks.md" <<EOF
---
name: python_cli_review_checks
capability: review
recipe_class: process
framework: $FW
---

## Check commands

\`\`\`yaml
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
\`\`\`
EOF
}

# review_with <row>: runs review checks with the recipe written for that row; prints the exit code.
review_with() {
  rm -f "$MARK"
  run_to "$WT" "$ROOT/rv-$1.out" "$ROOT/rv-$1.err" "$REVIEW" checks "$TASK" \
    --recipe "$FW=$ROOT/recipes/$1/test-execution.md" --check-recipe "$CHECK_RECIPE_FLAG"
}
# mut <jq filter>: one value of the mutation object in the review record.
mut() { jq -r ".mutation | $1" "$TASK/review/review.json" 2>/dev/null; }
ran() { if [ -e "$MARK" ]; then printf 'ran'; else printf 'not-run'; fi; }

# The stub mutmut: marks that it ran and prints the shape of mutmut 3.8.0's last line.
mkdir -p "$ROOT/bin"
printf '#!/bin/sh\n: >"%s"\nprintf "1/1  \\360\\237\\216\\211 1 \\360\\237\\231\\201 0\\n"\nexit 0\n' "$MARK" >"$ROOT/bin/mutmut"
chmod +x "$ROOT/bin/mutmut"

printf 'none\n' >"$ROOT/iface.md"; printf 'report\nStop: none\nDeviation: none\n' >"$ROOT/report.md"
printf '{ "findings": [] }\n' >"$ROOT/findings.json"
make_code_repo
env -u CLAUDE_PLUGIN_ROOT bash "$PROJECTS" create \
  --name mkfx --path "$CODE" --projects-home "$AIDA_PROJECTS_HOME" --framework "$FW" >>"$LOG" 2>&1 || exit 1
write_check_recipe
write_test_recipe "$ROOT/recipes/replay/test-execution.md" '["mutmut", "run"]'
write_test_recipe "$ROOT/recipes/scoped/test-execution.md" '["mutmut", "run", "{paths}"]'

# Scope, research and design: one order owning the four files, then start and preconditions.
env -u CLAUDE_PLUGIN_ROOT bash "$TASKS" create --project "$PROJECT" --name t1 -- add the js extra to ci >>"$LOG" 2>&1 || exit 1
must "$WT" "$SCOPE" init "$TASK"
must "$WT" "$SCOPE" set-goal "$TASK" --goal "add the js extra to ci" --expected-result "ci runs the js extra"
must "$WT" "$SCOPE" add "$TASK" --text "ci names the js extra" --verification "tests/test_ci_extras.py" --verified-by machine
mkdir -p "$TASK/records"
printf '{"schemaVersion":1,"stage":"scope","standsAlone":true,"decisions":["add the js extra"],"gaps":[]}\n' \
  >"$TASK/records/scope-distill.json"
must "$WT" "$SCOPE" approve "$TASK"
must "$WT" "$RESEARCH" start "$TASK"
must "$WT" "$RESEARCH" record "$TASK" --search prior --searched-for "prior art" \
  --text "the framework guide says to write it down" --source "guides/writing.md" --criteria-served c1
must "$WT" "$RESEARCH" check "$TASK"
must "$WT" "$PLAYBOOKS" load "$TASK"
must "$WT" "$DESIGN" start "$TASK"
must "$WT" "$DESIGN" create "$TASK" --title "add the js extra to ci" --criteria-served c1 --criteria-owned c1 \
  --reasoning "the brief says so" --diff-budget small --interface none
for f in "${LIVE_FILES[@]}"; do
  must "$WT" "$DESIGN" add-owned-file "$TASK" --id wo1 --path "$f"
done
must "$WT" "$DESIGN" add-done-when "$TASK" --id wo1 --text "ci names the js extra"
must "$WT" "$DESIGN" add-test "$TASK" --id wo1 --level unit --description "test_ci_extras checks the workflow"
must "$WT" "$DESIGN" account "$TASK" --id wo1 --finding prior#1
must "$WT" "$DESIGN" --run-mode interactive close "$TASK" --no-recipe
must "$WT" "$IMPLEMENT" start "$TASK"
must "$WT" "$IMPLEMENT" preconditions "$TASK" \
  --recipe "$FW=$ROOT/recipes/scoped/test-execution.md" --check-recipe "$CHECK_RECIPE_FLAG"

# Build: freeze the test, change the other three files, record, review and close wo1, finish.
mkdir -p "$WT/tests"
printf 'grep -q done .github/workflows/checks.yml || exit 1\n' >"$WT/tests/test_ci_extras.py"
must "$WT" "$IMPLEMENT" tests-freeze "$TASK" wo1 --test-recipe "$FW=$ROOT/recipes/scoped/test-execution.md" \
  --test-glob 'tests/test_*.py' --test "tests/test_ci_extras.py::checks_c1=c1" \
  --locks-in "checks_c1=tests/test_ci_extras.py names the workflow" --row "c1=confirmed::model::ok"
FREEZE="$(git -C "$WT" rev-parse HEAD)"
for f in .github/workflows/checks.yml README.md pyproject.toml; do printf 'done\n' >"$WT/$f"; done
git -C "$WT" add -A && git -C "$WT" commit -qm "wo1 attempt" >/dev/null 2>&1
must "$WT" "$IMPLEMENT" build-record "$TASK" wo1 \
  --interface "$ROOT/iface.md" --report "$ROOT/report.md" --started-at "$FREEZE" \
  --test-recipe "$FW=$ROOT/recipes/scoped/test-execution.md" --check-recipe "$CHECK_RECIPE_FLAG"
must "$WT" "$IMPLEMENT" review-record "$TASK" wo1 --findings "$ROOT/findings.json"
must "$WT" "$IMPLEMENT" close "$TASK" wo1
must "$WT" "$IMPLEMENT" finish "$TASK"

echo "--- replay: the catalog's python-cli mutation row, which takes no path"
RC="$(review_with replay)"
expect "checks exits 0, the stub never ran, the row reads undeclared" "$RC $(ran) $(mut .verdict)" "0 not-run undeclared"
expect "the detail names the recipe and the command, and asks for a scoped form" \
  "$(mut .detail | grep -c 'the mutation command of the test-execution recipe for python-cli, `mutmut run`, takes no changed-file path, so it would run over the tool.s whole default scope and was not run. The row needs a scoped form.')" "1"
expect "a catalog note names the recipe" \
  "$(jq -r '[ (.catalogNotes // [])[] | select((.seen | contains("takes no changed-file path")) and .where == "the test-execution recipe for python-cli") ] | length' "$TASK/review/review.json")" "1"
expect "check 4 still reads met, so the review does not block on the recipe" \
  "$(jq -r '.checks[] | select(.id == "test-and-mutation") | .verdict' "$TASK/review/review.json")" "met"

echo "--- scoped: the same tool with a path placeholder still runs"
RC="$(review_with scoped)"
expect "checks exits 0, the stub ran, the row reads met" "$RC $(ran) $(mut .verdict)" "0 ran met"

printf 'passed %s of %s\n' "$PASS" "$TOTAL"
[ "$PASS" -eq "$TOTAL" ]
