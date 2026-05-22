#!/usr/bin/env bash
# drupal-ai-contrib — re-verification ledger reader.
#
# Prints the unique contribution paths edited since the last verify — the stale-gate
# set that `contribution-verify` must re-fire (architecture pillar 5). The ledger is
# written by the PostToolUse hook hooks/reverify-mark.sh.
#
#   reverify-list.sh           print stale paths, one per line
#   reverify-list.sh --clear   print stale paths, then clear the ledger
#
# Prints nothing and exits 0 when there is no ledger (no stale gates).
set -u

proj="${CLAUDE_PROJECT_DIR:-$PWD}"
data="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}}"
key="$(printf '%s' "$proj" | cksum | cut -d' ' -f1)"
ledger="$data/reverify/$key.log"

[ -f "$ledger" ] || exit 0

cut -f2 "$ledger" 2>/dev/null | sort -u

if [ "${1:-}" = "--clear" ]; then
  : > "$ledger" 2>/dev/null || true
fi
exit 0
