#!/usr/bin/env bash
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
# which belongs to a deliberate `/project` call, not to a line printed before every turn.
#
# AIDA_UNATTENDED marks a session with nobody present to answer the offer below. It is not
# AIDA_RUN_MODE: run mode belongs to a task (foundations.md, Run mode), and no task is chosen
# yet when a session starts. Only an explicit AIDA_UNATTENDED counts; `CI` is deliberately
# not read, since this plugin's own test suite runs under it and would then assert the
# suppressed shape as the normal one.
#
# Depends on, shipped by other builders of this same part and never edited here:
#   ${CLAUDE_PLUGIN_ROOT}/scripts/lib/registry.sh (sourced, never executed)
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
  echo "Run \`/project\` to pick up where you left off."
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
  echo "Run \`/project create\` to set it up, or carry on without it."

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
    echo "\`/project\` puts that choice to you once and records your answer for this"
    echo "directory. Say no there and this paragraph stops appearing here."
  fi

  # Count what the list would show, which excludes complete and archived. Counting every row and
  # then showing fewer is a number that does not match what happens next.
  OTHERS="$(registry_list_projects active | grep -c .)"
  if [ "${OTHERS:-0}" -gt 0 ] 2>/dev/null; then
    echo ""
    echo "_(You have ${OTHERS} project(s) set up elsewhere; \`/project\` lists them.)_"
  fi
fi

exit 0
