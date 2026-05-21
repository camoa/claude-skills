/**
 * parity-compare.mjs — the visual-parity comparison engine.
 * drupal-dev-framework v4.14.0 (Task D — visual_and_e2e_review_gates).
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
 *   PARITY_RUN_DIR        directory the gate created for this run's artifacts (required)
 *   PARITY_CODE_PATH      the Drupal codePath — confinement root for file references
 *                         (the gate exports it; falls back to process.cwd())
 *   PARITY_MAX_DIFF_RATIO coarse pixel-diff threshold (optional; default 0.05)
 */
import { readFileSync, writeFileSync, statSync } from 'node:fs';
import { resolve as resolvePath, sep as pathSep } from 'node:path';
import { pathToFileURL } from 'node:url';

/** Engine version — `/setup-visual-parity` step 3 compares this to decide whether to
 *  refresh a project's copied-in engine. Machine-readable (paper-test F7). */
export const ENGINE_VERSION = '4.14.0';

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

/**
 * Run a visual-parity comparison for one surface at one viewport.
 *
 * @param {import('@playwright/test').Page} page  the Playwright page (build side)
 * @param {import('@playwright/test').TestInfo} testInfo
 * @param {{surfaceId:string, buildUrl:string, referenceType:string,
 *          referenceUri:string, compareSelectors?:string[]}} opts
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
  const maxDiffRatio = parseRatio(process.env.PARITY_MAX_DIFF_RATIO, DEFAULT_MAX_DIFF_RATIO);
  const resultPath = resolvePath(runDir, `${surfaceId}-${viewport}.parity.json`);
  const diffPath = resolvePath(runDir, `${surfaceId}-${viewport}.diff.png`);

  const result = {
    surface: surfaceId,
    viewport,
    reference_type: referenceType,
    css_diff_mode: RENDERABLE_TYPES.has(referenceType) ? 'full' : 'build-only',
    pixel_diff_ratio: null,
    pixel_diff_path: null,
    dimension_mismatch: false,
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
  if (referenceType === 'react-template' && isUnrenderableSource(referenceUri)) {
    skip(
      `react-template reference "${referenceUri}" is a source file — render it first ` +
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
  await page.evaluate(() => document.fonts && document.fonts.ready);
  const buildPng = await page.screenshot({ fullPage: true, animations: 'disabled' });
  const buildStyles = await extractComputedStyles(page, selectors);

  // --- reference side ----------------------------------------------------------------
  let referencePng;
  let referenceStyles = null;

  if (RENDERABLE_TYPES.has(referenceType)) {
    let refTarget;
    try {
      refTarget = resolveRenderableUri(referenceType, referenceUri, codePath);
    } catch (err) {
      skip(`renderable reference "${referenceUri}" rejected: ${err.message}`);
      return;
    }
    const refPage = await page.context().newPage();
    try {
      await refPage.setViewportSize(page.viewportSize() || { width: 1280, height: 720 });
      await refPage.goto(refTarget, { waitUntil: 'networkidle' });
      await refPage.evaluate(() => document.fonts && document.fonts.ready);
      referencePng = await refPage.screenshot({ fullPage: true, animations: 'disabled' });
      referenceStyles = await extractComputedStyles(refPage, selectors);
    } finally {
      await refPage.close();
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
    pixel = pixelDiff(buildPng, referencePng, PNG, pixelmatch);
  } catch (err) {
    skip(`reference image could not be decoded: ${err.message}`);
    return;
  }
  result.pixel_diff_ratio = pixel.ratio;
  result.dimension_mismatch = pixel.dimensionMismatch;
  if (pixel.dimensionMismatch) {
    result.notes.push(
      `build ${pixel.buildDims} vs reference ${pixel.refDims} — compared at the common ` +
      `${pixel.comparedDims} region. NOTE: any build content below the reference height ` +
      `is NOT compared (a build much taller than a static comp can pass while broken ` +
      `below the comp's fold — prefer a renderable reference or a single-viewport run).`,
    );
  }
  if (pixel.diffPng) {
    writeFileSync(diffPath, pixel.diffPng);
    result.pixel_diff_path = diffPath;
  }

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

  expect(
    pixelOverTolerance || cssDrift,
    pixelOverTolerance
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

export function fmtPct(ratio) {
  return `${(ratio * 100).toFixed(2)}%`;
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

/** Return an RGBA Uint8Array for the top-left w×h region of a decoded PNG. */
export function cropRGBA(png, w, h) {
  if (png.width === w && png.height === h) return png.data;
  const out = Buffer.alloc(w * h * 4);
  for (let y = 0; y < h; y++) {
    const srcStart = y * png.width * 4;
    png.data.copy(out, y * w * 4, srcStart, srcStart + w * 4);
  }
  return out;
}

// ---------------------------------------------------------------------------------------
// Playwright/pngjs-coupled helpers (called only from runParityCheck)
// ---------------------------------------------------------------------------------------

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

/** Coarse pixel diff via pixelmatch; crops to the common region on a dimension mismatch.
 *  Throws if either buffer fails to decode — the caller converts that to a clean skip. */
function pixelDiff(buildBuffer, referenceBuffer, PNG, pixelmatch) {
  const build = PNG.sync.read(buildBuffer);
  const reference = PNG.sync.read(referenceBuffer);

  const w = Math.min(build.width, reference.width);
  const h = Math.min(build.height, reference.height);
  const dimensionMismatch =
    build.width !== reference.width || build.height !== reference.height;

  const a = cropRGBA(build, w, h);
  const b = cropRGBA(reference, w, h);
  const diff = new PNG({ width: w, height: h });

  const mismatched = pixelmatch(a, b, diff.data, w, h, { threshold: 0.1 });
  return {
    ratio: w * h > 0 ? mismatched / (w * h) : 0,
    diffPng: PNG.sync.write(diff),
    dimensionMismatch,
    buildDims: `${build.width}x${build.height}`,
    refDims: `${reference.width}x${reference.height}`,
    comparedDims: `${w}x${h}`,
  };
}

function writeJson(path, obj) {
  writeFileSync(path, JSON.stringify(obj, null, 2));
}
