#!/usr/bin/env bash
# replies.sh: the reply rule for every AIDA role, and a count of each role's reply (gap row 505).
#
# SubagentStart: returns hooks/reply-rule.md as the role's additional context.
# SubagentStop, and PostToolUse on SubagentHandback: appends one JSON line to
# ${CLAUDE_PLUGIN_DATA}/reply-sizes.jsonl with the reply's non-empty lines and bytes, and the cap
# the role's own file states as "**Reply cap:** <n> line". A role with several modes states its cap
# as instruction, with no number first, so its cap is null.
#
# It never blocks and prints nothing on a reply. The log is evidence, and no step reads it. A role
# that is not AIDA's, or a payload that cannot be read, is left alone. In auto mode the report is
# the handback's message, and the stop's text is only the closing words, so both are logged with
# their event.
set -u
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd -P)}"
command -v jq >/dev/null 2>&1 || exit 0
INPUT="$(cat 2>/dev/null)"
AGENT="$(jq -r '.agent_type // empty' <<<"$INPUT" 2>/dev/null)"
case "$AGENT" in aida:?*) ;; *) exit 0 ;; esac
EVENT="$(jq -r '.hook_event_name // empty' <<<"$INPUT" 2>/dev/null)"

case "$EVENT" in
  SubagentStart)
    [ -f "$PLUGIN_ROOT/hooks/reply-rule.md" ] || exit 0
    jq -n --rawfile r "$PLUGIN_ROOT/hooks/reply-rule.md" \
      '{hookSpecificOutput: {hookEventName: "SubagentStart", additionalContext: $r}}'
    exit 0 ;;
  SubagentStop) TEXT="$(jq -r '.last_assistant_message // ""' <<<"$INPUT")" ;;
  PostToolUse)
    [ "$(jq -r '.tool_name // empty' <<<"$INPUT")" = SubagentHandback ] || exit 0
    TEXT="$(jq -r '.tool_input.message // ""' <<<"$INPUT")" ;;
  *) exit 0 ;;
esac

[ -n "${CLAUDE_PLUGIN_DATA:-}" ] || exit 0
mkdir -p "$CLAUDE_PLUGIN_DATA" 2>/dev/null || exit 0
LINES="$(printf '%s\n' "$TEXT" | grep -c '[^[:space:]]')"
BYTES="$(printf '%s' "$TEXT" | wc -c | tr -d ' ')"
CAP="$(sed -n 's/^\*\*Reply cap:\*\* \([0-9][0-9]*\) lines\{0,1\}[ .,].*/\1/p' "$PLUGIN_ROOT/agents/${AGENT#aida:}.md" 2>/dev/null | head -1)"
jq -nc --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg e "$EVENT" --arg a "$AGENT" --arg cap "$CAP" \
  --argjson lines "$LINES" --argjson bytes "$BYTES" \
  --arg s "$(jq -r '.session_id // ""' <<<"$INPUT")" --arg id "$(jq -r '.agent_id // ""' <<<"$INPUT")" \
  '($cap | if . == "" then null else tonumber end) as $c
   | {at: $at, session_id: $s, event: $e, agent_type: $a, agent_id: $id, lines: $lines, bytes: $bytes,
      cap: $c, over: (if $c == null then null else $lines > $c end)}' \
  >>"$CLAUDE_PLUGIN_DATA/reply-sizes.jsonl" 2>/dev/null
exit 0
