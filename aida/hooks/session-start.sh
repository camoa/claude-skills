#!/usr/bin/env bash
# The plugin root: the variable when the platform sets it (hooks), else this file's own place.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd -P)}"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
# session-start.sh: says which project owns this directory, at the start of every session.
#
# ideal/project.md, "Session start": say which project owns this directory, or that it is
# not set up and how many projects exist elsewhere, before the first turn. Drop the
# persuasion paragraph once this directory has declined the offer. Skip it entirely under an
# unattended run. Ported from version 5's hooks/session-start.sh.
#
# Resolution here mirrors "Picking up work" in ideal/project.md, cases 1, 2 and 4 (case 3 is
# case 1 winning when both would otherwise apply): a registered code path first, then a
# directory this project was last switched to by hand, and only then "not set up." This is
# the same order project-actions.sh's own `report` action applies, kept here as its own,
# lighter read: `report` also runs the full project check and prints the raw project JSON,
# which belongs to a deliberate `/aida:project` call, not to a line printed before every turn.
#
# AIDA_UNATTENDED marks a session with nobody present to answer the offer below. It is not
# AIDA_RUN_MODE: run mode belongs to a task (foundations.md, Run mode), and no task is chosen
# yet when a session starts. Only an explicit AIDA_UNATTENDED counts; `CI` is deliberately
# not read, since this plugin's own test suite runs under it and would then assert the
# suppressed shape as the normal one.
#
# Depends on, shipped by other builders of this same part and never edited here:
#   ${CLAUDE_PLUGIN_ROOT}/scripts/lib/registry.sh (sourced, never executed)
#   ${CLAUDE_PLUGIN_ROOT}/skills/next/scripts/next-actions.sh (executed, for the task lines)
#
# What this script does not do: it does not clear a per-workspace session file the way
# version 5's hook did. That file was a second, independent directory-to-project mapping
# (stages/02-v5-project-storage.md) that could go stale and disagree with the registry.
# ideal/project.md's "New" section merges it into the registry itself, as `directoryChoices`,
# durable on purpose so it survives a new terminal. Clearing it every session would undo
# that fix, so this script leaves it alone.

set -uo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT is not set}"
REGISTRY_LIB="${PLUGIN_ROOT}/scripts/lib/registry.sh"
REGISTRY_FILE="${AIDA_REGISTRY_PATH:-$HOME/.claude/aida/registry.json}"
NEXT_SCRIPT="${PLUGIN_ROOT}/skills/next/scripts/next-actions.sh"

echo "## AIDA"
echo ""

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required and was not found on PATH. The project for this directory could not be read."
  exit 0
fi

# shellcheck source=/dev/null
if ! source "$REGISTRY_LIB" 2>/dev/null; then
  echo "The project registry library at ${REGISTRY_LIB} could not be read. The project for this directory could not be read."
  exit 0
fi

UNATTENDED="false"
case "$(printf '%s' "${AIDA_UNATTENDED:-}" | tr '[:upper:]' '[:lower:]')" in
  true|yes|y|1|on) UNATTENDED="true" ;;
esac

CWD="$(pwd -P)"

MATCH=""
if MATCH="$(registry_resolve_by_directory "$CWD")"; then
  :
else
  MATCH=""
  CHOICE_ROW="$(registry_read_directory_choice "$CWD")"
  if [ -n "$CHOICE_ROW" ]; then
    CHOICE_NAME="$(printf '%s' "$CHOICE_ROW" | jq -r '.project')"
    if [ -r "$REGISTRY_FILE" ]; then
      MATCH="$(jq -c --arg n "$CHOICE_NAME" '[.projects[]? | select(.name == $n)] | first // empty' "$REGISTRY_FILE" 2>/dev/null)"
      [ "$MATCH" != "null" ] || MATCH=""
    fi
  fi
fi

if [ -n "$MATCH" ]; then
  PROJECT_NAME="$(printf '%s' "$MATCH" | jq -r '.name')"
  PROJECT_PATH="$(printf '%s' "$MATCH" | jq -r '.path')"
  registry_touch_last_accessed "$PROJECT_PATH"

  echo "This directory belongs to the **${PROJECT_NAME}** project."
  echo ""

  # The task in progress, and where it stands. The stage is derived from the records in the task
  # folder every time, never stored. Each stage writes one record when it closes, and the stage
  # is the first whose record is absent. Task discovery and the review verdict come from the next
  # skill's own script, read off its OPEN: lines. So there is no second walk of the tasks folder.
  # Version 5 kept this in a per-prompt hook and a session file. Version 6 keeps one copy of the
  # state, in the records, so this block reads and never writes.
  OPEN_TASKS="$("$NEXT_SCRIPT" report 2>/dev/null | sed -n '/^OPEN:$/,/^LEGACY_COMPLETE:$/p' \
    | grep '^{' | jq -c 'select(.state == "in_progress")' 2>/dev/null)"
  IN_PROGRESS="$(printf '%s\n' "$OPEN_TASKS" | grep -c '^{')"
  if [ "$IN_PROGRESS" -eq 1 ]; then
    TASK_ID="$(printf '%s' "$OPEN_TASKS" | jq -r '.id')"
    TASK_PATH="$(printf '%s' "$OPEN_TASKS" | jq -r '.path')"
    TASK_REVIEW="$(printf '%s' "$OPEN_TASKS" | jq -r '.review')"
    TASK_RUN_MODE="$(printf '%s' "$OPEN_TASKS" | jq -r '.runMode // empty')"
    TASK_NOTES="$(printf '%s' "$OPEN_TASKS" | jq -r '.notes // "none"')"
    if [ ! -f "$TASK_PATH/alignment.json" ]; then
      STAGE="scope"
    elif [ "$(jq -r '.exitCode // 1' "$TASK_PATH/records/research-check.json" 2>/dev/null)" != "0" ]; then
      STAGE="research"
    elif [ ! -f "$TASK_PATH/design-closed.json" ]; then
      STAGE="design"
    elif [ ! -f "$TASK_PATH/implementation/finished.json" ]; then
      STAGE="implementation"
    elif [ "$TASK_REVIEW" != "passed" ] && [ "$TASK_REVIEW" != "failed" ]; then
      STAGE="review"
    else
      STAGE="completion"
    fi
    echo "Task in progress: ${TASK_ID}"
    echo "Stage: ${STAGE}"
    # The newest saved note, read off the same task line. The window reads it before its first
    # turn; a note older than the record it overlaps was overtaken by that record's producer.
    [ "$TASK_NOTES" = "none" ] || echo "Notes: ${TASK_NOTES}, ${TASK_PATH}/notes/${TASK_NOTES}.md"
    [ "$TASK_RUN_MODE" != "autonomous" ] || echo "Run mode: autonomous"
    echo ""
  elif [ "$IN_PROGRESS" -gt 1 ]; then
    echo "${IN_PROGRESS} tasks are in progress; \`/aida:next\` lists them."
    echo ""
  fi

  # Per-project reminders, written by hand. Version 5 held these in an installed primer.
  REMINDERS="$PROJECT_PATH/reminders.md"
  if [ -s "$REMINDERS" ]; then
    echo "Reminders, from ${REMINDERS}:"
    cat "$REMINDERS"
    echo ""
  fi

  echo "Run \`/aida:project\` to pick up where you left off."
  echo ""
  echo "**When new work arrives, say where it goes before you start.** Work that produces"
  echo "findings or decisions someone needs later belongs in a task. A typo or a question"
  echo "does not; just do it. Judge the work, not the diff: a two-line edit that forces a"
  echo "version choice or a rebuild is a task. Either answer is fine, and the call is yours,"
  echo "but make it out loud in one line. Deciding silently that something is too small to"
  echo "track is the same as never having considered it, and whatever you learn doing"
  echo "untracked work is gone once this session closes."
else
  echo "This directory is not set up as a project, so nothing here is being tracked."
  echo ""
  echo "Run \`/aida:project create\` to set it up, or carry on without it."

  DECLINED="false"
  if registry_read_declined_offer "$CWD" >/dev/null; then
    DECLINED="true"
  fi

  if [ "$DECLINED" != "true" ] && [ "$UNATTENDED" != "true" ]; then
    echo ""
    echo "**If real work is starting here, set it up first.** Look around only as much as you"
    echo "need to name the thing: the stack, whether it runs, roughly what it is. Then set up"
    echo "the project and make the deep look its first task. Findings and decisions produced"
    echo "before there is a project have nowhere to go: they live in this session and are gone"
    echo "when it closes, and the next session starts over. Looking first and setting up"
    echo "afterwards is the common mistake."
    echo ""
    echo "\`/aida:project\` puts that choice to you once and records your answer for this"
    echo "directory. Say no there and this paragraph stops appearing here."
  fi

  # Count what the list would show, which excludes complete and archived. Counting every row and
  # then showing fewer is a number that does not match what happens next.
  OTHERS="$(registry_list_projects active | grep -c .)"
  if [ "${OTHERS:-0}" -gt 0 ] 2>/dev/null; then
    echo ""
    echo "_(You have ${OTHERS} project(s) set up elsewhere; \`/aida:project\` lists them.)_"
  fi
fi

exit 0
