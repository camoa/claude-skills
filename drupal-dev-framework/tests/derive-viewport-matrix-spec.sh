#!/usr/bin/env bash
# derive-viewport-matrix-spec.sh — verify scripts/derive-viewport-matrix.sh (v4.13.0, Task C).
#
# Covers: breakpoints.yml parse, min-width:0 → 375, height bands, weight sort,
# Radix fallback, CSS @media fallback, exit-3 on nothing-derivable.
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

# === Test 1: breakpoints.yml — 3 breakpoints, weight-sorted ===
CP1="$TMPDIR/cp1"
mkdir -p "$CP1/web/themes/custom/mytheme"
cat > "$CP1/web/themes/custom/mytheme/mytheme.breakpoints.yml" <<'EOF'
mytheme.desktop:
  label: desktop
  mediaQuery: '(min-width: 1200px)'
  weight: 2
mytheme.mobile:
  label: mobile
  mediaQuery: '(min-width: 0px)'
  weight: 0
mytheme.tablet:
  label: tablet
  mediaQuery: '(min-width: 768px)'
  weight: 1
EOF
OUT=$(bash "$SCRIPT" "$CP1"); RC=$?
if [ "$RC" -eq 0 ] && [ "$(echo "$OUT" | jq -r '.[0].name')" = "mobile" ] \
   && [ "$(echo "$OUT" | jq -r '.[2].name')" = "desktop" ]; then
  pass_check "breakpoints.yml parsed, weight-sorted (mobile..desktop)"
else
  fail_check "breakpoints.yml parse — rc=$RC out=$OUT"
fi

# === Test 2: min-width:0 → width 375, height 812 ===
if [ "$(echo "$OUT" | jq -r '.[0].width')" = "375" ] \
   && [ "$(echo "$OUT" | jq -r '.[0].height')" = "812" ]; then
  pass_check "min-width:0 → 375x812 (mobile-first canonical)"
else
  fail_check "min-width:0 mapping — got $(echo "$OUT" | jq -c '.[0]')"
fi

# === Test 3: height bands (768 → 1024, 1200 → 900) ===
if [ "$(echo "$OUT" | jq -r '.[1].height')" = "1024" ] \
   && [ "$(echo "$OUT" | jq -r '.[2].height')" = "900" ]; then
  pass_check "height bands: 768→1024, 1200→900"
else
  fail_check "height bands — tablet=$(echo "$OUT" | jq -r '.[1].height') desktop=$(echo "$OUT" | jq -r '.[2].height')"
fi

# === Test 4: nothing derivable → exit 3, [] ===
CP2="$TMPDIR/cp2"; mkdir -p "$CP2"
RC=0; OUT=$(bash "$SCRIPT" "$CP2" 2>/dev/null) || RC=$?
if [ "$RC" -eq 3 ] && [ "$OUT" = "[]" ]; then
  pass_check "no breakpoints + no CSS → exit 3, []"
else
  fail_check "nothing-derivable — rc=$RC out=$OUT"
fi

# === Test 5: Radix fallback ===
CP3="$TMPDIR/cp3"
mkdir -p "$CP3/web/themes/contrib/radix"
cat > "$CP3/web/themes/contrib/radix/radix.breakpoints.yml" <<'EOF'
radix.sm:
  mediaQuery: '(min-width: 576px)'
  weight: 0
radix.lg:
  mediaQuery: '(min-width: 992px)'
  weight: 1
EOF
RC=0; OUT=$(bash "$SCRIPT" "$CP3") || RC=$?
if [ "$RC" -eq 0 ] && [ "$(echo "$OUT" | jq 'length')" = "2" ] \
   && echo "$OUT" | jq -e '.[0]._source | startswith("breakpoints.yml:radix")' >/dev/null; then
  pass_check "Radix contrib fallback parsed"
else
  fail_check "Radix fallback — rc=$RC out=$OUT"
fi

# === Test 6: CSS @media fallback ===
CP4="$TMPDIR/cp4"
mkdir -p "$CP4/web/themes/custom/t"
cat > "$CP4/web/themes/custom/t/style.css" <<'EOF'
@media (min-width: 480px) { .a { color: red; } }
@media (min-width: 1024px) { .b { color: blue; } }
EOF
RC=0; OUT=$(bash "$SCRIPT" "$CP4") || RC=$?
if [ "$RC" -eq 0 ] && [ "$(echo "$OUT" | jq 'length')" -ge 2 ] \
   && echo "$OUT" | jq -e '.[0]._source == "css-media"' >/dev/null; then
  pass_check "CSS @media fallback → viewports with _source css-media"
else
  fail_check "CSS @media fallback — rc=$RC out=$OUT"
fi

# === Test 7: output is always a JSON array ===
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
