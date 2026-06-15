#!/usr/bin/env bash
# detect-frameworks-spec.sh — verify scripts/detect-frameworks.sh detection arms
# and stable output order (drupal, nextjs, claude-code-plugins).
#
# Tests:
#   1. Empty dir              → []
#   2. claude-code-plugins    → .claude-plugin/plugin.json exists → ["claude-code-plugins"]
#   3. drupal (composer.json) → ["drupal"]
#   4. nextjs (package.json)  → ["nextjs"]
#   5. drupal + claude-code-plugins → stable order ["drupal","claude-code-plugins"]
#   6. nextjs + claude-code-plugins → stable order ["nextjs","claude-code-plugins"]
#   7. drupal + nextjs + claude-code-plugins → stable order ["drupal","nextjs","claude-code-plugins"]
#   8. No codePath arg        → []
#   9. Non-existent dir       → []
#
# Run pre-PR. Zero model dependencies — pure bash/jq fixture-based.

set -eu

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${PLUGIN_ROOT}/scripts/detect-frameworks.sh"

if [ ! -f "$SCRIPT" ]; then
  printf 'FAIL: %s not found\n' "$SCRIPT" >&2
  exit 1
fi

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# detect <label> <dir> <expected-json>
detect() {
  local label="$1" dir="$2" expected="$3"
  local actual
  actual=$(bash "$SCRIPT" "$dir" 2>/dev/null)
  if [ "$actual" = "$expected" ]; then
    pass_check "$label → $expected"
  else
    fail_check "$label — got '$actual' (expected '$expected')"
  fi
}

# Helpers to seed fixture directories
seed_drupal_composer() {
  local dir="$1"
  mkdir -p "$dir"
  printf '{"require":{"drupal/core":"^10"}}\n' > "$dir/composer.json"
}

seed_nextjs_package() {
  local dir="$1"
  mkdir -p "$dir"
  printf '{"dependencies":{"next":"14.0.0"}}\n' > "$dir/package.json"
}

seed_claude_plugin() {
  local dir="$1"
  # Use plugin.json (individual plugin form); the detection arm checks the directory,
  # so marketplace.json (marketplace form) would also trigger — tested in integration probe below.
  mkdir -p "$dir/.claude-plugin"
  printf '{"name":"test-plugin","version":"1.0.0"}\n' > "$dir/.claude-plugin/plugin.json"
}

seed_claude_marketplace() {
  local dir="$1"
  # Marketplace form: .claude-plugin/marketplace.json (no plugin.json)
  mkdir -p "$dir/.claude-plugin"
  printf '{"name":"test-marketplace","plugins":[]}\n' > "$dir/.claude-plugin/marketplace.json"
}

# === Test 1: empty dir → [] ===
EMPTY_DIR="$TMPDIR/empty"
mkdir -p "$EMPTY_DIR"
detect "empty dir" "$EMPTY_DIR" "[]"

# === Test 2: claude-code-plugins only ===
PLUGIN_DIR="$TMPDIR/plugin-only"
mkdir -p "$PLUGIN_DIR"
seed_claude_plugin "$PLUGIN_DIR"
detect "claude-code-plugins only" "$PLUGIN_DIR" '["claude-code-plugins"]'

# === Test 3: drupal only (composer.json) ===
DRUPAL_DIR="$TMPDIR/drupal-only"
seed_drupal_composer "$DRUPAL_DIR"
detect "drupal only (composer.json)" "$DRUPAL_DIR" '["drupal"]'

# === Test 4: nextjs only ===
NEXTJS_DIR="$TMPDIR/nextjs-only"
seed_nextjs_package "$NEXTJS_DIR"
detect "nextjs only" "$NEXTJS_DIR" '["nextjs"]'

# === Test 5: drupal + claude-code-plugins — stable order ===
DRUPAL_PLUGIN_DIR="$TMPDIR/drupal-plugin"
seed_drupal_composer "$DRUPAL_PLUGIN_DIR"
seed_claude_plugin "$DRUPAL_PLUGIN_DIR"
detect "drupal + claude-code-plugins (stable order)" "$DRUPAL_PLUGIN_DIR" '["drupal","claude-code-plugins"]'

# === Test 6: nextjs + claude-code-plugins — stable order ===
NEXTJS_PLUGIN_DIR="$TMPDIR/nextjs-plugin"
seed_nextjs_package "$NEXTJS_PLUGIN_DIR"
seed_claude_plugin "$NEXTJS_PLUGIN_DIR"
detect "nextjs + claude-code-plugins (stable order)" "$NEXTJS_PLUGIN_DIR" '["nextjs","claude-code-plugins"]'

# === Test 7: drupal + nextjs + claude-code-plugins — stable order ===
ALL_DIR="$TMPDIR/all-three"
seed_drupal_composer "$ALL_DIR"
seed_nextjs_package "$ALL_DIR"
seed_claude_plugin "$ALL_DIR"
detect "drupal + nextjs + claude-code-plugins (stable order)" "$ALL_DIR" '["drupal","nextjs","claude-code-plugins"]'

# === Test 7b: marketplace form (.claude-plugin/marketplace.json, no plugin.json) ===
MKTPLACE_DIR="$TMPDIR/marketplace-form"
seed_claude_marketplace "$MKTPLACE_DIR"
detect "marketplace form (marketplace.json only)" "$MKTPLACE_DIR" '["claude-code-plugins"]'

# === Test 8: no codePath arg → [] ===
actual=$(bash "$SCRIPT" 2>/dev/null)
if [ "$actual" = "[]" ]; then
  pass_check "no codePath arg → []"
else
  fail_check "no codePath arg — got '$actual' (expected '[]')"
fi

# === Test 9: non-existent dir → [] ===
detect "non-existent dir" "/nonexistent-detect-frameworks-spec-dir" "[]"

# === Test 10: real marketplace dir (camoa-skills) emits claude-code-plugins ===
# The marketplace root carries .claude-plugin/marketplace.json (not plugin.json);
# the directory-presence check must still fire.
MARKETPLACE_DIR="${PLUGIN_ROOT}/.."
if [ -d "${MARKETPLACE_DIR}/.claude-plugin" ]; then
  actual=$(bash "$SCRIPT" "$MARKETPLACE_DIR" 2>/dev/null)
  if echo "$actual" | jq -e 'index("claude-code-plugins") != null' >/dev/null 2>&1; then
    pass_check "real marketplace root — claude-code-plugins detected in output"
  else
    fail_check "real marketplace root — claude-code-plugins NOT detected; got '$actual'"
  fi
else
  pass_check "real marketplace root — .claude-plugin/ dir not found (skipping integration probe)"
fi

# === Test 11: real plugin dir (ai-dev-assistant) emits claude-code-plugins ===
# Individual plugin carries .claude-plugin/plugin.json.
if [ -d "${PLUGIN_ROOT}/.claude-plugin" ]; then
  actual=$(bash "$SCRIPT" "$PLUGIN_ROOT" 2>/dev/null)
  if echo "$actual" | jq -e 'index("claude-code-plugins") != null' >/dev/null 2>&1; then
    pass_check "real plugin dir (ai-dev-assistant) — claude-code-plugins detected in output"
  else
    fail_check "real plugin dir (ai-dev-assistant) — claude-code-plugins NOT detected; got '$actual'"
  fi
else
  pass_check "real plugin dir — .claude-plugin/ dir not found (skipping)"
fi

if [ "$FAIL" -ne 0 ]; then
  printf '\ndetect-frameworks.sh invariants violated.\n' >&2
  exit 1
fi

printf '\nAll detect-frameworks-spec checks pass.\n'
exit 0
