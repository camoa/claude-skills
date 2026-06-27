#!/usr/bin/env bash
# Behavioral spec for scripts/mechanisms-hash.sh — the deterministic mechanism-challenge freshness hash
# (GAP G). The /implement backstop's staleness check must be reproducible, so the hash MUST be:
#   - SET semantics: invariant to order, duplicates, and per-line whitespace
#   - content-sensitive: a changed mechanism → a different hash (so a later-edited mechanism re-triggers)
#   - stable on the empty set (= sha256 of the empty string)
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(dirname "$HERE")"
K="$ROOT/scripts/mechanisms-hash.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); }
no(){ FAIL=$((FAIL+1)); echo "FAIL: $1"; }

A="$(printf '%s\n' "build image_style" "emit via preprocess" | bash "$K")"
# reordered + duplicated + padded → same hash (set + trim)
B="$(printf '%s\n' "  emit via preprocess  " "build image_style" "emit via preprocess" "" | bash "$K")"
[ "$A" = "$B" ] && ok || no "order/dup/whitespace must be set-invariant (A=$A B=$B)"

# changed content → different hash
C="$(printf '%s\n' "build image_style" "emit via formatter" | bash "$K")"
[ "$A" != "$C" ] && ok || no "content change must change the hash"

# empty set stable + equals sha256('')
E1="$(printf '' | bash "$K")"; E2="$(printf '\n   \n\t\n' | bash "$K")"
[ "$E1" = "$E2" ] && ok || no "empty set must be stable (E1=$E1 E2=$E2)"
[ "$E1" = "$(printf '' | sha256sum | awk '{print $1}')" ] && ok || no "empty set must equal sha256('')"

# output is a 64-char lowercase hex digest
[ "${#A}" -eq 64 ] && [[ "$A" =~ ^[0-9a-f]{64}$ ]] && ok || no "output must be a 64-char lowercase hex sha256 (got $A)"

echo "----"; echo "mechanisms-hash-spec: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
