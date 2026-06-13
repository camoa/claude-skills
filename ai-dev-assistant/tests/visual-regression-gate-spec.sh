#!/usr/bin/env bash
# visual-regression-gate-spec.sh — verify scripts/visual-regression-gate.sh
# (v4.13.0, Task C).
#
# The actual `npx playwright test` run needs a live Playwright + DDEV site, so
# this harness covers the setup-error guards and the JSON-output contract — the
# parts that are deterministic offline. Run pre-PR.

set -eu

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${PLUGIN_ROOT}/scripts/visual-regression-gate.sh"
[ -f "$SCRIPT" ] || { printf 'FAIL: %s not found\n' "$SCRIPT" >&2; exit 1; }

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# === Test 1: missing args → exit 2 ===
RC=0; bash "$SCRIPT" >/dev/null 2>&1 || RC=$?
if [ "$RC" -eq 2 ]; then
  pass_check "no args → exit 2"
else
  fail_check "no args should exit 2, got $RC"
fi

# === Test 2: codePath does not exist → exit 2 ===
RC=0; bash "$SCRIPT" /tmp/reg.yml "$TMPDIR/nope" >/dev/null 2>&1 || RC=$?
if [ "$RC" -eq 2 ]; then
  pass_check "missing codePath → exit 2"
else
  fail_check "missing codePath should exit 2, got $RC"
fi

# === Test 3: no tests/visual/ → exit 2 ===
CP="$TMPDIR/cp"; mkdir -p "$CP"
RC=0; bash "$SCRIPT" /tmp/reg.yml "$CP" >/dev/null 2>&1 || RC=$?
if [ "$RC" -eq 2 ]; then
  pass_check "no tests/visual/ → exit 2 (setup error)"
else
  fail_check "no tests/visual/ should exit 2, got $RC"
fi

# === Test 4: no playwright.config.ts → exit 2 ===
mkdir -p "$CP/tests/visual"
RC=0; bash "$SCRIPT" /tmp/reg.yml "$CP" >/dev/null 2>&1 || RC=$?
if [ "$RC" -eq 2 ]; then
  pass_check "no playwright.config.ts → exit 2"
else
  fail_check "no playwright.config.ts should exit 2, got $RC"
fi

# === Test 5: config with no visual-chromium-* projects → exit 0, warning ===
cat > "$CP/playwright.config.ts" <<'EOF'
import { defineConfig } from '@playwright/test';
export default defineConfig({ projects: [{ name: 'e2e-chromium' }] });
EOF
RC=0; OUT=$(bash "$SCRIPT" /tmp/reg.yml "$CP" 2>/dev/null) || RC=$?
if [ "$RC" -eq 0 ] \
   && echo "$OUT" | jq -e '.warnings[] | select(startswith("no_visual_projects"))' >/dev/null \
   && [ "$(echo "$OUT" | jq -c '.surfaces')" = "[]" ]; then
  pass_check "no visual-chromium-* projects → exit 0, no_visual_projects warning, surfaces []"
else
  fail_check "no-visual-projects — rc=$RC out=$OUT"
fi

# === Test 6: output JSON shape ===
if echo "$OUT" | jq -e 'has("surfaces") and has("summary") and has("registry_path") and has("project_pattern") and has("ci_mode") and has("playwright_exit") and has("warnings")' >/dev/null; then
  pass_check "output carries all required keys"
else
  fail_check "output shape — out=$OUT"
fi

# === Test 7: --ci flag reflected in output ===
OUT=$(bash "$SCRIPT" /tmp/reg.yml "$CP" --ci 2>/dev/null || true)
if [ "$(echo "$OUT" | jq -r '.ci_mode')" = "true" ]; then
  pass_check "--ci → ci_mode true in output"
else
  fail_check "--ci flag — out=$OUT"
fi

# === Test 8: summary has zeroed counts when nothing ran ===
if echo "$OUT" | jq -e '.summary | (.surfaces_run == 0 and .passed == 0 and .failed == 0 and .skipped == 0)' >/dev/null; then
  pass_check "summary counts zeroed when no projects ran"
else
  fail_check "summary counts — out=$OUT"
fi

# === Test 9 (regression, paper-test RT-4): --project-pattern with regex ===
# metacharacters → exit 2 (rejected before interpolation into a grep regex).
RC=0; bash "$SCRIPT" /tmp/reg.yml "$CP" --project-pattern '.*|evil' >/dev/null 2>&1 || RC=$?
if [ "$RC" -eq 2 ]; then
  pass_check "--project-pattern with metacharacters → exit 2"
else
  fail_check "--project-pattern validation should exit 2, got $RC"
fi
RC=0; bash "$SCRIPT" /tmp/reg.yml "$CP" --project-pattern 'visual-chromium-' >/dev/null 2>&1 || RC=$?
if [ "$RC" -ne 2 ]; then
  pass_check "--project-pattern 'visual-chromium-' (plain) accepted"
else
  fail_check "plain --project-pattern wrongly rejected"
fi

if [ "$FAIL" -ne 0 ]; then
  printf '\nvisual-regression-gate.sh invariants violated.\n' >&2
  exit 1
fi
printf '\nAll invariants pass for scripts/visual-regression-gate.sh.\n'
exit 0
