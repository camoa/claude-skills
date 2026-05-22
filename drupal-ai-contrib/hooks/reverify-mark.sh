#!/usr/bin/env bash
# drupal-ai-contrib — re-verification ledger (architecture pillar 5).
#
# PostToolUse(Edit|Write) hook: record every edited contribution source file so that
# `contribution-verify` can re-fire the gate for any path changed after its gate last
# passed. Reads the PostToolUse event JSON from stdin; degrades silently on any error
# (a logging hook must never disrupt the session).
#
# Coverage limit: this hook observes the Edit and Write tools only. A file changed via
# the Bash tool (shell redirects, `sed -i`) is NOT recorded — see CONVENTIONS.md
# "Known limitations". `contribution-verify` re-runs the full gate set regardless, so
# the ledger only adds *extra* re-runs; a missed entry never produces a false green.
set -u

input="$(cat 2>/dev/null || true)"
[ -n "$input" ] || exit 0

# Extract the edited file path from the event JSON. Try python3, then jq, then a
# grep/sed fallback — so the hook still records when python3 is absent rather than
# silently disabling re-verification.
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
if [ -z "$fp" ] && command -v jq >/dev/null 2>&1; then
  fp="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
fi
if [ -z "$fp" ]; then
  # Last-resort parse: the first "file_path": "..." value via grep/sed.
  fp="$(printf '%s' "$input" \
    | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | head -n1 \
    | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"//; s/"$//' 2>/dev/null || true)"
fi
[ -n "$fp" ] || exit 0

# Strip control characters (newline, tab, CR) — a crafted path must not inject extra
# tab-delimited rows into the ledger.
fp="$(printf '%s' "$fp" | tr -d '[:cntrl:]')"
[ -n "$fp" ] || exit 0

# Track contribution-relevant source files and the gate-config files that change what
# a gate does (composer.json, phpcs.xml.dist, phpstan.neon, phpunit.xml.dist, cspell
# wordlist); ignore everything else.
case "$fp" in
  *.php|*.module|*.inc|*.install|*.theme|*.profile|*.engine|*.yml|*.yaml|*.twig|*.js|*.css) ;;
  */composer.json|composer.json|*.dist|*.neon) ;;
  */.cspell-project-words.txt|.cspell-project-words.txt) ;;
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
