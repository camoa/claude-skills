#!/usr/bin/env bash
# Behavioral spec for scripts/project-offer-read.sh + scripts/project-offer-write.sh.
#
# The contract asks for a one-time, declinable proposal when real work starts in code that belongs to
# no project, and for the decline to be REMEMBERED FOR THAT DIRECTORY. What shipped was a paragraph
# printed in every greeting and nothing anywhere that records an answer, so saying no cost the same
# interruption every session, forever.
#
# The three-state grammar is not invented here. `**Code Map:**` and `**Task Rule:**` in
# project_state.md already distinguish "nobody has been asked" from "asked and declined" from
# "answered yes", and project-state-read.sh already parses that distinction. This is the same three
# states for a directory that has no project_state.md to hold them.
#
# The load-bearing properties:
#   - absent is not declined. A directory nobody has answered for reads null, and null is what makes
#     the offer fire. A mechanism that suppresses everything satisfies "do not re-offer" trivially.
#   - a decline is scoped to the directory it was given in, and to what is under it. Declining at a
#     repository root and being re-asked one `cd src` later is the same interruption with extra steps.
#   - a decline does NOT leak sideways. A sibling directory, and a directory sharing a name prefix,
#     have answered nothing.
#   - an unreadable or malformed store answers null, never "declined". Re-offering after a lost store
#     is a small cost; silently suppressing on garbage is a settled question nobody can reopen.
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(dirname "$HERE")"
R="$ROOT/scripts/project-offer-read.sh"
W="$ROOT/scripts/project-offer-write.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); }
no(){ FAIL=$((FAIL+1)); echo "FAIL: $1"; }

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed"; exit 0; }
[ -x "$R" ] || { echo "FAIL: $R missing or not executable"; echo "1 failed"; exit 1; }
[ -x "$W" ] || { echo "FAIL: $W missing or not executable"; echo "1 failed"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/repo" "$TMP/repo/src" "$TMP/repo2" "$TMP/other"
STORE="$TMP/store/project_offers.json"

read_at(){ AIDA_OFFERS="$STORE" "$R" "$1" 2>/dev/null; }
write_at(){ AIDA_OFFERS="$STORE" "$W" "$@" 2>/dev/null; }
f(){ printf '%s' "$1" | jq -r "$2" 2>/dev/null; }

# --- no store at all: a first run, not an error ------------------------------------------------
OUT="$(read_at "$TMP/repo")"; RC=$?
[ "$RC" -eq 0 ] && ok || no "a missing store still exits 0"
[ "$(printf '%s' "$OUT" | jq -s 'length' 2>/dev/null)" = "1" ] && ok || no "emits exactly one JSON document"
[ "$(f "$OUT" .offer)" = "null" ] && ok || no "a directory nobody has answered for reads offer:null"
[ "$(f "$OUT" .store_present)" = "false" ] && ok || no "a missing store is distinguishable from a real no-record"

# --- recording a decline ------------------------------------------------------------------------
OUT="$(write_at --dir "$TMP/repo" --answer declined)"; RC=$?
[ "$RC" -eq 0 ] && ok || no "recording a decline exits 0"
[ -f "$STORE" ] && ok || no "the writer creates the store, parent directory included"
jq empty "$STORE" >/dev/null 2>&1 && ok || no "the store it writes is valid JSON"

OUT="$(read_at "$TMP/repo")"
[ "$(f "$OUT" .offer.declined)" = "true" ] && ok || no "the declined directory reads declined:true"
[ "$(f "$OUT" .match)" = "exact" ] && ok || no "the directory the answer was given in reports match=exact"
[ "$(f "$OUT" .offer.recorded)" != "null" ] && ok || no "a recorded answer carries when it was recorded"

# --- THE EXCLUSION: everyone else still gets asked ----------------------------------------------
# A mechanism that suppresses the offer everywhere passes "do not re-offer" and fails the contract.
OUT="$(read_at "$TMP/other")"
[ "$(f "$OUT" .offer)" = "null" ] && ok || no "an unrelated directory has still answered nothing"
[ "$(f "$OUT" .store_present)" = "true" ] && ok || no "and that null is a real no-record, not a missing store"

# --- a name prefix is not the same directory ----------------------------------------------------
OUT="$(read_at "$TMP/repo2")"
[ "$(f "$OUT" .offer)" = "null" ] && ok || no "repo2 must not inherit the answer given in repo"

# --- what is under the declined directory is covered --------------------------------------------
OUT="$(read_at "$TMP/repo/src")"
[ "$(f "$OUT" .offer.declined)" = "true" ] && ok || no "a subdirectory of a declined repository is also declined"
[ "$(f "$OUT" .match)" = "below" ] && ok || no "a subdirectory reports match=below, not exact"

# --- the same directory named differently is the same directory ---------------------------------
OUT="$(read_at "$TMP/repo/src/../../repo")"
[ "$(f "$OUT" .offer.declined)" = "true" ] && ok || no "a path with .. resolves to the same record"

# --- an answer can be changed; the last one stands ----------------------------------------------
write_at --dir "$TMP/repo" --answer accepted --project demo >/dev/null
OUT="$(read_at "$TMP/repo")"
[ "$(f "$OUT" .offer.declined)" = "false" ] && ok || no "accepting after declining replaces the answer"
[ "$(f "$OUT" .offer.project)" = "demo" ] && ok || no "an accepted answer records which project was made"
[ "$(jq '[.directories[] | select(.dir | endswith("/repo"))] | length' "$STORE")" = "1" ] && ok \
  || no "changing the answer replaces the record rather than appending a second one"

# --- the deepest recorded answer wins -----------------------------------------------------------
write_at --dir "$TMP/repo" --answer declined >/dev/null
write_at --dir "$TMP/repo/src" --answer accepted --project inner >/dev/null
OUT="$(read_at "$TMP/repo/src")"
[ "$(f "$OUT" .offer.project)" = "inner" ] && ok || no "an answer given deeper wins over the one above it"
OUT="$(read_at "$TMP/repo")"
[ "$(f "$OUT" .offer.declined)" = "true" ] && ok || no "and the deeper answer does not overwrite the one above"

# --- a malformed store re-offers rather than suppressing ----------------------------------------
printf 'not json' > "$STORE"
OUT="$(read_at "$TMP/repo")"; RC=$?
[ "$RC" -eq 0 ] && ok || no "a malformed store still exits 0"
[ "$(f "$OUT" .offer)" = "null" ] && ok || no "a malformed store answers null, never declined"
[ "$(printf '%s' "$OUT" | jq -r '.warnings | index("store_malformed") != null')" = "true" ] && ok \
  || no "a malformed store is warned about, not silent"

# --- an unrecognised answer token is not read as a decline --------------------------------------
jq -n --arg d "$TMP/repo" '{schema_version:"1.0", directories:[{dir:$d, answer:"maybe"}]}' > "$STORE"
OUT="$(read_at "$TMP/repo")"
[ "$(f "$OUT" .offer)" = "null" ] && ok || no "an answer token outside declined|accepted reads as unanswered"
[ "$(printf '%s' "$OUT" | jq -r '.warnings | index("offer_bad_answer") != null')" = "true" ] && ok \
  || no "an unrecognised answer token is warned about"

# --- the writer refuses an answer it does not understand ----------------------------------------
rm -f "$STORE"
write_at --dir "$TMP/repo" --answer maybe >/dev/null 2>&1; RC=$?
[ "$RC" -eq 2 ] && ok || no "an answer outside declined|accepted exits 2"
[ ! -f "$STORE" ] && ok || no "a refused answer writes nothing at all"

write_at --answer declined >/dev/null 2>&1; RC=$?
[ "$RC" -eq 2 ] && ok || no "a missing --dir exits 2"

# --- a directory that does not exist -------------------------------------------------------------
OUT="$(read_at "$TMP/never-created")"; RC=$?
[ "$RC" -eq 0 ] && ok || no "reading a missing directory still exits 0"
[ "$(f "$OUT" .offer)" = "null" ] && ok || no "a missing directory has answered nothing"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
