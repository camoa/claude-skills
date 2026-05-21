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

Parse `$ARGUMENTS`. If `--variant cypress` is present, print the literal message above and stop.

Read `codePath` from the active project's `project_state.md` via the `project-state-reader` skill. If `codePath` is null or unknown, prompt the user to run `/set-code-path` first and stop.

## Step 2: --add-journey branch

If `--add-journey <description>` is present:
- Extract the description text following the flag.
- Build the agent input JSON: `{"codePath":"<path>","mode":"add-one","journey_hint":"<description>","existing_specs":["<slug>",...]}`
  - Populate `existing_specs` by globbing `<codePath>/tests/e2e/specs/*.md` and collecting the basenames without extension.
- Spawn the `journey-discovery-agent` with this input (see §Journey Discovery Flow).
- Skip remaining steps.

## Step 3: Idempotency check

Run `scripts/setup-atk-idempotency.sh <codePath>`. Capture the JSON output.

- `status: "complete"` and no `--force` flag → print the idempotency notice from the script (do not clobber), suggest `--add-journey` or `--update-atk`, and stop.
- `status: "partial"` → display which steps are done and which remain; prompt "Resume setup? [y/N]". Default N. User declines → stop.
- `status: "absent"` → proceed.

## Step 4: Three-phase ATK install

Invoke `scripts/setup-atk.sh <codePath> [--skip-demo-recipe] [--update-atk]` passing any relevant flags from `$ARGUMENTS`.

On non-zero exit from the script: surface the error output verbatim and stop.

## Step 5: Journey discovery

Unless `--skip-discovery` is present:

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
3. Prompt: `Which journeys should I scaffold tests for? (all / <comma-list of slugs> / none)`
4. For each confirmed slug, write `<codePath>/tests/e2e/specs/<slug>.md` with the plan-first spec format below.
5. Prompt: `The specs above are in tests/e2e/specs/. Review them, then press Enter to generate test files (or type 'skip' to generate later with --add-journey).`
6. On proceed (Enter): generate `<codePath>/tests/e2e/behavioral/project-custom/<slug>.spec.ts` from each spec.
7. On `skip`: print "Run \`/setup-atk --add-journey <slug>\` to generate test files when ready."

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
