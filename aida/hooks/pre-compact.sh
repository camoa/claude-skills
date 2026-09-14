#!/usr/bin/env bash
# The plugin root: the variable when the platform sets it (hooks), else this file's own place.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd -P)}"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
# pre-compact.sh: PreCompact hook. It refuses a manual `/compact` while the active task has
# stage work newer than its last save. It marks an automatic compaction for the session-start hook.
#
# A compaction with unsaved stage work is how a session forgets what it decided, and the save is
# one command. The person can still compact: they save first, and nothing here overrides them.
# An automatic compaction is never refused, because the platform says a refusal can fail the
# request it was recovering from. It leaves records/compacted.json instead, which
# session-start.sh names once and removes.
#
# The active task is the one session-start.sh names: the one task in progress under the project
# that owns cwd, read off next-actions.sh's report. With several in progress, the one whose
# worktree holds cwd. No such task: silent, exit 0.
#
# "Unsaved" is the one test a hook can make on disk: a file under the task folder written after
# the last save. `task save` stamps savedAt in task.json on every call, even with nothing to say.
# A task with no savedAt is compared against its newest note under notes/, the file a save with
# text appends to. A task never saved counts as unsaved from its first file. The marker itself
# does not count.
#
# Exit 2 refuses, and stderr is shown to the person on a manual compaction (the platform's hooks
# reference, PreCompact). Nothing is printed on stdout in any case.
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0
INPUT="$(cat 2>/dev/null)" || exit 0
TRIGGER="$(jq -r '.trigger // empty' <<<"$INPUT" 2>/dev/null)"
CWD="$(jq -r '.cwd // empty' <<<"$INPUT" 2>/dev/null)"
[ -n "$CWD" ] || CWD="$(pwd -P)"
NEXT_SCRIPT="${PLUGIN_ROOT}/skills/next/scripts/next-actions.sh"

OPEN_TASKS="$(cd "$CWD" 2>/dev/null && "$NEXT_SCRIPT" report 2>/dev/null | sed -n '/^OPEN:$/,/^LEGACY_COMPLETE:$/p' \
  | grep '^{' | jq -c 'select(.state == "in_progress")' 2>/dev/null)"
[ -n "$OPEN_TASKS" ] || exit 0
TASK="$(printf '%s\n' "$OPEN_TASKS" \
  | jq -c --arg cwd "$CWD/" '.worktree as $wt | select($wt != "none" and ($cwd | startswith($wt + "/")))' 2>/dev/null | head -1)"
if [ -z "$TASK" ] && [ "$(printf '%s\n' "$OPEN_TASKS" | grep -c '^{')" -eq 1 ]; then TASK="$OPEN_TASKS"; fi
[ -n "$TASK" ] || exit 0
TASK_ID="$(printf '%s' "$TASK" | jq -r '.id')"
TASK_PATH="$(printf '%s' "$TASK" | jq -r '.path')"
STAGE="$(printf '%s' "$TASK" | jq -r '.stage')"

SAVED_AT="$(jq -r '.savedAt // empty' "$TASK_PATH/task.json" 2>/dev/null)"
NOTE=""
[ -n "$SAVED_AT" ] || NOTE="$(find "$TASK_PATH/notes" -maxdepth 1 -name '[0-9-]*.md' 2>/dev/null | sort | tail -1)"
if [ -n "$SAVED_AT" ]; then
  # A file stamped at savedAt is the reference. touch -t takes YYYYMMDDhhmm.SS, so the stamp is
  # reshaped. task.json is excluded because the save writes it a moment after the stamp it holds.
  REF="$(mktemp)"
  TZ=UTC touch -t "$(printf '%s' "$SAVED_AT" | sed 's/[-:T]//g; s/Z$//; s/\(..\)$/.\1/')" "$REF"
  NEWER="$(find "$TASK_PATH" -type f -newer "$REF" ! -name task.json ! -name compacted.json ! -path '*/notes/*' 2>/dev/null | head -1)"
  rm -f "$REF"
elif [ -n "$NOTE" ]; then
  NEWER="$(find "$TASK_PATH" -type f -newer "$NOTE" ! -path '*/notes/*' ! -name compacted.json 2>/dev/null | head -1)"
else
  NEWER="$TASK_PATH/task.json"
fi
UNSAVED="false"
[ -z "$NEWER" ] || UNSAVED="true"

case "$TRIGGER" in
  manual)
    [ "$UNSAVED" = "true" ] || exit 0
    printf 'Task %s has unsaved %s stage work, so run `/aida:task save %s` before compacting.\n' \
      "$TASK_ID" "$STAGE" "$TASK_ID" >&2
    exit 2
    ;;
  auto)
    mkdir -p "$TASK_PATH/records" 2>/dev/null || exit 0
    jq -n --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson unsaved "$UNSAVED" '{at: $at, unsaved: $unsaved}' \
      > "$TASK_PATH/records/compacted.json" 2>/dev/null
    ;;
esac
exit 0
