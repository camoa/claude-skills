#!/usr/bin/env bash
# replies-hook-spec.sh: the reply hook (gap row 505). At a role's start it injects the reply rule.
# At a role's reply it logs the reply's size against the cap the role's file states, and it never
# blocks and never prints to the conversation. Each case feeds one payload on stdin.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=records.bash
source "$HERE/records.bash"
HOOK="$PLUGIN/hooks/replies.sh"
export CLAUDE_PLUGIN_DATA="$ROOT/data"
LOG="$CLAUDE_PLUGIN_DATA/reply-sizes.jsonl"

# hook <payload>: the hook's stdout on <payload>, in $ROOT/hook.out. Sets RC.
hook() {
  printf '%s' "$1" | CLAUDE_PLUGIN_ROOT="$PLUGIN" bash "$HOOK" >"$ROOT/hook.out" 2>/dev/null
  RC=$?
}
# stop <agent type> <text>: a SubagentStop payload.
stop() { jq -nc --arg a "$1" --arg m "$2" '{session_id: "s1", hook_event_name: "SubagentStop", agent_id: "a1", agent_type: $a, last_assistant_message: $m}'; }
# last_log <jq filter>: the filter on the log's last line.
last_log() { tail -n 1 "$LOG" 2>/dev/null | jq -r "$1"; }
log_lines() { if [ -f "$LOG" ]; then grep -c . "$LOG"; else echo 0; fi; }
# blocked: whether the hook's stdout holds a decision of any kind.
blocked() { jq -r '[.. | objects | (.decision?, .permissionDecision?) | select(. != null)] | length' "$ROOT/hook.out" 2>/dev/null || echo 0; }

hook "$(stop aida:distiller 'written')"
expect "a distiller reply of one line logs under its cap, prints nothing, and exits 0" \
  "$RC|$(wc -c <"$ROOT/hook.out" | tr -d ' ')|$(log_lines)|$(last_log '[.agent_type, .lines, .cap, .over] | map(tostring) | join(",")')" \
  '0|0|1|aida:distiller,1,1,false'

hook "$(stop aida:distiller "$(printf 'one\ntwo\nthree\nfour\nfive')")"
expect "a distiller reply of five lines logs over its cap, prints nothing, and exits 0" \
  "$RC|$(wc -c <"$ROOT/hook.out" | tr -d ' ')|$(log_lines)|$(last_log '[.lines, .over] | map(tostring) | join(",")')" \
  '0|0|2|5,true'

hook "$(jq -nc '{session_id: "s1", hook_event_name: "PostToolUse", tool_name: "SubagentHandback", agent_id: "a2",
  agent_type: "aida:outward-searcher", tool_input: {message: "finding one\nfinding two"}}')"
expect "a searcher's handback logs its size with no cap, and prints nothing" \
  "$(wc -c <"$ROOT/hook.out" | tr -d ' ')|$(log_lines)|$(last_log '[.event, .lines, .cap, .over] | map(tostring) | join(",")')" \
  '0|3|PostToolUse,2,null,null'

hook "$(stop Explore 'a reply')"
hook "$(stop '' 'a reply')"
expect "a reply from a role that is not AIDA's logs nothing" "$(log_lines)" '3'

hook "$(jq -nc '{session_id: "s1", hook_event_name: "SubagentStart", agent_id: "a3", agent_type: "aida:catalog-identifier"}')"
expect "a role's start gets the reply rule as its context" \
  "$RC|$(jq -r '.hookSpecificOutput.hookEventName' "$ROOT/hook.out")|$(jq -j '.hookSpecificOutput.additionalContext' "$ROOT/hook.out" | cmp -s - "$PLUGIN/hooks/reply-rule.md" && echo same)" \
  '0|SubagentStart|same'
expect "the start case holds no decision" "$(blocked)" '0'

finish
