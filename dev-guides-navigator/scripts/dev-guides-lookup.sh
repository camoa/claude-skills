#!/usr/bin/env bash
# dev-guides-lookup.sh — the navigator's six lookup modes, one script call each.
#
# The skill body used to give each mode as an inline compound shell block. A
# Claude Code session isolated in a git worktree refuses a compound command it
# cannot prove stays inside the worktree, so the flows live here and the skill
# runs one plain command with arguments. Every store operation still goes
# through dev-guides-store.sh; this script never writes the store itself.
#
# Usage:
#   dev-guides-lookup.sh guide <words...>                    # step 1-2: candidate topics
#   dev-guides-lookup.sh guide --topic <topic-path>          # step 3: the topic's routing table
#   dev-guides-lookup.sh guide --topic <topic-path> --file <file.md>   # step 6: the body's store path
#   dev-guides-lookup.sh recipe <words...>                   # step 1-2: candidate recipes
#   dev-guides-lookup.sh recipe --name <name>                # step 3: the body's store path
#   dev-guides-lookup.sh process-recipe <phase> <framework>  # one JSON report
#   dev-guides-lookup.sh identify <words...> [--framework <fw>]        # one JSON report
#   dev-guides-lookup.sh playbook <set-id>                   # one JSON report
#   dev-guides-lookup.sh tooling --name <name>               # a tooling recipe body's store path
#
# Output: `key: value` lines and paths, or the mode's JSON report. A guide or
# recipe body is not printed; the caller reads the file at body_path. Two
# exceptions: the topic routing table (guide --topic) is printed, because
# choosing a guide from it is the caller's decision, and a guide body whose
# manifest is unreachable has no store path, so it follows a `body:` line.
#
# Overrides, for fixtures: DEV_GUIDES_SITE_URL (default https://camoa.github.io/dev-guides),
# DEV_GUIDES_RAW_URL (default https://raw.githubusercontent.com/camoa/dev-guides/main/docs),
# DEV_GUIDES_STORE_DIR (read by the store script).
#
# Exit codes: 0 done, including every "not found" report; 2 usage or a fetch
# the mode cannot continue without.
#
# Portability: bash 3.2 and zsh. No arrays, no mapfile, no [[ ]].

set -uo pipefail
trap '' PIPE

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
STORE_SH="${SCRIPT_DIR}/dev-guides-store.sh"
STORE_ROOT="${DEV_GUIDES_STORE_DIR:-$HOME/.claude/dev-guides-store}"
SITE_BASE="${DEV_GUIDES_SITE_URL:-https://camoa.github.io/dev-guides}"
RAW_BASE="${DEV_GUIDES_RAW_URL:-https://raw.githubusercontent.com/camoa/dev-guides/main/docs}"

usage() {
  cat >&2 <<'USAGE'
Usage:
  dev-guides-lookup.sh guide <words...>
  dev-guides-lookup.sh guide --topic <topic-path> [--file <file.md>]
  dev-guides-lookup.sh recipe <words...>
  dev-guides-lookup.sh recipe --name <name>
  dev-guides-lookup.sh process-recipe <phase> <framework>
  dev-guides-lookup.sh identify <words...> [--framework <fw>]
  dev-guides-lookup.sh playbook <set-id>
  dev-guides-lookup.sh tooling --name <name>
USAGE
  exit 2
}

# The project memory dir, the same derivation the legacy cache files use.
mem_dir() {
  DASHED=$(printf '%s' "$PWD" | sed 's/[^a-zA-Z0-9]/-/g')
  printf '%s\n' "$HOME/.claude/projects/${DASHED}/memory"
}

# revalidate <index-name>; prints the store's JSON status line on stdout.
revalidate() {
  "$STORE_SH" revalidate "$1" "${SITE_BASE}/$1.txt" "${SITE_BASE}/$1.hash"
}

# raw_url_of <site-url>: the raw markdown address for a catalog line's site-url.
# Refuses a site-url that does not begin with the site prefix, because the
# prefix replace would otherwise be a no-op and leave an attacker-controlled
# value for curl (the SSRF guard the body states). Exit 1 on refusal.
raw_url_of() {
  REST="${1#"${SITE_BASE}/"}"
  [ "$REST" != "$1" ] || return 1
  REST="${REST%/}"
  printf '%s\n' "${RAW_BASE}/${REST}.md"
}

# candidate_lines <index-text> <words...>: the index lines that contain any word.
candidate_lines() {
  TEXT="$1"
  shift
  printf '%s\n' "$TEXT" | grep '^- ' | while IFS= read -r LINE; do
    for W in "$@"; do
      if printf '%s' "$LINE" | grep -qiF -- "$W"; then
        printf '%s\n' "$LINE"
        break
      fi
    done
  done
}

# body_by_name <index-name> <lock-class> <name>: recipe search step 3, and the tooling
# mode. Resolves <name> in the cached index, serves or fetches the body by the line's
# sha8, and records the footprint under <lock-class>. Returns 0 only after a new fetch,
# 1 on a miss or a cached hit. Exit 2 on a fetch or store failure.
body_by_name() {
  INDEX_TEXT=$("$STORE_SH" index-content "$1") || {
    printf 'result: not-found\n'
    printf 'reason: no index cached\n'
    return 1
  }
  MATCH_LINE=$(printf '%s\n' "$INDEX_TEXT" | grep -F -- "- ${3} [" | head -n 1)
  if [ -z "$MATCH_LINE" ]; then
    printf 'result: not-found\n'
    printf 'reason: no recipe named %s; fall back to guide search\n' "$3"
    return 1
  fi
  SHA8=$(printf '%s' "$MATCH_LINE" | sed 's/.*sha:\([^)]*\).*/\1/')
  SITE_URL=$(printf '%s' "$MATCH_LINE" | awk -F' — ' '{print $NF}' | tr -d '\n\r')
  printf 'name: %s\n' "$3"
  printf 'sha: %s\n' "$SHA8"
  if "$STORE_SH" blob-get "$SHA8" >/dev/null 2>&1; then
    printf 'cached: true\n'
    printf 'body_path: %s\n' "${STORE_ROOT}/blobs/${SHA8}"
    return 1
  fi
  RAW_URL=$(raw_url_of "$SITE_URL") || {
    printf 'result: not-found\n'
    printf 'reason: refusing non-canonical body URL\n'
    return 1
  }
  TMP=$(mktemp)
  if ! curl -fsSL -o "$TMP" "$RAW_URL" 2>/dev/null; then
    rm -f "$TMP"
    printf 'status: error\n'
    printf 'detail: could not fetch %s\n' "$RAW_URL"
    exit 2
  fi
  "$STORE_SH" blob-put "$SHA8" "$TMP" >/dev/null || { rm -f "$TMP"; exit 2; }
  rm -f "$TMP"
  MEM_DIR=$(mem_dir)
  mkdir -p "$MEM_DIR"
  "$STORE_SH" lock-set "$MEM_DIR" "$2" "$3" "\"${SHA8}\"" >/dev/null
  printf 'cached: false\n'
  printf 'body_path: %s\n' "${STORE_ROOT}/blobs/${SHA8}"
}

CMD="${1:-}"
[ $# -ge 1 ] && shift

case "$CMD" in

# ---------------------------------------------------------------------------
# guide <words...> | guide --topic <topic> [--file <file>]
# ---------------------------------------------------------------------------
guide)
  TOPIC=""
  FILE=""
  if [ "${1:-}" = "--topic" ]; then
    TOPIC="${2:-}"
    [ -n "$TOPIC" ] || usage
    shift 2
    if [ "${1:-}" = "--file" ]; then
      FILE="${2:-}"
      [ -n "$FILE" ] || usage
    fi
  else
    [ $# -ge 1 ] || usage
  fi

  if [ -z "$TOPIC" ]; then
    # Step 1: revalidate llms.txt. On error, serve the store's last-fetched
    # index when one exists (references/troubleshooting.md), else stop.
    RESULT=$(revalidate llms)
    STATUS=$(printf '%s' "$RESULT" | jq -r '.status')
    printf 'status: %s\n' "$STATUS"
    if [ "$STATUS" = "error" ]; then
      printf 'detail: %s\n' "$(printf '%s' "$RESULT" | jq -r '.detail')"
      if [ ! -f "${STORE_ROOT}/indexes/llms.json" ]; then
        printf 'result: index unavailable and nothing cached\n'
        exit 2
      fi
      printf 'fallback: last-fetched index\n'
    fi
    INDEX_TEXT=$("$STORE_SH" index-content llms) || exit 2

    # Legacy shim: ai-dev-assistant reads dev-guides-cache.json at the dashed-cwd path.
    LEGACY_DIR=$(mem_dir)
    mkdir -p "$LEGACY_DIR"
    cp "${STORE_ROOT}/indexes/llms.json" "${LEGACY_DIR}/dev-guides-cache.json"

    # Step 2 is the caller's match. Print the lines any search word hits.
    CANDIDATES=$(candidate_lines "$INDEX_TEXT" "$@")
    if [ -z "$CANDIDATES" ]; then
      printf 'candidates: 0\n'
      printf 'index: %s\n' "${STORE_ROOT}/indexes/llms.json"
      exit 0
    fi
    printf 'candidates: %s\n' "$(printf '%s\n' "$CANDIDATES" | grep -c '^- ')"
    printf '%s\n' "$CANDIDATES"
    exit 0
  fi

  if [ -z "$FILE" ]; then
    # Step 3: the topic's routing table, raw markdown, printed for the caller to choose from.
    printf 'topic: %s\n' "$TOPIC"
    INDEX_MD=$(curl -fsSL "${RAW_BASE}/${TOPIC}/index.md" 2>/dev/null) || {
      printf 'status: error\n'
      printf 'detail: could not fetch %s\n' "${RAW_BASE}/${TOPIC}/index.md"
      exit 2
    }
    printf '%s\n' "$INDEX_MD"
    exit 0
  fi

  # Step 6: the body, served from the blob store, fetched once per content version.
  # guide-index.json is fetched on use and never gated by llms.hash: a body edit
  # changes its sha256 here while llms.txt can stay unchanged.
  MANIFEST=$(curl -fsSL "${SITE_BASE}/${TOPIC}/guide-index.json" 2>/dev/null) || MANIFEST=""
  SHA256=$(printf '%s' "$MANIFEST" | jq -r --arg f "$FILE" '.[$f] // ""' 2>/dev/null) || SHA256=""
  printf 'topic: %s\n' "$TOPIC"
  printf 'file: %s\n' "$FILE"
  if [ -n "$SHA256" ] && "$STORE_SH" blob-get "$SHA256" >/dev/null 2>&1; then
    printf 'sha256: %s\n' "$SHA256"
    printf 'cached: true\n'
    printf 'body_path: %s\n' "${STORE_ROOT}/blobs/${SHA256}"
    exit 0
  fi
  TMP=$(mktemp)
  trap 'rm -f "$TMP"' EXIT
  if ! curl -fsSL -o "$TMP" "${RAW_BASE}/${TOPIC}/${FILE}" 2>/dev/null; then
    printf 'status: error\n'
    printf 'detail: could not fetch %s\n' "${RAW_BASE}/${TOPIC}/${FILE}"
    exit 2
  fi
  if [ -n "$SHA256" ]; then
    "$STORE_SH" blob-put "$SHA256" "$TMP" >/dev/null || exit 2
    MEM_DIR=$(mem_dir)
    mkdir -p "$MEM_DIR"
    "$STORE_SH" lock-set "$MEM_DIR" guides "${TOPIC}/${FILE}" "\"${SHA256}\"" >/dev/null
    printf 'sha256: %s\n' "$SHA256"
    printf 'cached: false\n'
    printf 'body_path: %s\n' "${STORE_ROOT}/blobs/${SHA256}"
    exit 0
  fi
  # Manifest unavailable: the body is served uncached this turn (graceful degradation).
  # No store path exists for it, so the body follows the summary lines on stdout.
  printf 'sha256: \n'
  printf 'cached: false\n'
  printf 'body_path: \n'
  printf 'body:\n'
  cat "$TMP"
  exit 0
  ;;

# ---------------------------------------------------------------------------
# recipe <words...> | recipe --name <name>
# ---------------------------------------------------------------------------
recipe)
  NAME=""
  if [ "${1:-}" = "--name" ]; then
    NAME="${2:-}"
    [ -n "$NAME" ] || usage
  else
    [ $# -ge 1 ] || usage
  fi
  MEM_DIR=$(mem_dir)

  if [ -z "$NAME" ]; then
    # Step 1: revalidate agentic-recipes.txt. On error, serve the store's last-fetched
    # index when one exists, the guide mode's rule; else stop. Nothing is fabricated.
    RESULT=$(revalidate agentic-recipes)
    STATUS=$(printf '%s' "$RESULT" | jq -r '.status')
    printf 'status: %s\n' "$STATUS"
    if [ "$STATUS" = "error" ]; then
      printf 'detail: %s\n' "$(printf '%s' "$RESULT" | jq -r '.detail')"
      if [ ! -f "${STORE_ROOT}/indexes/agentic-recipes.json" ]; then
        printf 'result: index unavailable and nothing cached\n'
        exit 2
      fi
      printf 'fallback: last-fetched index\n'
    fi
    INDEX_TEXT=$("$STORE_SH" index-content agentic-recipes) || exit 2
    # Compat shim, rebuilt before any body fetch so a recipe-loader index match works.
    "$STORE_SH" legacy-recipes-shim agentic-recipes task_recipes "$MEM_DIR" 2>/dev/null || true

    # Step 2 is the caller's match on capability and when-to-use. No body is fetched here.
    CANDIDATES=$(candidate_lines "$INDEX_TEXT" "$@")
    if [ -z "$CANDIDATES" ]; then
      printf 'candidates: 0\n'
      printf 'result: not-found\n'
      printf 'reason: no recipe for this capability; fall back to guide search\n'
      exit 0
    fi
    printf 'candidates: %s\n' "$(printf '%s\n' "$CANDIDATES" | grep -c '^- ')"
    printf '%s\n' "$CANDIDATES"
    exit 0
  fi

  # Step 3: the body, downloaded once per content version.
  # Refresh the compat shim after a new fetch, so the recipe is visible to recipe-loader.
  if body_by_name agentic-recipes task_recipes "$NAME"; then
    "$STORE_SH" legacy-recipes-shim agentic-recipes task_recipes "$MEM_DIR" 2>/dev/null || true
  fi
  exit 0
  ;;

# ---------------------------------------------------------------------------
# tooling --name <name>
# ---------------------------------------------------------------------------
tooling)
  [ "${1:-}" = "--name" ] && [ -n "${2:-}" ] || usage
  body_by_name tooling-recipes tooling_recipes "$2"
  exit 0
  ;;

# ---------------------------------------------------------------------------
# process-recipe <phase> <framework>
# ---------------------------------------------------------------------------
process-recipe)
  [ $# -ge 2 ] || usage
  PHASE="$1"
  FRAMEWORK="$2"

  # Step 1: revalidate the index. Error or nothing cached: report and stop.
  RESULT=$(revalidate process-recipes)
  STATUS=$(printf '%s' "$RESULT" | jq -r '.status')
  if [ "$STATUS" = "error" ]; then
    printf '{"key":null,"available":false,"reason":"index unavailable or network error"}\n'
    exit 0
  fi
  INDEX_TEXT=$("$STORE_SH" index-content process-recipes 2>/dev/null) || {
    printf '{"key":null,"available":false,"reason":"no index cached"}\n'
    exit 0
  }

  # Step 2: match (phase, framework) in the bracket.
  MATCH_LINE=$(printf '%s\n' "$INDEX_TEXT" | grep '^- ' | grep -F -- "[phase=${PHASE} framework=${FRAMEWORK}]" | head -n 1)
  if [ -z "$MATCH_LINE" ]; then
    printf '{"key":null,"available":false}\n'
    exit 0
  fi
  SHA8=$(printf '%s' "$MATCH_LINE" | sed 's/.*sha:\([^)]*\).*/\1/')
  # The LAST ' — ' field: when-to-use descriptions legitimately contain ' — '.
  SITE_URL=$(printf '%s' "$MATCH_LINE" | awk -F' — ' '{print $NF}' | tr -d '\n\r')
  # url-slug is the trailing path segment of the site-url (store-contract.md), not <name>.
  SLUG=$(printf '%s' "$SITE_URL" | sed 's#/*$##; s#.*/##')
  KEY="${PHASE}/${FRAMEWORK}/${SLUG}"

  # Step 3: fetch the body only when its sha's blob is absent, then record the footprint.
  BLOB_PATH="${STORE_ROOT}/blobs/${SHA8}"
  if [ ! -f "$BLOB_PATH" ]; then
    RAW_URL=$(raw_url_of "$SITE_URL") || {
      printf '{"key":null,"available":false,"reason":"refusing non-canonical body URL"}\n'
      exit 0
    }
    TMP=$(mktemp)
    if ! curl -fsSL -o "$TMP" "$RAW_URL" 2>/dev/null || ! "$STORE_SH" blob-put "$SHA8" "$TMP" >/dev/null; then
      rm -f "$TMP"
      jq -nc --arg k "$KEY" '{key:$k, available:false, reason:"body fetch failed"}'
      exit 0
    fi
    rm -f "$TMP"
  fi
  MEM_DIR=$(mem_dir)
  mkdir -p "$MEM_DIR"
  "$STORE_SH" lock-set "$MEM_DIR" process_recipes "$KEY" "\"${SHA8}\"" >/dev/null
  printf '{"key":"%s","available":true,"sha":"%s","body_path":"%s","body_cached":true}\n' \
    "$KEY" "$SHA8" "$BLOB_PATH"
  exit 0
  ;;

# ---------------------------------------------------------------------------
# identify <words...> [--framework <fw>]
# ---------------------------------------------------------------------------
identify)
  # Pull --framework out of the arguments; what remains in "$@" are the words.
  FRAMEWORK=""
  N=$#
  while [ "$N" -gt 0 ]; do
    ARG="$1"
    shift
    N=$((N - 1))
    if [ "$ARG" = "--framework" ]; then
      FRAMEWORK="${1:-}"
      [ -n "$FRAMEWORK" ] || usage
      shift
      N=$((N - 1))
      continue
    fi
    set -- ${1+"$@"} "$ARG"
  done
  [ $# -ge 1 ] || usage
  WORDS="$*"
  WORK=$(mktemp -d)

  # Step 1: revalidate each catalog on its own. An index that errors is unavailable by name.
  SEARCHED=""
  UNAVAILABLE=""
  for CATALOG in llms agentic-recipes tooling-recipes; do
    case "$CATALOG" in
      llms) SHORT="guides" ;;
      *) SHORT="$CATALOG" ;;
    esac
    RESULT=$(revalidate "$CATALOG")
    if [ "$(printf '%s' "$RESULT" | jq -r '.status')" = "error" ]; then
      UNAVAILABLE="${UNAVAILABLE}${SHORT}$(printf '\037')no published index$(printf '\036')"
      continue
    fi
    TEXT=$("$STORE_SH" index-content "$CATALOG" 2>/dev/null) || {
      UNAVAILABLE="${UNAVAILABLE}${SHORT}$(printf '\037')no index cached$(printf '\036')"
      continue
    }
    SEARCHED="${SEARCHED}${SHORT}$(printf '\036')"
    printf '%s\n' "$TEXT" > "${WORK}/${CATALOG}"
  done

  # The framework names the catalogs know, for the guide-line filter below.
  FW_KNOWN=$(cat "${WORK}"/* 2>/dev/null | grep -o 'framework=[a-z0-9-]*' | sed 's/framework=//' | sort -u)

  # Step 2: match the words against name and when-to-use, drop lines of another
  # framework, and rank by how many words hit. Records are 0x1f-separated.
  RECORDS=""
  for CATALOG in llms agentic-recipes tooling-recipes; do
    TEXT_FILE="${WORK}/${CATALOG}"
    [ -f "$TEXT_FILE" ] || continue
    case "$CATALOG" in
      llms) KIND="guide" ;;
      agentic-recipes) KIND="agentic-recipe" ;;
      *) KIND="tooling-recipe" ;;
    esac
    while IFS= read -r LINE; do
      case "$LINE" in
        "- "*) ;;
        *) continue ;;
      esac
      if [ "$KIND" = "guide" ]; then
        NAME=$(printf '%s' "$LINE" | sed 's/^- \[\([^]]*\)\].*/\1/')
        URL=$(printf '%s' "$LINE" | sed 's/^- \[[^]]*\](\([^)]*\)).*/\1/')
        DESC=$(printf '%s' "$LINE" | sed 's/^- \[[^]]*\]([^)]*): //; s/^[0-9]* guides — //')
        SHA=""
        LINE_FW="${URL#"${SITE_BASE}/"}"
        LINE_FW="${LINE_FW%%/*}"
      else
        NAME=$(printf '%s' "$LINE" | sed 's/^- \([^ ]*\) .*/\1/')
        URL=$(printf '%s' "$LINE" | awk -F' — ' '{print $NF}' | tr -d '\n\r')
        SHA=$(printf '%s' "$LINE" | sed 's/.*(sha:\([^)]*\)).*/\1/')
        DESC=$(printf '%s' "$LINE" | sed 's/^- [^(]*([^)]*): //')
        DESC="${DESC% — *}"
        LINE_FW=$(printf '%s' "$LINE" | sed -n 's/.*framework=\([^] ]*\).*/\1/p')
      fi
      if [ -n "$FRAMEWORK" ] && [ -n "$LINE_FW" ] && [ "$LINE_FW" != "$FRAMEWORK" ] && [ "$LINE_FW" != "none" ]; then
        # A guide line belongs to a framework only when its first path segment names one.
        if [ "$KIND" != "guide" ] || printf '%s\n' "$FW_KNOWN" | grep -qx -- "$LINE_FW"; then
          continue
        fi
      fi
      SCORE=0
      for W in "$@"; do
        if printf '%s %s' "$NAME" "$DESC" | grep -qiF -- "$W"; then
          SCORE=$((SCORE + 1))
        fi
      done
      [ "$SCORE" -gt 0 ] || continue
      RECORDS="${RECORDS}${SCORE}$(printf '\037')${KIND}$(printf '\037')${NAME}$(printf '\037')${DESC}$(printf '\037')${URL}$(printf '\037')${SHA}$(printf '\036')"
    done < "$TEXT_FILE"
  done
  rm -rf "$WORK"

  # Step 3: the report, and nothing else.
  FW_JSON="null"
  [ -z "$FRAMEWORK" ] || FW_JSON=$(jq -n --arg f "$FRAMEWORK" '$f')
  jq -n -c \
    --arg q "$WORDS" --argjson f "$FW_JSON" \
    --arg records "$RECORDS" --arg searched "$SEARCHED" --arg unavailable "$UNAVAILABLE" '
    {
      query: $q,
      framework: $f,
      matches: ($records | split("") | map(select(length > 0) | split("")
        | {score: (.[0] | tonumber), kind: .[1], name: .[2], description: .[3], url: .[4],
           sha: (if .[5] == "" then null else .[5] end)})
        | sort_by(-.score) | map(del(.score))),
      searched: ($searched | split("") | map(select(length > 0))),
      unavailable: ($unavailable | split("") | map(select(length > 0) | split("")
        | {catalog: .[0], reason: .[1]}))
    }'
  exit 0
  ;;

# ---------------------------------------------------------------------------
# playbook <set-id>
# ---------------------------------------------------------------------------
playbook)
  [ $# -ge 1 ] || usage
  SET_ID="$1"

  # Step 1: the set's line in llms.txt.
  RESULT=$(revalidate llms)
  if [ "$(printf '%s' "$RESULT" | jq -r '.status')" = "error" ]; then
    jq -nc --arg s "$SET_ID" '{set:$s, available:false, reason:"listing-unreachable"}'
    exit 0
  fi
  INDEX_TEXT=$("$STORE_SH" index-content llms 2>/dev/null) || {
    jq -nc --arg s "$SET_ID" '{set:$s, available:false, reason:"listing-unreachable"}'
    exit 0
  }
  # A set id is a topic path. Refuse anything that could leave the site prefix.
  case "$SET_ID" in
    "" | /* | */ | *..* | *[!a-z0-9./-]*)
      jq -nc --arg s "$SET_ID" '{set:$s, available:false, reason:"no-topic"}'
      exit 0 ;;
  esac
  SITE_URL="${SITE_BASE}/${SET_ID}/"
  MATCH_LINE=$(printf '%s\n' "$INDEX_TEXT" | grep -F -- "](${SITE_URL})" | head -n 1)
  if [ -z "$MATCH_LINE" ]; then
    jq -nc --arg s "$SET_ID" '{set:$s, available:false, reason:"no-topic"}'
    exit 0
  fi
  TITLE=$(printf '%s' "$MATCH_LINE" | sed 's/^- \[\([^]]*\)\].*/\1/')

  # Step 2: fetch plays.json. No .hash sidecar exists, so it is fetched on every call.
  TMP=$(mktemp)
  HTTP=$(curl -fsSL -o "$TMP" -w '%{http_code}' "${SITE_URL}plays.json" 2>/dev/null)
  CURL_EXIT=$?
  if [ "$HTTP" = "404" ]; then
    rm -f "$TMP"
    jq -nc --arg s "$SET_ID" '{set:$s, available:false, reason:"not-a-playbook"}'
    exit 0
  fi
  if [ "$CURL_EXIT" -ne 0 ] || ! jq -e 'type == "array"' "$TMP" >/dev/null 2>&1; then
    rm -f "$TMP"
    jq -nc --arg s "$SET_ID" '{set:$s, available:false, reason:"fetch-failed"}'
    exit 0
  fi

  # Step 3: store the body under its own sha256, record the footprint, report.
  # The hex digest is the first 64 characters of either tool's line.
  SHA256=$( (sha256sum "$TMP" 2>/dev/null || shasum -a 256 "$TMP") | cut -c1-64)
  "$STORE_SH" blob-put "$SHA256" "$TMP" >/dev/null || { rm -f "$TMP"; exit 2; }
  rm -f "$TMP"
  BODY_PATH="${STORE_ROOT}/blobs/${SHA256}"
  MEM_DIR=$(mem_dir)
  mkdir -p "$MEM_DIR"
  "$STORE_SH" lock-set "$MEM_DIR" playbooks "$SET_ID" "\"${SHA256}\"" >/dev/null
  jq -n -c --arg s "$SET_ID" --arg t "$TITLE" --arg p "$BODY_PATH" \
    --arg h "$(printf '%s' "$SHA256" | cut -c1-8)" --argjson n "$(jq 'length' "$BODY_PATH")" \
    '{set:$s, title:$t, available:true, body_path:$p, sha:$h, plays:$n}'
  exit 0
  ;;

*)
  usage
  ;;
esac
