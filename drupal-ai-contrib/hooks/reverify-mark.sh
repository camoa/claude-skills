#!/usr/bin/env bash
# drupal-ai-contrib — re-verification ledger (architecture pillar 5).
#
# PostToolUse(Edit|Write) hook: record every edited contribution source file so that
# `contribution-verify` can re-fire the gate for any path changed after its gate last
# passed. Reads the PostToolUse event JSON from stdin; degrades silently on any error
# (a logging hook must never disrupt the session).
set -u

input="$(cat 2>/dev/null || true)"
[ -n "$input" ] || exit 0

# Extract the edited file path from the event JSON.
fp=""
if command -v python3 >/dev/null 2>&1; then
  fp="$(printf '%s' "$input" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get("tool_input", {}).get("file_path", ""))
except Exception:
    pass
' 2>/dev/null || true)"
fi
[ -n "$fp" ] || exit 0

# Track only contribution-relevant source files; ignore everything else.
case "$fp" in
  *.php|*.module|*.inc|*.install|*.theme|*.profile|*.engine|*.yml|*.yaml|*.twig|*.js|*.css) ;;
  *) exit 0 ;;
esac

proj="${CLAUDE_PROJECT_DIR:-$PWD}"
data="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}}"
key="$(printf '%s' "$proj" | cksum | cut -d' ' -f1)"
ledger_dir="$data/reverify"

mkdir -p "$ledger_dir" 2>/dev/null || exit 0
stamp="$(date -u +%FT%TZ 2>/dev/null || date 2>/dev/null || echo unknown)"
printf '%s\t%s\n' "$stamp" "$fp" >> "$ledger_dir/$key.log" 2>/dev/null || true
exit 0
