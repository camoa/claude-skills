/**
 * _capture-stability.mjs — the single home for capture stability, shared by the
 * visual-regression specs and the visual-parity engine.
 *
 * WHY THIS FILE EXISTS
 * --------------------
 * The parity engine had a proven settle — freeze CSS, fonts, double frame — and
 * the regression template had `networkidle` plus `fonts.ready` and nothing else.
 * Keeping two copies is how they drifted. One definition lives here; both
 * runtimes import it.
 *
 * THE ORDER, AND WHY IT IS SPLIT IN TWO
 * -------------------------------------
 * Freezing everything before the settle scroll and freezing everything after it
 * are both wrong, in opposite directions:
 *
 *   - Freeze first: `scroll-behavior: auto` makes the settle scroll instant, but
 *     `animation: none` means a component whose base state is `opacity: 0`, made
 *     visible only by a scroll-triggered animation, never becomes visible. The
 *     capture records a blank region as though it were correct.
 *   - Freeze last: scroll-triggered animations complete, but smooth scrolling is
 *     still live during the settle, so the scroll is slow and its end state is
 *     timing-dependent.
 *
 * Neither has to be chosen. The scroll-behaviour override goes BEFORE the settle
 * so the scroll is instant; the animation/transition freeze goes AFTER it so
 * anything the scroll triggered has already run. That is `prepareForCapture`.
 *
 * Applying the scroll override twice is harmless — STABILITY_CSS still carries
 * it, so the parity path is unchanged.
 */

/** Applied BEFORE the settle scroll so programmatic scrolling is instant. */
export const SCROLL_BEHAVIOR_CSS = 'html { scroll-behavior: auto !important; }';

/** Capture-stability freeze — kills transitions, animations, the caret, and smooth
 *  scrolling so a capture is deterministic. Applied AFTER the settle scroll. */
export const STABILITY_CSS =
  '*, *::before, *::after { transition: none !important; animation: none !important; ' +
  'caret-color: transparent !important; } html { scroll-behavior: auto !important; }';

/**
 * Force lazy-loaded content to load and settle.
 *
 * `networkidle` fires before a below-the-fold lazy image ever issues its request,
 * so a full-page capture races the lazy loader. Measured: switching one project's
 * suite to full-page capture without this took it from 72 of 72 passing to 50
 * passing and 22 failing, with no change to the site.
 *
 * Scrolls the document in steps, re-reading the height each pass because loading
 * content grows the page, then returns to the top. Anything still marked lazy
 * after that was never reached, so it is forced and awaited directly.
 *
 * @param {import('@playwright/test').Page} page
 * @param {{step?: number, settleMs?: number, maxPasses?: number}} [opts]
 */
export async function settleLazyContent(page, opts = {}) {
  const step = opts.step ?? 800;
  const settleMs = opts.settleMs ?? 100;
  const maxPasses = opts.maxPasses ?? 200;

  await page.evaluate(
    async ({ step, settleMs, maxPasses }) => {
      const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
      const fullHeight = () => document.documentElement.scrollHeight;
      let y = 0;
      let passes = 0;
      // `maxPasses` bounds this: a page that grows every time it is scrolled
      // (an infinite feed) would otherwise never terminate.
      while (y < fullHeight() && passes < maxPasses) {
        window.scrollTo(0, y);
        await sleep(settleMs);
        y += step;
        passes += 1;
      }
      window.scrollTo(0, fullHeight());
      await sleep(settleMs);
      window.scrollTo(0, 0);
      await sleep(settleMs);
    },
    { step, settleMs, maxPasses },
  );

  await page.evaluate(async () => {
    const imgs = Array.from(document.images);
    for (const img of imgs) {
      if (img.loading === 'lazy') img.loading = 'eager';
    }
    // `decode()` rejects on a broken image; a broken image is the page's problem
    // and should show up in the capture, not abort the settle.
    await Promise.all(
      imgs.map((img) => (img.complete ? Promise.resolve() : img.decode().catch(() => {}))),
    );
  });

  await page.waitForLoadState('networkidle');
}

/** Freeze, settle fonts, then a double frame so the freeze and the font swap have
 *  painted before the screenshot. This is the sequence the parity engine proved. */
export async function stabilizeForCapture(page) {
  await page.addStyleTag({ content: STABILITY_CSS });
  await page.evaluate(() => document.fonts && document.fonts.ready);
  await page.evaluate(
    () => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))),
  );
}

/**
 * The full pre-capture sequence, in the order decided above:
 *   1. scroll-behaviour override   (so the settle scroll is instant)
 *   2. lazy-content settle          (so below-the-fold content exists)
 *   3. freeze transitions/animations/caret
 *   4. fonts.ready
 *   5. double requestAnimationFrame
 *
 * Steps 3 to 5 are `stabilizeForCapture`.
 */
export async function prepareForCapture(page, opts = {}) {
  await page.addStyleTag({ content: SCROLL_BEHAVIOR_CSS });
  await settleLazyContent(page, opts);
  await stabilizeForCapture(page);
}
