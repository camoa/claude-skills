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
 *   __MASKS_ARRAY__        the surface `masks` selectors, as QUOTED CSS STRINGS
 *                          (not locator calls). The template derives the locators
 *                          from them, so one list is both applied and measured.
 *                          (or an empty array when the surface has no masks)
 *   __SCREENSHOT_IMPORT__  extra import line for a capture helper — EMPTY by
 *                          default; a framework's process recipe may supply one
 *                          (e.g. an accessibility-aware screenshot helper)
 *   __SCREENSHOT_CAPTURE__ the capture call — defaults to Playwright-native
 *                          `toHaveScreenshot`; a recipe may override it
 *   __STABILITY_MODULE__   relative path to `_capture-stability.mjs`, which
 *                          setup copies next to the specs. Anonymous surfaces
 *                          get `./`; an authed surface two directories deeper
 *                          gets `../../`.
 *
 * The PLUGIN ships a framework-neutral capture. HOW a surface is captured —
 * and whether it also writes an accessibility-tree snapshot — is supplied by
 * your project's process recipe via the two __SCREENSHOT_*__ tokens. Nothing
 * here assumes a framework.
 *
 * CAPTURE EXTENT IS A DECISION, NOT A DEFAULT
 * -------------------------------------------
 * Playwright captures the viewport only unless told otherwise. On a long page
 * that silently puts most of the surface outside the baseline — measured on one
 * site, a 375x5617 page whose baseline covered 14% of it. Setup therefore writes
 * `fullPage` into the capture call from the surface's registry `capture` field,
 * which defaults to `full`. A surface that genuinely wants one viewport — a
 * component-library page, say — opts out per surface.
 *
 * The two failure modes are not symmetric, which is why `full` is the default:
 * a viewport capture that should have been full-page fails silently, while a
 * full-page capture that should have been a viewport fails loudly.
 *
 * KEEP THE SNAPSHOT NAME STABLE
 * ----------------------------
 * The capture names its snapshot exactly after the surface id so the baseline
 * filename is deterministic:
 *   <surface-id>-visual-chromium-<viewport>-linux.png
 * Changing the snapshot name (or adding a second capture call) orphans every
 * committed baseline for this surface. See tests/visual/README.md.
 */
import { existsSync } from 'node:fs';
import { test, expect } from '@playwright/test';
import {
  prepareForCapture,
  measureMaskCoverage,
  MASK_COVERAGE_WARN_FRACTION,
} from '__STABILITY_MODULE___capture-stability.mjs';
__SCREENSHOT_IMPORT__

test.describe('__SURFACE_ID__ visual regression', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('__SURFACE_URL__');
    // One settle, shared with the parity engine: scroll-behaviour override, then
    // the lazy-content settle, then freeze + fonts + a double frame. `networkidle`
    // alone is not a settle — it fires before a below-the-fold lazy image has even
    // issued its request, so a full-page capture races the loader.
    await prepareForCapture(page);
  });

  // Viewports (driven by playwright.config.ts visual-chromium-* projects):
  //   __VIEWPORTS__
  test('visual regression', async ({ page }, testInfo) => {
    // Masks — dynamic regions painted over before capture (from registry.yml
    // `masks`). A recipe-supplied capture helper may also write a paired
    // accessibility snapshot; such a11y diffs surface in the report (warning-only in v1).
    // ONE list of selectors, used for both applying the masks and measuring what
    // they cover. `[data-vrt-mask]` first, so a component can mark its own
    // volatile region in markup — in markup the mask travels with the component,
    // in a test file it rots. The parity engine already prepends this.
    const maskSelectors = [
      '[data-vrt-mask]',
      __MASKS_ARRAY__
    ];
    const masks = maskSelectors.map((selector) => page.locator(selector));

    // MEASURE WHAT THE MASKS HIDE. A mask is chosen to suppress noise and nothing
    // ever asked whether it also suppresses the subject. Measured on one real
    // project, the masks setup produced covered 29 of 29 teaser cards on one
    // surface — the gate would have passed a refactor that broke every card.
    // The bounding boxes are already in hand at this point, so this is free.
    const coverage = await measureMaskCoverage(page, maskSelectors);
    await testInfo.attach('__SURFACE_ID__-mask-coverage.json', {
      body: JSON.stringify(coverage, null, 2),
      contentType: 'application/json',
    });
    // A selector the measurement could NOT parse is not a selector that covers
    // nothing. Playwright's locator engine accepts forms `querySelectorAll` does
    // not — an xpath like `//body` masks the entire page and measures as zero.
    // Treat unmeasurable as unknown, loudly, never as safe.
    const unmeasurable = coverage.per_selector.filter((sel) => sel.count === -1);
    if (unmeasurable.length > 0) {
      const names = unmeasurable.map((sel) => sel.selector).join(', ');
      testInfo.annotations.push({
        type: 'mask-coverage',
        description: `Mask coverage could not be measured for: ${names}. These may be xpath or engine-specific selectors that the measurement cannot evaluate, so the reported fraction EXCLUDES whatever they hide. Verify by eye what they cover.`,
      });
      // eslint-disable-next-line no-console
      console.warn(`[visual] __SURFACE_ID__: unmeasurable mask selector(s): ${names}`);
    }

    if (coverage.masked_fraction > MASK_COVERAGE_WARN_FRACTION) {
      const pct = (coverage.masked_fraction * 100).toFixed(1);
      const detail = coverage.per_selector
        .map((s) => `${s.selector} x${s.count}`)
        .join(', ');
      // An annotation lands in the HTML report next to the surface, so the person
      // doing the review sees it rather than it scrolling past in a console log.
      testInfo.annotations.push({
        type: 'mask-coverage',
        description: `${pct}% of this surface is masked (${detail}). Check the masks are not covering the thing under test.`,
      });
      // eslint-disable-next-line no-console
      console.warn(`[visual] __SURFACE_ID__: ${pct}% masked — ${detail}`);
    }
    // ATTACH BEFORE ASSERTING. `toHaveScreenshot` attaches expected/actual/diff
    // only when the comparison FAILS, so with every surface passing the HTML
    // report renders green rows and zero images — and an instruction to walk
    // every surface cannot be complied with when there is nothing to walk.
    //
    // Attaching the resolved baseline costs no extra capture: it is the image
    // that is about to be compared against, and on a passing surface it is what
    // rendered. Playwright still adds its own actual and diff on a failure.
    //
    // The `-expected.png` suffix is load-bearing — the HTML reporter recognises
    // the expected/actual/diff trio by suffix and activates its drag-to-reveal
    // slider. Any other name produces a flat attachment list instead.
    const baselinePath = testInfo.snapshotPath('__SURFACE_ID__.png');
    if (existsSync(baselinePath)) {
      await testInfo.attach('__SURFACE_ID__-expected.png', {
        path: baselinePath,
        contentType: 'image/png',
      });
    }

    __SCREENSHOT_CAPTURE__
  });
});
