#!/usr/bin/env bash
# framework-support.sh: for a framework slug the caller has already identified, report what the
# dev-guides catalogs carry for it: process recipes, dedicated guides, agentic recipes.
#
# Usage: framework-support.sh <framework-slug> [--store <dir>]
#        framework-support.sh <slug> --process-catalog <f> --guides-catalog <f> --agentic-catalog <f>
#
# This script holds no framework list. It is handed a slug and looks it up. A slug the catalogs
# have never heard of is a perfectly good input and gets an honest empty answer.
#
# Output: one JSON object on stdout. Exit 0 always. The verdict is the answer, not the exit code.
# Exit 2 only on a missing slug argument.
#
# THE THREE CATALOGS ANSWER WITH DIFFERENT CONFIDENCE, and flattening that would be a lie:
#
#   process recipes  : keyed `[phase=<p> framework=<f>]`. A definitive yes or no, per phase.
#   guides           : keyed by the first path segment of the guide URL (`/dev-guides/<seg>/…`),
#                      which is the framework for framework-shaped topics. A definitive yes or no.
#   agentic recipes  : keyed `[<capability> framework=<f>]`, as of the dev-guides change of
#                      2026-08-27. A definitive yes or no, like the other two. Before that change
#                      the index carried no framework key at all and this could only be answered
#                      by grepping prose, so a stale cached index in the old format still yields
#                      `unknown`: reporting `none` for it would be a confident wrong answer, and
#                      "the catalog cannot be queried this way" is a different fact from "there
#                      are none".
#
# Verdicts: full | partial | none | unknown. `unknown` whenever a catalog could not be read.
# an uncached index means the question went unanswered, never that the answer is no.
#
# No writes. No network. No side effects.

set -uo pipefail

SLUG=""
STORE_DIR="${DEV_GUIDES_STORE_DIR:-$HOME/.claude/dev-guides-store}"
PROC_CAT=""; GUIDE_CAT=""; AGENT_CAT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --store)            STORE_DIR="${2:-}"; shift 2 ;;
    --process-catalog)  PROC_CAT="${2:-}"; shift 2 ;;
    --guides-catalog)   GUIDE_CAT="${2:-}"; shift 2 ;;
    --agentic-catalog)  AGENT_CAT="${2:-}"; shift 2 ;;
    -*) echo "framework-support: unknown arg '$1'" >&2; exit 2 ;;
    *)  [ -z "$SLUG" ] && SLUG="$1"; shift ;;
  esac
done

if [ -z "$SLUG" ]; then
  echo "Usage: framework-support.sh <framework-slug> [--store <dir>]" >&2
  exit 2
fi

[ -z "$PROC_CAT" ]  && PROC_CAT="$STORE_DIR/indexes/process-recipes.json"
[ -z "$GUIDE_CAT" ] && GUIDE_CAT="$STORE_DIR/indexes/llms.json"
[ -z "$AGENT_CAT" ] && AGENT_CAT="$STORE_DIR/indexes/agentic-recipes.json"

if ! command -v jq >/dev/null 2>&1; then
  printf '{"schema_version":"1.0","framework":"%s","verdict":"unknown","reason":"jq_missing"}\n' "$SLUG"
  exit 0
fi

read_content() { # <catalog path> → prints content, or nothing
  [ -f "$1" ] || return 1
  jq -r '.content // empty' "$1" 2>/dev/null
}

# ── process recipes: framework is an explicit key ────────────────────────────
PROC_STATUS="unknown"; PROC_PHASES='[]'; PROC_ENTRIES='[]'
if C=$(read_content "$PROC_CAT") && [ -n "$C" ]; then
  # The catalog header carries a format legend reading `[phase=<phase> framework=<framework>]`,
  # which parses exactly like a recipe entry. Before this guard, asking about the literal slug
  # `<framework>` reported a found recipe at phase `<phase>`: the documentation of the format
  # answering as though it were the thing it documents. A framework slug and a phase name never
  # contain angle brackets, so a token wrapped in them is a placeholder, not an answer.
  PROC_ENTRIES=$(printf '%s' "$C" | awk -v fw="$SLUG" '
    {
      f=""; p=""; s=""
      if (match($0, /framework=[^ \]]+/)) f = substr($0, RSTART+10, RLENGTH-10)
      if (match($0, /phase=[^ \]]+/))     p = substr($0, RSTART+6,  RLENGTH-6)
      if (match($0, /\(sha:[0-9a-f]+\)/)) s = substr($0, RSTART+5,  RLENGTH-6)
      if (f ~ /[<>]/ || p ~ /[<>]/) next
      if (f == fw && p != "") printf "%s\t%s\n", p, s
    }' | sort -u | jq -R -s -c 'split("\n") | map(select(length > 0) | split("\t") | {phase: .[0], sha: .[1]})')
  [ -z "$PROC_ENTRIES" ] && PROC_ENTRIES='[]'
  PROC_PHASES=$(jq -c '[.[].phase] | unique' <<<"$PROC_ENTRIES")
  if [ "$(jq 'length' <<<"$PROC_ENTRIES")" -gt 0 ]; then PROC_STATUS="found"; else PROC_STATUS="none"; fi
fi

# ── guides: framework is the first URL path segment ──────────────────────────
GUIDE_STATUS="unknown"; GUIDE_TOPICS='[]'
if C=$(read_content "$GUIDE_CAT") && [ -n "$C" ]; then
  GUIDE_TOPICS=$(printf '%s' "$C" | grep -oE "dev-guides/${SLUG}/[^)]*" 2>/dev/null \
    | sed "s|^dev-guides/||; s|/$||" | sort -u | head -100 \
    | jq -R -s -c 'split("\n") | map(select(length > 0))')
  [ -z "$GUIDE_TOPICS" ] && GUIDE_TOPICS='[]'
  if [ "$(jq 'length' <<<"$GUIDE_TOPICS")" -gt 0 ]; then GUIDE_STATUS="found"; else GUIDE_STATUS="none"; fi
fi

# ── agentic recipes: framework is a key on the entry line ────────────────────
AGENT_STATUS="unknown"; AGENT_REASON="catalog_unreadable"; AGENT_ENTRIES='[]'
if C=$(read_content "$AGENT_CAT") && [ -n "$C" ]; then
  # Entry lines only. The header carries a format legend containing a literal
  # `framework=<framework>` placeholder, which is documentation and not an entry; counting it
  # would make an old-format index look new and turn the stale-cache check below into a lie.
  ENTRY_LINES=$(printf '%s' "$C" | grep '^- ' 2>/dev/null || true)
  # `grep -c` prints 0 and exits 1 when nothing matches, so `|| echo 0` appends a SECOND zero
  # and the count becomes "0\n0". That made the integer test below error out and fall through to
  # the found/none branch, which reported `none` for an old-format index: the precise confident
  # wrong answer this whole third state exists to prevent.
  TOKEN_COUNT=$(printf '%s' "$ENTRY_LINES" | grep -c 'framework=[^ ]' 2>/dev/null) || true
  [ -n "$TOKEN_COUNT" ] || TOKEN_COUNT=0

  if [ "${TOKEN_COUNT:-0}" -eq 0 ]; then
    # Readable, and every entry predates the framework key. Not an error, and not an answer.
    AGENT_STATUS="unknown"
    AGENT_REASON="catalog_predates_framework_key"
  else
    # `framework=none` marks a deliberately stack-neutral recipe. It is a real value, so it is
    # never treated as a missing token, and a per-slug query must not match it.
    # `none` is the sentinel for a deliberately stack-neutral recipe, not a framework anyone
    # can be running, so a query for that literal string matches nothing rather than every
    # neutral recipe in the catalog.
    if [ "$SLUG" = "none" ]; then
      AGENT_ENTRIES='[]'
    else
    AGENT_ENTRIES=$(printf '%s' "$ENTRY_LINES" | awk -v fw="$SLUG" '
      {
        f = ""
        if (match($0, /framework=[^ \]]+/)) f = substr($0, RSTART+10, RLENGTH-10)
        sub(/\]$/, "", f)
        if (f == fw) { line = $0; sub(/^- /, "", line); print substr(line, 1, 200) }
      }' | head -60 | jq -R -s -c 'split("\n") | map(select(length > 0))')
    [ -z "$AGENT_ENTRIES" ] && AGENT_ENTRIES='[]'
    fi
    if [ "$(jq 'length' <<<"$AGENT_ENTRIES")" -gt 0 ]; then
      AGENT_STATUS="found"; AGENT_REASON=""
    else
      AGENT_STATUS="none"; AGENT_REASON=""
    fi
  fi
fi

# ── verdict ──────────────────────────────────────────────────────────────────
# All three catalogs count now that agentic recipes can be queried. `unknown` anywhere wins:
# a verdict of `none` while one catalog went unread would be the confident wrong answer this
# script exists to avoid.
FOUND=0
for st in "$PROC_STATUS" "$GUIDE_STATUS" "$AGENT_STATUS"; do
  [ "$st" = "found" ] && FOUND=$((FOUND + 1))
done
UNKNOWNS=0
for st in "$PROC_STATUS" "$GUIDE_STATUS" "$AGENT_STATUS"; do
  [ "$st" = "unknown" ] && UNKNOWNS=$((UNKNOWNS + 1))
done

# A found is a found. An unread catalog cannot take one away, so anything found makes the
# verdict at least `partial` even while another catalog went unread: support was confirmed, and
# reporting `unknown` there would hide a fact this script actually established. `unknown` is
# reserved for the case where it changes the answer, which is nothing found AND something unread:
# there, `none` would be the confident wrong answer. `full` needs all three, so it is never
# claimed on the strength of a catalog nobody could open.
if [ "$FOUND" -eq 3 ]; then
  VERDICT="full"
elif [ "$FOUND" -gt 0 ]; then
  VERDICT="partial"
elif [ "$UNKNOWNS" -gt 0 ]; then
  VERDICT="unknown"
else
  VERDICT="none"
fi

jq -n \
  --arg fw "$SLUG" --arg v "$VERDICT" \
  --arg ps "$PROC_STATUS" --argjson pp "$PROC_PHASES" --argjson pe "$PROC_ENTRIES" \
  --arg gs "$GUIDE_STATUS" --argjson gt "$GUIDE_TOPICS" \
  --arg as "$AGENT_STATUS" --arg ar "$AGENT_REASON" --argjson ac "$AGENT_ENTRIES" \
  --arg pc "$PROC_CAT" --arg gc "$GUIDE_CAT" --arg agc "$AGENT_CAT" \
  '{schema_version:"1.0",
    framework:$fw,
    verdict:$v,
    process_recipes:{status:$ps, phases:$pp, entries:$pe, catalog:$pc},
    guides:{status:$gs, topics:$gt, catalog:$gc},
    agentic_recipes:{status:$as, reason:(if $ar == "" then null else $ar end), entries:$ac, catalog:$agc},
    summary:{process_recipe_phases:($pp|length), guide_topics:($gt|length), agentic_recipes:($ac|length)}}'
