#!/usr/bin/env bash
# Pre-compact hook: Preserve dev-guides cache state before compaction
# Outputs cache location, hash, and last matched topics

echo "## Pre-Compaction Context (dev-guides-navigator)"
echo ""

# Find cache file
CACHE_FILE=""
for dir in ~/.claude/projects/*/memory/; do
  if [ -f "${dir}dev-guides-cache.json" ]; then
    CACHE_FILE="${dir}dev-guides-cache.json"
    break
  fi
done

if [ -z "$CACHE_FILE" ]; then
  echo "No dev-guides cache found. Guides will be fetched fresh on next use."
  exit 0
fi

echo "### Cache Location: $CACHE_FILE"

# Show cached hash
HASH=$(jq -r '.hash // empty' "$CACHE_FILE" 2>/dev/null)
if [ -n "$HASH" ]; then
  echo "### Cached Hash: ${HASH:0:16}..."
fi

# Count topics in cached llms.txt
TOPIC_COUNT=$(jq -r '.llms_txt // empty' "$CACHE_FILE" 2>/dev/null | grep -c "^- \[" 2>/dev/null)
if [ -n "$TOPIC_COUNT" ] && [ "$TOPIC_COUNT" -gt 0 ]; then
  echo "### Cached Topics: $TOPIC_COUNT"
fi
echo ""
echo "Cache is available. Use /dev-guides-navigator to find guides."
