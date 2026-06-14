/**
 * VISUAL REGRESSION SPEC TEMPLATE — ai-dev-assistant v4.13.0 (Task C).
 *
 * /setup-visual-regression copies this template once per registry surface to
 * <codePath>/tests/visual/<surface-id>.spec.ts, substituting the __TOKENS__
 * below from the surface's registry entry. Edit the generated file freely —
 * with ONE exception (see "KEEP THE SNAPSHOT NAME STABLE").
 *
 * Tokens substituted at generation time:
 *   __SURFACE_ID__         the registry surface `id` (kebab-case)
 *   __SURFACE_URL__        the registry surface `url`
 *   __VIEWPORTS__          comma-separated viewport names (informational comment)
 *   __MASKS_ARRAY__        the surface `masks` selectors, as page.locator(...) calls
 *                          (or an empty array when the surface has no masks)
 *   __SCREENSHOT_IMPORT__  extra import line for a capture helper — EMPTY by
 *                          default; a framework's process recipe may supply one
 *                          (e.g. an accessibility-aware screenshot helper)
 *   __SCREENSHOT_CAPTURE__ the capture call — defaults to Playwright-native
 *                          `toHaveScreenshot`; a recipe may override it
 *
 * The PLUGIN ships a framework-neutral capture. HOW a surface is captured —
 * and whether it also writes an accessibility-tree snapshot — is supplied by
 * your project's process recipe via the two __SCREENSHOT_*__ tokens. Nothing
 * here assumes a framework.
 *
 * KEEP THE SNAPSHOT NAME STABLE
 * ----------------------------
 * The capture names its snapshot exactly after the surface id so the baseline
 * filename is deterministic:
 *   <surface-id>-visual-chromium-<viewport>-linux.png
 * Changing the snapshot name (or adding a second capture call) orphans every
 * committed baseline for this surface. See tests/visual/README.md.
 */
import { test, expect } from '@playwright/test';
__SCREENSHOT_IMPORT__

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
    // `masks`). A recipe-supplied capture helper may also write a paired
    // accessibility snapshot; such a11y diffs surface in the report (warning-only in v1).
    const masks = [
      __MASKS_ARRAY__
    ];
    __SCREENSHOT_CAPTURE__
  });
});
