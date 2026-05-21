/**
 * VISUAL REGRESSION SPEC TEMPLATE — drupal-dev-framework v4.13.0 (Task C).
 *
 * /setup-visual-regression copies this template once per registry surface to
 * <codePath>/tests/visual/<surface-id>.spec.ts, substituting the __TOKENS__
 * below from the surface's registry entry. Edit the generated file freely —
 * with ONE exception (see "DO NOT RENAME THE TEST").
 *
 * Tokens substituted at generation time:
 *   __SURFACE_ID__   the registry surface `id` (kebab-case)
 *   __SURFACE_URL__  the registry surface `url`
 *   __VIEWPORTS__    comma-separated viewport names (informational comment)
 *   __MASKS_ARRAY__  the surface `masks` selectors, as page.locator(...) calls
 *                    (or an empty array when the surface has no masks)
 *
 * DO NOT RENAME THE TEST
 * ---------------------
 * The test is named exactly 'visual regression' so Playwright's snapshot
 * ordinal stays `-1-` and the baseline filename is deterministic:
 *   <surface-id>-1-visual-chromium-<viewport>-linux.png
 * Renaming the test (or adding a second screenshot call) orphans every
 * committed baseline for this surface. See tests/visual/README.md.
 */
import { test } from '@playwright/test';
import { takeAccessibleScreenshot } from '@lullabot/playwright-drupal';

test.describe('__SURFACE_ID__ visual regression', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('__SURFACE_URL__');
    await page.waitForLoadState('networkidle');
    // Fonts-ready stabilization — avoids font-swap flicker in the capture.
    await page.evaluate(() => document.fonts.ready);
  });

  // Viewports (driven by playwright.config.ts visual-chromium-* projects):
  //   __VIEWPORTS__
  test('visual regression', async ({ page }) => {
    // Masks — dynamic regions painted over before capture (from registry.yml
    // `masks`). takeAccessibleScreenshot also writes a paired a11y .txt
    // snapshot; a11y diffs surface in the report (warning-only in v1).
    const masks = [
      __MASKS_ARRAY__
    ];
    await takeAccessibleScreenshot(page, '__SURFACE_ID__', { mask: masks });
  });
});
