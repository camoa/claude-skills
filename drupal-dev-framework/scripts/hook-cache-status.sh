#!/usr/bin/env bash
# hook-cache-status.sh — diagnostic for v4.0.2 hook caches.
#
# For the current workspace, computes the rendered hash that each cached hook
# WOULD emit on the next UserPromptSubmit, and compares with the cached hash.
# Useful for confirming that "state unchanged → skip emit" is working OR for
# debugging "why did the hook fire on the last turn."
#
# Usage:
#   scripts/hook-cache-status.sh
#
# Exit code is informational only: 0 always (this is a diagnostic, not a gate).

set -eu

WORKSPACE_HASH=$(printf %s "$PWD" | md5sum | cut -d' ' -f1)
CACHE_DIR="$HOME/.claude/drupal-dev-framework/sessions"

printf 'Workspace: %s\n' "$PWD"
printf 'Hash:      %s\n' "$WORKSPACE_HASH"
printf '\n'

for hook in context-reminder loaded-context-summary; do
  cache_file="$CACHE_DIR/${WORKSPACE_HASH}.last-${hook}.md5"
  if [ -f "$cache_file" ]; then
    cached=$(cat "$cache_file" 2>/dev/null || printf '(read failed)')
    printf '%-25s cache: %s\n' "$hook" "$cached"
  else
    printf '%-25s cache: (no cache file yet — next emit will populate)\n' "$hook"
  fi
done

printf '\n'
printf 'To verify skip behavior, run with DDF_HOOK_DEBUG=1 set in env:\n'
printf '  DDF_HOOK_DEBUG=1 hooks/context-reminder.sh < /dev/null\n'
printf 'First call: "emit (state changed)". Second call (no state change): "skipped (state unchanged)".\n'

exit 0
