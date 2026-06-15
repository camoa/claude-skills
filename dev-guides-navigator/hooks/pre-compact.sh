#!/usr/bin/env bash
# Pre-compact hook: Preserve dev-guides catalog pointer before compaction
# Lightweight — just tells Claude the catalog exists, no content dumped

# Prefer the shared store (canonical — see references/store-contract.md),
# honouring DEV_GUIDES_STORE_DIR; fall back to the transitional per-project
# compat shim (glob, first match).
STORE_ROOT="${DEV_GUIDES_STORE_DIR:-$HOME/.claude/dev-guides-store}"
CACHE_FILE=""
if [ -f "${STORE_ROOT}/indexes/llms.json" ]; then
  CACHE_FILE="${STORE_ROOT}/indexes/llms.json"
else
  for dir in ~/.claude/projects/*/memory/; do
    if [ -f "${dir}dev-guides-cache.json" ]; then
      CACHE_FILE="${dir}dev-guides-cache.json"
      break
    fi
  done
fi

if [ -z "$CACHE_FILE" ]; then
  exit 0
fi

echo "## Pre-Compaction Context (dev-guides-navigator)"
echo ""
echo "Guide catalog available at \`$CACHE_FILE\`."
echo "Use \`/dev-guides-navigator\` to find guides — catalog will be reused."
