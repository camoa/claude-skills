#!/usr/bin/env bash
# Pre-compact hook: Preserve dev-guides cache pointer before compaction
# Lightweight — just tells Claude the cache exists, no content dumped

# Find cache file
CACHE_FILE=""
for dir in ~/.claude/projects/*/memory/; do
  if [ -f "${dir}dev-guides-cache.json" ]; then
    CACHE_FILE="${dir}dev-guides-cache.json"
    break
  fi
done

if [ -z "$CACHE_FILE" ]; then
  exit 0
fi

echo "## Pre-Compaction Context (dev-guides-navigator)"
echo ""
echo "Guide cache available at \`$CACHE_FILE\`."
echo "Use \`/dev-guides-navigator\` to find guides — cache will be reused."
