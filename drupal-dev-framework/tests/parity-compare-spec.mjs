/**
 * parity-compare-spec.mjs — verify the pure logic of
 * references/visual-review/parity-compare.mjs (v4.14.0, Task D).
 *
 * The Playwright/pngjs render path needs a live browser, so this harness covers
 * the deterministic pure functions — the parts testable offline. The external
 * deps (@playwright/test, pngjs, pixelmatch) load lazily inside runParityCheck(),
 * so importing the module here needs none of them installed.
 *
 *   Run:  node tests/parity-compare-spec.mjs
 */
import {
  projectViewport,
  parseRatio,
  isUnrenderableSource,
  resolveRenderableUri,
  compareStyles,
  assertSafeIdentifier,
  confinedPath,
  isSafeBuildUrl,
  RENDERABLE_TYPES,
  DEFAULT_MAX_DIFF_RATIO,
  ENGINE_VERSION,
} from '../references/visual-review/parity-compare.mjs';

let fail = 0;
const ok = (m) => console.log(`OK   ${m}`);
const bad = (m) => { console.error(`FAIL: ${m}`); fail = 1; };
const eq = (got, want, m) =>
  JSON.stringify(got) === JSON.stringify(want)
    ? ok(m)
    : bad(`${m} — got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`);
const truthy = (v, m) => (v ? ok(m) : bad(m));
const throws = (fn, m) => {
  try { fn(); bad(`${m} — expected a throw`); }
  catch { ok(m); }
};

// === ENGINE_VERSION (paper-test F7) ===
eq(ENGINE_VERSION, '4.14.0', 'ENGINE_VERSION is the machine-readable engine version');

// === projectViewport ===
eq(projectViewport('parity-chromium-desktop'), 'desktop', 'projectViewport strips the prefix');
eq(projectViewport('parity-chromium-wide-screen'), 'wide-screen', 'projectViewport keeps hyphens in the viewport name');
eq(projectViewport(''), 'default', 'projectViewport empty → "default"');
eq(projectViewport('e2e-chromium'), 'e2e-chromium', 'projectViewport non-parity name passes through');

// === parseRatio ===
eq(parseRatio('0.08', 0.05), 0.08, 'parseRatio accepts a valid ratio');
eq(parseRatio('bad', 0.05), 0.05, 'parseRatio rejects non-numeric → fallback');
eq(parseRatio('1.5', 0.05), 0.05, 'parseRatio rejects ratio ≥ 1 → fallback');
eq(parseRatio('0', 0.05), 0.05, 'parseRatio rejects 0 → fallback');
eq(parseRatio(undefined, DEFAULT_MAX_DIFF_RATIO), 0.05, 'parseRatio undefined → fallback (default 0.05)');

// === assertSafeIdentifier (paper-test A1/A4 — the spec-injection / path-traversal guard) ===
eq(assertSafeIdentifier('home-hero', 'surfaceId'), 'home-hero', 'assertSafeIdentifier passes a kebab-case id');
throws(() => assertSafeIdentifier("x'}); require('child_process').exec('evil'); ({y:'", 'surfaceId'),
  'assertSafeIdentifier throws on a JS-breakout id (the A1 CRITICAL payload)');
throws(() => assertSafeIdentifier('../../etc/passwd', 'surfaceId'),
  'assertSafeIdentifier throws on a path-traversal id (the A4 payload)');
throws(() => assertSafeIdentifier('Desktop', 'viewport'),
  'assertSafeIdentifier throws on an uppercase identifier');
throws(() => assertSafeIdentifier('', 'surfaceId'),
  'assertSafeIdentifier throws on an empty identifier');

// === confinedPath (paper-test A2/A3 — file-reference confinement) ===
truthy(confinedPath('themes/custom/foo/design/home.html', '/proj') === '/proj/themes/custom/foo/design/home.html',
  'confinedPath resolves an in-repo relative path under the root');
truthy(confinedPath('tests/parity/references/x.png', '/proj').startsWith('/proj/'),
  'confinedPath keeps a tests/parity/references path inside the root');
throws(() => confinedPath('../../../../etc/passwd', '/proj'),
  'confinedPath throws on a ../ traversal escaping the root');
throws(() => confinedPath('/etc/shadow', '/proj'),
  'confinedPath throws on an absolute path outside the root');

// === isSafeBuildUrl (paper-test A5 — buildUrl scheme check) ===
truthy(isSafeBuildUrl('/promo'), 'isSafeBuildUrl: a relative path is allowed (resolved vs baseURL)');
truthy(isSafeBuildUrl('https://mysite.ddev.site/'), 'isSafeBuildUrl: an https URL is allowed');
truthy(isSafeBuildUrl('http://localhost:8080/x'), 'isSafeBuildUrl: an http URL is allowed (local DDEV)');
truthy(!isSafeBuildUrl('file:///etc/passwd'), 'isSafeBuildUrl: a file:// URL is refused');
truthy(!isSafeBuildUrl('javascript:fetch("//evil")'), 'isSafeBuildUrl: a javascript: URL is refused');
truthy(!isSafeBuildUrl(''), 'isSafeBuildUrl: an empty string is refused');

// === isUnrenderableSource (DA-4) ===
truthy(isUnrenderableSource('design/home.jsx'), 'isUnrenderableSource: .jsx source → true');
truthy(isUnrenderableSource('design/home.tsx'), 'isUnrenderableSource: .tsx source → true');
truthy(!isUnrenderableSource('design/home.html'), 'isUnrenderableSource: .html → false (renderable)');
truthy(!isUnrenderableSource('https://comp.example/home.jsx'), 'isUnrenderableSource: served URL → false even with .jsx');

// === resolveRenderableUri (now codePath-confined) ===
eq(resolveRenderableUri('prod-url', 'https://prod.example/landing', '/proj'),
   'https://prod.example/landing', 'resolveRenderableUri prod-url http(s) passes through');
throws(() => resolveRenderableUri('prod-url', '/local/file.html', '/proj'),
   'resolveRenderableUri prod-url with a non-http scheme throws');
truthy(resolveRenderableUri('html-template', 'themes/foo/design/home.html', '/proj').startsWith('file:///proj/'),
   'resolveRenderableUri html-template in-repo path → confined file:// URL');
throws(() => resolveRenderableUri('html-template', '../../../../etc/passwd', '/proj'),
   'resolveRenderableUri html-template path-traversal → throws (confinement)');
throws(() => resolveRenderableUri('html-template', '/etc/passwd', '/proj'),
   'resolveRenderableUri html-template absolute escape → throws (confinement)');
eq(resolveRenderableUri('html-template', 'https://storybook.example/iframe', '/proj'),
   'https://storybook.example/iframe', 'resolveRenderableUri html-template http(s) passes through');

// === RENDERABLE_TYPES ===
truthy(RENDERABLE_TYPES.has('html-template') && RENDERABLE_TYPES.has('react-template')
       && RENDERABLE_TYPES.has('prod-url'), 'RENDERABLE_TYPES holds the 3 DOM-bearing types');
truthy(!RENDERABLE_TYPES.has('figma') && !RENDERABLE_TYPES.has('image'),
   'RENDERABLE_TYPES excludes the static types (figma, image)');

// === compareStyles ===
const build = {
  '.hero-title': { 'font-weight': '400', 'color': 'rgb(26, 26, 26)', 'font-size': '32px' },
  '.cta':        { 'background-color': 'rgb(26, 26, 26)' },
  'main':        null,
};
const reference = {
  '.hero-title': { 'font-weight': '500', 'color': 'rgb(34, 34, 34)', 'font-size': '32px' },
  '.cta':        { 'background-color': 'rgb(26, 26, 26)' },
  'main':        { 'display': 'grid' },
};

const diff = compareStyles(build, reference, ['.hero-title', '.cta', 'main']);
truthy(
  diff.rows.some((r) => r.selector === '.hero-title' && r.property === 'font-weight'
                        && r.build === '400' && r.reference === '500'),
  'compareStyles names the font-weight drift (400 vs 500)',
);
truthy(
  diff.rows.some((r) => r.selector === '.hero-title' && r.property === 'color'
                        && r.build === 'rgb(26, 26, 26)' && r.reference === 'rgb(34, 34, 34)'),
  'compareStyles names the colour drift as rgb() on both sides',
);
truthy(
  !diff.rows.some((r) => r.selector === '.hero-title' && r.property === 'font-size'),
  'compareStyles emits no row for an identical property (font-size)',
);
truthy(
  !diff.rows.some((r) => r.selector === '.cta'),
  'compareStyles emits no row for a fully-matching selector (.cta)',
);
truthy(
  diff.notes.some((n) => n.includes('main') && n.includes('not found in the build')),
  'compareStyles notes a selector missing on the build side, emits no row for it',
);

const identical = compareStyles(
  { h1: { color: 'rgb(0, 0, 0)' } },
  { h1: { color: 'rgb(0, 0, 0)' } },
  ['h1'],
);
eq(identical.rows, [], 'compareStyles: identical styles → empty diff (parity pass)');

if (fail) {
  console.error('\nparity-compare.mjs pure-logic invariants violated.');
  process.exit(1);
}
console.log('\nAll invariants pass for references/visual-review/parity-compare.mjs.');
