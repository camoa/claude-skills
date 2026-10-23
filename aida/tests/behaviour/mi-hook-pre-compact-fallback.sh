#!/usr/bin/env bash
# Fixture mi: a session that works no task is refused compaction for a task another
# session builds (gap row 398). hooks/pre-compact.sh took the project's only task in progress when no
# task tree held cwd. The AIDA developer's session ran from a docs folder the project owns while an
# autonomous session built aida-multi-client, and /compact was refused twice. hooks/session-start.sh
# told the same session "Task in progress: aida-multi-client ... Run mode: autonomous".
# The tie is the session's own transcript: that task is this session's when a tool call the
# session made since its last compaction names the task folder. The rows, on a task this fixture
# builds in the implementation stage:
#   other    its call named the folder before its last compaction only: compact passes, an
#            auto compact leaves no marker, session start lists the task without its run mode.
#   output   the folder only in /aida:next output, in the session-start Notes line, or as the
#            start of another task's folder: compact passes, session start lists the task.
#   own      its call names the folder after its last compaction: compact still refuses,
#            session start names the task, its run mode, and the marker, and removes the marker.
#   tree     cwd in the task's tree: compact refuses whatever the transcript says.
#   no path  a payload with no transcript_path: compact refuses and session start names the task.
#   no file  a transcript_path with no file yet: a session with no history works no task.
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
yes_no() { if "$@"; then printf yes; else printf no; fi; }
saw() { if grep -qF -- "$2" "$1"; then printf yes; else printf no; fi; }

ROOT="$(mktemp -d)" || exit 1
trap 'rm -rf "$ROOT"' EXIT
ROOT="$(cd "$ROOT" && pwd -P)"
export AIDA_REGISTRY_PATH="$ROOT/aida/registry.json"
export AIDA_PROJECTS_HOME="$ROOT/aida/projects"
export AIDA_SETTINGS_PATH="$ROOT/aida/settings.json"
CODE="$ROOT/code"
DOCS="$ROOT/docs"
PROJECT="$ROOT/aida/projects/mifx"
TASK="$PROJECT/tasks/aida-multi-client"
WT="$ROOT/code.worktrees/code-aida-multi-client"
TASKS="$PLUGIN/skills/task/scripts/task-actions.sh"
LOG="$ROOT/log.txt"

SH=bash; [ -n "${ZSH_VERSION:-}" ] && SH=zsh
# compact <trigger> <dir> <payload extra> <out>: the PreCompact hook, from that directory.
compact() {
  (cd "$2" && printf '{"trigger":"%s","cwd":"%s"%s}\n' "$1" "$2" "$3" \
    | env -u CLAUDE_PLUGIN_ROOT "$SH" "$PLUGIN/hooks/pre-compact.sh") >"$4" 2>&1
  printf '%s' "$?"
}
# start <dir> <payload or empty> <out>: the SessionStart hook after a compaction, from that directory.
start() {
  if [ -n "$2" ]; then
    (cd "$1" && printf '%s\n' "$2" | env -u CLAUDE_PLUGIN_ROOT "$SH" "$PLUGIN/hooks/session-start.sh") >"$3" 2>&1
  else
    (cd "$1" && env -u CLAUDE_PLUGIN_ROOT "$SH" "$PLUGIN/hooks/session-start.sh" </dev/null) >"$3" 2>&1
  fi
}

mkdir -p "$CODE" "$DOCS" && cd "$CODE" || exit 1
git init -q -b main && git config user.email fx@example.invalid && git config user.name fx
printf 'a\n' >a.txt
git add -A && git commit -qm init
cd "$HOME" || exit 1
env -u CLAUDE_PLUGIN_ROOT bash "$PLUGIN/skills/project/scripts/project-actions.sh" create \
  --name mifx --path "$CODE" --projects-home "$AIDA_PROJECTS_HOME" --framework fake >>"$LOG" 2>&1 || exit 1
# The docs folder is the project's by choice, as aida-v6 is camoa_skills'.
jq --arg d "$DOCS" '.directoryChoices += [{directory: $d, project: "mifx", chosenAt: "2026-10-22"}]' \
  "$AIDA_REGISTRY_PATH" >"$ROOT/reg" && mv "$ROOT/reg" "$AIDA_REGISTRY_PATH"

# The task made by task create, then set in the implementation stage: scope distilled, research
# checked, design closed. In progress, autonomous, saved at 21:42:14Z, every file older than the
# save but one stage file written after it.
env -u CLAUDE_PLUGIN_ROOT bash "$TASKS" create --project "$PROJECT" --name aida-multi-client -- run in many clients >>"$LOG" 2>&1 || exit 1
[ "$(jq -r '.worktree.path' "$TASK/task.json")" = "$WT" ] || { echo "setup failed: worktree"; exit 1; }
jq '.state = "in_progress" | .runMode = "autonomous" | .savedAt = "2026-10-22T21:42:14Z"' \
  "$TASK/task.json" >"$ROOT/t" && mv "$ROOT/t" "$TASK/task.json"
mkdir -p "$TASK/records"
printf '{}\n' >"$TASK/records/scope-distill.json"
printf '{"exitCode": 0}\n' >"$TASK/records/research-check.json"
printf '{}\n' >"$TASK/design-closed.json"
find "$TASK" -type f -exec touch -d '2026-10-22T21:00:00Z' {} +
touch "$TASK/design-closed.json"

# Transcripts in the platform's shape. Only a tool call the session made counts. OTHER's own call
# named the folder, then it compacted: the developer's session made the task two days before the
# refusal. NEXT ran /aida:next, whose output names the folder. NOTES holds only the session-start
# Notes line. PREFIX names another task whose folder starts with this one's name. OWN's own call
# names the folder after its last compaction.
OTHER="$ROOT/other.jsonl"; NEXT="$ROOT/next.jsonl"; NOTES="$ROOT/notes.jsonl"
PREFIX="$ROOT/prefix.jsonl"; OWN="$ROOT/own.jsonl"
BOUNDARY='{"type":"system","subtype":"compact_boundary","content":"Conversation compacted"}'
call() { printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t","name":"Bash","input":{"command":"%s"}}]}}\n' "$1"; }
{
  call "T=$TASK; mkdir -p \$T/sources"
  printf '%s\n' "$BOUNDARY"
  printf '{"type":"user","message":{"content":"Task aida-multi-client has unsaved implementation stage work"}}\n'
} >"$OTHER"
{
  printf '%s\n' "$BOUNDARY"
  call 'next-actions.sh --run-mode interactive open \"aida-multi-client\"'
  printf '{"type":"user","message":{"role":"user","content":[{"tool_use_id":"t","type":"tool_result","content":"path: %s\\nstage: implementation"}]}}\n' "$TASK"
} >"$NEXT"
{
  printf '%s\n' "$BOUNDARY"
  printf '{"type":"attachment","attachment":{"type":"hook_success","hookName":"SessionStart:compact","content":"Task in progress: aida-multi-client\\nNotes: 2026-10-22, %s/notes/2026-10-22.md"}}\n' "$TASK"
} >"$NOTES"
{
  printf '%s\n' "$BOUNDARY"
  call "design-actions.sh close $TASK-two"
} >"$PREFIX"
{
  printf '%s\n' "$BOUNDARY"
  call "cd $WT && design-actions.sh close \\\"$TASK\\\""
  # A long tail after the match, as a live transcript has: a search that stops at the first match
  # failed the hook's pipe under pipefail.
  yes '{"type":"user","message":{"content":"more work"}}' | head -n 200000
} >"$OWN"
MSG="Task aida-multi-client has unsaved implementation stage work"

echo "--- other: a session that named the task before its last compaction only"
RC="$(compact manual "$DOCS" ",\"transcript_path\":\"$OTHER\"" "$ROOT/c-other.txt")"
expect "a manual compact exits 0" "$RC" "0"
expect "and says nothing" "$(wc -c <"$ROOT/c-other.txt" | tr -d ' ')" "0"
RC="$(compact auto "$DOCS" ",\"transcript_path\":\"$OTHER\"" "$ROOT/a-other.txt")"
expect "an auto compact leaves no marker in the task" "$RC $(yes_no test -f "$TASK/records/compacted.json")" "0 no"
start "$DOCS" "{\"source\":\"compact\",\"transcript_path\":\"$OTHER\"}" "$ROOT/s-other.txt"
expect "session start lists the task as the project's" \
  "$(saw "$ROOT/s-other.txt" "Task in progress in this project: aida-multi-client")" "yes"
expect "and not as this session's, with no run mode and no folder" \
  "$(saw "$ROOT/s-other.txt" "Task in progress: ") $(saw "$ROOT/s-other.txt" "Run mode: autonomous") $(saw "$ROOT/s-other.txt" "$TASK")" "no no no"

echo "--- tool output and hook text: next, notes and prefix name no tie"
for tr in "$NEXT" "$NOTES" "$PREFIX"; do
  RC="$(compact manual "$DOCS" ",\"transcript_path\":\"$tr\"" "$ROOT/c-x.txt")"
  expect "$(basename "$tr" .jsonl): a manual compact exits 0" "$RC" "0"
done
start "$DOCS" "{\"source\":\"compact\",\"transcript_path\":\"$NOTES\"}" "$ROOT/s-notes.txt"
expect "notes: session start lists the task as the project's" \
  "$(saw "$ROOT/s-notes.txt" "Task in progress in this project: aida-multi-client")" "yes"

echo "--- own: a session that names the task after its last compaction"
RC="$(compact manual "$DOCS" ",\"transcript_path\":\"$OWN\"" "$ROOT/c-own.txt")"
expect "a manual compact exits 2" "$RC" "2"
expect "and names the unsaved work" "$(saw "$ROOT/c-own.txt" "$MSG")" "yes"
RC="$(compact auto "$DOCS" ",\"transcript_path\":\"$OWN\"" "$ROOT/a-own.txt")"
expect "an auto compact marks the task" "$RC $(yes_no test -f "$TASK/records/compacted.json")" "0 yes"
start "$DOCS" "{\"source\":\"compact\",\"transcript_path\":\"$OTHER\"}" "$ROOT/s-other2.txt"
expect "the other session leaves that marker alone" "$(yes_no test -f "$TASK/records/compacted.json")" "yes"
start "$DOCS" "{\"source\":\"compact\",\"transcript_path\":\"$OWN\"}" "$ROOT/s-own.txt"
expect "session start names the task, its run mode and the marker" \
  "$(saw "$ROOT/s-own.txt" "Task in progress: aida-multi-client") $(saw "$ROOT/s-own.txt" "Run mode: autonomous") $(saw "$ROOT/s-own.txt" "compacted automatically")" "yes yes yes"
expect "and removes the marker" "$(yes_no test -f "$TASK/records/compacted.json")" "no"

echo "--- tree: cwd in the task's tree"
RC="$(compact manual "$WT" ",\"transcript_path\":\"$OTHER\"" "$ROOT/c-tree.txt")"
expect "a manual compact exits 2 whatever the transcript says" "$RC $(saw "$ROOT/c-tree.txt" "$MSG")" "2 yes"

echo "--- no path: a payload with no transcript_path, as before"
RC="$(compact manual "$DOCS" "" "$ROOT/c-none.txt")"
expect "a manual compact exits 2" "$RC $(saw "$ROOT/c-none.txt" "$MSG")" "2 yes"
start "$DOCS" "" "$ROOT/s-none.txt"
expect "session start names the task" "$(saw "$ROOT/s-none.txt" "Task in progress: aida-multi-client")" "yes"

echo "--- no file: a transcript_path with no file yet"
RC="$(compact manual "$DOCS" ",\"transcript_path\":\"$ROOT/new.jsonl\"" "$ROOT/c-new.txt")"
expect "a manual compact exits 0" "$RC" "0"
start "$DOCS" "{\"source\":\"startup\",\"transcript_path\":\"$ROOT/new.jsonl\"}" "$ROOT/s-new.txt"
expect "session start lists the task" "$(saw "$ROOT/s-new.txt" "Task in progress in this project: aida-multi-client")" "yes"

printf 'passed %s of %s\n' "$PASS" "$TOTAL"
[ "$PASS" = "$TOTAL" ]
