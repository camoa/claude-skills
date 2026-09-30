#!/usr/bin/env bash
# own-scripts-hook-spec.sh: hooks/deny-destructive-commands.sh reads every file a command runs, so
# a refusal of one of the plugin's own scripts stops the skill that runs it. The review script was
# refused that way for a message string (live-run row 254). Feeds the hook `bash <script>` for every
# shell script in the plugin, the way an agent runs one, and names the file and line of each
# refusal. A refused line is found by feeding the hook each line of that file alone. The hooks
# folder is left out: the platform runs a hook, never the Bash tool, so this hook never reads one.
set -uo pipefail
if [ -n "${ZSH_VERSION:-}" ]; then SCRIPT_SOURCE="$0"; else SCRIPT_SOURCE="${BASH_SOURCE[0]}"; fi
PLUGIN="$(cd -- "$(dirname -- "$SCRIPT_SOURCE")/.." >/dev/null 2>&1 && pwd -P)"
HOOK="$PLUGIN/hooks/deny-destructive-commands.sh"
# The hook allows everything without jq, so this spec would pass without reading a script.
command -v jq >/dev/null 2>&1 || { printf 'jq is not installed\n'; exit 1; }

# decide <command>: prints the hook's refusal reason, or nothing when it allows the command.
decide() {
  jq -nc --arg c "$1" --arg d "$PLUGIN" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' \
    | env -u AIDA_ALLOW_DANGEROUS CLAUDE_PLUGIN_ROOT="$PLUGIN" bash "$HOOK" 2>/dev/null \
    | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null
}

FAIL=0
while IFS= read -r p; do
  reason="$(decide "bash $PLUGIN/$p")"
  [ -n "$reason" ] || continue
  FAIL=1; found=false; n=0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    [ -n "$line" ] && [ -n "$(decide "$line")" ] || continue
    printf 'refused: %s:%s\n' "$p" "$n"; found=true
  done <"$PLUGIN/$p"
  [ "$found" = true ] || printf 'refused: %s, on no single line: %s\n' "$p" "$reason"
done <<SCRIPTS
$(cd "$PLUGIN" && find . -name '*.sh' -not -path './hooks/*' | sed 's#^\./##' | sort)
SCRIPTS
exit "$FAIL"
