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

/**
 * Measure what the masks actually cover.
 *
 * A mask is chosen to suppress noise. Nothing ever asked whether it also
 * suppresses the subject. Measured on one real project, the two masks setup
 * produced (`img` and a dynamic-listing container) covered 29 of 29 teaser cards
 * on one surface and 32 of 34 on another — so the mask added to absorb churning
 * content painted over every component the suite exists to protect. The gate
 * would have passed a refactor that broke every card, and the human review saw
 * grey boxes where the subject should have been. Neither the tool nor the person
 * caught it at baseline sign-off, because no component reported it.
 *
 * The information is free at capture time: every mask locator already has a
 * bounding box.
 *
 * Overlapping masks must not double-count, so coverage is rasterised onto a
 * coarse grid rather than summed. The grid is deliberately cheap — this is a
 * warning signal, not a measurement anyone should tune against.
 *
 * @param {import('@playwright/test').Page} page
 * @param {string[]} selectors  the mask selectors, as CSS strings
 * @param {{grid?: number}} [opts]
 * @returns {Promise<{page_area:number, masked_area:number, masked_fraction:number,
 *                    per_selector:{selector:string,count:number}[]}>}
 */
export async function measureMaskCoverage(page, selectors, opts = {}) {
  const grid = opts.grid ?? 120;
  return page.evaluate(
    ({ selectors, grid }) => {
      const doc = document.documentElement;
      const w = Math.max(doc.scrollWidth, 1);
      const h = Math.max(doc.scrollHeight, 1);
      const cellW = w / grid;
      const cellH = h / grid;
      const covered = new Uint8Array(grid * grid);
      const perSelector = [];

      for (const sel of selectors) {
        let els = [];
        try {
          els = Array.from(document.querySelectorAll(sel));
        } catch {
          // An invalid selector matches nothing rather than throwing the capture.
          perSelector.push({ selector: sel, count: -1 });
          continue;
        }
        perSelector.push({ selector: sel, count: els.length });

        for (const el of els) {
          const r = el.getBoundingClientRect();
          if (r.width <= 0 || r.height <= 0) continue;
          // Rects are viewport-relative; the capture is document-relative.
          const top = r.top + window.scrollY;
          const left = r.left + window.scrollX;
          const c0 = Math.max(0, Math.floor(left / cellW));
          const c1 = Math.min(grid - 1, Math.floor((left + r.width) / cellW));
          const r0 = Math.max(0, Math.floor(top / cellH));
          const r1 = Math.min(grid - 1, Math.floor((top + r.height) / cellH));
          for (let row = r0; row <= r1; row++) {
            for (let col = c0; col <= c1; col++) covered[row * grid + col] = 1;
          }
        }
      }

      let cells = 0;
      for (let i = 0; i < covered.length; i++) cells += covered[i];
      const pageArea = w * h;
      return {
        page_area: pageArea,
        masked_area: Math.round((cells / (grid * grid)) * pageArea),
        masked_fraction: cells / (grid * grid),
        per_selector: perSelector,
      };
    },
    { selectors, grid },
  );
}

/** Above this fraction of the page, a mask is more likely hiding the subject than
 *  the noise. Chosen as a signal, not a tuned threshold — the point is that
 *  somebody looks, not that this number is exactly right. */
export const MASK_COVERAGE_WARN_FRACTION = 0.4;
