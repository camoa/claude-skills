#!/usr/bin/env bash
# Behavioral spec for scripts/project-for-cwd.sh — which project owns this directory?
#
# Written after watching a live session open in an unregistered Drupal site, get told "Found 28
# registered project(s), run next to select a project", go looking for a project by guessing folder
# names, find none, run three audits, and write the results to a temp folder because nothing ever
# offered it a project. The load-bearing properties:
#   - a directory that belongs to no project answers `registered:false`, no matter how many projects
#     exist elsewhere. The old greeting keyed on the global count, so the offer to create a project was
#     unreachable for anyone past their first one.
#   - a prefix is not a match: /srv/site2 must not resolve to the project at /srv/site
#   - the deepest code path wins, so a project nested in another resolves to the nearer one
#   - a missing registry is a first run, not an error
#   - always JSON on stdout, always exit 0 on a recoverable state
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(dirname "$HERE")"
K="$ROOT/scripts/project-for-cwd.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); }
no(){ FAIL=$((FAIL+1)); echo "FAIL: $1"; }

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed"; exit 0; }
[ -x "$K" ] || { echo "FAIL: $K missing or not executable"; echo "1 failed"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/code/site" "$TMP/code/site/web/themes" "$TMP/code/site2" "$TMP/code/site/inner" "$TMP/proj/a" "$TMP/proj/b"
REG="$TMP/registry.json"
jq -n --arg s "$TMP/code/site" --arg i "$TMP/code/site/inner" --arg pa "$TMP/proj/a" --arg pb "$TMP/proj/b" \
  '{version:"1.1", projectsBase:"/x", projects:[
     {name:"outer", path:$pa, codePath:$s},
     {name:"inner", path:$pb, codePath:$i}]}' > "$REG"
run(){ AIDA_REGISTRY="$REG" "$K" "$1" 2>/dev/null; }
f(){ printf '%s' "$1" | jq -r "$2" 2>/dev/null; }

# --- always JSON, always exit 0 ---------------------------------------------------------------
OUT="$(run "$TMP/code/site")"; RC=$?
[ "$RC" -eq 0 ] && ok || no "exit 0 on the happy path"
[ "$(printf '%s' "$OUT" | jq -s 'length' 2>/dev/null)" = "1" ] && ok || no "emits exactly one JSON document"

# --- exact match ------------------------------------------------------------------------------
[ "$(f "$OUT" .registered)" = "true" ] && ok || no "a project's own code path is registered"
[ "$(f "$OUT" .match)" = "exact" ] && ok || no "the code path itself matches exactly"
[ "$(f "$OUT" .project)" = "outer" ] && ok || no "names the owning project"

# --- a subdirectory belongs to the project ----------------------------------------------------
OUT="$(run "$TMP/code/site/web/themes")"
[ "$(f "$OUT" .registered)" = "true" ] && ok || no "a subdirectory is still inside the project"
[ "$(f "$OUT" .match)" = "below" ] && ok || no "a subdirectory reports match=below, not exact"

# --- THE REGRESSION: a sibling sharing a prefix is NOT a match --------------------------------
OUT="$(run "$TMP/code/site2")"
[ "$(f "$OUT" .registered)" = "false" ] && ok || no "site2 must not match the project at site"
[ "$(f "$OUT" .project)" = "null" ] && ok || no "a non-match names no project"

# --- deepest wins -----------------------------------------------------------------------------
OUT="$(run "$TMP/code/site/inner")"
[ "$(f "$OUT" .project)" = "inner" ] && ok || no "a nested project wins over the one containing it"

# --- unregistered, WITH many projects present: the whole point of the change -------------------
mkdir -p "$TMP/elsewhere"
OUT="$(run "$TMP/elsewhere")"
[ "$(f "$OUT" .registered)" = "false" ] && ok || no "an unrelated directory is unregistered"
[ "$(f "$OUT" .registry_present)" = "true" ] && ok || no "reports the registry existed, so this is a real answer not a fallback"

# --- trailing slash in the registry must not change the answer --------------------------------
jq -n --arg s "$TMP/code/site/" --arg pa "$TMP/proj/a" \
  '{version:"1.1", projects:[{name:"outer", path:$pa, codePath:$s}]}' > "$REG"
OUT="$(run "$TMP/code/site")"
[ "$(f "$OUT" .registered)" = "true" ] && ok || no "a trailing slash on codePath still matches"
OUT="$(run "$TMP/code/site2")"
[ "$(f "$OUT" .registered)" = "false" ] && ok || no "a trailing slash does not let a prefix sibling match"

# --- a project with no codePath is skipped, not crashed on ------------------------------------
jq -n --arg pa "$TMP/proj/a" '{version:"1.1", projects:[{name:"nocode", path:$pa}]}' > "$REG"
OUT="$(run "$TMP/code/site")"
[ "$(f "$OUT" .registered)" = "false" ] && ok || no "a project with no code path never matches"

# --- missing registry is a first run, not an error --------------------------------------------
OUT="$(AIDA_REGISTRY="$TMP/nope.json" "$K" "$TMP/code/site" 2>/dev/null)"; RC=$?
[ "$RC" -eq 0 ] && ok || no "missing registry still exits 0"
[ "$(f "$OUT" .registered)" = "false" ] && ok || no "missing registry answers unregistered"
[ "$(f "$OUT" .registry_present)" = "false" ] && ok || no "missing registry is distinguishable from a real no-match"

# --- malformed registry warns rather than lying -----------------------------------------------
printf 'not json' > "$REG"
OUT="$(run "$TMP/code/site")"
[ "$(f "$OUT" .registered)" = "false" ] && ok || no "malformed registry answers unregistered"
[ "$(printf '%s' "$OUT" | jq -r '.warnings | index("registry_malformed") != null')" = "true" ] && ok || no "malformed registry is warned about, not silent"

# --- a directory that does not exist ----------------------------------------------------------
OUT="$(run "$TMP/does-not-exist")"; RC=$?
[ "$RC" -eq 0 ] && ok || no "a missing directory still exits 0"
[ "$(f "$OUT" .registered)" = "false" ] && ok || no "a missing directory is unregistered"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
