#!/usr/bin/env bash
# recipe-key-check.sh — do this project's recorded process-recipe keys resolve to anything?
#
# The `**Process Recipes:**` block is the memory of a resolution decision, and every later phase
# reads it first to avoid re-resolving. A key that does not match the catalog is not a loud error:
# the block parses, reads authoritatively, and silently resolves nothing, so each phase falls back
# to a full lookup and the recorded decision is dead weight nobody notices.
#
# Seen live: a setup pass drove the lookup by hand instead of through `process-recipe-loader` and
# wrote each key's last segment from the catalog line's RECIPE NAME
# (`research/drupal/drupal_research_contrib_prior_art`) rather than from its URL SLUG
# (`research/drupal/contrib-prior-art`), which is what the navigator's key contract specifies. All
# six keys were wrong. Everything about the run looked right.
#
# The only ground truth is the catalog, so this compares against the cached process-recipes index
# rather than checking the key's shape — `drupal_research_contrib_prior_art` is a perfectly
# well-shaped segment and still resolves to nothing.
#
# Usage: recipe-key-check.sh <project_folder>
#
# Emits ONE JSON object and exits 0 always:
#   { status, index_status, checked, unresolvable, keys: [{key, phase, framework, slug, verdict,
#     expected_slug}], warnings[] }
#
# status:  ok        — every recorded key resolves
#          mismatch  — at least one does not
#          unknown   — no index cached, so nothing could be checked. NEVER reported as ok:
#                      not knowing is its own answer, and the whole point here is that a
#                      confident wrong answer is the failure being guarded against.
#          none      — no keys recorded; nothing to check
set -uo pipefail

PROJECT_DIR="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STORE_DIR="${DEV_GUIDES_STORE_DIR:-$HOME/.claude/dev-guides-store}"
INDEX="$STORE_DIR/indexes/process-recipes.json"

WARNINGS='[]'
add_warn(){ WARNINGS=$(jq -c --arg w "$1" '. + [$w]' <<<"$WARNINGS" 2>/dev/null || printf '[]'); }

if ! command -v jq >/dev/null 2>&1; then
  printf '{"status":"unknown","index_status":"jq_missing","checked":0,"unresolvable":0,"keys":[],"warnings":["jq_missing"]}\n'
  exit 0
fi

emit(){ # emit <status> <index_status> <keys_json>
  jq -n --arg s "$1" --arg i "$2" --argjson k "$3" --argjson w "$WARNINGS" \
    '{schema_version:"1.0", status:$s, index_status:$i,
      checked:($k|length),
      unresolvable:([$k[]|select(.verdict=="unresolvable")]|length),
      keys:$k, warnings:$w}'
  exit 0
}

# --- the recorded keys ----------------------------------------------------------
STATE=$(bash "$SCRIPT_DIR/project-state-read.sh" "$PROJECT_DIR" 2>/dev/null) || STATE=""
RECORDED=$(printf '%s' "$STATE" | jq -c '[.processRecipes[]? | .key] // []' 2>/dev/null) || RECORDED='[]'
[ -z "$RECORDED" ] && RECORDED='[]'
if [ "$(printf '%s' "$RECORDED" | jq 'length')" -eq 0 ]; then
  emit none not_read '[]'
fi

# --- the catalog ----------------------------------------------------------------
# Read the shared store's cached index the same way recipe-loader does. Never fetch, never invoke
# the navigator: this is a check, and a check that goes to the network is a check people turn off.
if [ ! -r "$INDEX" ]; then
  add_warn "process_recipes_index_not_cached"
  emit unknown absent "$(printf '%s' "$RECORDED" | jq -c '[.[] | {key:., verdict:"unchecked"}]')"
fi
CONTENT=$(jq -r '.content // ""' "$INDEX" 2>/dev/null)
if [ -z "$CONTENT" ]; then
  add_warn "process_recipes_index_empty"
  emit unknown empty "$(printf '%s' "$RECORDED" | jq -c '[.[] | {key:., verdict:"unchecked"}]')"
fi

# Catalog line grammar (navigator SKILL, "Process-Recipe Lookup"):
#   - <name> [phase=<phase> framework=<framework>] (sha:<sha8>): <when-to-use> — <site-url>
# The key's last segment is the site-url's trailing path segment, NOT <name>.
CATALOG=$(printf '%s' "$CONTENT" | awk '
  /^- .*\[phase=/ {
    line = $0
    phase = ""; fw = ""
    if (match(line, /phase=[^ \]]+/))     phase = substr(line, RSTART+6, RLENGTH-6)
    if (match(line, /framework=[^ \]]+/)) fw    = substr(line, RSTART+10, RLENGTH-10)
    # The site-url carries a trailing slash, so strip trailing whitespace AND slashes
    # before taking the last path segment — otherwise every slug comes out empty and the
    # check reports every key unresolvable, which is a worse failure than the one it guards.
    sub(/[[:space:]]+$/, "", line)
    sub(/\/+$/, "", line)
    n = split(line, parts, "/")
    slug = parts[n]
    sub(/\.md$/, "", slug)
    if (phase != "" && fw != "" && slug != "") print phase "/" fw "/" slug
  }
')

KEYS='[]'
BAD=0
while IFS= read -r K; do
  [ -z "$K" ] && continue
  PHASE="${K%%/*}"; REST="${K#*/}"; FW="${REST%%/*}"; SLUG="${REST#*/}"
  VERDICT="unresolvable"
  case "$CATALOG" in *"$K"*) VERDICT="ok" ;; esac
  # When it does not resolve, say what the catalog offers for that (phase, framework) — a check
  # that only says "wrong" costs a second investigation.
  EXPECTED=$(printf '%s\n' "$CATALOG" | awk -F/ -v p="$PHASE" -v f="$FW" '$1==p && $2==f {print $3}' | head -1)
  [ "$VERDICT" = "unresolvable" ] && BAD=$((BAD + 1))
  KEYS=$(jq -c --argjson a "$KEYS" --arg k "$K" --arg p "$PHASE" --arg f "$FW" --arg s "$SLUG" \
               --arg v "$VERDICT" --arg e "$EXPECTED" \
    -n '$a + [{key:$k, phase:$p, framework:$f, slug:$s, verdict:$v,
               expected_slug:(if $e=="" then null else $e end)}]')
done <<< "$(printf '%s' "$RECORDED" | jq -r '.[]')"

if [ "$BAD" -gt 0 ]; then emit mismatch present "$KEYS"; fi
emit ok present "$KEYS"
