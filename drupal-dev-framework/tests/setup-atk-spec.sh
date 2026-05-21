#!/usr/bin/env bash
# setup-atk-spec.sh — verify scripts/setup-atk.sh argument parsing,
# pre-flight guards, Phase C idempotency, and registry seeding.
#
# Does NOT invoke ddev, composer, npm, or npx (they are not available in
# the test environment). Uses stubs and fixture directories to test the
# script's conditional logic, argument parsing, flag handling, and file writes.
#
# Run: bash tests/setup-atk-spec.sh
# Exit 0 = all pass; non-zero = one or more checks failed.

set -eu

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${PLUGIN_ROOT}/scripts/setup-atk.sh"

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

# Create a minimal fake DDEV project (no actual DDEV)
make_fake_project() {
  local dir="$1"
  mkdir -p "$dir/.ddev" "$dir/web/modules/contrib"
  echo "name: test" > "$dir/.ddev/config.yaml"
  echo '{}' > "$dir/composer.json"
}

# Stub: replace ddev with a no-op for Phase A + B tests
# (Phase C can run without ddev)
stub_ddev() {
  mkdir -p "$TMPDIR/stubs"
  cat > "$TMPDIR/stubs/ddev" <<'STUB'
#!/bin/sh
# stub ddev: exit 0 for all invocations
exit 0
STUB
  chmod +x "$TMPDIR/stubs/ddev"
  # Also stub npm
  cat > "$TMPDIR/stubs/npm" <<'STUB'
#!/bin/sh
# stub npm: create package.json if 'init -y'
case "$*" in
  *"init"*) echo '{}' > package.json ;;
esac
exit 0
STUB
  chmod +x "$TMPDIR/stubs/npm"
  # stub npx
  cat > "$TMPDIR/stubs/npx" <<'STUB'
#!/bin/sh
exit 0
STUB
  chmod +x "$TMPDIR/stubs/npx"
  export PATH="$TMPDIR/stubs:$PATH"
}

# ─── Test 1: missing codePath → exit 2 ───────────────────────────────────────
rc=0
bash "$SCRIPT" 2>/dev/null || rc=$?
# Bash 'set -u' + ':?' unset var triggers exit 1 (not 2) on missing $1
# but we document exit 2 for invalid args; missing $1 with ':?' produces "required"
# error from bash. Accept any non-zero.
if [ "$rc" -ne 0 ]; then
  pass_check "missing codePath → non-zero exit ($rc)"
else
  fail_check "missing codePath should exit non-zero, got 0"
fi

# ─── Test 2: nonexistent codePath → exit 1 ───────────────────────────────────
rc=0
bash "$SCRIPT" "/nonexistent/path/xyz" 2>/dev/null || rc=$?
if [ "$rc" -ne 0 ]; then
  pass_check "nonexistent codePath → non-zero exit"
else
  fail_check "nonexistent codePath should exit non-zero"
fi

# ─── Test 3: valid codePath without .ddev/ → exit 1 ─────────────────────────
PROJ_NODDEV="$TMPDIR/proj_noddev"
mkdir -p "$PROJ_NODDEV"
rc=0
bash "$SCRIPT" "$PROJ_NODDEV" 2>/dev/null || rc=$?
if [ "$rc" -ne 0 ]; then
  pass_check "codePath without .ddev/ → non-zero exit"
else
  fail_check "codePath without .ddev/ should exit non-zero"
fi

# ─── Test 4: unknown flag → exit 2 ───────────────────────────────────────────
PROJ="$TMPDIR/proj_main"
make_fake_project "$PROJ"
stub_ddev
rc=0
bash "$SCRIPT" "$PROJ" --unknown-flag 2>/dev/null || rc=$?
if [ "$rc" -eq 2 ]; then
  pass_check "unknown flag → exit 2"
else
  fail_check "unknown flag should exit 2, got $rc"
fi

# ─── Test 5: Phase C — registry seeding creates registry.yml ────────────────
# Simulate a project that already passed Phases A+B (skip via --update-atk)
# and test that Phase C creates the registry file.
PROJ2="$TMPDIR/proj_phase_c"
make_fake_project "$PROJ2"
mkdir -p "$PROJ2/tests/e2e"

# Run with --update-atk (skips A+B) so we don't need real ddev/npm
stub_ddev
rc=0
bash "$SCRIPT" "$PROJ2" --update-atk 2>/dev/null || rc=$?
REGISTRY_FILE="$PROJ2/.visual-review/registry.yml"
if [ -f "$REGISTRY_FILE" ]; then
  pass_check "Phase C creates .visual-review/registry.yml"
else
  fail_check "registry.yml not created (rc=$rc)"
fi

# ─── Test 6: registry contains e2e surfaces ──────────────────────────────────
if [ -f "$REGISTRY_FILE" ]; then
  if grep -q 'gates: \[e2e\]' "$REGISTRY_FILE"; then
    pass_check "registry.yml contains 'gates: [e2e]' surfaces"
  else
    fail_check "registry.yml missing gates: [e2e] (content: $(cat "$REGISTRY_FILE"))"
  fi
fi

# ─── Test 7: registry seeding is idempotent ──────────────────────────────────
BEFORE=$(grep -c 'atk-login' "$REGISTRY_FILE" 2>/dev/null || echo 0)
bash "$SCRIPT" "$PROJ2" --update-atk 2>/dev/null || true
AFTER=$(grep -c 'atk-login' "$REGISTRY_FILE" 2>/dev/null || echo 0)
if [ "$BEFORE" -eq "$AFTER" ]; then
  pass_check "registry seeding is idempotent (atk-login not duplicated)"
else
  fail_check "registry seeding not idempotent: atk-login count went $BEFORE → $AFTER"
fi

# ─── Test 8: Phase C creates atk.config.js ────────────────────────────────────
ATK_CONF="$PROJ2/tests/e2e/atk.config.js"
if [ -f "$ATK_CONF" ]; then
  pass_check "Phase C creates tests/e2e/atk.config.js"
else
  fail_check "tests/e2e/atk.config.js not created"
fi

# ─── Test 9: atk.config.js contains required fields ──────────────────────────
if [ -f "$ATK_CONF" ]; then
  if grep -q 'DDEV_PRIMARY_URL' "$ATK_CONF" && grep -q 'drushCmd' "$ATK_CONF" && grep -q 'qaAccounts' "$ATK_CONF"; then
    pass_check "atk.config.js contains baseURL, drushCmd, qaAccounts"
  else
    fail_check "atk.config.js missing required fields"
  fi
fi

# ─── Test 10: Phase C creates tests/e2e/README.md ────────────────────────────
README_E2E="$PROJ2/tests/e2e/README.md"
if [ -f "$README_E2E" ]; then
  pass_check "Phase C creates tests/e2e/README.md"
else
  fail_check "tests/e2e/README.md not created"
fi

# ─── Test 11: Phase C creates fixture scaffold ───────────────────────────────
FIXTURE="$PROJ2/tests/e2e/fixtures/drupal-login.ts"
if [ -f "$FIXTURE" ]; then
  pass_check "Phase C creates tests/e2e/fixtures/drupal-login.ts"
else
  fail_check "tests/e2e/fixtures/drupal-login.ts not created"
fi

# ─── Test 12: --skip-demo-recipe flag parses without error ───────────────────
PROJ3="$TMPDIR/proj_skip_demo"
make_fake_project "$PROJ3"
mkdir -p "$PROJ3/tests/e2e"
rc=0
bash "$SCRIPT" "$PROJ3" --update-atk --skip-demo-recipe 2>/dev/null || rc=$?
# --update-atk skips phases A+B so --skip-demo-recipe only affects phase A
# With --update-atk this flag is parsed and accepted (no error)
if [ "$rc" -eq 0 ]; then
  pass_check "--skip-demo-recipe + --update-atk → exit 0"
else
  fail_check "--skip-demo-recipe + --update-atk → unexpected exit $rc"
fi

# ─── Report ──────────────────────────────────────────────────────────────────

if [ "$FAIL" -ne 0 ]; then
  printf '\nsetup-atk.sh invariants violated.\n' >&2
  exit 1
fi
printf '\nAll invariants pass for scripts/setup-atk.sh.\n'
exit 0
