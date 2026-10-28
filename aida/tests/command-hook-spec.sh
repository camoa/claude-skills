#!/usr/bin/env bash
# command-hook-spec.sh: hooks/deny-destructive-commands.sh asks the person before a command that
# throws work away or publishes it, where Claude Code can show a prompt. It refuses that command
# where no prompt can show, and it refuses a dispatched role and stops it. A write to the guard is
# refused in every case. Text no shell runs is not a command (gap row 460).
# The commands are built with printf, because the hook reads this file when a session runs it.
set -u
# shellcheck source=records.bash
source "$(dirname "${BASH_SOURCE[0]}")/records.bash"
HOOK="$PLUGIN/hooks/deny-destructive-commands.sh"
# out <payload as JSON> [env assignment]: the hook's output for one call.
out() {
  printf '%s' "$1" | jq -c '{cwd: "/"} + .' \
    | env -u AIDA_ALLOW_DANGEROUS CLAUDE_PLUGIN_ROOT="$PLUGIN" ${2:+"$2"} bash "$HOOK"
}
# bash_call <command> <permission mode> [agent id]: a Bash payload.
bash_call() {
  jq -nc --arg c "$1" --arg m "$2" --arg a "${3:-}" \
    '{tool_name: "Bash", tool_input: {command: $c}} + (if $m == "" then {} else {permission_mode: $m} end)
     + (if $a == "" then {} else {agent_id: $a, agent_type: "aida:fixer"} end)'
}
# decision <output>: deny, ask or allow, and "stop" after it when the output ends the turn.
decision() {
  printf '%s' "$1" | jq -r '(.hookSpecificOutput.permissionDecision // "allow")
    + (if .continue == false then " stop" else "" end)'
}
PUSH="$(printf 'git %s origin main' push)"

expect "the main session in default mode is asked about a push" \
  "$(decision "$(out "$(bash_call "$PUSH" default)")")" ask
expect "the main session in auto mode is asked about a recursive delete of home" \
  "$(decision "$(out "$(bash_call "$(printf 'rm -%s ~' rf)" auto)")")" ask
expect "bypassPermissions shows no prompt, so a push is refused" \
  "$(decision "$(out "$(bash_call "$PUSH" bypassPermissions)")")" deny
expect "a payload with no permission mode is refused" \
  "$(decision "$(out "$(bash_call "$PUSH" "")")")" deny
expect "a dispatched role is refused a push and stopped" \
  "$(decision "$(out "$(bash_call "$PUSH" default agent-1)")")" "deny stop"
expect "a plain status passes" \
  "$(decision "$(out "$(bash_call "git status" default)")")" allow
expect "a write to the hooks folder is refused in default mode" \
  "$(decision "$(out "$(jq -nc --arg f "$PLUGIN/hooks/hooks.json" \
    '{tool_name: "Write", permission_mode: "default", tool_input: {file_path: $f, content: "{}"}}')")")" deny
expect "AIDA_ALLOW_DANGEROUS=1 lets the push through" \
  "$(decision "$(out "$(bash_call "$PUSH" bypassPermissions)" AIDA_ALLOW_DANGEROUS=1)")" allow
expect "a quoted heredoc to python names a git verb in backticks: no question" \
  "$(decision "$(out "$(bash_call "$(printf 'python3 - <<%sEOF%s\nprint("a \140git archive\140 export")\nEOF' "'" "'")" default)")")" allow

finish
