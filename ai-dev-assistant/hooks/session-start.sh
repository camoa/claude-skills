#!/bin/bash
# Session start hook for ai-dev-assistant
# Checks required plugins and registered projects

# Clear stale session context for THIS session only
DDF_DIR=$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")
. "$DDF_DIR/scripts/session-paths.sh"
rm -f "$(ddf_session_file)"

# Note: dev-guides-navigator presence is now enforced at install time via the
# `dependencies` field in .claude-plugin/plugin.json. The former soft runtime
# check was removed once that declaration landed — install-time enforcement
# supersedes it and makes missing-dependency failures loud instead of silent.

REGISTRY="${AIDA_REGISTRY:-$HOME/.claude/ai-dev-assistant/active_projects.json}"

echo "## AI Dev Assistant"
echo ""

# Which project owns THIS directory? Counting every project the user has ever made and telling them to
# pick one is useless in a codebase that belongs to none of them — and the "start a new project" line
# used to appear only when the registry was completely empty, so nobody saw it after their first project
# ever. Answer for the directory in front of us.
WHERE=$("$DDF_DIR/scripts/project-for-cwd.sh" "$PWD" 2>/dev/null)
REGISTERED=$(printf '%s' "$WHERE" | jq -r '.registered // false' 2>/dev/null || echo "false")
PROJECT=$(printf '%s' "$WHERE" | jq -r '.project // ""' 2>/dev/null || echo "")

# Has this directory already turned the proposal down? The argument below is an offer, and an offer
# that cannot be declined is a demand. Until this existed the paragraph printed in every session
# forever, so saying no cost the same interruption every time and nothing recorded that it had been
# said. A recorded decline suppresses the ARGUMENT only; the one-line fact that this code is
# unregistered, and the command that changes that, stay — a person who changes their mind must not
# have to remember how.
DECLINED=$(printf '%s' "$WHERE" | jq -r '.offer.declined // false' 2>/dev/null || echo "false")

# An unattended run has nobody to answer a proposal, so it is not handed one. Only an explicit
# AIDA_UNATTENDED counts: `CI` is deliberately NOT read, because this repository's own test suite
# runs under it and would then be asserting the suppressed shape as the normal one.
UNATTENDED="false"
case "$(printf '%s' "${AIDA_UNATTENDED:-}" | tr '[:upper:]' '[:lower:]')" in
  true|yes|y|1|on) UNATTENDED="true" ;;
esac

if [ "$REGISTERED" = "true" ] && [ -n "$PROJECT" ]; then
  echo "This code belongs to the **$PROJECT** project."
  echo ""
  echo "Run \`/ai-dev-assistant:next\` to pick up where you left off."
  echo ""
  echo "**When new work arrives, say where it goes before you start.** Work that produces findings or"
  echo "decisions someone needs later belongs in a task — \`/ai-dev-assistant:next\` opens one, and it"
  echo "creates the task first and offers the scope contract after, so capturing costs nothing."
  echo "A typo or a question does not; just do it. Judge the work, not the diff — a two-line edit that"
  echo "forces a version choice or a rebuild is a task. Either answer is fine and the call is"
  echo "yours, but make it out loud in one line. Deciding silently that something is too small to track"
  echo "is indistinguishable from never having considered it, and whatever you learn doing untracked"
  echo "work is gone when this session closes."
else
  echo "This code is not set up as a project yet, so nothing here is being tracked."
  echo ""
  echo "Run \`/ai-dev-assistant:new <project-name>\` to set it up, or carry on without it."
  if [ "$DECLINED" != "true" ] && [ "$UNATTENDED" != "true" ]; then
    echo ""
    echo "**If real work is starting here, set it up first.** Look around only as much as you need to"
    echo "name the thing — the stack, whether it runs, roughly what it is. Then set up the project and"
    echo "make the deep analysis its first task. Findings and decisions produced before there is a"
    echo "project have nowhere to go: they live in this session and are gone when it closes, and the"
    echo "next session starts over. Auditing first and setting up afterwards is the common mistake."
    echo ""
    echo "\`/ai-dev-assistant:next\` puts that choice to you once and records your answer for this"
    echo "directory. Say no there and this paragraph stops appearing here."
  fi
  if [ -f "$REGISTRY" ]; then
    OTHERS=$(jq -r '.projects | length' "$REGISTRY" 2>/dev/null || echo "0")
    if [ "$OTHERS" -gt 0 ] 2>/dev/null; then
      echo ""
      echo "_(You have $OTHERS project(s) set up elsewhere; \`/ai-dev-assistant:next\` lists them.)_"
    fi
  fi
fi

exit 0
