/**
 * VISUAL PARITY SPEC — ai-dev-assistant v4.14.0 (Task D).
 *
 * /setup-visual-parity copies this file VERBATIM (no token substitution) once per
 * registry surface that has a `parity_reference`, to <codePath>/tests/parity/<surface-id>.spec.ts.
 *
 * SECURITY (paper-test remediation A1): this spec contains NO substituted values. The
 * surface id is derived from the spec's own filename — and /setup-visual-parity
 * charset-validates that id (^[a-z0-9][a-z0-9-]*$) before it ever becomes a filename.
 * All untrusted per-surface data (build URL, reference type/uri, compare selectors)
 * lives in tests/parity/parity-surfaces.json and is read as DATA at runtime — it is
 * never concatenated into JavaScript source. An untrusted registry therefore cannot
 * inject code into a generated spec.
 *
 * Because the file is copied verbatim, every <surface-id>.spec.ts is byte-identical;
 * they differ only in filename. Editing one has no effect on the others.
 *
 * DO NOT RENAME THE TEST OR THE FILE
 * ----------------------------------
 * The test is named exactly 'visual parity'; the file stem IS the surface id.
 * parity-compare.mjs derives the viewport from the Playwright project name
 * (parity-chromium-<viewport>) and writes its result to
 * PARITY_RUN_DIR/<surface-id>-<viewport>.parity.json, which visual-parity-gate.sh
 * merges by that exact name. Renaming the file or the test breaks the join. See
 * tests/parity/README.md.
 *
 * Unlike visual regression, parity has NO committed baseline — it compares the build
 * against the EXTERNAL design reference declared in registry.yml / parity-surfaces.json.
 */
import { test } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { basename, dirname, join } from 'node:path';
import { runParityCheck } from './parity-compare.mjs';

const here = fileURLToPath(import.meta.url);
const surfaceId = basename(here).replace(/\.spec\.ts$/, '');
const surfaces = JSON.parse(
  readFileSync(join(dirname(here), 'parity-surfaces.json'), 'utf8'),
);

test.describe(`${surfaceId} visual parity`, () => {
  test('visual parity', async ({ page }, testInfo) => {
    const cfg = surfaces[surfaceId];
    if (!cfg) {
      throw new Error(
        `parity: surface "${surfaceId}" has no entry in parity-surfaces.json — ` +
        `re-run /setup-visual-parity`,
      );
    }
    await runParityCheck(page, testInfo, {
      surfaceId,
      buildUrl: cfg.buildUrl,
      referenceType: cfg.referenceType,
      referenceUri: cfg.referenceUri,
      compareSelectors: cfg.compareSelectors,
    });
  });
});
