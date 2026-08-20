// mask-coverage-spec.mjs — the mask-coverage measurement, exercised without a
// browser by stubbing the DOM the evaluated function reads.
//
// The union logic is the part worth testing: overlapping masks must not
// double-count, or a surface with two overlapping selectors reports >100% and
// the warning fires on every run until someone turns it off.

import { measureMaskCoverage } from '../references/visual-review/_capture-stability.mjs';

let fails = 0;
const ok = (m) => console.log(`OK   ${m}`);
const bad = (m) => { console.error(`FAIL: ${m}`); fails += 1; };
const near = (a, b, tol = 0.03) => Math.abs(a - b) <= tol;

// A `page` whose evaluate just runs the function, with document/window stubbed.
function fakePage(pageW, pageH, matches) {
  return {
    evaluate: async (fn, arg) => {
      globalThis.document = {
        documentElement: { scrollWidth: pageW, scrollHeight: pageH },
        querySelectorAll: (sel) => {
          if (sel === 'BAD[') throw new Error('invalid selector');
          return (matches[sel] || []).map((r) => ({
            getBoundingClientRect: () => ({ ...r, top: r.y, left: r.x }),
          }));
        },
      };
      globalThis.window = { scrollX: 0, scrollY: 0 };
      try { return await fn(arg); } finally {
        delete globalThis.document; delete globalThis.window;
      }
    },
  };
}

// 1. A quarter of the page.
let r = await measureMaskCoverage(fakePage(1000, 1000, { '.a': [{ x: 0, y: 0, width: 500, height: 500 }] }), ['.a']);
near(r.masked_fraction, 0.25) ? ok('a half-by-half mask reports ~25% of the page')
  : bad(`quarter-page mask reported ${r.masked_fraction}`);

// 2. THE ONE THAT MATTERS: two fully overlapping masks are not 50%.
r = await measureMaskCoverage(fakePage(1000, 1000, {
  '.a': [{ x: 0, y: 0, width: 500, height: 500 }],
  '.b': [{ x: 0, y: 0, width: 500, height: 500 }],
}), ['.a', '.b']);
near(r.masked_fraction, 0.25) ? ok('two identical overlapping masks still report ~25%, not 50%')
  : bad(`overlapping masks double-counted: ${r.masked_fraction}`);

// 3. Nothing masked is zero, not NaN.
r = await measureMaskCoverage(fakePage(800, 600, {}), ['.none']);
r.masked_fraction === 0 ? ok('no matches reports exactly 0')
  : bad(`empty match reported ${r.masked_fraction}`);

// 4. Element counts are reported per selector, which is what names the culprit.
r = await measureMaskCoverage(fakePage(1000, 1000, {
  '.card': [{ x: 0, y: 0, width: 10, height: 10 }, { x: 20, y: 20, width: 10, height: 10 }],
}), ['.card']);
r.per_selector[0].count === 2 ? ok('per-selector element counts are reported')
  : bad(`expected count 2, got ${JSON.stringify(r.per_selector)}`);

// 5. An invalid selector must not throw the capture away.
r = await measureMaskCoverage(fakePage(1000, 1000, {}), ['BAD[']);
r.per_selector[0].count === -1 ? ok('an invalid selector is reported, not thrown')
  : bad(`invalid selector handling: ${JSON.stringify(r.per_selector)}`);

// 6. Zero-area elements contribute nothing.
r = await measureMaskCoverage(fakePage(1000, 1000, { '.h': [{ x: 0, y: 0, width: 0, height: 0 }] }), ['.h']);
r.masked_fraction === 0 ? ok('a zero-area element contributes no coverage')
  : bad(`zero-area element counted: ${r.masked_fraction}`);

// 7. The whole page masked reads as ~100% — the case the warning exists for.
r = await measureMaskCoverage(fakePage(1000, 8000, { '.all': [{ x: 0, y: 0, width: 1000, height: 8000 }] }), ['.all']);
r.masked_fraction > 0.98 ? ok('a mask over the whole page reports ~100%')
  : bad(`full-page mask reported ${r.masked_fraction}`);

console.log('');
if (fails) { console.error('mask-coverage-spec: FAILURES above'); process.exit(1); }
console.log('mask-coverage-spec: all checks passed');
