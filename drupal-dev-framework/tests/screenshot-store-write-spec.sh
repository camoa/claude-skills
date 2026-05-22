#!/usr/bin/env bash
# screenshot-store-write-spec.sh — verify scripts/screenshot-store-write.sh
# write-baseline-codepath (added v4.13.0, Task C) + legacy regression.
#
# Covers: sidecar write, sha256 correctness, prior_hash chain, arg + enum
# validation, png-missing exit 3, legacy write-baseline still works.
# Run pre-PR.

set -eu

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${PLUGIN_ROOT}/scripts/screenshot-store-write.sh"
[ -f "$SCRIPT" ] || { printf 'FAIL: %s not found\n' "$SCRIPT" >&2; exit 1; }

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

CP="$TMPDIR/cp"
SNAP="$CP/tests/visual/home-hero.spec.ts-snapshots"
mkdir -p "$SNAP"
PNG="home-hero-1-visual-chromium-desktop-linux.png"
printf 'PNGDATA1' > "$SNAP/$PNG"

# === Test 1: write-baseline-codepath writes the sidecar, status ok ===
RC=0
OUT=$(bash "$SCRIPT" write-baseline-codepath "$CP" home-hero "$PNG" desktop lullabot-playwright task_c) || RC=$?
META="$SNAP/home-hero-1-visual-chromium-desktop-linux.meta.json"
if [ "$RC" -eq 0 ] && [ "$(echo "$OUT" | jq -r '.status')" = "ok" ] && [ -f "$META" ]; then
  pass_check "write-baseline-codepath → status ok, .meta.json written"
else
  fail_check "write-baseline-codepath — rc=$RC out=$OUT"
fi

# === Test 2: sidecar sha256 matches the PNG ===
EXPECT=$(sha256sum "$SNAP/$PNG" | awk '{print $1}')
if [ "$(jq -r '.sha256' "$META")" = "$EXPECT" ]; then
  pass_check "sidecar sha256 matches the PNG"
else
  fail_check "sha256 mismatch — meta=$(jq -r '.sha256' "$META") expect=$EXPECT"
fi

# === Test 3: 9-field meta, captured_by + viewport correct, prior_hash null ===
if [ "$(jq -r '.captured_by' "$META")" = "lullabot-playwright" ] \
   && [ "$(jq -r '.viewport' "$META")" = "desktop" ] \
   && [ "$(jq -r '.role' "$META")" = "baseline" ] \
   && [ "$(jq -r '.prior_hash' "$META")" = "null" ]; then
  pass_check "meta fields: captured_by, viewport, role, prior_hash null (first write)"
else
  fail_check "meta fields — $(cat "$META")"
fi

# === Test 4: prior_hash chain on a second write ===
FIRST_HASH=$(jq -r '.sha256' "$META")
printf 'PNGDATA2-CHANGED' > "$SNAP/$PNG"
bash "$SCRIPT" write-baseline-codepath "$CP" home-hero "$PNG" desktop lullabot-playwright task_c >/dev/null
if [ "$(jq -r '.prior_hash' "$META")" = "$FIRST_HASH" ]; then
  pass_check "second write → prior_hash = previous sidecar's sha256"
else
  fail_check "prior_hash chain — got $(jq -r '.prior_hash' "$META") expect $FIRST_HASH"
fi

# === Test 5: invalid surface id → exit 2 ===
RC=0; bash "$SCRIPT" write-baseline-codepath "$CP" "Bad Id" "$PNG" desktop lullabot-playwright t >/dev/null 2>&1 || RC=$?
if [ "$RC" -eq 2 ]; then
  pass_check "invalid surface id → exit 2"
else
  fail_check "invalid surface id should exit 2, got $RC"
fi

# === Test 6: invalid captured_by → exit 2 ===
RC=0; bash "$SCRIPT" write-baseline-codepath "$CP" home-hero "$PNG" desktop bogus-method t >/dev/null 2>&1 || RC=$?
if [ "$RC" -eq 2 ]; then
  pass_check "captured_by not in enum → exit 2"
else
  fail_check "invalid captured_by should exit 2, got $RC"
fi

# === Test 7: migrated-from-screenshots-store is an accepted captured_by ===
RC=0; bash "$SCRIPT" write-baseline-codepath "$CP" home-hero "$PNG" desktop migrated-from-screenshots-store t >/dev/null 2>&1 || RC=$?
if [ "$RC" -eq 0 ]; then
  pass_check "captured_by migrated-from-screenshots-store accepted"
else
  fail_check "migrated-from-screenshots-store should be accepted, got $RC"
fi

# === Test 8: missing PNG → exit 3 ===
RC=0; bash "$SCRIPT" write-baseline-codepath "$CP" home-hero "nope-1-visual-chromium-desktop-linux.png" desktop lullabot-playwright t >/dev/null 2>&1 || RC=$?
if [ "$RC" -eq 3 ]; then
  pass_check "missing baseline PNG → exit 3"
else
  fail_check "missing PNG should exit 3, got $RC"
fi

# === Test 9: legacy write-baseline still works (regression) ===
LP="$TMPDIR/legacy"; mkdir -p "$LP"
SRC="$TMPDIR/src.png"; printf 'SRCPNG' > "$SRC"
RC=0
OUT=$(bash "$SCRIPT" write-baseline "$LP" home-hero 1920x1080 "$SRC" playwright-mcp task_c) || RC=$?
if [ "$RC" -eq 0 ] && [ "$(echo "$OUT" | jq -r '.status')" = "ok" ] \
   && [ -f "$LP/.screenshots/home-hero/1920x1080.png" ]; then
  pass_check "legacy write-baseline still works (.screenshots/ store)"
else
  fail_check "legacy write-baseline regression — rc=$RC out=$OUT"
fi

# === Test 10: bad arg count → exit 2 ===
RC=0; bash "$SCRIPT" write-baseline-codepath "$CP" home-hero >/dev/null 2>&1 || RC=$?
if [ "$RC" -eq 2 ]; then
  pass_check "write-baseline-codepath with too few args → exit 2"
else
  fail_check "bad arg count should exit 2, got $RC"
fi

if [ "$FAIL" -ne 0 ]; then
  printf '\nscreenshot-store-write.sh invariants violated.\n' >&2
  exit 1
fi
printf '\nAll invariants pass for scripts/screenshot-store-write.sh.\n'
exit 0
