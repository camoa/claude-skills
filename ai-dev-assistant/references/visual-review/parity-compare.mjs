/**
 * parity-compare.mjs — the visual-parity comparison engine.
 * ai-dev-assistant v4.14.0 (Task D — visual_and_e2e_review_gates).
 *
 * `/setup-visual-parity` copies this file ONCE into <codePath>/tests/parity/ so the
 * generated per-surface specs can `import './parity-compare.mjs'` at the project's
 * codePath ( ${CLAUDE_PLUGIN_ROOT} is not resolvable at Playwright runtime ). Plain ESM
 * — no TypeScript compilation step; Playwright imports it directly.
 *
 * It produces the TWO-LAYER diff Task D's research settled on:
 *   1. coarse pixel diff (pixelmatch) — "something is off"
 *   2. structured CSS-actionable diff (getComputedStyle) — "here is WHAT, and by how much"
 *
 * The CSS-actionable diff is TIERED by reference type (research D1 / css-actionable-diff.md):
 *   - renderable references (html-template / react-template / prod-url) have a DOM on
 *     BOTH sides → a full property-level diff;
 *   - static references (figma / image) are flat PNGs with no DOM → build-side computed
 *     styles only, honestly labelled `css_diff_mode: "build-only"`.
 *
 * CROSS-STACK support (v4.15.0 — visual-parity deltas). When the reference is a
 * different rendering engine (e.g. Vite/React) than the build (Drupal/Twig), an exact
 * pixel match is impossible — anti-aliasing, font hinting, sub-pixel layout, and
 * volatile content (timestamps, seeded data) all add a non-zero diff floor. Six deltas
 * make the diff SALIENT rather than zero: forwarded masks (D1), capture stabilisation
 * (D2), full-height pad-max alignment (D3), per-surface ratio thresholds (D4), the
 * Expected/Actual/Diff slider contract (D5), a JSONL trend stream (D6), env-agnostic
 * reference URLs (D7), and a minimum-rendered-content guard (D8). Every delta is
 * additive — a surface that opts into none captures exactly as it did at v4.14.0.
 *
 * SECURITY (paper-test remediation A1/A2/A3/A4/A6): the registry that supplies
 * surfaceId / buildUrl / referenceUri / compareSelectors is untrusted input. This engine
 * therefore: (a) charset-validates surfaceId + viewport before any path join;
 * (b) confines every file reference to PARITY_CODE_PATH; (c) scheme-checks buildUrl;
 * (d) wraps the reference decode. surfaceId/buildUrl/etc. NEVER reach this engine via
 * source-code substitution — the generated spec is verbatim and reads them as DATA.
 *
 * Dependencies: `@playwright/test`, `pixelmatch`, `pngjs` — imported LAZILY inside
 * runParityCheck() so the pure exported helpers stay unit-testable by
 * tests/parity-compare-spec.mjs without those packages installed.
 *
 * Runtime env:
 *   PARITY_RUN_DIR             directory the gate created for this run's artifacts (required)
 *   PARITY_CODE_PATH           the project codePath — confinement root for file references
 *                              (the gate exports it; falls back to process.cwd())
 *   PARITY_MAX_DIFF_RATIO      coarse pixel-diff threshold (optional; default 0.05).
 *                              A surface's own `max_diff_ratio` overrides this (D4).
 *   PARITY_REFERENCE_BASE_URL  optional base URL for resolving RELATIVE renderable
 *                              reference URIs (D7) — lets one registry run against ddev,
 *                              CI, or staging with no edit. Absolute URIs are used as-is.
 *   PARITY_STATS_PATH          optional path for the JSONL trend stream (D6); falls back
 *                              to <PARITY_RUN_DIR>/parity-stats.jsonl.
 */
import { readFileSync, writeFileSync, appendFileSync, statSync } from 'node:fs';
import { resolve as resolvePath, sep as pathSep } from 'node:path';
import { pathToFileURL } from 'node:url';

/** Engine version — `/setup-visual-parity` step 3 compares this to decide whether to
 *  refresh a project's copied-in engine. Machine-readable (paper-test F7). */
export const ENGINE_VERSION = '4.15.0';

/** Curated CSS-actionable property set — box model / typography / colour / layout.
 *  Kebab-case so getComputedStyle().getPropertyValue() expands shorthands consistently. */
export const COMPARE_PROPERTIES = [
  // box model
  'width', 'height',
  'margin-top', 'margin-right', 'margin-bottom', 'margin-left',
  'padding-top', 'padding-right', 'padding-bottom', 'padding-left',
  'gap', 'border-top-width', 'border-right-width', 'border-bottom-width', 'border-left-width',
  // typography
  'font-family', 'font-size', 'font-weight', 'line-height', 'letter-spacing', 'text-transform',
  // colour
  'color', 'background-color', 'border-top-color',
  // layout
  'display', 'flex-direction', 'justify-content', 'align-items', 'position',
];

/** Default selector set when a surface registers no `compare_selectors`. */
export const DEFAULT_SELECTORS = ['h1', 'h2', 'h3', 'button', '.button', '.cta', 'main'];

export const DEFAULT_MAX_DIFF_RATIO = 0.05;

/** Reference types whose reference has a renderable DOM. */
export const RENDERABLE_TYPES = new Set(['html-template', 'react-template', 'prod-url']);

/** Kebab-case identifier — surface ids and viewport names (surface-registry-schema §3.2/3.3). */
export const SAFE_IDENTIFIER_RE = /^[a-z0-9][a-z0-9-]*$/;

/** Reference files larger than this are refused before decode (paper-test A11). */
export const MAX_REFERENCE_BYTES = 64 * 1024 * 1024;

/** Mask + pad colour (D1/D3). Magenta is unlikely to appear in real UI, so masked
 *  regions and padded rows contribute no meaningful diff and are obvious in artifacts. */
export const MASK_COLOR = '#ff00ff';
/** RGBA form of MASK_COLOR for pad-max alignment fill (D3). */
export const MASK_COLOR_RGBA = [255, 0, 255, 255];

/** The universal mask attribute — any element a template marks gets painted out (D1). */
export const DATA_VRT_MASK_SELECTOR = '[data-vrt-mask]';

/** Capture-stability freeze CSS (D2) — kills transitions/animations, the caret, and
 *  smooth scrolling so a capture is deterministic across two rendering engines. */
export const STABILITY_CSS =
  '*, *::before, *::after { transition: none !important; animation: none !important; ' +
  'caret-color: transparent !important; } html { scroll-behavior: auto !important; }';

/** Valid `dimension_align` modes (D3). `crop-min` is the v4.14.0 behaviour. */
export const DIMENSION_ALIGN_MODES = new Set(['crop-min', 'pad-max']);
export const DEFAULT_DIMENSION_ALIGN = 'crop-min';

/**
 * Run a visual-parity comparison for one surface at one viewport.
 *
 * @param {import('@playwright/test').Page} page  the Playwright page (build side)
 * @param {import('@playwright/test').TestInfo} testInfo
 * @param {{surfaceId:string, buildUrl:string, referenceType:string,
 *          referenceUri:string, compareSelectors?:string[], maskSelectors?:string[],
 *          dimensionAlign?:('crop-min'|'pad-max'), maxDiffRatio?:number,
 *          contentFloor?:{minHeight?:number, selectors?:Object<string,number>}}} opts
 */
export async function runParityCheck(page, testInfo, opts) {
  // Lazy deps — see the module header (keeps the pure helpers offline-testable).
  const { expect } = await import('@playwright/test');
  const { PNG } = await import('pngjs');
  const pixelmatch = (await import('pixelmatch')).default;

  const { surfaceId, buildUrl, referenceType, referenceUri } = opts;
  const selectors =
    Array.isArray(opts.compareSelectors) && opts.compareSelectors.length > 0
      ? opts.compareSelectors
      : DEFAULT_SELECTORS;
  // Per-surface mask selectors (D1) — registry `masks`, forwarded by the spec. The
  // universal [data-vrt-mask] attribute is ALWAYS added on top (see buildMaskLocators).
  const maskSelectors = Array.isArray(opts.maskSelectors) ? opts.maskSelectors : [];
  const dimensionAlign = normalizeDimensionAlign(opts.dimensionAlign);
  const contentFloor = opts.contentFloor && typeof opts.contentFloor === 'object'
    ? opts.contentFloor
    : null;

  // --- input validation (paper-test A4): surfaceId + viewport must be safe kebab-case
  //     BEFORE they are joined into a filesystem path. ---
  assertSafeIdentifier(surfaceId, 'surfaceId');
  const viewport = projectViewport(testInfo.project.name);
  assertSafeIdentifier(viewport, 'viewport');

  const runDir = process.env.PARITY_RUN_DIR;
  if (!runDir) {
    throw new Error('parity-compare: PARITY_RUN_DIR is not set — run via visual-parity-gate.sh');
  }
  const codePath = resolvePath(process.env.PARITY_CODE_PATH || process.cwd());
  // Effective coarse pixel-diff threshold (D4): a surface's own max_diff_ratio overrides
  // the global env default. The EFFECTIVE value is written into the result fragment so
  // visual-parity-gate.sh applies the identical number (the F1/F8 verdict-parity rule).
  const globalMaxDiffRatio = parseRatio(process.env.PARITY_MAX_DIFF_RATIO, DEFAULT_MAX_DIFF_RATIO);
  const maxDiffRatio = resolveMaxDiffRatio(opts.maxDiffRatio, globalMaxDiffRatio);
  const resultPath = resolvePath(runDir, `${surfaceId}-${viewport}.parity.json`);
  const diffPath = resolvePath(runDir, `${surfaceId}-${viewport}.diff.png`);
  const expectedPath = resolvePath(runDir, `${surfaceId}-${viewport}-expected.png`);
  const actualPath = resolvePath(runDir, `${surfaceId}-${viewport}-actual.png`);
  // D7: resolve a RELATIVE renderable reference URI against PARITY_REFERENCE_BASE_URL.
  // Static references stay raw file paths (confined + read from disk).
  const referenceUriResolved = RENDERABLE_TYPES.has(referenceType)
    ? resolveReferenceUri(referenceUri, process.env.PARITY_REFERENCE_BASE_URL)
    : referenceUri;

  const result = {
    surface: surfaceId,
    viewport,
    reference_type: referenceType,
    css_diff_mode: RENDERABLE_TYPES.has(referenceType) ? 'full' : 'build-only',
    pixel_diff_ratio: null,
    pixel_diff_path: null,
    max_diff_ratio: maxDiffRatio,
    dimension_align: dimensionAlign,
    dimension_mismatch: false,
    content_floor_failed: false,
    content_floor_violations: [],
    css_diff: [],
    build_styles: null,
    notes: [],
    skipped: false,
    skip_reason: null,
  };

  // Helper — write the fragment + register the Playwright skip, then bail.
  const skip = (reason) => {
    result.skipped = true;
    result.skip_reason = reason;
    writeJson(resultPath, result);
    testInfo.skip(true, reason);
  };

  // --- v1 scope guard: a raw React/JS source path is not renderable headless (DA-4) ---
  if (referenceType === 'react-template' && isUnrenderableSource(referenceUriResolved)) {
    skip(
      `react-template reference "${referenceUriResolved}" is a source file — render it first ` +
      `(static export / Storybook build) and register the resulting .html or a served URL.`,
    );
    return;
  }

  // --- build side: render + screenshot + computed styles -----------------------------
  if (!isSafeBuildUrl(buildUrl)) {
    skip(`build URL "${buildUrl}" is not a relative path or an http(s) URL — refused`);
    return;
  }
  await page.goto(buildUrl, { waitUntil: 'networkidle' });
  await stabilizeForCapture(page);                         // D2
  // The mask locators come from untrusted registry `masks` selectors; an invalid CSS
  // selector throws when Playwright RESOLVES it during screenshot(). Convert that (and
  // any other capture failure) into a clean skip — never an uncaught throw that escapes
  // before the fragment is written (paper-test A10/F2; mirrors extractComputedStyles).
  let buildPng;
  try {
    buildPng = await page.screenshot(screenshotOptions(buildMaskLocators(page, maskSelectors)));
  } catch (err) {
    skip(`build capture failed — a mask selector in ${JSON.stringify(maskSelectors)} may be ` +
         `invalid CSS: ${err.message}`);
    return;
  }
  const buildStyles = await extractComputedStyles(page, selectors);

  // --- minimum-rendered-content guard (D8) — runs against the BUILD (candidate) so an
  //     empty / unseeded page FAILS loudly instead of passing a near-blank diff. ---
  if (contentFloor) {
    const measured = await measureContent(page, contentFloor);
    const violations = contentFloorViolations(measured, contentFloor);
    if (violations.length > 0) {
      result.content_floor_failed = true;
      result.content_floor_violations = violations;
      result.notes.push(
        `content floor not met: ${violations.join('; ')} — the build rendered too little ` +
        `to be a meaningful parity comparison`,
      );
    }
  }

  // --- reference side ----------------------------------------------------------------
  let referencePng;
  let referenceStyles = null;

  if (RENDERABLE_TYPES.has(referenceType)) {
    let refTarget;
    try {
      refTarget = resolveRenderableUri(referenceType, referenceUriResolved, codePath);
    } catch (err) {
      skip(`renderable reference "${referenceUriResolved}" rejected: ${err.message}`);
      return;
    }
    const refPage = await page.context().newPage();
    let refCaptureError = null;
    try {
      await refPage.setViewportSize(page.viewportSize() || { width: 1280, height: 720 });
      await refPage.goto(refTarget, { waitUntil: 'networkidle' });
      await stabilizeForCapture(refPage);                 // D2
      referencePng = await refPage.screenshot(screenshotOptions(buildMaskLocators(refPage, maskSelectors)));
      referenceStyles = await extractComputedStyles(refPage, selectors);
    } catch (err) {
      // A reference goto/capture failure — including a mask selector that is invalid CSS
      // — degrades to a clean skip, never an uncaught throw (paper-test A10/F2).
      refCaptureError = err;
    } finally {
      await refPage.close();
    }
    if (refCaptureError) {
      skip(`reference capture failed for "${referenceUriResolved}" — a mask selector in ` +
           `${JSON.stringify(maskSelectors)} may be invalid CSS: ${refCaptureError.message}`);
      return;
    }
  } else {
    // static reference — figma / image: a flat PNG, no DOM. Confine the path to the
    // project root, cap its size, then read.
    let refPath;
    try {
      refPath = confinedPath(referenceUri, codePath);
      const bytes = statSync(refPath).size;
      if (bytes > MAX_REFERENCE_BYTES) {
        skip(`static reference "${referenceUri}" is ${bytes} bytes — exceeds the ` +
             `${MAX_REFERENCE_BYTES}-byte cap`);
        return;
      }
      referencePng = readFileSync(refPath);
    } catch (err) {
      skip(`static reference not usable at "${referenceUri}": ${err.message}`);
      return;
    }
    result.build_styles = buildStyles; // honest best-effort — build side only
    result.notes.push('reference is a static image — CSS diff is build-side only');
  }

  // --- coarse pixel diff -------------------------------------------------------------
  // pixelDiff decodes both PNG buffers; the reference buffer is untrusted, so a decode
  // failure (truncated / non-PNG / bomb) becomes a clean skip, never an uncaught throw
  // that drops the whole fragment (paper-test F2/A10).
  let pixel;
  try {
    pixel = pixelDiff(buildPng, referencePng, PNG, pixelmatch, dimensionAlign);
  } catch (err) {
    skip(`reference image could not be decoded: ${err.message}`);
    return;
  }
  result.pixel_diff_ratio = pixel.ratio;
  result.dimension_mismatch = pixel.dimensionMismatch;
  if (pixel.dimensionMismatch) {
    result.notes.push(
      dimensionAlign === 'pad-max'
        ? `build ${pixel.buildDims} vs reference ${pixel.refDims} — aligned to the taller ` +
          `${pixel.comparedDims} region (pad-max); the shorter side is bottom-padded with the ` +
          `mask colour, so below-the-fold divergence (a missing or extra section) surfaces as diff.`
        : `build ${pixel.buildDims} vs reference ${pixel.refDims} — compared at the common ` +
          `${pixel.comparedDims} region. NOTE: any build content below the reference height ` +
          `is NOT compared (a build much taller than a static comp can pass while broken ` +
          `below the comp's fold — prefer a renderable reference, dimension_align: pad-max, ` +
          `or a single-viewport run).`,
    );
  }
  if (pixel.diffPng) {
    writeFileSync(diffPath, pixel.diffPng);
    result.pixel_diff_path = diffPath;
  }

  // --- slider contract (D5): write expected/actual PNGs and attach the trio with the
  //     load-bearing -expected/-actual/-diff.png suffixes so the Playwright HTML
  //     reporter activates the Expected/Actual/Diff slider on each surface result. ---
  writeFileSync(expectedPath, referencePng);
  writeFileSync(actualPath, buildPng);
  await testInfo.attach(`${surfaceId}-${viewport}-expected.png`, { path: expectedPath, contentType: 'image/png' });
  await testInfo.attach(`${surfaceId}-${viewport}-actual.png`, { path: actualPath, contentType: 'image/png' });
  if (result.pixel_diff_path) {
    await testInfo.attach(`${surfaceId}-${viewport}-diff.png`, { path: diffPath, contentType: 'image/png' });
  }

  // --- JSONL trend stream (D6): one OS-atomic line per surface/run. appendFileSync is
  //     atomic for single-line writes, so it is safe under parallel Playwright workers. ---
  appendStats(runDir, {
    surfaceId,
    project: testInfo.project.name,
    viewport,
    diffRatio: pixel.ratio,
    diffPixels: pixel.diffPixels,
    totalPixels: pixel.totalPixels,
    width: pixel.width,
    height: pixel.height,
    timestamp: new Date().toISOString(),
  });

  // --- structured CSS-actionable diff (full mode only) -------------------------------
  if (result.css_diff_mode === 'full' && referenceStyles) {
    const { rows, notes } = compareStyles(buildStyles, referenceStyles, selectors);
    result.css_diff = rows;
    result.notes.push(...notes);
  }

  // The result JSON is written BEFORE the assertion so a FAILING surface still yields
  // the actionable fix list for the AI / /review.
  writeJson(resultPath, result);

  // --- assert: fail when the build drifts from the design intent ---------------------
  // Predicate matches visual-parity-gate.sh's per-surface verdict exactly (paper-test F8).
  const pixelOverTolerance =
    result.pixel_diff_ratio != null && result.pixel_diff_ratio >= maxDiffRatio;
  const cssDrift = result.css_diff.length > 0;
  const contentFloorFailed = result.content_floor_failed;

  expect(
    pixelOverTolerance || cssDrift || contentFloorFailed,
    contentFloorFailed
      ? `content floor not met — ${result.content_floor_violations.join('; ')} (see ${resultPath})`
      : pixelOverTolerance
        ? `pixel diff ${fmtPct(result.pixel_diff_ratio)} ≥ tolerance ${fmtPct(maxDiffRatio)}`
        : `${result.css_diff.length} CSS-actionable difference(s) vs the design reference ` +
          `— see ${resultPath}`,
  ).toBe(false);
}

// ---------------------------------------------------------------------------------------
// pure helpers — exported for tests/parity-compare-spec.mjs (no external deps)
// ---------------------------------------------------------------------------------------

/** Throw unless `value` is a safe kebab-case identifier (paper-test A1/A4). */
export function assertSafeIdentifier(value, label) {
  if (typeof value !== 'string' || !SAFE_IDENTIFIER_RE.test(value)) {
    throw new Error(
      `parity-compare: ${label} "${value}" is not a safe kebab-case identifier ` +
      `(^[a-z0-9][a-z0-9-]*$)`,
    );
  }
  return value;
}

/** Strip the `parity-chromium-` prefix from a Playwright project name → viewport name. */
export function projectViewport(projectName) {
  const m = /^parity-chromium-(.+)$/.exec(projectName || '');
  return m ? m[1] : (projectName || 'default');
}

/** Parse a `0 < ratio < 1` string; fall back when malformed. */
export function parseRatio(raw, fallback) {
  const n = Number.parseFloat(raw);
  return Number.isFinite(n) && n > 0 && n < 1 ? n : fallback;
}

/**
 * Resolve the effective per-surface diff ratio (D4). A surface `max_diff_ratio` (number
 * or numeric string) in the open interval (0,1) overrides `fallback` (the global env
 * default); anything else falls through. Distinct from pixelmatch's per-PIXEL
 * sensitivity (`threshold: 0.1`, internal to pixelDiff) — this is the per-surface RATIO gate.
 */
export function resolveMaxDiffRatio(perSurface, fallback) {
  if (perSurface == null) return fallback;
  const n = typeof perSurface === 'number' ? perSurface : Number.parseFloat(perSurface);
  return Number.isFinite(n) && n > 0 && n < 1 ? n : fallback;
}

/** Normalize a `dimension_align` value to a valid mode, defaulting to crop-min (D3). */
export function normalizeDimensionAlign(value) {
  return DIMENSION_ALIGN_MODES.has(value) ? value : DEFAULT_DIMENSION_ALIGN;
}

/**
 * Resolve a RELATIVE renderable reference URI against a base URL (D7). Absolute http(s)
 * URIs pass through unchanged; when no base is set the URI is returned untouched (so the
 * v4.14.0 file-path behaviour is preserved). The base + relative path are joined with a
 * single slash. Only meaningful for renderable references — the caller restricts it.
 */
export function resolveReferenceUri(uri, baseUrl) {
  if (typeof uri !== 'string' || uri.length === 0) return uri;
  if (/^https?:\/\//i.test(uri)) return uri;              // already absolute
  if (typeof baseUrl !== 'string' || baseUrl.length === 0) return uri;
  if (!/^https?:\/\//i.test(baseUrl)) return uri;         // base must be an http(s) origin
  return `${baseUrl.replace(/\/+$/, '')}/${uri.replace(/^\/+/, '')}`;
}

/** A `.jsx`/`.tsx`/`.js`/`.ts` path is React source, not a renderable artifact (DA-4). */
export function isUnrenderableSource(uri) {
  if (/^https?:\/\//i.test(uri)) return false;          // a served URL is fine
  return /\.(jsx?|tsx?|mjs|cjs)$/i.test(uri);
}

/**
 * A build URL is acceptable when it is a relative path (resolved against the Playwright
 * baseURL — the common case for a DDEV site) OR an explicit http(s) URL. Any other
 * scheme — `file:`, `data:`, `javascript:` — is refused (paper-test A5).
 */
export function isSafeBuildUrl(url) {
  if (typeof url !== 'string' || url.length === 0) return false;
  const scheme = /^([a-z][a-z0-9+.-]*):/i.exec(url);
  if (!scheme) return true;                              // relative — resolved vs baseURL
  return /^https?$/i.test(scheme[1]);
}

/**
 * Resolve a file reference and confine it to `codePath` (paper-test A2/A3/A6).
 * Throws when the resolved path escapes the project root.
 */
export function confinedPath(uri, codePath) {
  const root = resolvePath(codePath);
  const resolved = resolvePath(root, uri);
  if (resolved !== root && !resolved.startsWith(root + pathSep)) {
    throw new Error(`path "${uri}" escapes the project root ${root}`);
  }
  return resolved;
}

/**
 * Resolve a renderable reference to a navigable URL. `prod-url` accepts only http(s);
 * file-backed `html-template` / `react-template` paths are confined to `codePath`.
 */
export function resolveRenderableUri(type, uri, codePath) {
  if (type === 'prod-url') {
    if (!/^https?:\/\//i.test(uri)) {
      throw new Error(`prod-url reference must be an http(s) URL — got "${uri}"`);
    }
    return uri;
  }
  // html-template / react-template: an http(s) URL passes through; anything else is a
  // file path, confined to the project root.
  if (/^https?:\/\//i.test(uri)) return uri;
  return pathToFileURL(confinedPath(uri, codePath)).href;
}

/** Compare two computed-style maps → structured `{selector,property,build,reference}` rows. */
export function compareStyles(buildStyles, referenceStyles, selectors) {
  const rows = [];
  const notes = [];
  for (const sel of selectors) {
    const b = buildStyles[sel];
    const r = referenceStyles[sel];
    if (!b && !r) continue;                       // absent on both sides — nothing to say
    if (!b) { notes.push(`selector "${sel}" not found in the build`); continue; }
    if (!r) { notes.push(`selector "${sel}" not found in the reference`); continue; }
    for (const prop of COMPARE_PROPERTIES) {
      if (b[prop] !== r[prop]) {
        rows.push({ selector: sel, property: prop, build: b[prop], reference: r[prop] });
      }
    }
  }
  return { rows, notes };
}

/**
 * Compute content-floor violations (D8) from already-measured build values. Pure so the
 * decision logic is unit-testable; the measurement (DOM read) is done by measureContent().
 * `floor.minHeight` — fail when the rendered scrollHeight is below it.
 * `floor.selectors` — `{selector: minCount}`; fail when fewer than minCount match.
 */
export function contentFloorViolations(measured, floor) {
  const out = [];
  if (!floor || typeof floor !== 'object') return out;
  if (typeof floor.minHeight === 'number' && floor.minHeight > 0) {
    const h = measured && typeof measured.height === 'number' ? measured.height : 0;
    if (h < floor.minHeight) {
      out.push(`rendered height ${h}px < required ${floor.minHeight}px`);
    }
  }
  if (floor.selectors && typeof floor.selectors === 'object') {
    const counts = (measured && measured.counts) || {};
    for (const [sel, min] of Object.entries(floor.selectors)) {
      if (typeof min !== 'number' || min <= 0) continue;
      const got = typeof counts[sel] === 'number' ? counts[sel] : 0;
      if (got < min) {
        out.push(`selector "${sel}" matched ${got} element(s) < required ${min}`);
      }
    }
  }
  return out;
}

/** Return an RGBA Uint8Array for the top-left w×h region of a decoded PNG (crop-min). */
export function cropRGBA(png, w, h) {
  if (png.width === w && png.height === h) return png.data;
  const out = Buffer.alloc(w * h * 4);
  for (let y = 0; y < h; y++) {
    const srcStart = y * png.width * 4;
    png.data.copy(out, y * w * 4, srcStart, srcStart + w * 4);
  }
  return out;
}

/**
 * Return a w×h RGBA buffer holding the top-left of `png`, with any area beyond the image
 * filled by `padColor` (D3 pad-max). When w×h fits inside the image this is a plain crop;
 * when h exceeds the image height the extra rows are padColor — so a shorter page padded
 * to the taller height adds NO real diff against a same-colour pad on the other side.
 */
export function alignRGBA(png, w, h, padColor) {
  const out = Buffer.alloc(w * h * 4);
  const [pr, pg, pb, pa] = padColor;
  for (let i = 0; i < out.length; i += 4) {
    out[i] = pr; out[i + 1] = pg; out[i + 2] = pb; out[i + 3] = pa;
  }
  const copyH = Math.min(h, png.height);
  const copyW = Math.min(w, png.width);
  for (let y = 0; y < copyH; y++) {
    const srcStart = y * png.width * 4;
    png.data.copy(out, y * w * 4, srcStart, srcStart + copyW * 4);
  }
  return out;
}

// ---------------------------------------------------------------------------------------
// Playwright/pngjs-coupled helpers (called only from runParityCheck)
// ---------------------------------------------------------------------------------------

/** Stabilise a page for a deterministic capture (D2): freeze CSS, settle fonts, then
 *  a double-rAF so the freeze and font swap have painted before the screenshot. */
async function stabilizeForCapture(page) {
  await page.addStyleTag({ content: STABILITY_CSS });
  await page.evaluate(() => document.fonts && document.fonts.ready);
  await page.evaluate(
    () => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))),
  );
}

/** Build the mask locator list (D1): the universal [data-vrt-mask] attribute plus any
 *  per-surface CSS selectors. Non-string/empty selectors are dropped defensively. */
function buildMaskLocators(page, maskSelectors) {
  const locators = [page.locator(DATA_VRT_MASK_SELECTOR)];
  for (const sel of maskSelectors) {
    if (typeof sel === 'string' && sel.trim().length > 0) {
      locators.push(page.locator(sel));
    }
  }
  return locators;
}

/** Common screenshot options (D1/D2): full page, animations off, caret hidden, masked. */
function screenshotOptions(maskLocators) {
  return {
    fullPage: true,
    animations: 'disabled',
    caret: 'hide',
    mask: maskLocators,
    maskColor: MASK_COLOR,
  };
}

/** Measure the build content for the content-floor guard (D8): rendered height and the
 *  match count for each declared selector. Invalid selectors count as 0 (never throw). */
async function measureContent(page, floor) {
  const sels = floor && floor.selectors && typeof floor.selectors === 'object'
    ? Object.keys(floor.selectors)
    : [];
  return page.evaluate((selectorList) => {
    const height = Math.max(
      document.documentElement ? document.documentElement.scrollHeight : 0,
      document.body ? document.body.scrollHeight : 0,
    );
    const counts = {};
    for (const sel of selectorList) {
      try {
        counts[sel] = document.querySelectorAll(sel).length;
      } catch {
        counts[sel] = 0; // an invalid selector yields no match — never throws out
      }
    }
    return { height, counts };
  }, sels);
}

/** Extract computed styles for `selectors` (first match of each) on `page`. */
async function extractComputedStyles(page, selectors) {
  return page.evaluate(
    ({ sels, props }) => {
      const out = {};
      for (const sel of sels) {
        let el = null;
        try {
          el = document.querySelector(sel);
        } catch {
          el = null; // an invalid selector string yields no match — never throws out
        }
        if (!el) {
          out[sel] = null;
          continue;
        }
        const cs = window.getComputedStyle(el);
        const entry = {};
        for (const p of props) entry[p] = cs.getPropertyValue(p).trim();
        out[sel] = entry;
      }
      return out;
    },
    { sels: selectors, props: COMPARE_PROPERTIES },
  );
}

/** Coarse pixel diff via pixelmatch. `dimension_align` (D3) controls how a size mismatch
 *  is reconciled: `crop-min` (default) crops both to the common region; `pad-max` pads the
 *  shorter image to the taller height with the mask colour so full-height content compares.
 *  Throws if either buffer fails to decode — the caller converts that to a clean skip. */
function pixelDiff(buildBuffer, referenceBuffer, PNG, pixelmatch, dimensionAlign = DEFAULT_DIMENSION_ALIGN) {
  const build = PNG.sync.read(buildBuffer);
  const reference = PNG.sync.read(referenceBuffer);

  const dimensionMismatch =
    build.width !== reference.width || build.height !== reference.height;

  let w, h, a, b;
  if (dimensionAlign === 'pad-max') {
    w = Math.min(build.width, reference.width);
    h = Math.max(build.height, reference.height);
    a = alignRGBA(build, w, h, MASK_COLOR_RGBA);
    b = alignRGBA(reference, w, h, MASK_COLOR_RGBA);
  } else {
    w = Math.min(build.width, reference.width);
    h = Math.min(build.height, reference.height);
    a = cropRGBA(build, w, h);
    b = cropRGBA(reference, w, h);
  }
  const diff = new PNG({ width: w, height: h });

  const mismatched = pixelmatch(a, b, diff.data, w, h, { threshold: 0.1 });
  return {
    ratio: w * h > 0 ? mismatched / (w * h) : 0,
    diffPng: PNG.sync.write(diff),
    dimensionMismatch,
    diffPixels: mismatched,
    totalPixels: w * h,
    width: w,
    height: h,
    buildDims: `${build.width}x${build.height}`,
    refDims: `${reference.width}x${reference.height}`,
    comparedDims: `${w}x${h}`,
  };
}

/** Append one JSON line to the run's parity-stats.jsonl (D6). PARITY_STATS_PATH overrides
 *  the default <runDir>/parity-stats.jsonl. Write-only; a failure here never fails the run. */
function appendStats(runDir, record) {
  try {
    const statsPath = process.env.PARITY_STATS_PATH || resolvePath(runDir, 'parity-stats.jsonl');
    appendFileSync(statsPath, JSON.stringify(record) + '\n');
  } catch {
    // trend telemetry is best-effort — never let it break the comparison
  }
}

function writeJson(path, obj) {
  writeFileSync(path, JSON.stringify(obj, null, 2));
}
