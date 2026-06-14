#!/usr/bin/env bash
# dev-guides-store.sh — content-addressable store + per-project lockfile
# for dev-guides-navigator. Zero-model: pure bash/jq deterministic plumbing.
#
# Usage:
#   dev-guides-store.sh revalidate <index-name> <index-url> <hash-url>
#   dev-guides-store.sh index-content <index-name>
#   dev-guides-store.sh blob-put <key> [<file>] # reads stdin when <file> omitted
#   dev-guides-store.sh blob-get <key>
#   dev-guides-store.sh lock-read <project-memory-dir>
#   dev-guides-store.sh lock-set <project-memory-dir> <class> <key> <value-json>
#
# Store root: $DEV_GUIDES_STORE_DIR (default: ~/.claude/dev-guides-store/)
#
# Store layout:
#   <store>/indexes/<index-name>.json    { hash, fetched_at, content }
#   <store>/blobs/<sha256>               raw body bytes, content-addressed
#
# Lockfile: <project-memory-dir>/dev-guides.lock.json
#   { guides: {"topic/file": sha256}, task_recipes: {name: sha8},
#     process_recipes: {"phase/fw/url-slug": sha8} }
# All three classes are plain footprints of what a project touched; nothing is
# pinned. process_recipes values are plain sha8 strings, exactly like task_recipes.
#
# Exit codes:
#   0  success
#   2  usage / client error (incl. curl failures + empty responses in revalidate)
#   3  cache miss (blob-get, index-content)
#   4  integrity failure (blob-put: bytes do not hash to the claimed key)
#
# Portability: bash 3.2+ (macOS native bash). No mapfile, no declare -A,
# no bash-4-only features. Uses jq 1.6+ for --rawfile.

set -uo pipefail

# ---------------------------------------------------------------------------
# Store root — honour override so tests can point at a temp dir
# ---------------------------------------------------------------------------
STORE_DIR="${DEV_GUIDES_STORE_DIR:-$HOME/.claude/dev-guides-store}"

# ---------------------------------------------------------------------------
# Blob-key validation + content hashing (integrity + path-traversal defense)
# ---------------------------------------------------------------------------
# A blob key is content-addressed: a full sha256 (64 hex, guides) or its 8-char
# prefix (sha8, task/process recipes). Reject anything else BEFORE it is used as
# a path segment — this is what stops a hostile index/manifest value such as
# "../../../.bashrc" from escaping <store>/blobs/.
_is_hex_key() {
  case "$1" in
    "" | *[!0-9a-f]*) return 1 ;;
  esac
  [ "${#1}" -eq 8 ] || [ "${#1}" -eq 64 ]
}

# Print the lowercase hex sha256 of file $1 using the first available hasher, or
# nothing if none is installed (verification then degrades to skip — the key
# validation above still applies unconditionally).
_sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$1" | awk '{print $NF}'
  fi
}

# ---------------------------------------------------------------------------
# Subcommand dispatch on $1
# ---------------------------------------------------------------------------
CMD="${1:-}"

case "$CMD" in

# ---------------------------------------------------------------------------
# revalidate <index-name> <index-url> <hash-url>
#
# Two-hash N-index revalidation:
#   1. Fetch the tiny <hash-url> (the .hash file).
#   2. Compare to the stored .hash in the index JSON.
#   3. Equal → "fresh", exit 0, NO body fetch.
#   4. Different/absent → fetch <index-url>, write index JSON, "updated".
# ---------------------------------------------------------------------------
revalidate)
  if [ $# -lt 4 ]; then
    printf 'Usage: dev-guides-store.sh revalidate <index-name> <index-url> <hash-url>\n' >&2
    exit 2
  fi
  INDEX_NAME="$2"
  INDEX_URL="$3"
  HASH_URL="$4"
  INDEX_FILE="${STORE_DIR}/indexes/${INDEX_NAME}.json"

  # Read stored hash (absent index file → empty string → always-different)
  STORED_HASH=""
  if [ -f "$INDEX_FILE" ]; then
    STORED_HASH=$(jq -r '.hash // ""' "$INDEX_FILE" 2>/dev/null || true)
  fi

  # Fetch the remote hash file — curl supports file:// URLs for testing
  REMOTE_HASH_RAW=$(curl -fsSL "$HASH_URL" 2>/dev/null) || {
    jq -nc --arg n "$INDEX_NAME" --arg u "$HASH_URL" \
      '{index: $n, status: "error", detail: ("curl failed fetching hash-url: " + $u)}'
    exit 2
  }
  # Trim all whitespace; hash files commonly have a trailing newline
  REMOTE_HASH=$(printf '%s' "$REMOTE_HASH_RAW" | tr -d '[:space:]')

  # Guard an empty (200-with-empty-body) hash response: storing hash:"" would
  # never short-circuit, thrashing the cache, and pairs an empty hash with a
  # full re-fetch every call.
  if [ -z "$REMOTE_HASH" ]; then
    jq -nc --arg n "$INDEX_NAME" --arg u "$HASH_URL" \
      '{index: $n, status: "error", detail: ("hash-url returned an empty hash: " + $u)}'
    exit 2
  fi

  # Same hash → cache is fresh; skip body fetch
  if [ -n "$STORED_HASH" ] && [ "$STORED_HASH" = "$REMOTE_HASH" ]; then
    jq -nc --arg n "$INDEX_NAME" --arg h "$REMOTE_HASH" \
      '{index: $n, status: "fresh", hash: $h}'
    exit 0
  fi

  # Different or absent → fetch index body into a temp file.
  # Temp file preserves binary content exactly (avoids $() trailing-newline strip).
  TMP_BODY=$(mktemp)
  trap 'rm -f "$TMP_BODY"' EXIT

  if ! curl -fsSL -o "$TMP_BODY" "$INDEX_URL" 2>/dev/null; then
    rm -f "$TMP_BODY"
    trap - EXIT
    jq -nc --arg n "$INDEX_NAME" --arg u "$INDEX_URL" \
      '{index: $n, status: "error", detail: ("curl failed fetching index-url: " + $u)}'
    exit 2
  fi

  # Guard a 200-with-empty-body: storing it would poison the index cache
  # permanently — the matching hash short-circuits every future revalidate, so
  # the empty body is never re-fetched. Keep the previously-good index instead.
  if [ ! -s "$TMP_BODY" ]; then
    rm -f "$TMP_BODY"
    trap - EXIT
    jq -nc --arg n "$INDEX_NAME" --arg u "$INDEX_URL" \
      '{index: $n, status: "error", detail: ("index-url returned an empty body: " + $u)}'
    exit 2
  fi

  # Write index JSON — --rawfile safely encodes arbitrary text as a JSON string
  # (jq 1.6+; avoids the trailing-newline loss of $() + --arg).
  # Atomic: write to a sibling temp file then mv, so a crash mid-write cannot
  # leave a truncated index file.
  TS=$(date -u +%FT%TZ)
  mkdir -p "${STORE_DIR}/indexes"
  TMP_INDEX=$(mktemp "${STORE_DIR}/indexes/tmp.XXXXXX") || exit 2
  trap 'rm -f "$TMP_BODY" "$TMP_INDEX"' EXIT
  if ! { jq -n --arg h "$REMOTE_HASH" --arg ts "$TS" --rawfile content "$TMP_BODY" \
    '{hash: $h, fetched_at: $ts, content: $content}' > "$TMP_INDEX" && mv "$TMP_INDEX" "$INDEX_FILE"; }; then
    rm -f "$TMP_BODY" "$TMP_INDEX"
    trap - EXIT
    jq -nc --arg n "$INDEX_NAME" \
      '{index: $n, status: "error", detail: "failed writing index file"}'
    exit 2
  fi

  rm -f "$TMP_BODY"
  trap - EXIT

  jq -nc --arg n "$INDEX_NAME" --arg h "$REMOTE_HASH" \
    '{index: $n, status: "updated", hash: $h}'
  exit 0
  ;;

# ---------------------------------------------------------------------------
# index-content <index-name>
# Prints the cached raw index text to stdout (not the JSON envelope).
# Exit 3 on miss (no output).
# ---------------------------------------------------------------------------
index-content)
  if [ $# -lt 2 ]; then
    printf 'Usage: dev-guides-store.sh index-content <index-name>\n' >&2
    exit 2
  fi
  INDEX_NAME="$2"
  INDEX_FILE="${STORE_DIR}/indexes/${INDEX_NAME}.json"
  if [ ! -f "$INDEX_FILE" ]; then
    exit 3
  fi
  jq -r '.content' "$INDEX_FILE"
  exit 0
  ;;

# ---------------------------------------------------------------------------
# blob-put <key> [<file>]
# <key> is a CALLER-SUPPLIED content id: a full sha256 (64 hex, guides) or its
# 8-char prefix (sha8, recipes/process-recipes). The lockfile stores these same
# ids, so blobs are addressable by the exact id the caller already holds.
# <key> is validated as 8|64 lowercase hex (path-traversal defense) and the
# body's actual sha256 is verified against it (integrity) before it is stored.
# Body bytes come from <file> if given, else from STDIN.
# Writes <store>/blobs/<key> atomically (temp+mv, idempotent). Prints <key>.
# Empty/missing <key> → exit 2; invalid key → exit 2; digest mismatch → exit 4.
# ---------------------------------------------------------------------------
blob-put)
  if [ $# -lt 2 ] || [ -z "$2" ]; then
    printf 'dev-guides-store: blob-put requires a non-empty <key>\n' >&2
    printf 'Usage: dev-guides-store.sh blob-put <key> [<file>]\n' >&2
    exit 2
  fi
  BLOB_KEY="$2"
  if ! _is_hex_key "$BLOB_KEY"; then
    printf 'dev-guides-store: blob-put: invalid key (must be 8 or 64 lowercase hex): %s\n' "$BLOB_KEY" >&2
    exit 2
  fi
  BLOB_PATH="${STORE_DIR}/blobs/${BLOB_KEY}"

  mkdir -p "${STORE_DIR}/blobs"

  # Buffer the bytes to a sibling temp so the digest can be verified and the
  # final blob published atomically (a crash mid-write never leaves a partial
  # blob a concurrent reader could see).
  TMP_BLOB=$(mktemp "${STORE_DIR}/blobs/.tmp.XXXXXX") || exit 2
  trap 'rm -f "$TMP_BLOB"' EXIT
  if [ $# -ge 3 ] && [ -f "$3" ]; then
    if ! cp "$3" "$TMP_BLOB"; then
      printf 'dev-guides-store: blob-put: write failed for key %s\n' "$BLOB_KEY" >&2
      exit 2
    fi
  else
    if ! cat > "$TMP_BLOB"; then
      printf 'dev-guides-store: blob-put: write failed for key %s\n' "$BLOB_KEY" >&2
      exit 2
    fi
  fi

  # Integrity: the bytes must hash to the claimed key, so a tampered/truncated
  # fetch can never be stored under a trusted id and re-served to every project.
  # Degrades to skip only if no sha256 tool is installed (key validation above
  # still holds).
  ACTUAL=$(_sha256_of "$TMP_BLOB")
  if [ -n "$ACTUAL" ]; then
    if [ "${#BLOB_KEY}" -eq 8 ]; then
      EXPECT=$(printf '%s' "$ACTUAL" | cut -c1-8)
    else
      EXPECT="$ACTUAL"
    fi
    if [ "$EXPECT" != "$BLOB_KEY" ]; then
      printf 'dev-guides-store: blob-put: digest mismatch for key %s (bytes hash to %s)\n' "$BLOB_KEY" "$EXPECT" >&2
      exit 4
    fi
  fi

  if ! mv "$TMP_BLOB" "$BLOB_PATH"; then
    printf 'dev-guides-store: blob-put: publish failed for key %s\n' "$BLOB_KEY" >&2
    exit 2
  fi
  trap - EXIT
  printf '%s\n' "$BLOB_KEY"
  exit 0
  ;;

# ---------------------------------------------------------------------------
# blob-get <key>
# Prints blob bytes for the caller-supplied <key>; exit 3 on miss (no output).
# <key> is validated as 8|64 lowercase hex so a hostile id cannot traverse out
# of <store>/blobs/ to read an arbitrary file.
# ---------------------------------------------------------------------------
blob-get)
  if [ $# -lt 2 ]; then
    printf 'Usage: dev-guides-store.sh blob-get <key>\n' >&2
    exit 2
  fi
  BLOB_KEY="$2"
  if ! _is_hex_key "$BLOB_KEY"; then
    printf 'dev-guides-store: blob-get: invalid key (must be 8 or 64 lowercase hex): %s\n' "$BLOB_KEY" >&2
    exit 2
  fi
  BLOB_PATH="${STORE_DIR}/blobs/${BLOB_KEY}"
  if [ ! -f "$BLOB_PATH" ]; then
    exit 3
  fi
  cat "$BLOB_PATH"
  exit 0
  ;;

# ---------------------------------------------------------------------------
# lock-read <project-memory-dir>
# Prints the lockfile as compact JSON; absent or malformed → {}.
# Always exits 0.
# ---------------------------------------------------------------------------
lock-read)
  if [ $# -lt 2 ]; then
    printf 'Usage: dev-guides-store.sh lock-read <project-memory-dir>\n' >&2
    exit 2
  fi
  MEM_DIR="$2"
  LOCK_FILE="${MEM_DIR}/dev-guides.lock.json"
  if [ ! -f "$LOCK_FILE" ]; then
    printf '{}\n'
    exit 0
  fi
  # Defensive: validate first, emit once — prevents trailing-garbage input
  # from printing both a partial value AND the {} fallback.
  if jq -e . "$LOCK_FILE" >/dev/null 2>&1; then
    jq -c . "$LOCK_FILE"
  else
    printf '{}\n'
  fi
  exit 0
  ;;

# ---------------------------------------------------------------------------
# lock-set <project-memory-dir> <class> <key> <value-json>
# <class> must be one of: guides | task_recipes | process_recipes
# Merges .<class>[<key>] = <value-json> into the lockfile.
# Preserves all other top-level keys. Malformed existing lockfile → {}.
# Prints the updated lockfile (compact) and writes it. Exit 0 on success,
# exit 2 on invalid class or bad args.
# ---------------------------------------------------------------------------
lock-set)
  if [ $# -lt 5 ]; then
    printf 'Usage: dev-guides-store.sh lock-set <project-memory-dir> <class> <key> <value-json>\n' >&2
    exit 2
  fi
  MEM_DIR="$2"
  CLASS="$3"
  KEY="$4"
  VAL_JSON="$5"
  LOCK_FILE="${MEM_DIR}/dev-guides.lock.json"

  case "$CLASS" in
    guides|task_recipes|process_recipes) ;;
    *)
      printf 'dev-guides-store: invalid class "%s" — must be guides, task_recipes, or process_recipes\n' \
        "$CLASS" >&2
      exit 2
      ;;
  esac

  # Load existing or empty; treat malformed as {}
  EXISTING='{}'
  if [ -f "$LOCK_FILE" ]; then
    EXISTING=$(jq -c '.' "$LOCK_FILE" 2>/dev/null) || EXISTING='{}'
  fi

  mkdir -p "$MEM_DIR"

  # Ensure .<class> is an object (even if corrupt), then set the key.
  # All other top-level keys in the existing lockfile are preserved.
  # Fail-closed: if --argjson rejects invalid JSON, exit 2 WITHOUT touching $LOCK_FILE.
  UPDATED=$(printf '%s' "$EXISTING" | jq -c \
    --arg cls "$CLASS" --arg k "$KEY" --argjson v "$VAL_JSON" '
    .[$cls] = ((.[$cls] // {} | if type == "object" then . else {} end) | .[$k] = $v)
  ') || {
    printf 'dev-guides-store: lock-set: invalid value-json\n' >&2
    exit 2
  }
  [ -n "$UPDATED" ] || { printf 'dev-guides-store: lock-set: empty jq result\n' >&2; exit 2; }

  # Atomic write: temp-then-mv so a crash mid-write cannot destroy all entries.
  TMP_LOCK=$(mktemp "${LOCK_FILE}.tmp.XXXXXX") || exit 2
  printf '%s\n' "$UPDATED" > "$TMP_LOCK" && mv "$TMP_LOCK" "$LOCK_FILE" || {
    rm -f "$TMP_LOCK"
    exit 2
  }
  printf '%s\n' "$UPDATED"
  exit 0
  ;;

# ---------------------------------------------------------------------------
# legacy-recipes-shim <index-name> <class> <project-memory-dir>
#
# Compat shim. Rebuilds the legacy per-project dev-guides-recipes-cache.json
# that recipe-loader (ai-dev-assistant) reads directly, assembled from the new
# store: the cached index body + the lockfile <class> map + the blobs.
# Shape (matches the pre-0.9.0 cache recipe-loader expects):
#   { index: {hash,fetched_at,content},
#     recipes: { <name>: {sha, content} } }
# task_recipes and process_recipes values are both plain string sha8 now; the
# legacy {sha,...}-object form is still tolerated for back-compat. Body bytes
# read via --rawfile to preserve content.
# Index absent → exit 3 (caller must revalidate first). Idempotent: rebuilds
# the whole file each call. Symmetric with the Mode-1 guide-cache cp shim.
# ---------------------------------------------------------------------------
legacy-recipes-shim)
  if [ $# -lt 4 ]; then
    printf 'Usage: dev-guides-store.sh legacy-recipes-shim <index-name> <class> <project-memory-dir>\n' >&2
    exit 2
  fi
  INDEX_NAME="$2"
  CLASS="$3"
  MEM_DIR="$4"
  case "$CLASS" in
    guides|task_recipes|process_recipes) ;;
    *)
      printf 'dev-guides-store: legacy-recipes-shim: invalid class "%s"\n' "$CLASS" >&2
      exit 2
      ;;
  esac
  INDEX_FILE="${STORE_DIR}/indexes/${INDEX_NAME}.json"
  LOCK_FILE="${MEM_DIR}/dev-guides.lock.json"
  OUT_FILE="${MEM_DIR}/dev-guides-recipes-cache.json"

  [ -f "$INDEX_FILE" ] || exit 3
  INDEX_JSON=$(jq -c '{hash, fetched_at, content}' "$INDEX_FILE" 2>/dev/null) || exit 2

  # Assemble the recipes map from the lockfile <class> entries. Process
  # substitution (not a pipe) keeps the while loop in the main shell so RECIPES
  # accumulates. Missing blob for a recorded sha → skip that recipe.
  RECIPES='{}'
  if [ -f "$LOCK_FILE" ] && jq -e . "$LOCK_FILE" >/dev/null 2>&1; then
    while IFS=$'\t' read -r RNAME RSHA; do
      [ -n "$RNAME" ] || continue
      [ -n "$RSHA" ] || continue
      # Skip a sha that is not a valid content id — same traversal defense as
      # blob-get; a lockfile is just data and must not steer the path.
      _is_hex_key "$RSHA" || continue
      BLOB_PATH="${STORE_DIR}/blobs/${RSHA}"
      # Missing blob for a recorded sha → skip that recipe.
      [ -f "$BLOB_PATH" ] || continue
      RECIPES=$(printf '%s' "$RECIPES" | jq -c \
        --arg n "$RNAME" --arg s "$RSHA" --rawfile body "$BLOB_PATH" \
        '. + {($n): {sha: $s, content: $body}}') || continue
    done < <(jq -r --arg cls "$CLASS" '
      (.[$cls] // {}) | to_entries[]
      | [.key, (if (.value|type) == "string" then .value else (.value.sha // "") end)]
      | @tsv
    ' "$LOCK_FILE")
  fi

  mkdir -p "$MEM_DIR"
  TMP_OUT=$(mktemp "${OUT_FILE}.tmp.XXXXXX") || exit 2
  jq -nc --argjson index "$INDEX_JSON" --argjson recipes "$RECIPES" \
    '{index: $index, recipes: $recipes}' > "$TMP_OUT" && mv "$TMP_OUT" "$OUT_FILE" || {
    rm -f "$TMP_OUT"
    exit 2
  }
  exit 0
  ;;

# ---------------------------------------------------------------------------
# usage (no subcommand or unrecognised)
# ---------------------------------------------------------------------------
*)
  cat >&2 <<'USAGE'
dev-guides-store.sh — content-addressable store + project lockfile (dev-guides-navigator)

Subcommands:
  revalidate <index-name> <index-url> <hash-url>
      Two-hash N-index revalidation; prints {"index","status","hash"} JSON.
  index-content <index-name>
      Print cached raw index content; exit 3 on miss.
  blob-put <key> [<file>]
      Store bytes under caller-supplied <key> (stdin when no file); print <key>.
  blob-get <key>
      Print stored bytes; exit 3 on miss.
  lock-read <project-memory-dir>
      Print project dev-guides.lock.json (compact); absent/malformed → {}.
  lock-set <project-memory-dir> <class> <key> <value-json>
      Merge key into lockfile. <class>: guides | task_recipes | process_recipes
  legacy-recipes-shim <index-name> <class> <project-memory-dir>
      Rebuild the legacy dev-guides-recipes-cache.json from store+lockfile+blobs
      (compat shim for recipe-loader). Index absent → exit 3.

Store root: $DEV_GUIDES_STORE_DIR (default: ~/.claude/dev-guides-store/)

Exit codes:  0=success  2=usage/client-error  3=cache-miss
USAGE
  exit 2
  ;;
esac
