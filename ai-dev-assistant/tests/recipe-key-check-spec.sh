#!/usr/bin/env bash
# recipe-key-check-spec.sh — a recorded key that resolves to nothing.
#
# The failure this guards is quiet by construction. The **Process Recipes:** block parses, reads
# authoritatively, and matches no catalog entry, so every phase silently re-resolves and the
# recorded decision is dead weight. Observed live: a setup pass drove the lookup by hand and wrote
# each key's last segment from the catalog line's recipe NAME rather than its URL SLUG. Six keys,
# all wrong, nothing anywhere said so.

set -eu
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
K="${PLUGIN_ROOT}/scripts/recipe-key-check.sh"

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }
[ -x "$K" ] || { printf 'FAIL: %s not executable\n' "$K" >&2; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
STORE="$T/store"; mkdir -p "$STORE/indexes"

# A catalog whose lines carry the real grammar, trailing slash included — the trailing slash is
# what made the first version of this check report every key unresolvable.
python3 - "$STORE/indexes/process-recipes.json" <<'PY'
import json,sys
lines = [
 "## Drupal",
 "- demo_research_prior_art [phase=research framework=demo] (sha:aaaaaaaa): find prior art — https://example.test/dev-guides/process-recipes/demo/prior-art/",
 "- demo_design_architecture [phase=design framework=demo] (sha:bbbbbbbb): design it — https://example.test/dev-guides/process-recipes/demo/architecture/",
]
json.dump({"content":"\n".join(lines)}, open(sys.argv[1],"w"))
PY

proj() { # proj <name> <key-line>...
  local d="$T/$1"; mkdir -p "$d"; shift
  { printf '# P\n**Process Recipes:**\n'; for l in "$@"; do printf -- '- %s → source=dev-guides\n' "$l"; done; } > "$d/project_state.md"
  printf '%s' "$d"
}
run() { DEV_GUIDES_STORE_DIR="$STORE" bash "$K" "$1" 2>/dev/null; }

# --- keys built from the URL slug resolve --------------------------------------
GOOD=$(proj good "research/demo/prior-art" "design/demo/architecture")
OUT=$(run "$GOOD")
[ "$(printf '%s' "$OUT" | jq -r .status)" = "ok" ] \
  && pass_check "keys built from the url slug resolve" \
  || fail_check "correct keys must resolve, got $(printf '%s' "$OUT" | jq -c '.keys')"

# --- keys built from the recipe NAME do not, and the check says what to use -----
BAD=$(proj bad "research/demo/demo_research_prior_art" "design/demo/demo_design_architecture")
OUT=$(run "$BAD")
[ "$(printf '%s' "$OUT" | jq -r .status)" = "mismatch" ] \
  && pass_check "keys built from the recipe name are caught" \
  || fail_check "recipe-name keys must be reported as a mismatch"
[ "$(printf '%s' "$OUT" | jq -r .unresolvable)" = "2" ] \
  && pass_check "every bad key is counted, not just the first" \
  || fail_check "all unresolvable keys must be counted"
[ "$(printf '%s' "$OUT" | jq -r '.keys[0].expected_slug')" = "prior-art" ] \
  && pass_check "the check names the slug that would have worked" \
  || fail_check "a mismatch must name the expected slug, or it costs a second investigation"

# --- a phase/framework the catalog has never heard of --------------------------
OUT=$(run "$(proj unknownfw "research/nosuch/prior-art")")
[ "$(printf '%s' "$OUT" | jq -r .status)" = "mismatch" ] \
  && [ "$(printf '%s' "$OUT" | jq -r '.keys[0].expected_slug')" = "null" ] \
  && pass_check "an unknown framework is a mismatch with no slug to suggest" \
  || fail_check "an unknown framework must not be reported ok"

# --- nothing recorded is not a problem -----------------------------------------
EMPTY="$T/empty"; mkdir -p "$EMPTY"; printf '# P\n' > "$EMPTY/project_state.md"
[ "$(run "$EMPTY" | jq -r .status)" = "none" ] \
  && pass_check "no recorded keys reports none, not a failure" \
  || fail_check "an empty block must report none"

# --- no cached index means UNKNOWN, never ok -----------------------------------
# The whole point is that a confident wrong answer is the failure. A check that cannot check
# must not answer.
OUT=$(DEV_GUIDES_STORE_DIR="$T/nostore" bash "$K" "$GOOD" 2>/dev/null)
[ "$(printf '%s' "$OUT" | jq -r .status)" = "unknown" ] \
  && pass_check "an uncached index reports unknown, never ok" \
  || fail_check "without a catalog the check must report unknown"
[ "$(printf '%s' "$OUT" | jq -r '[.warnings[]] | index("process_recipes_index_not_cached") // "none"')" != "none" ] \
  && pass_check "the uncached index is named in warnings" \
  || fail_check "an uncached index must be surfaced"

# --- always JSON, always exit 0 -------------------------------------------------
run "$T/does-not-exist" | jq empty >/dev/null 2>&1 \
  && pass_check "a missing project folder still emits valid JSON" \
  || fail_check "the check must always emit valid JSON"

if [ "$FAIL" -ne 0 ]; then
  printf '\nSome invariants FAILED for scripts/recipe-key-check.sh.\n' >&2
  exit 1
fi
printf '\nAll invariants pass for scripts/recipe-key-check.sh.\n'
exit 0
