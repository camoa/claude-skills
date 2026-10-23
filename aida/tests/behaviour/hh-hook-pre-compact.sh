#!/usr/bin/env bash
# Fixture hh: a save in the same second as a stage write (live-run row 263).
# `task save` stamps savedAt to the whole second, and a file time carries a fraction. So a stage
# file written just before the save, in the same second, must not make hooks/pre-compact.sh
# refuse. A stage file written in a later second still refuses, and a save over no stage file
# still passes. Setup is copied from run-eh-fixture.sh. Runs under bash, which CI runs on Linux, from $HOME,
# with CLAUDE_PLUGIN_ROOT unset.
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
PROJECT="$ROOT/aida/projects/hhfx"
SCOPE="$PLUGIN/skills/scope/scripts/scope-actions.sh"
TASKS="$PLUGIN/skills/task/scripts/task-actions.sh"
HOOK="$PLUGIN/hooks/pre-compact.sh"
LOG="$ROOT/log.txt"

SH=bash; [ -n "${ZSH_VERSION:-}" ] && SH=zsh
in_wt() { wt="$1"; shift; (cd "$wt" && env -u CLAUDE_PLUGIN_ROOT "$SH" "$@") >>"$LOG" 2>&1; }
must() { in_wt "$@" || { printf 'setup failed: %s\n' "$*"; tail -12 "$LOG"; exit 1; }; }
# compact <worktree> <out file>: the PreCompact hook on a manual compaction, from that worktree.
compact() {
  (cd "$1" && printf '{"trigger":"manual","cwd":"%s"}\n' "$1" \
    | env -u CLAUDE_PLUGIN_ROOT "$SH" "$HOOK") >"$2" 2>&1
  printf '%s' "$?"
}
wt_of() { printf '%s/code.worktrees/code-%s' "$ROOT" "$1"; }
# Waits for the clock to cross into the next second. No sleep: the loop asks the clock.
settle() {
  second="$(date -u +%S)"
  while [ "$(date -u +%S)" = "$second" ]; do :; done
}
# mtime_iso <file>: the file's modification time as a UTC stamp in the shape savedAt has.
mtime_iso() {
  epoch="$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null)"
  jq -rn --argjson e "$epoch" '$e | todate'
}

mkdir -p "$CODE" && cd "$CODE" || exit 1
git init -q -b main && git config user.email fx@example.invalid && git config user.name fx
printf 'a\n' >a.php
git add -A && git commit -qm init && git checkout -q -b work
cd "$HOME" || exit 1
env -u CLAUDE_PLUGIN_ROOT bash "$PLUGIN/skills/project/scripts/project-actions.sh" create \
  --name hhfx --path "$CODE" --projects-home "$AIDA_PROJECTS_HOME" --framework fake >>"$LOG" 2>&1 || exit 1

echo "--- a save with no stage file passes, as before"
env -u CLAUDE_PLUGIN_ROOT bash "$TASKS" create --project "$PROJECT" --name h2 -- write one document >>"$LOG" 2>&1 || exit 1
WH2="$(wt_of h2)"
must "$WH2" "$TASKS" start --project "$PROJECT" h2 -- the work starts
must "$WH2" "$TASKS" save --project "$PROJECT" h2
RC="$(compact "$WH2" "$ROOT/out-h2.txt")"
expect "a manual compact exits 0" "$RC" "0"
expect "nothing was said" "$(wc -c <"$ROOT/out-h2.txt" | tr -d ' ')" "0"

echo "--- a stage file written in the second of the save does not refuse"
env -u CLAUDE_PLUGIN_ROOT bash "$TASKS" create --project "$PROJECT" --name h1 -- write one document >>"$LOG" 2>&1 || exit 1
H1="$PROJECT/tasks/h1"; WH1="$(wt_of h1)"
must "$WH1" "$TASKS" start --project "$PROJECT" h1 -- the work starts
must "$WH1" "$SCOPE" init "$H1"
must "$WH1" "$TASKS" save --project "$PROJECT" h1
# The stage file is set half a second into savedAt's second, the live shape. Timing alone let the
# save cross a second under load. A whole second would not do: that file was never newer.
# GNU and BSD touch -d both take this ISO form with a fraction.
touch -d "$(jq -r '.savedAt | rtrimstr("Z")' "$H1/task.json").5Z" "$H1/alignment.json"
expect "the stage file and savedAt share one second" \
  "$(mtime_iso "$H1/alignment.json")" "$(jq -r '.savedAt' "$H1/task.json")"
RC="$(compact "$WH1" "$ROOT/out-h1a.txt")"
expect "a manual compact exits 0" "$RC" "0"
expect "nothing was said" "$(wc -c <"$ROOT/out-h1a.txt" | tr -d ' ')" "0"

echo "--- a stage file written in a later second still refuses"
settle
must "$WH1" "$SCOPE" set-goal "$H1" --goal "do the work" --expected-result "work done"
RC="$(compact "$WH1" "$ROOT/out-h1b.txt")"
expect "a manual compact exits 2" "$RC" "2"
expect "the refusal names the save" \
  "$(grep -c -F -e "run \`/aida:task save h1\` before compacting" "$ROOT/out-h1b.txt")" "1"

printf 'passed %s of %s\n' "$PASS" "$TOTAL"
[ "$PASS" -eq "$TOTAL" ]
