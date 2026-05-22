#!/usr/bin/env bash
# migrate-screenshots-to-codepath-spec.sh — verify scripts/migrate-screenshots-to-codepath.sh
# (v4.13.0, Task C).
#
# Covers: nothing-to-migrate exit 1, PNG + meta copy, captured_by/viewport
# rewrite, stub spec generation, size mapping, JSON report shape.
# Run pre-PR.

set -eu

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${PLUGIN_ROOT}/scripts/migrate-screenshots-to-codepath.sh"
[ -f "$SCRIPT" ] || { printf 'FAIL: %s not found\n' "$SCRIPT" >&2; exit 1; }

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# === Test 1: no .screenshots/ → exit 1 ===
MP="$TMPDIR/mp"; CP="$TMPDIR/cp"
mkdir -p "$MP" "$CP"
RC=0; OUT=$(bash "$SCRIPT" "$MP" "$CP") || RC=$?
if [ "$RC" -eq 1 ] && echo "$OUT" | jq -e '.migrated == []' >/dev/null; then
  pass_check "no .screenshots/ → exit 1, migrated:[]"
else
  fail_check "no-store — rc=$RC out=$OUT"
fi

# === Test 2: migrate a component with PNG + meta ===
mkdir -p "$MP/.screenshots/home-hero"
printf 'PNGDATA' > "$MP/.screenshots/home-hero/1920x1080.png"
cat > "$MP/.screenshots/home-hero/1920x1080.meta.json" <<'EOF'
{"schema_version":"1.0","role":"baseline","viewport":"1920x1080",
 "captured_at":"2026-01-01T00:00:00Z","sha256":"abc","originating_task":"t",
 "captured_by":"playwright-mcp","prior_hash":null,"source":null}
EOF
RC=0; OUT=$(bash "$SCRIPT" "$MP" "$CP") || RC=$?
if [ "$RC" -eq 0 ] && echo "$OUT" | jq -e '.migrated[0].component == "home-hero"' >/dev/null; then
  pass_check "component with PNG+meta migrated, exit 0"
else
  fail_check "migrate — rc=$RC out=$OUT"
fi

# === Test 3: baseline PNG copied to codePath-native snapshot dir ===
SNAP="$CP/tests/visual/home-hero.spec.ts-snapshots"
if ls "$SNAP"/home-hero-1-visual-chromium-*-linux.png >/dev/null 2>&1; then
  pass_check "baseline PNG copied to <surface>.spec.ts-snapshots/"
else
  fail_check "baseline PNG not found in $SNAP"
fi

# === Test 4: copied meta has captured_by + viewport rewritten ===
META=$(ls "$SNAP"/*.meta.json 2>/dev/null | head -1)
if [ -n "$META" ] \
   && [ "$(jq -r '.captured_by' "$META")" = "migrated-from-screenshots-store" ] \
   && [ "$(jq -r '.viewport' "$META")" != "1920x1080" ]; then
  pass_check "copied meta: captured_by + viewport rewritten"
else
  fail_check "meta rewrite — $META = $([ -n "$META" ] && cat "$META")"
fi

# === Test 5: stub spec generated ===
if [ -f "$CP/tests/visual/home-hero.spec.ts" ] \
   && grep -q 'takeAccessibleScreenshot' "$CP/tests/visual/home-hero.spec.ts"; then
  pass_check "stub spec generated with takeAccessibleScreenshot"
else
  fail_check "stub spec missing or malformed"
fi

# === Test 6: --viewports-json nearest-width mapping ===
CP2="$TMPDIR/cp2"; MP2="$TMPDIR/mp2"
mkdir -p "$CP2" "$MP2/.screenshots/card"
printf 'X' > "$MP2/.screenshots/card/375x812.png"
OUT=$(bash "$SCRIPT" "$MP2" "$CP2" --viewports-json '[{"name":"phone","width":390},{"name":"desktop","width":1440}]')
if echo "$OUT" | jq -e '.migrated[0].viewports[0].viewport == "phone"' >/dev/null; then
  pass_check "--viewports-json nearest-width: 375 → phone"
else
  fail_check "viewports-json mapping — out=$OUT"
fi

# === Test 7: report JSON shape ===
if echo "$OUT" | jq -e 'has("migrated") and has("warnings")' >/dev/null; then
  pass_check "report has migrated[] + warnings[]"
else
  fail_check "report shape — out=$OUT"
fi

# === Test 8 (regression, paper-test RT-6): non-kebab component dir skipped ===
CP3="$TMPDIR/cp3"; MP3="$TMPDIR/mp3"
mkdir -p "$CP3" "$MP3/.screenshots/../evil" "$MP3/.screenshots/Bad Name"
printf 'X' > "$MP3/.screenshots/Bad Name/375x812.png"
RC=0; OUT=$(bash "$SCRIPT" "$MP3" "$CP3" 2>/dev/null) || RC=$?
if echo "$OUT" | jq -e '.warnings[] | select(test("not kebab-case"))' >/dev/null \
   && ! echo "$OUT" | jq -e '.migrated[] | select(.component | test("[^a-z0-9-]"))' >/dev/null; then
  pass_check "non-kebab component dir → skipped with warning (path-traversal blocked)"
else
  fail_check "non-kebab component handling — rc=$RC out=$OUT"
fi

# === Test 9 (regression, paper-test EC-5): two viewports → same size bucket ===
CP4="$TMPDIR/cp4mig"; MP4="$TMPDIR/mp4mig"
mkdir -p "$CP4" "$MP4/.screenshots/hero"
printf 'A' > "$MP4/.screenshots/hero/370x800.png"
printf 'B' > "$MP4/.screenshots/hero/400x850.png"
OUT=$(bash "$SCRIPT" "$MP4" "$CP4" 2>/dev/null)
MIGRATED_PNGS=$(ls "$CP4/tests/visual/hero.spec.ts-snapshots/"*.png 2>/dev/null | wc -l)
if [ "$MIGRATED_PNGS" -eq 1 ] && echo "$OUT" | jq -e '.warnings[] | select(test("already migrated this run"))' >/dev/null; then
  pass_check "two viewports → same size: first kept, second skipped + warned (no overwrite)"
else
  fail_check "size-collision handling — migrated=$MIGRATED_PNGS out=$OUT"
fi

if [ "$FAIL" -ne 0 ]; then
  printf '\nmigrate-screenshots-to-codepath.sh invariants violated.\n' >&2
  exit 1
fi
printf '\nAll invariants pass for scripts/migrate-screenshots-to-codepath.sh.\n'
exit 0
