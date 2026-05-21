#!/usr/bin/env bash
# setup-atk-idempotency-spec.sh — verify scripts/setup-atk-idempotency.sh
# detection logic, JSON output shape, status semantics, and exit-0-always.
#
# Does NOT invoke ddev (not available in test env). Uses fixture directories
# to simulate absent/partial/complete states.
#
# Run: bash tests/setup-atk-idempotency-spec.sh
# Exit 0 = all pass; non-zero = one or more checks failed.

set -eu

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${PLUGIN_ROOT}/scripts/setup-atk-idempotency.sh"

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

# Run script and return its output + exit code
run_script() {
  local code_path="$1"
  local rc=0
  local out
  out=$(bash "$SCRIPT" "$code_path" 2>/dev/null) || rc=$?
  echo "$out"
}

check_json_key() {
  local label="$1" json="$2" key="$3" expected="$4"
  local actual
  actual=$(echo "$json" | jq -r ".$key" 2>/dev/null || echo "__jq_fail__")
  if [ "$actual" = "$expected" ]; then
    pass_check "$label: .$key = $expected"
  else
    fail_check "$label: .$key expected $expected, got $actual"
  fi
}

# ─── Test 1: missing codePath → exit 0 + absent ──────────────────────────────
rc=0
OUT=$(bash "$SCRIPT" 2>/dev/null) || rc=$?
if [ "$rc" -eq 0 ]; then
  pass_check "missing codePath → exit 0"
else
  fail_check "missing codePath should exit 0, got $rc"
fi

STATUS=$(echo "$OUT" | jq -r '.status' 2>/dev/null || echo "")
if [ "$STATUS" = "absent" ]; then
  pass_check "missing codePath → status=absent"
else
  fail_check "missing codePath → expected status=absent, got '$STATUS'"
fi

# ─── Test 2: nonexistent codePath → exit 0 + absent ─────────────────────────
rc=0
OUT=$(bash "$SCRIPT" "/nonexistent/xyz" 2>/dev/null) || rc=$?
if [ "$rc" -eq 0 ]; then
  pass_check "nonexistent codePath → exit 0"
else
  fail_check "nonexistent codePath should exit 0, got $rc"
fi
check_json_key "nonexistent codePath" "$OUT" "status" "absent"

# ─── Test 3: empty project → status=absent ───────────────────────────────────
PROJ_EMPTY="$TMPDIR/proj_empty"
mkdir -p "$PROJ_EMPTY"
OUT=$(run_script "$PROJ_EMPTY")
check_json_key "empty project" "$OUT" "status" "absent"
check_json_key "empty project" "$OUT" "atk_composer_installed" "false"
check_json_key "empty project" "$OUT" "tests_e2e_exists" "false"

# ─── Test 4: output JSON always has all required keys ────────────────────────
if echo "$OUT" | jq -e \
   'has("atk_composer_installed") and has("atk_module_enabled") and
    has("tests_e2e_exists") and has("playwright_config_has_e2e_entry") and
    has("registry_has_e2e_surfaces") and has("status")' >/dev/null 2>&1; then
  pass_check "output JSON has all 6 required keys"
else
  fail_check "output JSON missing required keys: $OUT"
fi

# ─── Test 5: exit 0 always — even bogus path ─────────────────────────────────
rc=0
bash "$SCRIPT" "/completely/bogus/path" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then
  pass_check "exit 0 always (bogus path)"
else
  fail_check "should exit 0 with bogus path, got $rc"
fi

# ─── Test 6: tests/e2e/ exists → tests_e2e_exists=true ──────────────────────
PROJ_PARTIAL="$TMPDIR/proj_partial"
mkdir -p "$PROJ_PARTIAL/.ddev" "$PROJ_PARTIAL/tests/e2e"
echo "name: test" > "$PROJ_PARTIAL/.ddev/config.yaml"
OUT=$(run_script "$PROJ_PARTIAL")
check_json_key "with tests/e2e/" "$OUT" "tests_e2e_exists" "true"

# ─── Test 7: partial install → status=partial ────────────────────────────────
# Only tests/e2e/ exists; no registry, no playwright config
check_json_key "partial install" "$OUT" "status" "partial"

# ─── Test 8: playwright.config.ts with e2e-chromium → playwright_config=true ─
PROJ_PW="$TMPDIR/proj_pw"
mkdir -p "$PROJ_PW/.ddev" "$PROJ_PW/tests/e2e"
echo "name: test" > "$PROJ_PW/.ddev/config.yaml"
cat > "$PROJ_PW/playwright.config.ts" <<'PW'
export default {
  projects: [{ name: 'e2e-chromium', testDir: './tests/e2e/behavioral' }]
};
PW
OUT=$(run_script "$PROJ_PW")
check_json_key "playwright config with e2e-chromium" "$OUT" "playwright_config_has_e2e_entry" "true"

# ─── Test 9: registry with e2e surfaces → registry_has_e2e_surfaces=true ─────
PROJ_REG="$TMPDIR/proj_reg"
mkdir -p "$PROJ_REG/.ddev" "$PROJ_REG/tests/e2e" "$PROJ_REG/.visual-review"
echo "name: test" > "$PROJ_REG/.ddev/config.yaml"
cat > "$PROJ_REG/.visual-review/registry.yml" <<'REG'
schema_version: "1.0"
surfaces:
  - id: atk-login
    url: "/user/login"
    gates: [e2e]
REG
OUT=$(run_script "$PROJ_REG")
check_json_key "registry with e2e surfaces" "$OUT" "registry_has_e2e_surfaces" "true"

# ─── Test 10: registry without e2e → registry_has_e2e_surfaces=false ─────────
PROJ_REG2="$TMPDIR/proj_reg2"
mkdir -p "$PROJ_REG2/.ddev" "$PROJ_REG2/.visual-review"
echo "name: test" > "$PROJ_REG2/.ddev/config.yaml"
cat > "$PROJ_REG2/.visual-review/registry.yml" <<'REG2'
schema_version: "1.0"
surfaces:
  - id: homepage
    url: "/"
    gates: [visual_regression]
REG2
OUT=$(run_script "$PROJ_REG2")
check_json_key "registry without e2e gates" "$OUT" "registry_has_e2e_surfaces" "false"

# ─── Test 11: all checks false → status=absent ───────────────────────────────
PROJ_ALL_FALSE="$TMPDIR/proj_all_false"
mkdir -p "$PROJ_ALL_FALSE/.ddev"
echo "name: test" > "$PROJ_ALL_FALSE/.ddev/config.yaml"
OUT=$(run_script "$PROJ_ALL_FALSE")
check_json_key "all checks false" "$OUT" "status" "absent"

# ─── Test 12: output is valid JSON ───────────────────────────────────────────
OUT=$(run_script "$PROJ_EMPTY")
if echo "$OUT" | jq empty >/dev/null 2>&1; then
  pass_check "output is always valid JSON"
else
  fail_check "output is not valid JSON: $OUT"
fi

# ─── Report ──────────────────────────────────────────────────────────────────

if [ "$FAIL" -ne 0 ]; then
  printf '\nsetup-atk-idempotency.sh invariants violated.\n' >&2
  exit 1
fi
printf '\nAll invariants pass for scripts/setup-atk-idempotency.sh.\n'
exit 0
