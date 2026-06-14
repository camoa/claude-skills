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
 *   - E2E (behavioral)   — ATK + Playwright                      → tests/e2e/
 *   - Visual regression  — @lullabot/playwright-drupal           → tests/visual/
 *   - Visual parity      — @lullabot/playwright-drupal+pixelmatch → tests/parity/
 *
 * Both runtimes ride ONE `playwright.config.ts`. They differ only at the
 * test-library layer and are separated by distinct `projects[]` + `testDir`
 * entries — never by a second config file. See `references/visual-review-
 * walkthrough.md` for the full two-runtime model.
 *
 * DDEV-FIRST
 * ----------
 * The framework assumes a DDEV-hosted Drupal site. `/setup-*` checks for
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
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? 'github' : 'list',

  use: {
    baseURL: BASE_URL,
    trace: 'on-first-retry',
  },

  /* Shared screenshot-comparison defaults. Visual regression (Task C) inherits
     these; per-surface `masks` from the surface registry are applied at call
     time, not here. `animations: 'disabled'` and a small `maxDiffPixelRatio`
     keep diffs stable across runs. */
  expect: {
    toHaveScreenshot: {
      animations: 'disabled',
      maxDiffPixelRatio: 0.01,
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
   * login the project's process recipe supplies (example: a Drupal recipe fills
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
