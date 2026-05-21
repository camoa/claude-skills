#!/usr/bin/env bash
# setup-atk.sh — three-phase ATK + Playwright install.
#
# Usage: setup-atk.sh <codePath> [--skip-demo-recipe] [--update-atk]
#
#   <codePath>: absolute path to the Drupal project root (must contain .ddev/)
#   --skip-demo-recipe: skip automated_testing_kit_demo_recipe install
#   --update-atk: re-run Phase C only (re-copy behavioral/atk/ and helpers/atk/
#                 from the currently-installed module); skip Phases A + B
#
# Phases:
#   A — Drupal-side: ddev composer require + drush en (skipped if --update-atk)
#   B — Host-side runner: npm init + npm install + npx playwright install (skipped if --update-atk)
#   C — Scaffold tests/e2e/ + copy ATK catalog + extend playwright.config.ts
#        + seed .visual-review/registry.yml with e2e surfaces
#
# Note: YAML reads (registry.yml) are NOT performed by this script.
# The calling command (setup-atk.md, executed by Claude) reads the registry
# and passes structured data as arguments. This script only writes to registry.yml
# by appending YAML blocks — it never parses YAML.
#
# Playwright runs HOST-SIDE. Never wrap npx/npm in ddev exec.
# The browser reaches the DDEV site via DDEV_PRIMARY_URL / PLAYWRIGHT_BASE_URL.
#
# Exit codes:
#   0 — success
#   1 — runtime error (ddev not found, npm failure, cp failure, etc.)
#   2 — invalid arguments

set -uo pipefail

# ─── argument parsing ────────────────────────────────────────────────────────

CODE_PATH="${1:?codePath required}"
SKIP_DEMO_RECIPE=0
UPDATE_ATK=0

shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-demo-recipe) SKIP_DEMO_RECIPE=1 ;;
    --update-atk)       UPDATE_ATK=1 ;;
    *)
      echo "setup-atk: unknown flag: $1" >&2
      echo "  usage: setup-atk.sh <codePath> [--skip-demo-recipe] [--update-atk]" >&2
      exit 2
      ;;
  esac
  shift
done

# ─── pre-flight ──────────────────────────────────────────────────────────────

if [[ ! -d "$CODE_PATH" ]]; then
  echo "setup-atk: codePath does not exist: $CODE_PATH" >&2
  exit 1
fi

if [[ ! -f "$CODE_PATH/.ddev/config.yaml" ]]; then
  echo "setup-atk: no .ddev/config.yaml found at $CODE_PATH" >&2
  echo "  DDEV must be initialised before running /setup-atk." >&2
  exit 1
fi

if ! command -v ddev >/dev/null 2>&1; then
  echo "setup-atk: ddev not found in PATH" >&2
  exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "setup-atk: npm not found in PATH (required for host-side Playwright install)" >&2
  exit 1
fi

# ─── Phase A: Drupal-side install ────────────────────────────────────────────

if [[ "$UPDATE_ATK" -eq 0 ]]; then
  echo "setup-atk: Phase A — installing ATK Drupal modules..."

  (cd "$CODE_PATH" && ddev composer require 'drupal/automated_testing_kit:^2.0') || {
    echo "setup-atk: Phase A failed: composer require automated_testing_kit" >&2
    exit 1
  }

  (cd "$CODE_PATH" && ddev drush en automated_testing_kit qa_accounts -y) || {
    echo "setup-atk: Phase A failed: drush en automated_testing_kit qa_accounts" >&2
    exit 1
  }

  if [[ "$SKIP_DEMO_RECIPE" -eq 0 ]]; then
    (cd "$CODE_PATH" && ddev composer require 'drupal/automated_testing_kit_demo_recipe:^2.0') || {
      echo "setup-atk: Phase A failed: composer require automated_testing_kit_demo_recipe" >&2
      exit 1
    }

    (cd "$CODE_PATH" && ddev drush recipe modules/contrib/automated_testing_kit_demo_recipe) || {
      echo "setup-atk: Phase A failed: drush recipe automated_testing_kit_demo_recipe" >&2
      exit 1
    }

    (cd "$CODE_PATH" && ddev drush cache:rebuild) || {
      echo "setup-atk: Phase A failed: drush cache:rebuild" >&2
      exit 1
    }
  fi

  echo "setup-atk: Phase A complete."
fi

# ─── Phase B: Host-side Playwright runner ────────────────────────────────────

if [[ "$UPDATE_ATK" -eq 0 ]]; then
  echo "setup-atk: Phase B — installing Playwright runner in tests/e2e/..."

  mkdir -p "$CODE_PATH/tests/e2e"

  (cd "$CODE_PATH/tests/e2e" && npm init -y) || {
    echo "setup-atk: Phase B failed: npm init" >&2
    exit 1
  }

  (cd "$CODE_PATH/tests/e2e" && npm install -D '@playwright/test@^1.44') || {
    echo "setup-atk: Phase B failed: npm install @playwright/test" >&2
    exit 1
  }

  (cd "$CODE_PATH/tests/e2e" && npx playwright install --with-deps) || {
    echo "setup-atk: Phase B failed: npx playwright install --with-deps" >&2
    exit 1
  }

  echo "setup-atk: Phase B complete."
fi

# ─── Phase C: scaffold + catalog copy ────────────────────────────────────────

echo "setup-atk: Phase C — scaffolding tests/e2e/..."

ATK_MODULE_DIR="$CODE_PATH/web/modules/contrib/automated_testing_kit"
E2E_DIR="$CODE_PATH/tests/e2e"
PLUGIN_ROOT_GUESS="${CLAUDE_PLUGIN_ROOT:-}"

# Ensure directory structure
mkdir -p \
  "$E2E_DIR/behavioral/atk" \
  "$E2E_DIR/behavioral/project-custom/examples" \
  "$E2E_DIR/specs" \
  "$E2E_DIR/fixtures" \
  "$E2E_DIR/helpers/atk" \
  "$E2E_DIR/helpers/project"

# Copy ATK canned tests and helpers from installed module
if [[ -d "$ATK_MODULE_DIR/tests/playwright" ]]; then
  cp -R "$ATK_MODULE_DIR/tests/playwright/." "$E2E_DIR/behavioral/atk/" || {
    echo "setup-atk: Phase C failed: cp ATK behavioral tests" >&2
    exit 1
  }
  echo "setup-atk: copied ATK canned tests → tests/e2e/behavioral/atk/"
else
  echo "setup-atk: WARNING: $ATK_MODULE_DIR/tests/playwright not found; skipping catalog copy" >&2
  echo "  Run 'ddev composer require drupal/automated_testing_kit:^2.0' first." >&2
fi

if [[ -d "$ATK_MODULE_DIR/js-helpers/playwright" ]]; then
  cp -R "$ATK_MODULE_DIR/js-helpers/playwright/." "$E2E_DIR/helpers/atk/" || {
    echo "setup-atk: Phase C failed: cp ATK helpers" >&2
    exit 1
  }
  echo "setup-atk: copied ATK helpers → tests/e2e/helpers/atk/"
else
  echo "setup-atk: WARNING: $ATK_MODULE_DIR/js-helpers/playwright not found; skipping helpers copy" >&2
fi

# Write atk.config.js if absent
ATK_CONFIG="$E2E_DIR/atk.config.js"
if [[ ! -f "$ATK_CONFIG" ]]; then
  cat > "$ATK_CONFIG" <<'ATKCONFIG'
// atk.config.js — ATK-specific runner environment.
// Lives alongside playwright.config.ts; do NOT put ATK env here in playwright.config.ts.
module.exports = {
  baseURL: process.env.PLAYWRIGHT_BASE_URL || process.env.DDEV_PRIMARY_URL || 'https://localhost',
  drushCmd: 'ddev drush',
  qaAccounts: {
    admin:  { username: 'site_admin', password: process.env.QA_ADMIN_PASSWORD || 'site_admin' },
    editor: { username: 'editor',     password: process.env.QA_EDITOR_PASSWORD || 'editor' },
  },
  ignoreHTTPSErrors: true,
};
ATKCONFIG
  echo "setup-atk: wrote tests/e2e/atk.config.js"
fi

# Write fixture scaffold if absent
FIXTURE_FILE="$E2E_DIR/fixtures/drupal-login.ts"
if [[ ! -f "$FIXTURE_FILE" ]]; then
  cat > "$FIXTURE_FILE" <<'FIXTURE'
// drupal-login.ts — Playwright fixture helpers for ATK login.
// loginAsRole wraps ATK's drupalLogin helper for role-based auth.
import { test as base } from '@playwright/test';

export async function loginAsRole(page: any, role: string) {
  // Delegate to ATK helper — import selectively, not the whole catalog.
  // Example (uncomment and adjust import path after catalog copy):
  // import { drupalLogin } from '../helpers/atk/drupal-login';
  // await drupalLogin(page, role);

  // Testor per-worker DB reset (opt-in — uncomment to enable):
  // const { execSync } = require('child_process');
  // execSync('ddev drush testor:restore qa-baseline', { stdio: 'inherit' });
}

// Re-export base for extending
export { base };
FIXTURE
  echo "setup-atk: wrote tests/e2e/fixtures/drupal-login.ts"
fi

# Write a11y + perf commented examples
EXAMPLES_A11Y="$E2E_DIR/behavioral/project-custom/examples/a11y-example.spec.ts.disabled"
if [[ ! -f "$EXAMPLES_A11Y" ]]; then
  cat > "$EXAMPLES_A11Y" <<'A11Y'
// a11y-example — axe-core accessibility assertion (v2 candidate; not auto-run).
// Rename to .spec.ts and enable /validate:a11y to include in the gate.
// import { test, expect } from '@playwright/test';
// import { injectAxe, checkA11y } from 'axe-playwright';
//
// test('homepage a11y @a11y', async ({ page }) => {
//   await page.goto('/');
//   await injectAxe(page);
//   await checkA11y(page, null, { runOnly: { type: 'tag', values: ['wcag2a', 'wcag2aa'] } });
// });
A11Y
fi

EXAMPLES_PERF="$E2E_DIR/behavioral/project-custom/examples/perf-example.spec.ts.disabled"
if [[ ! -f "$EXAMPLES_PERF" ]]; then
  cat > "$EXAMPLES_PERF" <<'PERF'
// perf-example — Lighthouse performance assertion (v2 candidate; not auto-run).
// Rename to .spec.ts and enable /validate:perf to include in the gate.
// import { test, expect } from '@playwright/test';
// import { playAudit } from 'playwright-lighthouse';
//
// test('homepage perf @perf', async ({ page, browser }) => {
//   await page.goto('/');
//   const { lhr } = await playAudit({ page, thresholds: { performance: 80 } });
//   expect(lhr.categories.performance.score * 100).toBeGreaterThan(80);
// });
PERF
fi

# Write tests/e2e/README.md if absent
README_FILE="$E2E_DIR/README.md"
if [[ ! -f "$README_FILE" ]]; then
  cat > "$README_FILE" <<'README'
# E2E Tests (ATK + Playwright)

Behavioral E2E tests powered by [Automated Testing Kit](https://www.drupal.org/project/automated_testing_kit)
and Playwright. Set up by `/drupal-dev-framework:setup-atk`.

## Quick start

```bash
npx playwright test --project e2e-chromium          # run all E2E tests
npx playwright test --project e2e-chromium --grep @smoke  # smoke subset
```

## Directory layout

```
tests/e2e/
├── atk.config.js            — ATK runner env (baseURL, drushCmd, qaAccounts)
├── behavioral/
│   ├── atk/                 — ATK canned tests (~36); never edit in-place
│   └── project-custom/      — journey tests scaffolded by /setup-atk
├── specs/                   — plan-first Markdown specs (human-reviewable)
├── fixtures/drupal-login.ts — loginAsRole wrapper
├── helpers/
│   ├── atk/                 — ATK Playwright helpers (copied from module)
│   └── project/             — project-specific helpers
└── README.md                — this file
```

## ATK catalog updates

After upgrading `drupal/automated_testing_kit` via Composer, re-copy the catalog:

```bash
/drupal-dev-framework:setup-atk --update-atk
```

## Testor (opt-in)

For consistent test databases across team members, configure Testor:
1. `ddev drush testor:pull dev` — pull a baseline snapshot
2. Enable the fixture in `fixtures/drupal-login.ts`
See `testing/atk/atk-testor.md` in dev-guides for full setup.

## References

- ATK guide: https://camoa.github.io/dev-guides/testing/atk/
- Playwright E2E patterns: https://camoa.github.io/dev-guides/testing/playwright/
- AI test generation: https://camoa.github.io/dev-guides/testing/ai-test-generation/
README
  echo "setup-atk: wrote tests/e2e/README.md"
fi

# ─── Extend playwright.config.ts ─────────────────────────────────────────────

PW_CONFIG="$CODE_PATH/playwright.config.ts"

# If no playwright.config.ts exists and PLUGIN_ROOT_GUESS is set, copy the base template
if [[ ! -f "$PW_CONFIG" ]]; then
  BASE_TEMPLATE=""
  if [[ -n "$PLUGIN_ROOT_GUESS" && -f "$PLUGIN_ROOT_GUESS/references/visual-review/playwright-base.config.ts" ]]; then
    BASE_TEMPLATE="$PLUGIN_ROOT_GUESS/references/visual-review/playwright-base.config.ts"
  fi
  if [[ -n "$BASE_TEMPLATE" ]]; then
    cp "$BASE_TEMPLATE" "$PW_CONFIG" || {
      echo "setup-atk: failed to copy playwright-base.config.ts to $PW_CONFIG" >&2
      exit 1
    }
    echo "setup-atk: copied playwright-base.config.ts → playwright.config.ts"
  else
    # Bootstrap a minimal playwright.config.ts
    cat > "$PW_CONFIG" <<'PWCONF'
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  use: {
    baseURL: process.env.PLAYWRIGHT_BASE_URL || process.env.DDEV_PRIMARY_URL || 'https://localhost',
    ignoreHTTPSErrors: true,
  },
  projects: [],
});
PWCONF
    echo "setup-atk: created minimal playwright.config.ts (no base template found)"
  fi
fi

# Append e2e-chromium project entry if not already present
if ! grep -q 'e2e-chromium' "$PW_CONFIG" 2>/dev/null; then
  cat >> "$PW_CONFIG" <<'E2EENTRY'

// Added by /setup-atk — ATK behavioral E2E tests (do not remove):
// {
//   name: 'e2e-chromium',
//   testDir: './tests/e2e/behavioral',
//   use: {
//     ...devices['Desktop Chrome'],
//     testIdAttribute: 'data-qa-id',  // required for ATK getByTestId() selectors
//   },
// },
//
// NOTE: add this object inside the `projects: []` array above.
// The script cannot safely parse + inject into TypeScript; paste manually
// or run: /drupal-dev-framework:setup-atk again after reviewing the config.
E2EENTRY
  echo "setup-atk: playwright.config.ts — appended e2e-chromium project stub (paste into projects[])"
  echo "setup-atk: IMPORTANT: add the e2e-chromium entry into the projects[] array manually."
else
  echo "setup-atk: playwright.config.ts already has e2e-chromium entry — no change"
fi

# ─── Seed surface registry ────────────────────────────────────────────────────

REGISTRY_DIR="$CODE_PATH/.visual-review"
REGISTRY_FILE="$REGISTRY_DIR/registry.yml"

mkdir -p "$REGISTRY_DIR"

# Only seed ATK surfaces that are not already present (idempotent by id)
seed_surface() {
  local id="$1" url="$2"
  if grep -q "^  - id: $id$" "$REGISTRY_FILE" 2>/dev/null; then
    echo "setup-atk: registry surface '$id' already present — skipped"
    return
  fi
  cat >> "$REGISTRY_FILE" <<SURFACE
  - id: $id
    url: "$url"
    gates: [e2e]
SURFACE
  echo "setup-atk: added registry surface '$id' ($url)"
}

# Ensure the registry file has a surfaces: block
if [[ ! -f "$REGISTRY_FILE" ]]; then
  cat > "$REGISTRY_FILE" <<'REGHDR'
# .visual-review/registry.yml — surface coverage manifest.
# Managed by /setup-atk (e2e surfaces) and /setup-visual-regression (vr surfaces).
# Schema: references/visual-review/surface-registry-schema.md
schema_version: "1.0"
surfaces:
REGHDR
  echo "setup-atk: created .visual-review/registry.yml"
elif ! grep -q '^surfaces:' "$REGISTRY_FILE" 2>/dev/null; then
  echo 'surfaces:' >> "$REGISTRY_FILE"
fi

seed_surface "atk-login"    "/user/login"
seed_surface "atk-homepage" "/"
seed_surface "atk-register" "/user/register"
seed_surface "atk-logout"   "/user/logout"
seed_surface "atk-content"  "/node/1"

echo "setup-atk: Phase C complete."
echo "setup-atk: setup complete. Next: /drupal-dev-framework:validate:e2e"
exit 0
