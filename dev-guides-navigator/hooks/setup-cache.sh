#!/usr/bin/env bash
# Setup hook: pre-warm the dev-guides llms.txt cache.
#
# Fires only on `claude --init-only`, `claude -p --init`, or `claude -p --maintenance`
# — never on normal interactive startup. Pure optimization: if anything below fails
# (no jq, no curl, network down), the navigator skill still fills the cache lazily
# on first use. The hook never blocks and never errors the session.
#
# Writes the {hash, fetched_at, content} schema documented in
# skills/dev-guides-navigator/references/cache-format.md (a cross-plugin contract).

set -u

command -v jq   >/dev/null 2>&1 || exit 0
command -v curl >/dev/null 2>&1 || exit 0

# Cache path: dasherized absolute cwd (see references/cache-format.md).
DASHED=$(printf '%s' "$PWD" | sed 's/[^a-zA-Z0-9]/-/g')
CACHE_DIR="$HOME/.claude/projects/${DASHED}/memory"
CACHE_FILE="${CACHE_DIR}/dev-guides-cache.json"

HASH=$(curl -fsS --max-time 10 https://camoa.github.io/dev-guides/llms.hash 2>/dev/null) || exit 0
[ -n "$HASH" ] || exit 0

# Already warm and current (has content + matching hash)? Nothing to do.
if [ -f "$CACHE_FILE" ]; then
  CACHED_HASH=$(jq -r '.hash // ""' "$CACHE_FILE" 2>/dev/null || echo "")
  HAS_CONTENT=$(jq -r 'has("content")' "$CACHE_FILE" 2>/dev/null || echo "false")
  if [ "$CACHED_HASH" = "$HASH" ] && [ "$HAS_CONTENT" = "true" ]; then
    echo '{"hookSpecificOutput":{"hookEventName":"Setup","additionalContext":"dev-guides cache already warm and current."}}'
    exit 0
  fi
fi

CONTENT=$(curl -fsS --max-time 20 https://camoa.github.io/dev-guides/llms.txt 2>/dev/null) || exit 0
[ -n "$CONTENT" ] || exit 0

mkdir -p "$CACHE_DIR" 2>/dev/null || exit 0
FETCHED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

jq -n --arg hash "$HASH" --arg fetched_at "$FETCHED_AT" --arg content "$CONTENT" \
  '{hash: $hash, fetched_at: $fetched_at, content: $content}' > "$CACHE_FILE" 2>/dev/null || exit 0

echo "{\"hookSpecificOutput\":{\"hookEventName\":\"Setup\",\"additionalContext\":\"dev-guides llms.txt cache pre-warmed at ${CACHE_FILE}.\"}}"
exit 0
