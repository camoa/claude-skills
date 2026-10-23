#!/usr/bin/env bash
# Fixture dt: the contract page is rendered on every write (live-run rows 121,
# 130 and 132). Builds a project and one task, scoped through the plugin's own scope actions on
# the setup of run-cu-fixture.sh. Rows: approve rewrites alignment.md so the criterion lines read
# owner; set-goal rewrites it; update rewrites it; add and add-non-goal give the page a line;
# remove takes one away; each prints rendered:; render still works alone. Runs under bash 3.2 and zsh, from $HOME, with CLAUDE_PLUGIN_ROOT unset, and calls the
# plugin scripts under the shell this runner runs under.
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
PROJECT="$ROOT/aida/projects/dtfx"
TASK="$PROJECT/tasks/t1"
PAGE="$TASK/alignment.md"
SCOPE="$PLUGIN/skills/scope/scripts/scope-actions.sh"
LOG="$ROOT/log.txt"
WT=""

# Every stage action runs from the task's worktree (exit 79 otherwise), under the shell this
# runner runs under, so the zsh run proves the plugin script under zsh. Output goes to the log.
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
  printf 'a\n' >a.php
  git add -A && git commit -qm init && git checkout -q -b work
  cd "$HOME" || exit 1
}

make_project() {
  env -u CLAUDE_PLUGIN_ROOT "$SH" "$PLUGIN/skills/project/scripts/project-actions.sh" create \
    --name dtfx --path "$CODE" --projects-home "$AIDA_PROJECTS_HOME" --framework fake >>"$LOG" 2>&1 || exit 1
}

make_task() {
  env -u CLAUDE_PLUGIN_ROOT "$SH" "$PLUGIN/skills/task/scripts/task-actions.sh" create \
    --project "$PROJECT" --name t1 -- change some files >>"$LOG" 2>&1 || exit 1
  WT="$(jq -r '.worktree.path' "$TASK/task.json")"
  [ -d "$WT" ] || { printf 'setup failed: no worktree for t1\n'; exit 1; }
}

# Two designer criteria and one render, the way the draft is first shown. The distill sidecar is
# an agent's record, so the fixture writes it.
draft_contract() {
  must "$SCOPE" init "$TASK"
  must "$SCOPE" set-goal "$TASK" --goal "change files" --expected-result "files changed"
  must "$SCOPE" add "$TASK" --text "a.php changes" --verification "look" --verified-by person
  must "$SCOPE" add "$TASK" --text "a.php is logged" --verification "look" --verified-by person
  must "$SCOPE" render "$TASK"
  mkdir -p "$TASK/records"
  printf '{"schemaVersion":1,"stage":"scope","standsAlone":true,"decisions":["change files"],"gaps":[]}\n' \
    >"$TASK/records/scope-distill.json"
}

# line <file> <key>: the summary line for one key.
line() { grep "^$2:" "$1" | head -1; }
# designer_lines and owner_lines: how many criterion lines on the page say each author.
designer_lines() { grep -c 'Asked for by designer' "$PAGE"; }
owner_lines() { grep -c 'Asked for by owner' "$PAGE"; }

make_code_repo
make_project
make_task
draft_contract

echo "--- the draft's page reads designer on both criteria"
expect "two designer lines" "$(designer_lines)" "2"
expect "no owner line" "$(owner_lines)" "0"

echo "--- approve rewrites the page: the criterion lines read owner after"
rc="$(try "$ROOT/approve.txt" "$SCOPE" approve "$TASK")"
expect "approve exits 0" "$rc" "0"
expect "approve promoted both" "$(line "$ROOT/approve.txt" promoted)" "promoted: 2"
expect "approve prints rendered:" "$(line "$ROOT/approve.txt" rendered)" "rendered: $PAGE"
expect "rendered: comes before standsAlone:" \
  "$(grep -n -E '^(rendered|standsAlone):' "$ROOT/approve.txt" | cut -d: -f2 | tr '\n' ' ')" "rendered standsAlone "
expect "no designer line on the page" "$(designer_lines)" "0"
expect "two owner lines on the page" "$(owner_lines)" "2"
expect "the committed page reads owner" \
  "$(git -C "$PROJECT" show HEAD:tasks/t1/alignment.md | grep -c 'Asked for by owner')" "2"

echo "--- set-goal rewrites the page"
rc="$(try "$ROOT/set-goal.txt" "$SCOPE" set-goal "$TASK" --goal "change files and say so" --expected-result "files changed")"
expect "set-goal exits 0" "$rc" "0"
expect "set-goal prints rendered:" "$(line "$ROOT/set-goal.txt" rendered)" "rendered: $PAGE"
expect "the page carries the new goal" "$(grep -c '^change files and say so$' "$PAGE")" "1"
expect "the page no longer carries the old goal alone" "$(grep -c '^change files$' "$PAGE")" "0"

echo "--- update rewrites the page"
rc="$(try "$ROOT/update.txt" "$SCOPE" update "$TASK" --id c2 --text "a.php is logged twice")"
expect "update exits 0" "$rc" "0"
expect "update prints rendered:" "$(line "$ROOT/update.txt" rendered)" "rendered: $PAGE"
expect "the page carries the new criterion text" "$(grep -c 'a.php is logged twice' "$PAGE")" "1"
expect "the page still reads owner on both" "$(owner_lines)" "2"

echo "--- add rewrites the page: the page gains the criterion"
rc="$(try "$ROOT/add.txt" "$SCOPE" add "$TASK" --text "a.php is tested" --verification "look" --verified-by person)"
expect "add exits 0" "$rc" "0"
expect "add prints rendered:" "$(line "$ROOT/add.txt" rendered)" "rendered: $PAGE"
expect "the page carries the new criterion" "$(grep -c 'a.php is tested' "$PAGE")" "1"
expect "the page reads designer on the new one" "$(designer_lines)" "1"

echo "--- add-non-goal rewrites the page: the page gains the non-goal"
rc="$(try "$ROOT/add-non-goal.txt" "$SCOPE" add-non-goal "$TASK" --text "no deploy")"
expect "add-non-goal exits 0" "$rc" "0"
expect "add-non-goal prints rendered:" "$(line "$ROOT/add-non-goal.txt" rendered)" "rendered: $PAGE"
expect "the page carries the non-goal" "$(grep -c '^- no deploy (`n1`)$' "$PAGE")" "1"

echo "--- remove rewrites the page: the page loses the criterion"
rc="$(try "$ROOT/remove.txt" "$SCOPE" remove "$TASK" --id c1)"
expect "remove exits 0" "$rc" "0"
expect "remove prints rendered:" "$(line "$ROOT/remove.txt" rendered)" "rendered: $PAGE"
expect "the page no longer lists c1" "$(grep -c '(`c1`)' "$PAGE")" "0"
expect "the page no longer carries c1's text" "$(grep -c 'a.php changes$' "$PAGE")" "0"
expect "the page still lists c2 and c3" "$(grep -c '(`c[23]`)' "$PAGE")" "2"

echo "--- render still works alone"
rm -f "$PAGE"
rc="$(try "$ROOT/render.txt" "$SCOPE" render "$TASK")"
expect "render exits 0" "$rc" "0"
expect "render prints rendered:" "$(line "$ROOT/render.txt" rendered)" "rendered: $PAGE"
expect "render prints nothing else" "$(wc -l <"$ROOT/render.txt" | tr -d ' ')" "1"
expect "the page is back with the current text" "$(grep -c 'a.php is logged twice' "$PAGE")" "1"
rc="$(try "$ROOT/render-arg.txt" "$SCOPE" render "$TASK" extra)"
expect "render refuses an argument with exit 3" "$rc" "3"

printf 'passed %s of %s\n' "$PASS" "$TOTAL"
[ "$PASS" -eq "$TOTAL" ]
