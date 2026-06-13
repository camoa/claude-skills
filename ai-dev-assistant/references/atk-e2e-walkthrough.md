# ATK E2E Walkthrough

> _Drupal-flavored component — a stack-neutral version lands in slice-1b. The Drupal specifics below are the current reference implementation._

**Introduced:** ai-dev-assistant v4.12.0 (Task B — ATK E2E Gate)
**Commands:** `/setup-atk` · `/validate:e2e`
**dev-guides:** `testing/atk/` · `testing/playwright/` · `testing/ai-test-generation/`

---

## 1. Overview

**What ATK provides:**
- ~36 canned Drupal behavioral E2E tests (auth, content CRUD, forms, navigation, error pages, search, media)
- ~24 helper functions: `loginAsRole`, `runDrush`, `drupalCreateNode`, `drupalLogin`
- `data-qa-id` selector hooks (injected server-side by ATK's preprocess hooks)
- `ddev drush atk:preflight` — validates the test environment before any test runs
- Optional Testor snapshot management (`ddev drush testor:pull/push/snapshot`) — see §5

**What the framework builds on top:**
- AI-assisted journey discovery (site-specific coverage, not just canned tests)
- Plan-first test authoring (`tests/e2e/specs/<slug>.md` → human review → `.spec.ts`)
- `_e2e.json` gate audit + standard validation envelope
- `/review` dispatcher integration
- Surface registry seeding (`gate: e2e` surfaces)

**The three-phase install** (run by `scripts/setup-atk.sh`):
- Phase A — Drupal: `composer require drupal/automated_testing_kit:^2.0` + `drush en`
- Phase B — Host-side: `npm init` + `npm install @playwright/test` + `npx playwright install --with-deps`
- Phase C — Scaffold: `tests/e2e/` directory structure + ATK catalog copy + `playwright.config.ts` extension

ATK's built-in VR (visual regression) mode is **not used**. Task C (Lullabot) owns visual regression.

---

## 2. Setup walkthrough

> **Security note (RT-V7):** Only run `/setup-atk` on repositories you trust. Phase C copies ATK catalog test files from the Composer-installed module into `tests/e2e/behavioral/atk/`, and subsequently `npx playwright test` executes those files on your host machine with full Node.js access. If the `drupal/automated_testing_kit` Composer package has been substituted or the module directory has been tampered with in the cloned repo, that test code will run on your system. This is inherent to running any test runner against repo-supplied test files — the same caution applies to any `npm test` or `phpunit` run on untrusted code.

### First-time setup

```
/ai-dev-assistant:setup-atk
```

What happens:
1. Checks for an existing install (`scripts/setup-atk-idempotency.sh`).
2. If absent: runs the three-phase install via `scripts/setup-atk.sh`.
3. Unless `--skip-discovery`: spawns `journey-discovery-agent` to analyze routes, forms, content types, and permissions.
4. Displays proposed journeys. You pick which ones to scaffold.
5. Writes `tests/e2e/specs/<slug>.md` (plan-first Markdown specs).
6. After you review the specs, generates `tests/e2e/behavioral/project-custom/<slug>.spec.ts`.

### With real content (skip the demo recipe)

```
/ai-dev-assistant:setup-atk --skip-demo-recipe
```

Use `--skip-demo-recipe` on sites with existing content. Without the recipe, ATK's canned tests may fail because expected content types or nodes are absent — this is expected; project-custom journey tests will still pass.

### Skip journey discovery

```
/ai-dev-assistant:setup-atk --skip-discovery
```

Installs ATK and scaffolds `tests/e2e/` without the discovery step. Add journeys later with `--add-journey`.

### Idempotency

Re-running `/setup-atk` on an already-set-up project prints:
```
ATK already set up. Use --add-journey to add a new journey, or --update-atk to refresh the ATK catalog.
```
Pass `--force` to override.

---

## 3. Journey authoring

### Plan-first pattern

The framework follows the AI-testgen four-phase pattern:

1. **Discover** — `journey-discovery-agent` analyzes the site's structure.
2. **Plan** — `tests/e2e/specs/<slug>.md` is written. **You review and edit this file.**
3. **Generate** — `tests/e2e/behavioral/project-custom/<slug>.spec.ts` is generated from the spec.
4. **Maintain** — Healer cycle: when tests break, update the spec first, then regenerate.

The spec file in `tests/e2e/specs/` is the **source of truth**. The `.spec.ts` is regenerable. Never manually edit `.spec.ts` without also updating the corresponding spec.

### spec file format

```markdown
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

### Test tags

- `@smoke` — include in PR checks (`--smoke-only` Playwright run)
- `@regression` — full regression suite; nightly
- `@<surface-id>` — ties the test to a registered surface (e.g., `@atk-login`)

Tag at least one tag per test. `@smoke` is the minimum for journey tests.

### Adding a journey post-setup

```
/ai-dev-assistant:setup-atk --add-journey "editor creates and publishes a press release"
```

Re-runs the discovery flow scoped to one new journey. Existing specs and tests are untouched.

---

## 4. Running the gate

### Basic run

```
/ai-dev-assistant:validate:e2e <task>
```

### Smoke-only (fast PR check)

```
/ai-dev-assistant:validate:e2e <task> --smoke-only
```

Passes `--grep "@smoke"` to Playwright. Runs only `@smoke`-tagged tests.

### Surface scoping via the registry

When `--task <name>` is provided, `/validate:e2e` reads `.visual-review/registry.yml` and filters surfaces where `gates` contains `e2e`. The surface `id` values are passed as a `--grep "@<id>"` pattern to Playwright. Only tests tagged with a matching `@<id>` run.

Example: if the registry has `id: atk-login`, tests tagged `@atk-login` run.

### Bypass (soft gate)

```
/ai-dev-assistant:validate:e2e <task> --skip "ATK not installed on this environment"
```

Writes a bypass `_e2e.json` and exits clean. The bypass is visible in `/ai-dev-assistant:audit-status`.

### Reading the HTML report

Playwright generates an HTML report at `tests/e2e/.playwright-results/index.html`. Open in a browser:

```bash
cd <codePath>
npx playwright show-report tests/e2e/.playwright-results
```

The report shows per-test pass/fail, trace viewer, and screenshots on failure.

---

## 5. DDEV + CI

### Environment variables

| Variable | Purpose | Used by |
|----------|---------|---------|
| `PLAYWRIGHT_BASE_URL` | Override `baseURL` in `atk.config.js` | CI (non-DDEV runners) |
| `DDEV_PRIMARY_URL` | DDEV-provided base URL | Local dev |
| `QA_ADMIN_PASSWORD` | QA admin password | `atk.config.js` (fallback: `site_admin`) |
| `QA_EDITOR_PASSWORD` | QA editor password | `atk.config.js` (fallback: `editor`) |

### GitHub Actions pattern

```yaml
name: E2E Tests
on: [push, pull_request]
jobs:
  e2e:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ddev/github-action-setup-ddev@v1
      - run: ddev start
      - run: ddev composer install
      - run: ddev drush recipe modules/contrib/automated_testing_kit_demo_recipe
      - run: ddev drush atk:preflight
      - run: cd tests/e2e && npx playwright install --with-deps
      - run: npx playwright test --project e2e-chromium
        env:
          PLAYWRIGHT_BASE_URL: ${{ env.DDEV_PRIMARY_URL }}
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: playwright-report
          path: tests/e2e/.playwright-results/
```

Key notes:
- `--with-deps` is **required** in CI. Omitting it is the most common CI failure (browsers not installed).
- `if: always()` on artifact upload preserves the HTML report even on test failure.
- `PLAYWRIGHT_BASE_URL` env override is the non-DDEV runner hook.
- `ddev/github-action-setup-ddev@v1` handles Docker setup.

### Testor (opt-in, not required)

ATK's Testor manages database snapshots for consistent test state across team members. It operates independently of the framework's task isolation.

To enable:
1. Configure S3/SFTP credentials as environment variables.
2. Run `ddev drush testor:pull dev` to pull a baseline snapshot.
3. Enable the worker fixture in `tests/e2e/fixtures/drupal-login.ts`.

See `testing/atk/atk-testor.md` in dev-guides for full Testor configuration.

---

## 6. ATK upgrade path

After upgrading `drupal/automated_testing_kit` via Composer:

```
/ai-dev-assistant:setup-atk --update-atk
```

This re-runs Phase C only — re-copies `tests/e2e/behavioral/atk/` and `tests/e2e/helpers/atk/` from the newly-installed module. Your project-custom journey tests in `tests/e2e/behavioral/project-custom/` are not touched.

> **Resume tip (EC-F5):** If `/setup-atk` failed midway through Phase C (e.g., after Phases A and B completed), use `--update-atk` to re-run Phase C only — there is no separate "resume Phase C" command. Do not use a plain `/setup-atk` re-run, which would restart Phases A and B unnecessarily.

**Never modify `behavioral/atk/` files in-place.** If you need to override an ATK canned test, copy it to `behavioral/project-custom/` with a new name.

---

## 7. v2 stubs — `/validate:a11y` and `/validate:perf`

ATK ships accessibility (axe-core) and performance (Lighthouse) patterns, but they are deferred to v2 as separate gates. In v1:

- Commented examples are in `tests/e2e/behavioral/project-custom/examples/`:
  - `a11y-example.spec.ts.disabled` — axe-core `injectAxe` + `checkA11y` pattern
  - `perf-example.spec.ts.disabled` — Lighthouse score assertion via `playwright-lighthouse`
- `/validate:a11y` and `/validate:perf` are documented here as **future commands** — not yet shipped.
- Neither is part of the `/review` dispatch in v1.

To opt in early: rename the `.disabled` file, install `axe-playwright` or `playwright-lighthouse`, and run the tests directly with `npx playwright test`.

---

## 8. Coexistence with `/setup-visual-regression` (Task C)

| Concern | Notes |
|---------|-------|
| `playwright.config.ts` | Both commands append separate `projects[]` entries: `e2e-chromium` (ATK) vs `visual-chromium` (Lullabot). Whichever runs first creates the file; the second appends. |
| `tests/` directories | Independent: `tests/e2e/` (ATK) vs `tests/visual/` (Lullabot). Separate `package.json` files, no version conflict. |
| Surface registry | Both write to `.visual-review/registry.yml` with different `gates` values (`e2e` vs `visual_regression`). A surface can have both gates. |
| DDEV | Neither command modifies `settings.local.php`. ATK targets DDEV MySQL; Lullabot uses SQLite per worker in a separate Playwright project. |
| `testIdAttribute` | Set in the `e2e-chromium` project `use:` block only — does not affect `visual-chromium`. |
