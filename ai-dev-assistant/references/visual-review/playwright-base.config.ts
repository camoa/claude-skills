/**
 * playwright-base.config.ts — REFERENCE TEMPLATE (ai-dev-assistant v4.11.0)
 * ============================================================================
 *
 * This file is a TEMPLATE. Task A (foundation) ships it for documentation only —
 * it is NOT a working `playwright.config.ts` and Task A creates no config in any
 * project. The first `/setup-*` command to run (`/setup-e2e` from Task B, or
 * `/setup-visual-regression` from Task C) copies this template to the project's
 * codePath as `playwright.config.ts` and appends its own `projects[]` entry.
 *
 * It documents the SHARED CONFIG CONTRACT for the epic's two runtimes:
 *
 *   - E2E (behavioral)   — the framework's behavioral-test harness (process recipe) + Playwright → tests/e2e/
 *   - Visual regression  — the framework's visual-regression package (process recipe) → tests/visual/
 *   - Visual parity      — the framework's visual-regression package + pixelmatch   → tests/parity/
 *
 * Both runtimes ride ONE `playwright.config.ts`. They differ only at the
 * test-library layer and are separated by distinct `projects[]` + `testDir`
 * entries — never by a second config file. See `references/visual-review-
 * walkthrough.md` for the full two-runtime model.
 *
 * DDEV-FIRST
 * ----------
 * The framework assumes a DDEV-hosted site. `/setup-*` checks for
 * `<codePath>/.ddev/config.yaml` before writing this config. With no `.ddev/`
 * directory, setup stops with:
 *
 *   "No .ddev/config.yaml found at <codePath>. The visual + E2E review gates
 *    are DDEV-first. Start DDEV for this project, or see the BYO-container
 *    appendix in references/visual-review-walkthrough.md."
 *
 * The base URL is read from `DDEV_PRIMARY_URL` (exported inside `ddev` shells)
 * with a `PLAYWRIGHT_BASE_URL` override for non-DDEV / CI runners.
 */

import { defineConfig } from '@playwright/test';

const BASE_URL =
  process.env.PLAYWRIGHT_BASE_URL ||
  process.env.DDEV_PRIMARY_URL ||
  'https://localhost';

export default defineConfig({
  /* `testDir` is intentionally the repo root — each entry in `projects[]`
     narrows to its own directory via its own `testDir`. */
  testDir: '.',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  /* WORKERS — a single-container backend cannot serve one browser per CPU core.
     This config refuses to be written without `.ddev/config.yaml` (see DDEV-FIRST
     above), so the backend is KNOWN to be one web container with one PHP-FPM
     pool. Playwright's default is one worker per core; measured on a 16-core
     workstation that failed 36 of 72 captures with no change to the site, purely
     from the harness competing with itself. Two fixed it completely and held
     across four further full runs. Raise it only against a backend that can
     actually serve the concurrency. `fullyParallel` stays on — with a cap it
     means "parallel up to the cap", which is the intent. */
  workers: 2,
  /* RETRIES — zero locally, on purpose. A retry that turns a flaky run green is
     the same class of defect as a tolerance tuned until the suite passes: both
     make an unreliable harness look reliable. If this suite needs retries to go
     green, the capture is not stabilised and that is the thing to fix. */
  retries: process.env.CI ? 1 : 0,
  /* Always emit the `html` reporter alongside the console reporter: it is what
     produces `playwright-report/`, whose image-diff view carries the **Slider**
     (drag-to-reveal baseline↔current) widget that `--show-diffs` /
     `npx playwright show-report` opens. `open: 'never'` keeps it from
     auto-launching a browser mid-gate (it is opened on demand). Without the html
     reporter, `show-report` has no report to show. NOTE: this config-level
     reporter governs CI and manual `npx playwright test` runs; the VR *gate*
     (`scripts/visual-regression-gate.sh`) passes `--reporter=json,html` on the
     CLI (a CLI `--reporter` replaces the config one), so it must — and does —
     request html itself. */
  reporter: process.env.CI
    ? [['github'], ['html', { open: 'never' }]]
    : [['list'], ['html', { open: 'never' }]],

  use: {
    baseURL: BASE_URL,
    trace: 'on-first-retry',
  },

  /* Shared screenshot-comparison defaults. Visual regression inherits these;
     per-surface `masks` from the surface registry are applied at call time, not
     here.

     TOLERANCE IS AN ABSOLUTE COUNT, NOT A RATIO. A ratio is a fraction of image
     area, so under full-page capture the budget grows with page height and is
     loosest exactly where pages are tallest: 0.5% of 1440x900 is ~6,500 px, a
     sane gate; 0.5% of 1440x8000 is ~57,600 px, enough to hide a whole
     component. An absolute count does not move when a page grows.

     100 is measured, not chosen. Five runs against an unchanged site with every
     tolerance key removed — which Playwright treats as a budget of zero, not as
     a fallback default — produced 75 of 75 byte-identical captures. The observed
     noise floor was zero, so 100 is about a hundredfold headroom and still only
     a ten-by-ten block.

     Derive your own: `/setup-visual-regression` offers to repeat the suite
     against an unchanged site and report the floor it observes. A project that
     needs a large tolerance has an unstabilised capture, and the tolerance is
     hiding it. */
  expect: {
    toHaveScreenshot: {
      animations: 'disabled',
      caret: 'hide',
      maxDiffPixels: 100,
    },
  },

  /* ----------------------------------------------------------------------
   * EXTENSION POINT — each `/setup-*` command APPENDS one entry here.
   *
   * `/setup-e2e` (Task B) appends:
   *   { name: 'e2e-chromium',    testDir: './tests/e2e',
   *     use: { ...devices['Desktop Chrome'] } }
   *
   * `/setup-visual-regression` (Task C) appends one entry per derived viewport:
   *   { name: 'visual-chromium-<viewport>', testDir: './tests/visual',
   *     testIgnore: ['**\/.auth/**', '**\/auth/**'],
   *     use: { ...devices['Desktop Chrome'], viewport: {...} } }
   *
   * `/setup-visual-parity` (Task D) appends one entry per registry viewport:
   *   { name: 'parity-chromium-<viewport>', testDir: './tests/parity',
   *     use: { ...devices['Desktop Chrome'], viewport: {...} } }
   *
   * AUTHENTICATED VISUAL REGRESSION (stack-neutral)
   * -----------------------------------------------
   * A surface with a non-null `auth_context: "<ctx>"` in the registry is
   * captured while logged in. `/setup-visual-regression` wires this with two
   * extra project kinds per distinct context `<ctx>`, plus a guard on the
   * anonymous projects above:
   *
   *   1. A SETUP project that produces the session once, before the authed
   *      surfaces run. Its name does NOT carry the `visual-chromium-` prefix,
   *      so the gate's project discovery does not run it directly — it runs
   *      automatically as a `dependencies` entry of the authed project:
   *        { name: 'visual-setup-<ctx>', testDir: './tests/visual/.auth',
   *          testMatch: /<ctx>\.setup\.ts$/,
   *          use: { ...devices['Desktop Chrome'] } }
   *
   *   2. One AUTHED visual project per viewport. It depends on the setup
   *      project and loads the session it wrote via `storageState`:
   *        { name: 'visual-chromium-<vp>-<ctx>', testDir: './tests/visual/auth/<ctx>',
   *          dependencies: ['visual-setup-<ctx>'],
   *          use: { ...devices['Desktop Chrome'], viewport: {...},
   *                 storageState: 'tests/visual/.auth/<ctx>.json' } }
   *
   *   3. The anonymous `visual-chromium-<vp>` projects gain
   *      `testIgnore: ['**\/.auth/**', '**\/auth/**']` so they never also pick
   *      up the setup specs or the authed surface specs.
   *
   * The `storageState` file `tests/visual/.auth/<ctx>.json` is a runtime artifact
   * (gitignored). It is produced by `tests/visual/.auth/<ctx>.setup.ts`, whose
   * login the project's process recipe supplies (example: a framework recipe fills
   * it with its role-login). The plugin treats `<ctx>` as an opaque key — it
   * never learns how the session was obtained.
   *
   * Setup is idempotent and order-independent: each command adds ONLY its own
   * `<runtime>-chromium-*` entries and leaves every sibling entry untouched.
   * -------------------------------------------------------------------- */
  projects: [
    // (empty in the template — populated by /setup-e2e and /setup-visual-regression)
  ],
});
