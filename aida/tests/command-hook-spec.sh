#!/usr/bin/env bash
# command-hook-spec.sh: hooks/deny-destructive-commands.sh reads the body of a heredoc with a quoted
# delimiter, or a single-quoted `-c` argument, sent to a program that is not a shell, as text. No
# shell expands that text, so a git verb in it is not a command (gap row 460). An unquoted
# delimiter, double quotes, or a shell still have it read.
# The commands are built with octal escapes, \140 for a backtick and \044 for a dollar sign, because
# the hook reads this file when a session runs it.
set -u
# shellcheck source=records.bash
source "$(dirname "${BASH_SOURCE[0]}")/records.bash"
HOOK="$PLUGIN/hooks/deny-destructive-commands.sh"
# decision <command>: the hook's decision on the command, deny or allow.
decision() {
  jq -nc --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}, cwd: "/"}' \
    | env -u AIDA_ALLOW_DANGEROUS CLAUDE_PLUGIN_ROOT="$PLUGIN" bash "$HOOK" \
    | jq -r '.hookSpecificOutput.permissionDecision // "allow"'
}

expect "a quoted heredoc to python names a git verb in backticks: allowed" \
  "$(decision "$(printf 'python3 - <<%sEOF%s\nprint("a \140git archive\140 export")\nEOF' "'" "'")")" allow
expect "an unquoted heredoc to python runs its backticks: refused" \
  "$(decision "$(printf 'python3 - <<EOF\nprint("\140git \044x\140")\nEOF')")" deny
expect "a quoted heredoc to bash is commands: refused" \
  "$(decision "$(printf 'bash <<%sEOF%s\ngit \044x\nEOF' "'" "'")")" deny
expect "a single-quoted -c argument to python names a git verb in backticks: allowed" \
  "$(decision "$(printf 'python3 -c %sprint("a \140git archive\140 export")%s' "'" "'")")" allow
expect "a double-quoted -c argument to python runs its backticks: refused" \
  "$(decision "$(printf 'python3 -c "print(%s\140git \044x\140%s)"' "'" "'")")" deny

finish
