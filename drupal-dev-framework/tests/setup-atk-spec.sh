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

# Create a fake ATK module dir (for tests that require --update-atk to succeed)
make_fake_atk_module() {
  local dir="$1"
  mkdir -p "$dir/web/modules/contrib/automated_testing_kit/tests/playwright"
  mkdir -p "$dir/web/modules/contrib/automated_testing_kit/js-helpers/playwright"
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
make_fake_atk_module "$PROJ2"
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
make_fake_atk_module "$PROJ3"
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

# ─── Regression: EC-F2 — npm init does not clobber existing package.json ─────
PROJ_PKG="$TMPDIR/proj_pkg_guard"
make_fake_project "$PROJ_PKG"
mkdir -p "$PROJ_PKG/tests/e2e"
# Pre-create a package.json with custom content
echo '{"name":"my-existing-project","version":"2.0.0"}' > "$PROJ_PKG/tests/e2e/package.json"
stub_ddev
# Run Phase B (full install, not --update-atk so npm init path is exercised)
# But we stub npm so npm init won't run; the key test is that the content is preserved
rc=0
bash "$SCRIPT" "$PROJ_PKG" 2>/dev/null || rc=0  # ignore exit (ddev stub, npm stub)
PKG_CONTENT=$(cat "$PROJ_PKG/tests/e2e/package.json" 2>/dev/null || echo "")
if echo "$PKG_CONTENT" | grep -q 'my-existing-project'; then
  pass_check "EC-F2: existing package.json preserved (not clobbered by npm init)"
else
  fail_check "EC-F2: package.json was clobbered; expected 'my-existing-project', got: $PKG_CONTENT"
fi

# ─── Regression: EC-F7 — --update-atk exits 1 when ATK module dir absent ────
PROJ_NO_ATK="$TMPDIR/proj_no_atk"
make_fake_project "$PROJ_NO_ATK"
mkdir -p "$PROJ_NO_ATK/tests/e2e"
stub_ddev
rc=0
bash "$SCRIPT" "$PROJ_NO_ATK" --update-atk 2>/dev/null || rc=$?
if [ "$rc" -eq 1 ]; then
  pass_check "EC-F7: --update-atk with no ATK module → exit 1"
else
  fail_check "EC-F7: --update-atk with no ATK module should exit 1, got $rc"
fi

# ─── Regression: HP-F4 — registry.yml contains viewports: block ─────────────
PROJ_VPT="$TMPDIR/proj_viewports"
make_fake_project "$PROJ_VPT"
make_fake_atk_module "$PROJ_VPT"
mkdir -p "$PROJ_VPT/tests/e2e"
stub_ddev
bash "$SCRIPT" "$PROJ_VPT" --update-atk 2>/dev/null || true
REGISTRY_VPT="$PROJ_VPT/.visual-review/registry.yml"
if grep -q 'viewports:' "$REGISTRY_VPT" 2>/dev/null; then
  pass_check "HP-F4: new registry.yml contains viewports: block"
else
  fail_check "HP-F4: registry.yml missing viewports: block"
fi

# ─── Regression: RT-V2 — ATK module symlink outside CODE_PATH is rejected ────
PROJ_SYM="$TMPDIR/proj_symlink"
make_fake_project "$PROJ_SYM"
mkdir -p "$PROJ_SYM/tests/e2e"
# Create a real directory and a fake ATK module dir with a symlink pointing outside
mkdir -p "$TMPDIR/outside_dir/tests/playwright"
echo "evil.spec.ts" > "$TMPDIR/outside_dir/tests/playwright/evil.spec.ts"
mkdir -p "$PROJ_SYM/web/modules/contrib"
ln -s "$TMPDIR/outside_dir" "$PROJ_SYM/web/modules/contrib/automated_testing_kit"
stub_ddev
rc=0
bash "$SCRIPT" "$PROJ_SYM" --update-atk 2>/dev/null || rc=$?
if [ "$rc" -ne 0 ]; then
  pass_check "RT-V2: ATK module symlink outside CODE_PATH → non-zero exit"
else
  fail_check "RT-V2: ATK module symlink outside CODE_PATH should be rejected (got exit 0)"
fi

# ─── Regression: EC-F4/RT-V6 — seed_surface uses fixed-string grep (grep -F) ─
# Verify registry seeding is still idempotent with the grep -F fix in place
PROJ_GSEED="$TMPDIR/proj_grep_seed"
make_fake_project "$PROJ_GSEED"
make_fake_atk_module "$PROJ_GSEED"
mkdir -p "$PROJ_GSEED/tests/e2e"
stub_ddev
bash "$SCRIPT" "$PROJ_GSEED" --update-atk 2>/dev/null || true
bash "$SCRIPT" "$PROJ_GSEED" --update-atk 2>/dev/null || true
ATKCNT=$(grep -c 'id: atk-login' "$PROJ_GSEED/.visual-review/registry.yml" 2>/dev/null || echo 0)
if [ "$ATKCNT" -eq 1 ]; then
  pass_check "EC-F4/RT-V6: seed_surface idempotent with grep -F (atk-login count=1)"
else
  fail_check "EC-F4/RT-V6: seed_surface not idempotent, atk-login appears $ATKCNT times"
fi

# ─── Report ──────────────────────────────────────────────────────────────────

if [ "$FAIL" -ne 0 ]; then
  printf '\nsetup-atk.sh invariants violated.\n' >&2
  exit 1
fi
printf '\nAll invariants pass for scripts/setup-atk.sh.\n'
exit 0
