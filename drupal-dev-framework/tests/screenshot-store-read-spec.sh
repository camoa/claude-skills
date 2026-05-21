#!/usr/bin/env bash
# screenshot-store-read-spec.sh — verify scripts/screenshot-store-read.sh
# (reworked v4.13.0, Task C — codePath-native).
#
# Covers: store_missing, codePath-native scan, viewport-name parse,
# hash_mismatch, component_missing_meta, --legacy-path flag, exit-0-always.
# Run pre-PR.

set -eu

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${PLUGIN_ROOT}/scripts/screenshot-store-read.sh"
[ -f "$SCRIPT" ] || { printf 'FAIL: %s not found\n' "$SCRIPT" >&2; exit 1; }

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# === Test 1: no tests/visual/ → store_missing, store_exists false, exit 0 ===
CP="$TMPDIR/cp"; mkdir -p "$CP"
RC=0; OUT=$(bash "$SCRIPT" "$CP") || RC=$?
if [ "$RC" -eq 0 ] && [ "$(echo "$OUT" | jq -r '.store_exists')" = "false" ] \
   && echo "$OUT" | jq -e '.warnings[] | select(.code == "store_missing")' >/dev/null; then
  pass_check "no tests/visual/ → store_missing, store_exists false, exit 0"
else
  fail_check "store_missing — rc=$RC out=$OUT"
fi

# === Test 2: codePath-native baseline scanned, viewport name parsed ===
SNAP="$CP/tests/visual/home-hero.spec.ts-snapshots"
mkdir -p "$SNAP"
printf 'PNGDATA' > "$SNAP/home-hero-1-visual-chromium-desktop-linux.png"
HASH=$(sha256sum "$SNAP/home-hero-1-visual-chromium-desktop-linux.png" | awk '{print $1}')
cat > "$SNAP/home-hero-1-visual-chromium-desktop-linux.meta.json" <<EOF
{"schema_version":"1.0","role":"baseline","viewport":"desktop",
 "captured_at":"2026-01-01T00:00:00Z","sha256":"$HASH","originating_task":"t",
 "captured_by":"lullabot-playwright","prior_hash":null,"source":null}
EOF
OUT=$(bash "$SCRIPT" "$CP")
if [ "$(echo "$OUT" | jq -r '.store_exists')" = "true" ] \
   && [ "$(echo "$OUT" | jq -r '.components[0].name')" = "home-hero" ] \
   && [ "$(echo "$OUT" | jq -r '.components[0].viewports[0].viewport')" = "desktop" ]; then
  pass_check "codePath-native scan: surface=home-hero, viewport=desktop"
else
  fail_check "codePath scan — out=$OUT"
fi

# === Test 3: matching hash → no hash_mismatch warning ===
if ! echo "$OUT" | jq -e '.. | objects | select(.code? == "hash_mismatch")' >/dev/null; then
  pass_check "matching sha256 → no hash_mismatch"
else
  fail_check "false hash_mismatch — out=$OUT"
fi

# === Test 4: tampered PNG → hash_mismatch warning ===
printf 'TAMPERED' > "$SNAP/home-hero-1-visual-chromium-desktop-linux.png"
OUT=$(bash "$SCRIPT" "$CP")
if echo "$OUT" | jq -e '.components[0].viewports[0].warnings[] | select(.code == "hash_mismatch")' >/dev/null; then
  pass_check "tampered PNG → hash_mismatch warning"
else
  fail_check "hash_mismatch not detected — out=$OUT"
fi

# === Test 5: PNG without meta → component_missing_meta ===
SNAP2="$CP/tests/visual/footer.spec.ts-snapshots"
mkdir -p "$SNAP2"
printf 'X' > "$SNAP2/footer-1-visual-chromium-phone-linux.png"
OUT=$(bash "$SCRIPT" "$CP")
if echo "$OUT" | jq -e '.components[] | select(.name=="footer") | .viewports[0].warnings[] | select(.code == "component_missing_meta")' >/dev/null; then
  pass_check "PNG without meta → component_missing_meta"
else
  fail_check "component_missing_meta not detected — out=$OUT"
fi

# === Test 6: has_previous always false, previous_meta null (codePath-native) ===
if [ "$(echo "$OUT" | jq -r '.components[0].viewports[0].has_previous')" = "false" ] \
   && [ "$(echo "$OUT" | jq -r '.components[0].viewports[0].previous_meta')" = "null" ]; then
  pass_check "codePath-native: has_previous false, previous_meta null"
else
  fail_check "previous tier — out=$OUT"
fi

# === Test 7: --legacy-path → legacy_store_present ===
MP="$TMPDIR/mp"; mkdir -p "$MP/.screenshots"
OUT=$(bash "$SCRIPT" "$CP" --legacy-path "$MP")
if [ "$(echo "$OUT" | jq -r '.legacy_store_present')" = "true" ]; then
  pass_check "--legacy-path with .screenshots/ → legacy_store_present true"
else
  fail_check "legacy_store_present — out=$OUT"
fi
OUT=$(bash "$SCRIPT" "$CP")
if echo "$OUT" | jq -e 'has("legacy_store_present") | not' >/dev/null; then
  pass_check "no --legacy-path → legacy_store_present omitted"
else
  fail_check "legacy_store_present should be absent without flag — out=$OUT"
fi

# === Test 8: output carries required keys ===
if echo "$OUT" | jq -e 'has("schema_version") and has("project_path") and has("store_path") and has("store_exists") and has("components") and has("warnings")' >/dev/null; then
  pass_check "output carries all required keys"
else
  fail_check "output keys — out=$OUT"
fi

if [ "$FAIL" -ne 0 ]; then
  printf '\nscreenshot-store-read.sh invariants violated.\n' >&2
  exit 1
fi
printf '\nAll invariants pass for scripts/screenshot-store-read.sh.\n'
exit 0
