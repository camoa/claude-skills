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
# text appends to. A task never saved is unsaved only once it holds a version 6 record: task.json,
# task.md and the .v5 files a version 5 repair keeps
# (skills/task/scripts/task-actions.sh, keep_v5_files) do not count on their own.
#
# Two folders are excluded beside notes/ in all three branches (live-run row 152).
#
# inputs/ first. docs/task.md calls it material carried in from before the task existed. A file
# there is usually not work this window decided. Research is the exception: it writes a fetched
# page and a pulled tree there. Each of those is already a finding's source, and that finding's
# record under research/ still refuses, so the window is one step wide.
#
# records/ second. It is derived check output, and the project's ignore file keeps it out of
# history. That covers records/compacted.json, which this hook writes, and records/check-task.json,
# which `task start` writes about the task.
#
# One bound, for the next author. Nothing stops a stage writing its only record under records/, and
# this hook would then not see that stage. One check refuses one case.
# skills/design/scripts/design-actions.sh:915-919 refuses an owned path there for a record order
# alone. An order proved by tests is not refused.
#
# One step already sits in that window. Research's playbooks step writes only
# records/playbooks-catalog.json, records/playbooks.json and records/playbooks.md, while research/
# is still empty. A manual compact is allowed there. It is safe on two counts: the step asks nobody
# anything, and every record it wrote has a producer that runs again. So a record must never live
# only under records/ when it carries a person's answer, or when nothing can produce it again.
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
  NEWER="$(find "$TASK_PATH" -type f -newer "$REF" ! -name task.json ! -path '*/notes/*' ! -path '*/inputs/*' ! -path '*/records/*' 2>/dev/null | head -1)"
  rm -f "$REF"
elif [ -n "$NOTE" ]; then
  # task.json is excluded here for the reason the branch above gives. The save that wrote this note
  # wrote task.json straight after it. Without this, the note is never the newest file.
  NEWER="$(find "$TASK_PATH" -type f -newer "$NOTE" ! -name task.json ! -path '*/notes/*' ! -path '*/inputs/*' ! -path '*/records/*' 2>/dev/null | head -1)"
else
  # A never-saved task holds only task.json, task.md and whatever a version 5 repair kept under
  # a .v5 name (skills/task/scripts/task-actions.sh, keep_v5_files). None of those is a version 6
  # stage record, so this task is unsaved only once a version 6 stage writes something else.
  NEWER="$(find "$TASK_PATH" -type f ! -name task.json ! -name task.md \
    ! -name '*.v5.md' ! -name '*.v5' ! -path '*/notes/*' ! -path '*/inputs/*' ! -path '*/records/*' ! -path '*.v5/*' 2>/dev/null | head -1)"
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
