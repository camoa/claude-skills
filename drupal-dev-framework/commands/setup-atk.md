---
description: "Install ATK + Playwright scaffold, discover site journeys, and scaffold behavioral E2E tests. Idempotent. Run once to set up; use --add-journey to add a single journey post-setup."
allowed-tools: Read, Write, Edit, Bash, Glob, Skill, Task
argument-hint: "[--add-journey <description>] [--skip-demo-recipe] [--skip-discovery]"
---

# /setup-atk

Installs ATK (Automated Testing Kit) `^2.0` + Playwright onto the Drupal project, scaffolds `tests/e2e/`, extends `playwright.config.ts`, seeds the surface registry, and (unless `--skip-discovery`) discovers site journeys and authors plan-first E2E tests. Full walkthrough: `references/atk-e2e-walkthrough.md`.

## Arguments

- _(no args)_ — full setup: three-phase ATK install + journey discovery
- `--add-journey <description>` — re-enter journey discovery for one new journey (no reinstall)
- `--skip-demo-recipe` — skip the `automated_testing_kit_demo_recipe`; use on sites with real content
- `--skip-discovery` — install ATK scaffold only; skip journey discovery
- `--force` — re-run setup even when idempotency check reports `complete`

Unsupported flag: `--variant cypress` → print `"/setup-atk: only the Playwright variant is supported in v1. --variant cypress is not available."` and exit.

## Step 1: Validate arguments

Parse `$ARGUMENTS`. If `--variant` appears (in any form: `--variant cypress`, `--variant=cypress`, `--VARIANT cypress`, case-insensitive) with the value `cypress`, print the literal message above and stop. (EC-F14)

Read `codePath` from the active project's `project_state.md` by running `${CLAUDE_PLUGIN_ROOT}/scripts/project-state-read.sh "<project_folder>"` (Bash) and parsing its JSON `.codePath`. If `codePath` is null or unknown (`.codePath == null` or a `code_path_unknown`/`code_path_missing` warning), prompt the user to run `/set-code-path` first and stop.

## Step 2: --add-journey branch

If `--add-journey <description>` is present:
- Guard: if `tests/e2e/` does not exist at `<codePath>`, print: `"setup-atk: run /setup-atk first before using --add-journey."` and stop. (EC-F6)
- Extract the description text following the flag. If the description is empty (nothing after the flag), print: `"setup-atk: provide a journey description: /setup-atk --add-journey <description>"` and stop. (EC-F15)
- Note: `--skip-discovery` has no effect when `--add-journey` is also present — `--add-journey` takes precedence and `--skip-discovery` is silently ignored. (EC-F16)
- Build the agent input JSON: `{"codePath":"<path>","mode":"add-one","journey_hint":"<description>","existing_specs":["<slug>",...]}`
  - Populate `existing_specs` by globbing `<codePath>/tests/e2e/specs/*.md` and collecting the basenames without extension. If the directory is absent, `existing_specs` is `[]`.
- Spawn the `journey-discovery-agent` with this input (see §Journey Discovery Flow).
- Skip remaining steps.

## Step 3: Idempotency check

Run `scripts/setup-atk-idempotency.sh <codePath>`. Capture the JSON output.

- `status: "complete"` and no `--force` flag → print the idempotency notice from the script (do not clobber), suggest `--add-journey` or `--update-atk`, and stop.
- `status: "partial"` → display which steps are done and which remain using this mapping (EC-F22):
  - `atk_composer_installed: false` → "ATK Composer package: not installed"
  - `atk_module_enabled: false` → "ATK Drupal module: not enabled"
  - `tests_e2e_exists: false` → "tests/e2e/ directory: not created"
  - `playwright_config_has_e2e_entry: false` → "playwright.config.ts e2e-chromium entry: not active (stub appended — paste manually)"
  - `registry_has_e2e_surfaces: false` → "Surface registry (.visual-review/registry.yml): no e2e surfaces"

  Prompt "Resume setup? [y/N]". Default N. User declines → stop.
- `status: "absent"` → proceed.

## Step 4: Three-phase ATK install

Invoke `scripts/setup-atk.sh <codePath> [--skip-demo-recipe] [--update-atk]` passing any relevant flags from `$ARGUMENTS`.

On non-zero exit from the script: surface the error output verbatim and stop.

## Step 5: Journey discovery

Unless `--skip-discovery` **or `--update-atk`** is present (both imply skipping discovery): (HP-F8)

Build agent input JSON:
```
{"codePath":"<path>","mode":"full","journey_hint":null,"existing_specs":[]}
```

Spawn the `journey-discovery-agent` with this input.

## Journey Discovery Flow

After the agent returns its JSON output:

1. Display the `proposed_journeys` table to the user:
   - slug | title | role | priority | atk_canned_covers
2. Display `analysis_summary`.
3. If `proposed_journeys` is empty: print `"No journeys were proposed. Run /setup-atk --add-journey <description> to add a journey manually."` and skip to Step 6. (EC-F3)
4. Prompt: `Which journeys should I scaffold tests for? (all / <comma-list of slugs> / none)`
5. Before writing any files: validate each confirmed slug matches `^[a-z0-9][a-z0-9-]*$`. If a slug contains spaces or non-kebab characters, sanitize it (lowercase, replace spaces and invalid chars with `-`) or skip it with a warning. (EC-F9)
6. For each confirmed slug, write `<codePath>/tests/e2e/specs/<slug>.md` with the plan-first spec format below.
7. Prompt: `The specs above are in tests/e2e/specs/. Review them, then press Enter to generate test files (or type 'skip' to generate later with --add-journey).`
8. On proceed (Enter): generate `<codePath>/tests/e2e/behavioral/project-custom/<slug>.spec.ts` from each spec.
9. On `skip`: print `"Run /setup-atk --add-journey <description> to generate test files when ready."` (EC-F3)

**Plan-first spec format** (`tests/e2e/specs/<slug>.md`):
```
## Journey: <title>

### Scenario: <scenario group>

#### Test: <test name>

**Steps:**
1. Navigate to <url>
2. ...

**Expected:**
- Page loads with status 200
- Content renders without `.messages--error`

**Negative checks:**
- No unexpected `/user/login` redirect
- No console errors
- Watchdog clean (ddev drush watchdog:show --count=5)
```

**`.spec.ts` scaffold template**:
```typescript
import { test, expect } from '@playwright/test';
import { loginAsRole } from '../helpers/atk/drupal-login';

test.describe('<title>', () => {
  test('<test name> @smoke @<slug>', async ({ page }) => {
    // Setup
    await loginAsRole(page, '<role>');
    // Steps
    await page.goto('<url>');
    // Assertions
    await expect(page.locator('.messages--error')).toHaveCount(0);
    // Negative checks
    expect(page.url()).not.toContain('/user/login');
  });
});
```

Use `page.getByTestId('<id>')` for ATK-injected `data-qa-id` selectors. For Big Pipe: assert on final content, not placeholder. For AJAX: `waitForResponse` targeting `/system/ajax`.

## Step 6: Summary

Print a summary:
- Files created under `tests/e2e/`
- Journey specs staged (if any)
- Surface registry surfaces added
- Next steps: `run /drupal-dev-framework:validate:e2e` · `add more journeys with --add-journey` · `review specs in tests/e2e/specs/`
