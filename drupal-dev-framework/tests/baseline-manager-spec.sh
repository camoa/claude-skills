#!/usr/bin/env bash
# baseline-manager-spec.sh — verify scripts/baseline-manager.sh (v4.13.0, Task C).
#
# Covers the PLAN-mode contract (the offline-deterministic surface) — mode +
# arg validation, surfaces_planned scan, --grep scoping, blanket flag, reason
# catalog warning, two-stage confirm (no write without --confirmed).
# EXECUTE mode runs `npx playwright test` and is not exercised here. Run pre-PR.

set -eu

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${PLUGIN_ROOT}/scripts/baseline-manager.sh"
[ -f "$SCRIPT" ] || { printf 'FAIL: %s not found\n' "$SCRIPT" >&2; exit 1; }

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

CP="$TMPDIR/cp"
mkdir -p "$CP/tests/visual" "$CP/.visual-review"
REG="$CP/.visual-review/registry.yml"
touch "$REG"
: > "$CP/tests/visual/home-hero.spec.ts"
: > "$CP/tests/visual/article-card.spec.ts"
: > "$CP/tests/visual/footer.spec.ts"
cat > "$CP/playwright.config.ts" <<'EOF'
projects: [
  { name: 'visual-chromium-desktop' },
  { name: 'visual-chromium-phone' },
]
EOF

# === Test 1: no mode → exit 2 ===
RC=0; bash "$SCRIPT" --registry "$REG" --codepath "$CP" >/dev/null 2>&1 || RC=$?
if [ "$RC" -eq 2 ]; then
  pass_check "no --bootstrap / --update-baselines → exit 2"
else
  fail_check "no mode should exit 2, got $RC"
fi

# === Test 2: --update-baselines without reason → exit 2 ===
RC=0; bash "$SCRIPT" --update-baselines --registry "$REG" --codepath "$CP" >/dev/null 2>&1 || RC=$?
if [ "$RC" -eq 2 ]; then
  pass_check "--update-baselines with no reason → exit 2"
else
  fail_check "--update-baselines no reason should exit 2, got $RC"
fi

# === Test 3: plan mode --bootstrap → stage plan, reason bootstrap, exit 0 ===
RC=0; OUT=$(bash "$SCRIPT" --bootstrap --registry "$REG" --codepath "$CP") || RC=$?
if [ "$RC" -eq 0 ] && [ "$(echo "$OUT" | jq -r '.stage')" = "plan" ] \
   && [ "$(echo "$OUT" | jq -r '.reason')" = "bootstrap" ]; then
  pass_check "plan mode --bootstrap → stage:plan, reason:bootstrap, exit 0"
else
  fail_check "plan --bootstrap — rc=$RC out=$OUT"
fi

# === Test 4: surfaces_planned scanned from tests/visual/*.spec.ts ===
if [ "$(echo "$OUT" | jq -r '.surfaces_planned | sort | join(",")')" = "article-card,footer,home-hero" ]; then
  pass_check "surfaces_planned = all 3 spec stems"
else
  fail_check "surfaces_planned — $(echo "$OUT" | jq -c '.surfaces_planned')"
fi

# === Test 5: blanket true with no --grep ===
if [ "$(echo "$OUT" | jq -r '.blanket')" = "true" ]; then
  pass_check "no --grep → blanket true"
else
  fail_check "blanket should be true — out=$OUT"
fi

# === Test 6: --grep scopes surfaces_planned + sets blanket false ===
OUT=$(bash "$SCRIPT" --update-baselines intentional-ui-change --registry "$REG" --codepath "$CP" --grep 'home-hero')
if [ "$(echo "$OUT" | jq -r '.blanket')" = "false" ] \
   && [ "$(echo "$OUT" | jq -c '.surfaces_planned')" = '["home-hero"]' ]; then
  pass_check "--grep home-hero → blanket false, surfaces_planned [home-hero]"
else
  fail_check "--grep scoping — out=$OUT"
fi

# === Test 7: known trigger → no unknown_trigger warning ===
if ! echo "$OUT" | jq -e '.warnings[] | select(startswith("unknown_trigger"))' >/dev/null; then
  pass_check "known trigger 'intentional-ui-change' → no warning"
else
  fail_check "known trigger wrongly warned — out=$OUT"
fi

# === Test 8: unknown trigger → unknown_trigger warning (still exit 0) ===
RC=0; OUT=$(bash "$SCRIPT" --update-baselines my-freeform-reason --registry "$REG" --codepath "$CP" --grep 'footer') || RC=$?
if [ "$RC" -eq 0 ] && echo "$OUT" | jq -e '.warnings[] | select(startswith("unknown_trigger"))' >/dev/null; then
  pass_check "unknown trigger → unknown_trigger warning, still exit 0"
else
  fail_check "unknown trigger — rc=$RC out=$OUT"
fi

# === Test 9: plan mode writes nothing (no baseline-history.jsonl) ===
if [ ! -f "$CP/.visual-review/baseline-history.jsonl" ]; then
  pass_check "plan mode wrote no baseline-history.jsonl"
else
  fail_check "plan mode must not write baseline-history.jsonl"
fi

# === Test 10: viewports parsed from playwright.config.ts ===
OUT=$(bash "$SCRIPT" --bootstrap --registry "$REG" --codepath "$CP")
if [ "$(echo "$OUT" | jq -r '.viewports | sort | join(",")')" = "desktop,phone" ]; then
  pass_check "viewports parsed from playwright.config.ts: desktop, phone"
else
  fail_check "viewports — $(echo "$OUT" | jq -c '.viewports')"
fi

# === Test 11: history_path is a sibling of the registry ===
if [ "$(echo "$OUT" | jq -r '.history_path')" = "$CP/.visual-review/baseline-history.jsonl" ]; then
  pass_check "history_path sits beside the registry"
else
  fail_check "history_path — $(echo "$OUT" | jq -r '.history_path')"
fi

# === Test 12 (regression, paper-test EC-10): execute mode with --confirmed ===
# but NO visual-chromium-* projects → exit 2, refuses unscoped --update-snapshots
# (would otherwise regenerate ATK's e2e snapshots). The abort happens before
# npx is reached, so this is offline-deterministic.
CP2="$TMPDIR/cp2"
mkdir -p "$CP2/tests/visual" "$CP2/.visual-review"
REG2="$CP2/.visual-review/registry.yml"; touch "$REG2"
: > "$CP2/tests/visual/x.spec.ts"
cat > "$CP2/playwright.config.ts" <<'EOF'
projects: [ { name: 'e2e-chromium' } ]
EOF
RC=0; OUT=$(bash "$SCRIPT" --bootstrap --registry "$REG2" --codepath "$CP2" --confirmed 2>/dev/null) || RC=$?
if [ "$RC" -eq 2 ] && echo "$OUT" | jq -e '.warnings[] | select(startswith("no_visual_projects"))' >/dev/null; then
  pass_check "execute mode, no visual projects → exit 2, refuses unscoped --update-snapshots"
else
  fail_check "no-visual-projects execute guard — rc=$RC out=$OUT"
fi

if [ "$FAIL" -ne 0 ]; then
  printf '\nbaseline-manager.sh invariants violated.\n' >&2
  exit 1
fi
printf '\nAll invariants pass for scripts/baseline-manager.sh.\n'
exit 0
