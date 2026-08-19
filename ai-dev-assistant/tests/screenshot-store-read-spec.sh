#!/usr/bin/env bash
# screenshot-store-read-spec.sh — verify scripts/screenshot-store-read.sh
# (reworked v4.13.0, Task C — codePath-native).
#
# Covers: store_missing, codePath-native scan, viewport-name parse,
# hash_mismatch, component_missing_meta, --legacy-path flag, exit-0-always,
# BOTH filename shapes (ordinal and the no-ordinal form the starter template
# actually emits), authed baselines under tests/visual/auth/<ctx>/, and the
# --registry cross-reference that separates an unregistered leftover directory
# from a registered surface with no baselines. Run pre-PR.

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

# === Test 9 (regression, paper-test EC-1): a PNG not matching <stem>- → ===
# warning + exit 0, never a crash (jq -n on the warning-append path).
SNAP3="$CP/tests/visual/widget.spec.ts-snapshots"
mkdir -p "$SNAP3"
printf 'X' > "$SNAP3/totally-unrelated.png"
RC=0; OUT=$(bash "$SCRIPT" "$CP" 2>/dev/null) || RC=$?
if [ "$RC" -eq 0 ] && echo "$OUT" | jq -e '.warnings[] | select(.code == "meta_schema_mismatch")' >/dev/null; then
  pass_check "stray PNG not matching <stem>- → meta_schema_mismatch warning, exit 0 (no crash)"
else
  fail_check "stray-PNG handling — rc=$RC out=$OUT"
fi

# === Test 10 (regression, paper-test EC-4): PNG whose project segment is ===
# not visual-chromium-<viewport> → warning + skipped, no garbage viewport.
printf 'Y' > "$SNAP3/widget-1-firefox-desktop-linux.png"
OUT=$(bash "$SCRIPT" "$CP" 2>/dev/null)
GARBAGE=$(echo "$OUT" | jq -r '.components[] | select(.name=="widget") | .viewports[]?.viewport' 2>/dev/null || true)
if [ -z "$GARBAGE" ] && echo "$OUT" | jq -e '.warnings[] | select(.code == "meta_schema_mismatch")' >/dev/null; then
  pass_check "non-visual-chromium project segment → warning, no garbage viewport emitted"
else
  fail_check "non-visual-chromium segment — garbage='$GARBAGE' out=$OUT"
fi

# === Test 11: the NO-ORDINAL filename shape the starter template produces ===
# Every fixture above is ordinal-form. The plugin's own template names its
# snapshot (`toHaveScreenshot('<id>.png')`), which suppresses the ordinal, so
# the shape a default setup emits was the one shape this suite never built —
# which is why a reader that rejected all of them passed it.
SNAP4="$CP/tests/visual/blog.spec.ts-snapshots"
mkdir -p "$SNAP4"
printf 'BLOG' > "$SNAP4/blog-visual-chromium-tablet-linux.png"
OUT=$(bash "$SCRIPT" "$CP" 2>/dev/null)
BLOG_VP=$(echo "$OUT" | jq -r '.components[] | select(.name=="blog") | .viewports[0].viewport')
if [ "$BLOG_VP" = "tablet" ]; then
  pass_check "no-ordinal baseline (template default shape) parsed: surface=blog, viewport=tablet"
else
  fail_check "no-ordinal shape — viewport='$BLOG_VP' out=$OUT"
fi

# === Test 12: authed baseline with a -<ctx> segment, two levels deeper ===
# Scaffolded under tests/visual/auth/<ctx>/, so it is both deeper than the old
# maxdepth 1 scan and carrying a context segment the viewport must not absorb.
AUTH_SNAP="$CP/tests/visual/auth/editor/account.spec.ts-snapshots"
mkdir -p "$AUTH_SNAP"
printf 'ACCT' > "$AUTH_SNAP/account-visual-chromium-lg-editor-linux.png"
OUT=$(bash "$SCRIPT" "$CP" 2>/dev/null)
ACCT_VP=$(echo "$OUT" | jq -r '.components[] | select(.name=="account") | .viewports[0].viewport')
if [ "$ACCT_VP" = "lg" ]; then
  pass_check "authed baseline under auth/<ctx>/ scanned; viewport=lg, context not folded in"
else
  fail_check "authed baseline — viewport='$ACCT_VP' (expected lg) out=$OUT"
fi

# === Registry cross-reference fixtures ===
# A removed surface leaves its emptied <id>.spec.ts-snapshots/ behind. Without
# the registry that directory is indistinguishable from a registered surface
# that has never been baselined, and a pre-check built on this reader cannot
# fail loudly on the second while ignoring the first.
RCP="$TMPDIR/rcp"
mkdir -p "$RCP/tests/visual/live-one.spec.ts-snapshots"
mkdir -p "$RCP/tests/visual/gone.spec.ts-snapshots"   # orphan: emptied, unregistered
printf 'L' > "$RCP/tests/visual/live-one.spec.ts-snapshots/live-one-visual-chromium-desktop-linux.png"
cat > "$RCP/registry.yml" <<'EOF'
schema_version: "1.3"
viewports:
  - {name: desktop, width: 1920, height: 1080}
surfaces:
  - id: live-one
    url: "/"
    gates: [visual_regression]
  - id: no-baseline
    url: "/nb"
    gates: [visual_regression]
  - id: e2e-only
    url: "/e"
    gates: [e2e]
EOF

HAVE_YAML=0
if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
  HAVE_YAML=1
fi

# === Test 13: without a registry the cross-reference is announced as not run ===
# and nothing is dropped — an unchecked reader must not look like a clean one.
OUT=$(bash "$SCRIPT" "$RCP" 2>/dev/null)
if [ "$(echo "$OUT" | jq -r '.registry_checked')" = "false" ] \
   && echo "$OUT" | jq -e '.warnings[] | select(.code == "registry_not_checked")' >/dev/null \
   && [ "$(echo "$OUT" | jq -r '[.components[].name] | index("gone") != null')" = "true" ] \
   && [ "$(echo "$OUT" | jq -r '.components[] | select(.name=="gone") | .orphan')" = "null" ]; then
  pass_check "no registry → registry_checked false, registry_not_checked warning, orphan null (not a claim)"
else
  fail_check "no-registry posture — out=$OUT"
fi

if [ "$HAVE_YAML" -eq 1 ]; then
  OUT=$(bash "$SCRIPT" "$RCP" --registry "$RCP/registry.yml" 2>/dev/null)

  # === Test 14: an unregistered leftover directory is marked, not dropped ===
  if [ "$(echo "$OUT" | jq -r '.registry_checked')" = "true" ] \
     && [ "$(echo "$OUT" | jq -r '.components[] | select(.name=="gone") | .orphan')" = "true" ] \
     && echo "$OUT" | jq -e '.warnings[] | select(.code == "orphan_snapshot_dir") | select(.detail | test("gone"))' >/dev/null; then
    pass_check "orphan snapshot dir → orphan true + orphan_snapshot_dir warning naming it"
  else
    fail_check "orphan detection — out=$OUT"
  fi

  # === Test 15: the three cases are distinguishable from the output alone ===
  WITH_BASE=$(echo "$OUT" | jq -r '[.components[] | select(.orphan == false and (.viewports | length) > 0) | .name] | join(",")')
  NO_BASE=$(echo "$OUT" | jq -r '[.components[] | select(.orphan == false and (.viewports | length) == 0) | .name] | join(",")')
  ORPHANED=$(echo "$OUT" | jq -r '[.components[] | select(.orphan == true) | .name] | join(",")')
  if [ "$WITH_BASE" = "live-one" ] && [ "$NO_BASE" = "no-baseline" ] && [ "$ORPHANED" = "gone" ] \
     && echo "$OUT" | jq -e '.warnings[] | select(.code == "surface_without_baselines") | select(.detail | test("no-baseline"))' >/dev/null; then
    pass_check "registered-with-baselines / registered-without / unregistered-leftover all distinguishable"
  else
    fail_check "three-case split — with='$WITH_BASE' without='$NO_BASE' orphan='$ORPHANED' out=$OUT"
  fi

  # === Test 16: an e2e-only surface is not reported as missing a baseline ===
  if ! echo "$OUT" | jq -e '.warnings[] | select(.code == "surface_without_baselines") | select(.detail | test("e2e-only"))' >/dev/null; then
    pass_check "surface without the visual_regression gate is not flagged as unbaselined"
  else
    fail_check "e2e-only surface flagged as missing a visual baseline — out=$OUT"
  fi
else
  fail_check "python3 + PyYAML unavailable — the registry cross-reference tests did NOT run (install PyYAML; a skipped check is not a passing one)"
fi

# === Test 17: an unreadable registry degrades to no-registry, exit 0 ===
RC=0; OUT=$(bash "$SCRIPT" "$RCP" --registry "$RCP/does-not-exist.yml" 2>/dev/null) || RC=$?
if [ "$RC" -eq 0 ] && [ "$(echo "$OUT" | jq -r '.registry_checked')" = "false" ] \
   && echo "$OUT" | jq -e '.warnings[] | select(.code == "registry_not_checked")' >/dev/null; then
  pass_check "unreadable registry → degrades to no-registry behaviour, says so, exit 0"
else
  fail_check "registry degradation — rc=$RC out=$OUT"
fi

if [ "$FAIL" -ne 0 ]; then
  printf '\nscreenshot-store-read.sh invariants violated.\n' >&2
  exit 1
fi
printf '\nAll invariants pass for scripts/screenshot-store-read.sh.\n'
exit 0
