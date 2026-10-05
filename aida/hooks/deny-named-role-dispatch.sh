#!/usr/bin/env bash
# The plugin root: the variable when the platform sets it (hooks), else this file's own place.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd -P)}"
# deny-named-role-dispatch.sh: a PreToolUse hook on Agent (gap row 320).
#
# Every role guard knows a role by the payload's agent_type. With agent teams on, an Agent call
# that passes a `name` starts a teammate (the mirror's sub-agents page, "Subagent names"), and
# that teammate's hook payloads carry the name as agent_type, not the role. A live distiller named
# distill-initial-packs was refused its own sidecars. The implementer, fixer and reviewer
# dispatches of that session were named too, so the guards that match their role passed them.
# No skill resumes a role by name. So a dispatch of one of this plugin's roles with a `name` is
# refused, and the reason says to dispatch it again without one.
# Allow, silent, on everything else, and without jq.
INPUT="$(cat 2>/dev/null)"
command -v jq >/dev/null 2>&1 || exit 0
TYPE="$(jq -r '.tool_input.subagent_type // empty' <<<"$INPUT" 2>/dev/null)"
NAME="$(jq -r '.tool_input.name // empty' <<<"$INPUT" 2>/dev/null)"
[ -n "$NAME" ] && [ -f "$PLUGIN_ROOT/agents/${TYPE##*:}.md" ] || exit 0
case "$TYPE" in
  *:*) [ "${TYPE%%:*}" = "$(jq -r '.name // empty' "$PLUGIN_ROOT/.claude-plugin/plugin.json" 2>/dev/null)" ] || exit 0 ;;
esac
jq -nc --arg r "$TYPE was dispatched with the name $NAME. Dispatch it again with the same type and no name. A named dispatch can start a teammate, and its hooks then see $NAME as the agent type, not the role, so the role's guards miss it." \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
