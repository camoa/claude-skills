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

REGISTRY="$HOME/.claude/ai-dev-assistant/active_projects.json"

echo "## AI Dev Assistant"
echo ""

# Which project owns THIS directory? Counting every project the user has ever made and telling them to
# pick one is useless in a codebase that belongs to none of them — and the "start a new project" line
# used to appear only when the registry was completely empty, so nobody saw it after their first project
# ever. Answer for the directory in front of us.
WHERE=$("$DDF_DIR/scripts/project-for-cwd.sh" "$PWD" 2>/dev/null)
REGISTERED=$(printf '%s' "$WHERE" | jq -r '.registered // false' 2>/dev/null || echo "false")
PROJECT=$(printf '%s' "$WHERE" | jq -r '.project // ""' 2>/dev/null || echo "")

if [ "$REGISTERED" = "true" ] && [ -n "$PROJECT" ]; then
  echo "This code belongs to the **$PROJECT** project."
  echo ""
  echo "Run \`/ai-dev-assistant:next\` to pick up where you left off."
else
  echo "This code is not set up as a project yet, so nothing here is being tracked."
  echo ""
  echo "Run \`/ai-dev-assistant:new <project-name>\` to set it up, or carry on without it."
  echo ""
  echo "**If real work is starting here, set it up first.** Look around only as much as you need to"
  echo "name the thing — the stack, whether it runs, roughly what it is. Then set up the project and"
  echo "make the deep analysis its first task. Findings and decisions produced before there is a"
  echo "project have nowhere to go: they live in this session and are gone when it closes, and the"
  echo "next session starts over. Auditing first and setting up afterwards is the common mistake."
  if [ -f "$REGISTRY" ]; then
    OTHERS=$(jq -r '.projects | length' "$REGISTRY" 2>/dev/null || echo "0")
    if [ "$OTHERS" -gt 0 ] 2>/dev/null; then
      echo ""
      echo "_(You have $OTHERS project(s) set up elsewhere; \`/ai-dev-assistant:next\` lists them.)_"
    fi
  fi
fi

exit 0
