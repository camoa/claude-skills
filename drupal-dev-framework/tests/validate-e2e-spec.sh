#!/usr/bin/env bash
# validate-e2e-spec.sh — verify scripts/validate-e2e.sh argument parsing,
# JSON output shape, exit codes, and --surfaces-json integration.
#
# Does NOT invoke npx playwright or ddev (not available in test env).
# Uses stubs that simulate Playwright success/failure output to test
# the script's JSON assembly, verdict logic, and exit codes.
#
# Run: bash tests/validate-e2e-spec.sh
# Exit 0 = all pass; non-zero = one or more checks failed.

set -eu

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${PLUGIN_ROOT}/scripts/validate-e2e.sh"

if [ ! -f "$SCRIPT" ]; then
  printf 'FAIL: %s not found\n' "$SCRIPT" >&2
  exit 1
fi

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# ─── helpers ─────────────────────────────────────────────────────────────────

# Create stubs dir and add to PATH
setup_stubs() {
  mkdir -p "$TMPDIR/stubs"
  export PATH="$TMPDIR/stubs:$PATH"
}

# Create a stub npx that echoes Playwright pass output and exits 0
stub_npx_pass() {
  cat > "$TMPDIR/stubs/npx" <<'STUB'
#!/bin/sh
# Simulate: "39 passed, 0 failed, 0 skipped"
echo "  39 passed (10s)"
echo "  39 passed, 0 skipped"
exit 0
STUB
  chmod +x "$TMPDIR/stubs/npx"
}

# Create a stub npx that echoes Playwright fail output and exits 1
stub_npx_fail() {
  cat > "$TMPDIR/stubs/npx" <<'STUB'
#!/bin/sh
# Simulate: "37 passed, 2 failed"
echo "  × anonymous-reads-article [chromium] (5.2s)"
echo "  × editor-creates-post [chromium] (3.1s)"
echo "  37 passed, 2 failed"
exit 1
STUB
  chmod +x "$TMPDIR/stubs/npx"
}

# Stub ddev to exit 0 (preflight passes)
stub_ddev_ok() {
  cat > "$TMPDIR/stubs/ddev" <<'STUB'
#!/bin/sh
exit 0
STUB
  chmod +x "$TMPDIR/stubs/ddev"
}

# Create a fake codePath with .ddev/config.yaml
make_code_path() {
  local dir="$1"
  mkdir -p "$dir/.ddev"
  echo "name: test" > "$dir/.ddev/config.yaml"
}

# ─── Test 1: missing codePath → non-zero exit ────────────────────────────────
rc=0
bash "$SCRIPT" 2>/dev/null || rc=$?
if [ "$rc" -ne 0 ]; then
  pass_check "missing codePath → non-zero exit"
else
  fail_check "missing codePath should exit non-zero"
fi

# ─── Test 2: nonexistent codePath → exit 2 ───────────────────────────────────
rc=0
bash "$SCRIPT" "/nonexistent/xyz" 2>/dev/null || rc=$?
if [ "$rc" -eq 2 ]; then
  pass_check "nonexistent codePath → exit 2"
else
  fail_check "nonexistent codePath should exit 2, got $rc"
fi

# ─── Test 3: unknown flag → exit 2 ───────────────────────────────────────────
PROJ="$TMPDIR/proj"
make_code_path "$PROJ"
setup_stubs
stub_npx_pass
stub_ddev_ok
rc=0
bash "$SCRIPT" "$PROJ" --unknown-flag 2>/dev/null || rc=$?
if [ "$rc" -eq 2 ]; then
  pass_check "unknown flag → exit 2"
else
  fail_check "unknown flag should exit 2, got $rc"
fi

# ─── Test 4: pass run → exit 0 + valid JSON + verdict pass ───────────────────
stub_npx_pass
stub_ddev_ok
rc=0
OUT=$(bash "$SCRIPT" "$PROJ" 2>/dev/null) || rc=$?
if [ "$rc" -eq 0 ]; then
  pass_check "pass run → exit 0"
else
  fail_check "pass run → unexpected exit $rc"
fi

# Check JSON structure
if echo "$OUT" | jq -e \
   'has("schema_version") and has("gate_type") and has("verdict") and
    has("total_tests") and has("passed") and has("failed") and
    has("skipped") and has("report_path") and
    has("failed_tests") and has("preflight_warnings")' >/dev/null 2>&1; then
  pass_check "pass run: output JSON has all required keys"
else
  fail_check "pass run: output JSON missing keys — got: $OUT"
fi

if [ "$(echo "$OUT" | jq -r '.verdict')" = "pass" ]; then
  pass_check "pass run: verdict=pass"
else
  fail_check "pass run: verdict should be pass, got: $(echo "$OUT" | jq -r '.verdict')"
fi

if [ "$(echo "$OUT" | jq -r '.gate_type')" = "e2e" ]; then
  pass_check "pass run: gate_type=e2e"
else
  fail_check "pass run: gate_type should be e2e"
fi

# ─── Test 5: fail run → exit 1 + verdict fail ────────────────────────────────
stub_npx_fail
stub_ddev_ok
rc=0
OUT=$(bash "$SCRIPT" "$PROJ" 2>/dev/null) || rc=$?
if [ "$rc" -eq 1 ]; then
  pass_check "fail run → exit 1"
else
  fail_check "fail run should exit 1, got $rc"
fi

if [ "$(echo "$OUT" | jq -r '.verdict')" = "fail" ]; then
  pass_check "fail run: verdict=fail"
else
  fail_check "fail run: verdict should be fail"
fi

if [ "$(echo "$OUT" | jq -r '.failed')" -gt 0 ] 2>/dev/null; then
  pass_check "fail run: .failed > 0"
else
  fail_check "fail run: .failed should be > 0, got: $(echo "$OUT" | jq -r '.failed')"
fi

# ─── Test 6: --smoke-only flag parses and is accepted ────────────────────────
stub_npx_pass
stub_ddev_ok
rc=0
OUT=$(bash "$SCRIPT" "$PROJ" --smoke-only 2>/dev/null) || rc=$?
if [ "$rc" -eq 0 ]; then
  pass_check "--smoke-only → exit 0"
else
  fail_check "--smoke-only → unexpected exit $rc"
fi

# ─── Test 7: --surfaces-json flag parses and is accepted ─────────────────────
stub_npx_pass
stub_ddev_ok
rc=0
OUT=$(bash "$SCRIPT" "$PROJ" --surfaces-json '["atk-login","atk-homepage"]' 2>/dev/null) || rc=$?
if [ "$rc" -eq 0 ]; then
  pass_check "--surfaces-json → exit 0"
else
  fail_check "--surfaces-json → unexpected exit $rc"
fi

# ─── Test 8: --task flag parses and is accepted ───────────────────────────────
stub_npx_pass
stub_ddev_ok
rc=0
OUT=$(bash "$SCRIPT" "$PROJ" --task "my_feature" 2>/dev/null) || rc=$?
if [ "$rc" -eq 0 ]; then
  pass_check "--task → exit 0"
else
  fail_check "--task → unexpected exit $rc"
fi

# ─── Test 9: output JSON is always valid JSON ─────────────────────────────────
stub_npx_pass
stub_ddev_ok
OUT=$(bash "$SCRIPT" "$PROJ" 2>/dev/null)
if echo "$OUT" | jq empty >/dev/null 2>&1; then
  pass_check "output is always valid JSON"
else
  fail_check "output is not valid JSON: $OUT"
fi

# ─── Test 10: report_path field is non-empty ─────────────────────────────────
stub_npx_pass
stub_ddev_ok
OUT=$(bash "$SCRIPT" "$PROJ" 2>/dev/null)
RPATH=$(echo "$OUT" | jq -r '.report_path')
if [ -n "$RPATH" ]; then
  pass_check "report_path is non-empty: $RPATH"
else
  fail_check "report_path is empty"
fi

# ─── Report ──────────────────────────────────────────────────────────────────

if [ "$FAIL" -ne 0 ]; then
  printf '\nvalidate-e2e.sh invariants violated.\n' >&2
  exit 1
fi
printf '\nAll invariants pass for scripts/validate-e2e.sh.\n'
exit 0
