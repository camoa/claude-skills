#!/usr/bin/env bash
# derive-viewport-matrix-spec.sh — verify scripts/derive-viewport-matrix.sh (v4.13.0, Task C).
#
# Covers (framework-neutral kernel): --breakpoints-from parse + dedup + canonical
# heights, explicit height passthrough, malformed/missing --breakpoints-from → exit 2,
# CSS @media fallback under a neutral --css-root, exit-3 on nothing-derivable,
# zero framework knowledge (no theme/docroot auto-detection).
# Run pre-PR. Companion to tests/change-impact-classify-spec.sh.

set -eu

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${PLUGIN_ROOT}/scripts/derive-viewport-matrix.sh"
[ -f "$SCRIPT" ] || { printf 'FAIL: %s not found\n' "$SCRIPT" >&2; exit 1; }

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# === Test 1: --breakpoints-from — 3 breakpoints, input order preserved ===
CP1="$TMPDIR/cp1"; mkdir -p "$CP1"
cat > "$TMPDIR/bp1.json" <<'EOF'
[
  { "name": "mobile",  "width": 0 },
  { "name": "tablet",  "width": 768 },
  { "name": "desktop", "width": 1200 }
]
EOF
OUT=$(bash "$SCRIPT" "$CP1" --breakpoints-from "$TMPDIR/bp1.json"); RC=$?
if [ "$RC" -eq 0 ] && [ "$(echo "$OUT" | jq -r '.[0].name')" = "mobile" ] \
   && [ "$(echo "$OUT" | jq -r '.[2].name')" = "desktop" ]; then
  pass_check "--breakpoints-from parsed, input order preserved (mobile..desktop)"
else
  fail_check "--breakpoints-from parse — rc=$RC out=$OUT"
fi

# === Test 2: canonical heights applied (0 → 812, 768 → 1024, 1200 → 900) ===
if [ "$(echo "$OUT" | jq -r '.[0].height')" = "812" ] \
   && [ "$(echo "$OUT" | jq -r '.[1].height')" = "1024" ] \
   && [ "$(echo "$OUT" | jq -r '.[2].height')" = "900" ]; then
  pass_check "canonical heights: 0→812, 768→1024, 1200→900"
else
  fail_check "canonical heights — got $(echo "$OUT" | jq -c 'map(.height)')"
fi

# === Test 3: explicit height passthrough overrides the band ===
cat > "$TMPDIR/bp3.json" <<'EOF'
[ { "name": "mobile", "width": 375, "height": 667 } ]
EOF
RC=0; OUT=$(bash "$SCRIPT" "$CP1" --breakpoints-from "$TMPDIR/bp3.json") || RC=$?
if [ "$RC" -eq 0 ] && [ "$(echo "$OUT" | jq -r '.[0].height')" = "667" ]; then
  pass_check "explicit height passthrough (375 → 667, not the band 812)"
else
  fail_check "explicit height passthrough — rc=$RC out=$OUT"
fi

# === Test 4: dedup by width, first occurrence wins ===
cat > "$TMPDIR/bp4.json" <<'EOF'
[
  { "name": "tablet",  "width": 768 },
  { "name": "tablet2", "width": 768 },
  { "name": "desktop", "width": 1200 }
]
EOF
RC=0; OUT=$(bash "$SCRIPT" "$CP1" --breakpoints-from "$TMPDIR/bp4.json") || RC=$?
if [ "$RC" -eq 0 ] && [ "$(echo "$OUT" | jq 'length')" = "2" ] \
   && [ "$(echo "$OUT" | jq -r '.[0].name')" = "tablet" ]; then
  pass_check "dedup by width — first occurrence wins (tablet, not tablet2)"
else
  fail_check "dedup by width — rc=$RC out=$OUT"
fi

# === Test 5: --breakpoints-from missing file → exit 2 ===
RC=0; OUT=$(bash "$SCRIPT" "$CP1" --breakpoints-from "$TMPDIR/nope.json" 2>/dev/null) || RC=$?
if [ "$RC" -eq 2 ] && [ "$OUT" = "[]" ]; then
  pass_check "missing --breakpoints-from file → exit 2, []"
else
  fail_check "missing --breakpoints-from — rc=$RC out=$OUT"
fi

# === Test 6: --breakpoints-from not a JSON array → exit 2 ===
echo '{ "rules": [] }' > "$TMPDIR/bp_obj.json"
RC=0; OUT=$(bash "$SCRIPT" "$CP1" --breakpoints-from "$TMPDIR/bp_obj.json" 2>/dev/null) || RC=$?
if [ "$RC" -eq 2 ] && [ "$OUT" = "[]" ]; then
  pass_check "non-array --breakpoints-from → exit 2, []"
else
  fail_check "non-array --breakpoints-from — rc=$RC out=$OUT"
fi

# === Test 7: --breakpoints-from array of all-invalid entries → exit 2 ===
echo '[ { "name": "x" }, { "width": "wide" } ]' > "$TMPDIR/bp_bad.json"
RC=0; OUT=$(bash "$SCRIPT" "$CP1" --breakpoints-from "$TMPDIR/bp_bad.json" 2>/dev/null) || RC=$?
if [ "$RC" -eq 2 ] && [ "$OUT" = "[]" ]; then
  pass_check "all-invalid --breakpoints-from entries → exit 2, []"
else
  fail_check "all-invalid --breakpoints-from — rc=$RC out=$OUT"
fi

# === Test 8: nothing derivable → exit 3, [] ===
CP2="$TMPDIR/cp2"; mkdir -p "$CP2"
RC=0; OUT=$(bash "$SCRIPT" "$CP2" 2>/dev/null) || RC=$?
if [ "$RC" -eq 3 ] && [ "$OUT" = "[]" ]; then
  pass_check "no breakpoints input + no CSS → exit 3, []"
else
  fail_check "nothing-derivable — rc=$RC out=$OUT"
fi

# === Test 9: CSS @media fallback under neutral --css-root ===
CP4="$TMPDIR/cp4"
mkdir -p "$CP4/src/styles"
cat > "$CP4/src/styles/app.css" <<'EOF'
@media (min-width: 480px) { .a { color: red; } }
@media (min-width: 1024px) { .b { color: blue; } }
EOF
RC=0; OUT=$(bash "$SCRIPT" "$CP4" --css-root "$CP4/src") || RC=$?
if [ "$RC" -eq 0 ] && [ "$(echo "$OUT" | jq 'length')" -ge 2 ] \
   && echo "$OUT" | jq -e '.[0]._source == "css-media"' >/dev/null; then
  pass_check "CSS @media fallback under --css-root → _source css-media"
else
  fail_check "CSS @media fallback — rc=$RC out=$OUT"
fi

# === Test 10: CSS fallback defaults --css-root to <codePath> ===
RC=0; OUT=$(bash "$SCRIPT" "$CP4") || RC=$?
if [ "$RC" -eq 0 ] && [ "$(echo "$OUT" | jq 'length')" -ge 2 ]; then
  pass_check "CSS scan defaults to <codePath> when --css-root omitted"
else
  fail_check "CSS default scan root — rc=$RC out=$OUT"
fi

# === Test 11: no framework auto-detection — a breakpoints.yml is NOT read ===
CP5="$TMPDIR/cp5"
mkdir -p "$CP5/web/themes/custom/mytheme"
cat > "$CP5/web/themes/custom/mytheme/mytheme.breakpoints.yml" <<'EOF'
mytheme.mobile:
  mediaQuery: '(min-width: 0px)'
  weight: 0
EOF
RC=0; OUT=$(bash "$SCRIPT" "$CP5" 2>/dev/null) || RC=$?
if [ "$RC" -eq 3 ] && [ "$OUT" = "[]" ]; then
  pass_check "no framework auto-detection — breakpoints.yml ignored, exit 3"
else
  fail_check "unexpected framework detection — rc=$RC out=$OUT"
fi

# === Test 12: output is always a JSON array ===
if echo "$OUT" | jq -e 'type == "array"' >/dev/null; then
  pass_check "output is a JSON array"
else
  fail_check "output not a JSON array — got $OUT"
fi

if [ "$FAIL" -ne 0 ]; then
  printf '\nderive-viewport-matrix.sh invariants violated.\n' >&2
  exit 1
fi
printf '\nAll invariants pass for scripts/derive-viewport-matrix.sh.\n'
exit 0
