#!/usr/bin/env bash
# The plugin root: the variable when the platform sets it (hooks), else this file's own place.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd -P)}"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
# deny-destructive-commands.sh. A PreToolUse hook on Bash: refuses commands that throw work away
# or publish it, before they run. The list is version 5's, from block-dangerous-commands.sh. Any
# `git push`, a force push, a hard reset, `git clean`, `git branch -D`, `git checkout .` and
# `git restore .`. A recursive delete of root, the home directory, or the working tree. Plain
# `git push` stays refused because version 6 never publishes: completion writes the pull request
# body and a person pushes. Version 5 never wired this hook; here it is wired in hooks/hooks.json.
#
# This is friction against an accident, not a boundary, because it matches text on a
# whitespace-normalized command line. A rephrased form passes: a flag between `git` and its verb, a
# quoted verb, a variable, or the working tree as a full path. A refused phrase inside a safe
# command's quoted argument, such as a commit message, is refused too; closing either gap means
# parsing the shell grammar.
#
# FAIL-OPEN. No jq, empty or unreadable stdin, a payload with no command: allow, silent. A refusal
# that failed closed would refuse every Bash call in the session on a transient fault. That is
# worse than the command it guards against.
#
# Override: AIDA_ALLOW_DANGEROUS=1 in the hook's own environment, which is the shell that launched
# this session, allows everything for that session.
#
# Deny is the documented JSON form (permissionDecision: deny, permissionDecisionReason shown to
# the model), on exit 0, the same as hooks/deny-frozen-test-writes.sh.
set -uo pipefail

[ "${AIDA_ALLOW_DANGEROUS:-}" != "1" ] || { echo '{}'; exit 0; }
command -v jq >/dev/null 2>&1 || { echo '{}'; exit 0; }
INPUT="$(cat 2>/dev/null)" || { echo '{}'; exit 0; }
CMD="$(jq -r 'select(.tool_name == "Bash") | .tool_input.command // empty' <<<"$INPUT" 2>/dev/null)"
[ -n "$CMD" ] || { echo '{}'; exit 0; }

# Runs of spaces and tabs become one space, so a double space or a tab between words still matches.
CMD_NORM="$(printf '%s' "$CMD" | tr -s ' \t' ' ')"

deny() {
  jq -nc --arg r "deny-destructive-commands: refused, because the command $1. Run it yourself if you mean it. AIDA_ALLOW_DANGEROUS=1 in the shell that launched this session turns this hook off." \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

matches() { printf '%s' "$CMD_NORM" | grep -Eq "$1"; }

# A target or a flag is matched as a whole argument, so `rm -rf ./build` and `git checkout -b x`
# pass. The force push runs first so its reason
# names it; the plain push below would catch it anyway.
matches 'push( [^ ;&|]+)* (-f|--force)' && deny "is a force push"
matches 'git push( |$|;|&|\|)' && deny "is a git push, and version 6 never publishes: a person pushes"
matches 'reset --hard' && deny "is a hard reset"
matches 'git clean -[a-zA-Z]*[fxX]' && deny "runs git clean, which deletes untracked files"
matches 'git branch -D( |$|;|&|\|)' && deny "force-deletes a branch"
matches 'git (checkout|restore)( --)? \.( |$|;|&|\|)' && deny "discards every uncommitted change in the working tree"
matches 'rm -f?[rR]f? (/|/\*|~|~/|\.|\./|\*)( |$|;|&|\|)' && deny "deletes root, the home directory, or the working tree recursively"

echo '{}'
exit 0
