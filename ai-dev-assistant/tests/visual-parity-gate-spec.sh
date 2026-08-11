#!/usr/bin/env bash
# visual-parity-gate-spec.sh — verify scripts/visual-parity-gate.sh
# (v4.14.0, Task D).
#
# The actual `npx playwright test` run needs a live Playwright + DDEV site, so
# this harness covers the setup-error guards and the JSON-output contract — the
# parts that are deterministic offline. Run pre-PR.

set -eu

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${PLUGIN_ROOT}/scripts/visual-parity-gate.sh"
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

# === Test 3: no tests/parity/ → exit 2 ===
CP="$TMPDIR/cp"; mkdir -p "$CP"
RC=0; bash "$SCRIPT" /tmp/reg.yml "$CP" >/dev/null 2>&1 || RC=$?
if [ "$RC" -eq 2 ]; then
  pass_check "no tests/parity/ → exit 2 (setup error)"
else
  fail_check "no tests/parity/ should exit 2, got $RC"
fi

# === Test 4: no playwright.config.ts → exit 2 ===
mkdir -p "$CP/tests/parity"
RC=0; bash "$SCRIPT" /tmp/reg.yml "$CP" >/dev/null 2>&1 || RC=$?
if [ "$RC" -eq 2 ]; then
  pass_check "no playwright.config.ts → exit 2"
else
  fail_check "no playwright.config.ts should exit 2, got $RC"
fi

# === Test 5: config with no parity-chromium-* projects → exit 0, warning ===
cat > "$CP/playwright.config.ts" <<'EOF'
import { defineConfig } from '@playwright/test';
export default defineConfig({ projects: [{ name: 'visual-chromium-desktop' }] });
EOF
RC=0; OUT=$(bash "$SCRIPT" /tmp/reg.yml "$CP" 2>/dev/null) || RC=$?
if [ "$RC" -eq 0 ] \
   && echo "$OUT" | jq -e '.warnings[] | select(startswith("no_parity_projects"))' >/dev/null \
   && [ "$(echo "$OUT" | jq -c '.surfaces')" = "[]" ]; then
  pass_check "no parity-chromium-* projects → exit 0, no_parity_projects warning, surfaces []"
else
  fail_check "no-parity-projects — rc=$RC out=$OUT"
fi

# === Test 6: output JSON shape ===
if echo "$OUT" | jq -e 'has("surfaces") and has("summary") and has("registry_path") and has("project_pattern") and has("ci_mode") and has("all_viewports") and has("run_dir") and has("max_diff_ratio") and has("playwright_exit") and has("warnings")' >/dev/null; then
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

# === Test 8: --all-viewports reflected in output ===
OUT=$(bash "$SCRIPT" /tmp/reg.yml "$CP" --all-viewports 2>/dev/null || true)
if [ "$(echo "$OUT" | jq -r '.all_viewports')" = "true" ]; then
  pass_check "--all-viewports → all_viewports true in output"
else
  fail_check "--all-viewports flag — out=$OUT"
fi

# === Test 9: summary has zeroed counts when nothing ran ===
if echo "$OUT" | jq -e '.summary | (.surfaces_run == 0 and .passed == 0 and .failed == 0 and .skipped == 0)' >/dev/null; then
  pass_check "summary counts zeroed when no projects ran"
else
  fail_check "summary counts — out=$OUT"
fi

# === Test 10: --project-pattern with regex metacharacters → exit 2 ===
RC=0; bash "$SCRIPT" /tmp/reg.yml "$CP" --project-pattern '.*|evil' >/dev/null 2>&1 || RC=$?
if [ "$RC" -eq 2 ]; then
  pass_check "--project-pattern with metacharacters → exit 2"
else
  fail_check "--project-pattern validation should exit 2, got $RC"
fi
RC=0; bash "$SCRIPT" /tmp/reg.yml "$CP" --project-pattern 'parity-chromium-' >/dev/null 2>&1 || RC=$?
if [ "$RC" -ne 2 ]; then
  pass_check "--project-pattern 'parity-chromium-' (plain) accepted"
else
  fail_check "plain --project-pattern wrongly rejected"
fi

# === Test 11: PARITY_MAX_DIFF_RATIO validated as a real ratio in (0,1) ===
# The gate predicate must match parity-compare.mjs parseRatio() exactly (paper-test F1).
for badval in 'not-a-ratio' '0.0' '.0' '1' '1.5' '-0.2'; do
  RC=0; PARITY_MAX_DIFF_RATIO="$badval" bash "$SCRIPT" /tmp/reg.yml "$CP" >/dev/null 2>&1 || RC=$?
  if [ "$RC" -eq 2 ]; then
    pass_check "PARITY_MAX_DIFF_RATIO='$badval' (outside (0,1)) → exit 2"
  else
    fail_check "PARITY_MAX_DIFF_RATIO='$badval' should exit 2, got $RC"
  fi
done
for goodval in '0.05' '0.08' '0.999' '.5'; do
  RC=0; OUT=$(PARITY_MAX_DIFF_RATIO="$goodval" bash "$SCRIPT" /tmp/reg.yml "$CP" 2>/dev/null) || RC=$?
  if [ "$RC" -ne 2 ]; then
    pass_check "PARITY_MAX_DIFF_RATIO='$goodval' (in (0,1)) accepted"
  else
    fail_check "PARITY_MAX_DIFF_RATIO='$goodval' wrongly rejected"
  fi
done
RC=0; OUT=$(PARITY_MAX_DIFF_RATIO='0.08' bash "$SCRIPT" /tmp/reg.yml "$CP" 2>/dev/null) || RC=$?
if [ "$(echo "$OUT" | jq -r '.max_diff_ratio')" = "0.08" ]; then
  pass_check "valid PARITY_MAX_DIFF_RATIO env echoed into output"
else
  fail_check "PARITY_MAX_DIFF_RATIO echo — out=$OUT"
fi

# === Test 12: per-surface threshold (D4) + content-floor (D8) verdict, end-to-end ===
# Drive the REAL gate merge+verdict logic by stubbing `npx` to emit synthetic
# .parity.json fragments into PARITY_RUN_DIR (no live Playwright). This exercises the
# actual jq verdict expression in the gate — not a copy — so the F1 verdict-parity rule
# (gate uses each fragment's effective max_diff_ratio, content_floor_failed forces fail,
# a legacy fragment with no max_diff_ratio falls back to the global) is tested for real.
CP2="$TMPDIR/cp2"; mkdir -p "$CP2/tests/parity"
cat > "$CP2/playwright.config.ts" <<'EOF'
import { defineConfig } from '@playwright/test';
export default defineConfig({ projects: [{ name: 'parity-chromium-desktop' }] });
EOF

FAKEBIN="$TMPDIR/fakebin"; mkdir -p "$FAKEBIN"
cat > "$FAKEBIN/npx" <<'EOF'
#!/usr/bin/env bash
# fake npx: ignore the playwright args, write the per-surface fragments the gate merges.
mkdir -p "$PARITY_RUN_DIR"
# 1) plain pass: under the global 0.05
cat > "$PARITY_RUN_DIR/s-pass-desktop.parity.json" <<J
{"surface":"s-pass","viewport":"desktop","reference_type":"html-template","pixel_diff_ratio":0.02,"max_diff_ratio":0.05,"css_diff":[],"content_floor_failed":false,"content_floor_violations":[],"skipped":false}
J
# 2) per-surface threshold rescues a cross-stack surface (0.30 < 0.40 → pass, would FAIL at global 0.05)
cat > "$PARITY_RUN_DIR/s-hi-thresh-pass-desktop.parity.json" <<J
{"surface":"s-hi-thresh-pass","viewport":"desktop","reference_type":"prod-url","pixel_diff_ratio":0.30,"max_diff_ratio":0.40,"css_diff":[],"content_floor_failed":false,"content_floor_violations":[],"skipped":false}
J
# 3) over even the high per-surface threshold (0.50 >= 0.40 → fail)
cat > "$PARITY_RUN_DIR/s-hi-thresh-fail-desktop.parity.json" <<J
{"surface":"s-hi-thresh-fail","viewport":"desktop","reference_type":"prod-url","pixel_diff_ratio":0.50,"max_diff_ratio":0.40,"css_diff":[],"content_floor_failed":false,"content_floor_violations":[],"skipped":false}
J
# 4) content-floor failure forces fail despite a tiny pixel diff (D8)
cat > "$PARITY_RUN_DIR/s-floor-desktop.parity.json" <<J
{"surface":"s-floor","viewport":"desktop","reference_type":"html-template","pixel_diff_ratio":0.01,"max_diff_ratio":0.05,"css_diff":[],"content_floor_failed":true,"content_floor_violations":["rendered height 40px < required 800px"],"skipped":false}
J
# 5) legacy fragment with NO max_diff_ratio → falls back to the global 0.05 (0.10 >= 0.05 → fail)
cat > "$PARITY_RUN_DIR/s-legacy-desktop.parity.json" <<J
{"surface":"s-legacy","viewport":"desktop","reference_type":"image","pixel_diff_ratio":0.10,"css_diff":[],"skipped":false}
J
exit 0
EOF
chmod +x "$FAKEBIN/npx"

RC=0; OUT=$(PATH="$FAKEBIN:$PATH" PARITY_MAX_DIFF_RATIO='0.05' bash "$SCRIPT" /tmp/reg.yml "$CP2" 2>/dev/null) || RC=$?

verdict_of() { echo "$OUT" | jq -r --arg id "$1" '.surfaces[] | select(.id == $id) | .verdict'; }

if [ "$(verdict_of s-pass)" = "pass" ]; then
  pass_check "D4: a surface under its threshold → pass"
else
  fail_check "D4 s-pass verdict — out=$OUT"
fi
if [ "$(verdict_of s-hi-thresh-pass)" = "pass" ]; then
  pass_check "D4: per-surface max_diff_ratio rescues a cross-stack surface (0.30 < 0.40)"
else
  fail_check "D4 s-hi-thresh-pass — expected pass via per-surface threshold — out=$OUT"
fi
if [ "$(verdict_of s-hi-thresh-fail)" = "fail" ]; then
  pass_check "D4: over even the high per-surface threshold → fail"
else
  fail_check "D4 s-hi-thresh-fail — out=$OUT"
fi
if [ "$(verdict_of s-floor)" = "fail" ]; then
  pass_check "D8: content_floor_failed forces fail despite a tiny pixel diff"
else
  fail_check "D8 s-floor verdict — out=$OUT"
fi
if [ "$(verdict_of s-legacy)" = "fail" ]; then
  pass_check "D4 back-compat: a fragment with no max_diff_ratio falls back to the global (0.10 >= 0.05)"
else
  fail_check "D4 legacy fallback — out=$OUT"
fi
# summary + exit code: 2 pass, 3 fail, 0 skipped → exit 1
if echo "$OUT" | jq -e '.summary | (.surfaces_run == 5 and .passed == 2 and .failed == 3 and .skipped == 0)' >/dev/null; then
  pass_check "D4/D8: summary counts 2 passed / 3 failed across the fragment set"
else
  fail_check "summary counts — out=$OUT"
fi
if [ "$RC" -eq 1 ]; then
  pass_check "D4/D8: >=1 failed surface → exit 1"
else
  fail_check "expected exit 1 with failures, got $RC"
fi
# the verdict-bearing fields are surfaced in each row (output-shape extension)
if echo "$OUT" | jq -e '.surfaces[] | select(.id == "s-floor") | has("max_diff_ratio") and has("content_floor_failed") and has("content_floor_violations")' >/dev/null; then
  pass_check "rows carry max_diff_ratio + content_floor_failed + content_floor_violations"
else
  fail_check "row shape missing new fields — out=$OUT"
fi

if [ "$FAIL" -ne 0 ]; then
  printf '\nvisual-parity-gate.sh invariants violated.\n' >&2
  exit 1
fi
printf '\nAll invariants pass for scripts/visual-parity-gate.sh.\n'
exit 0
