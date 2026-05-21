#!/usr/bin/env bash
# setup-atk-idempotency.sh — detect existing ATK + Playwright install state.
#
# Usage: setup-atk-idempotency.sh <codePath>
#
#   <codePath>: absolute path to the Drupal project root
#
# Emits a single JSON object to stdout with the install state.
# Never modifies any file. Exit 0 always.
#
# Output shape:
#   {
#     "atk_composer_installed": bool,
#     "atk_module_enabled": bool,
#     "tests_e2e_exists": bool,
#     "playwright_config_has_e2e_entry": bool,
#     "registry_has_e2e_surfaces": bool,
#     "status": "absent | partial | complete"
#   }
#
# Status semantics:
#   "absent"   — nothing installed; proceed with full install
#   "partial"  — some steps done; caller should ask "Resume setup?"
#   "complete" — ATK installed, tests/e2e/ exists, playwright.config.ts has
#                e2e-chromium entry, registry has ATK surfaces → no clobber

set -uo pipefail

CODE_PATH="${1:-}"

emit_json() {
  local atk_comp="$1" atk_mod="$2" e2e_dir="$3" pw_entry="$4" reg_surfs="$5" status="$6"
  printf '{"atk_composer_installed":%s,"atk_module_enabled":%s,"tests_e2e_exists":%s,"playwright_config_has_e2e_entry":%s,"registry_has_e2e_surfaces":%s,"status":"%s"}\n' \
    "$atk_comp" "$atk_mod" "$e2e_dir" "$pw_entry" "$reg_surfs" "$status"
}

# Guard: missing or empty codePath
if [[ -z "$CODE_PATH" ]]; then
  emit_json false false false false false absent
  exit 0
fi

if [[ ! -d "$CODE_PATH" ]]; then
  emit_json false false false false false absent
  exit 0
fi

# ─── Check 1: ATK in composer.json ───────────────────────────────────────────
ATK_COMP=false
if command -v ddev >/dev/null 2>&1 && [[ -f "$CODE_PATH/.ddev/config.yaml" ]]; then
  if (cd "$CODE_PATH" && ddev composer show drupal/automated_testing_kit 2>/dev/null | grep -q '^name'); then
    ATK_COMP=true
  fi
elif [[ -f "$CODE_PATH/composer.json" ]]; then
  # Fallback: grep composer.json directly when DDEV is unavailable
  if grep -q '"drupal/automated_testing_kit"' "$CODE_PATH/composer.json" 2>/dev/null; then
    ATK_COMP=true
  fi
fi

# ─── Check 2: ATK module enabled ─────────────────────────────────────────────
ATK_MOD=false
if command -v ddev >/dev/null 2>&1 && [[ -f "$CODE_PATH/.ddev/config.yaml" ]]; then
  if (cd "$CODE_PATH" && ddev drush pm:list --status=enabled 2>/dev/null | grep -q 'automated_testing_kit'); then
    ATK_MOD=true
  fi
fi

# ─── Check 3: tests/e2e/ directory exists ────────────────────────────────────
E2E_DIR=false
if [[ -d "$CODE_PATH/tests/e2e" ]]; then
  E2E_DIR=true
fi

# ─── Check 4: playwright.config.ts has e2e-chromium entry ────────────────────
# HP-F6: exclude commented lines so the stub comment appended by setup-atk.sh
# does NOT falsely report the entry as active.
PW_ENTRY=false
if grep -v -E '^\s*//' "$CODE_PATH/playwright.config.ts" 2>/dev/null | grep -q 'e2e-chromium'; then
  PW_ENTRY=true
fi

# ─── Check 5: registry has e2e surfaces ──────────────────────────────────────
REG_SURFS=false
REGISTRY="$CODE_PATH/.visual-review/registry.yml"
if [[ -f "$REGISTRY" ]] && grep -q 'gates: \[e2e\]' "$REGISTRY" 2>/dev/null; then
  REG_SURFS=true
fi

# ─── Determine status ────────────────────────────────────────────────────────
CHECKS_TRUE=0
for v in "$ATK_COMP" "$ATK_MOD" "$E2E_DIR" "$PW_ENTRY" "$REG_SURFS"; do
  [[ "$v" = "true" ]] && CHECKS_TRUE=$(( CHECKS_TRUE + 1 ))
done

STATUS="absent"
if [[ "$CHECKS_TRUE" -eq 5 ]]; then
  STATUS="complete"
elif [[ "$CHECKS_TRUE" -gt 0 ]]; then
  STATUS="partial"
fi

emit_json "$ATK_COMP" "$ATK_MOD" "$E2E_DIR" "$PW_ENTRY" "$REG_SURFS" "$STATUS"
exit 0
