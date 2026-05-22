#!/usr/bin/env node
/**
 * Build the `scaffoldTemplate` command for a traced template.
 *
 *   node examples/render-from-trace.mjs <trace.json> <tokens.json> \
 *     "<presentation name>" "<folderSeg1,folderSeg2,...>" \
 *     | node dist/cli.js
 *
 * <trace.json>  — output of tracer/trace-template.py
 * <tokens.json> — a BrandTokens JSON (fonts + colours from brand-philosophy.md)
 * arg 3         — Drive presentation name, convention "<template> Template"
 * arg 4         — optional comma-separated Drive folder path
 *
 * Emits the command document on stdout; pipe it to `dist/cli.js`. See the
 * slides-renderer skill for the full workflow.
 */
import { readFileSync } from 'node:fs';
import { traceToLayoutSpec } from '../dist/trace-to-layout.js';

const [tracePath, tokensPath, name, folderCsv] = process.argv.slice(2);
if (!tracePath || !tokensPath || !name) {
  process.stderr.write(
    'usage: render-from-trace.mjs <trace.json> <tokens.json> "<name>" ["<folder,path>"]\n',
  );
  process.exit(2);
}

const trace = JSON.parse(readFileSync(tracePath, 'utf8'));
const tokens = JSON.parse(readFileSync(tokensPath, 'utf8'));
const { layoutSpec, gradients, imagePaths, skipped } = traceToLayoutSpec(trace);

process.stderr.write(
  `traced → ${layoutSpec.slides.length} slide(s), ` +
    `${Object.keys(gradients).length} gradient(s), ` +
    `${Object.keys(imagePaths).length} image(s); ${skipped.length} op(s) skipped\n`,
);
if (skipped.length) {
  process.stderr.write(`  skipped: ${JSON.stringify(skipped)}\n`);
}

const doc = {
  command: 'scaffoldTemplate',
  args: {
    tokens,
    layoutSpec,
    gradients,
    imagePaths,
    presentationName: name,
    ...(folderCsv ? { driveFolderPath: folderCsv.split(',').map((s) => s.trim()) } : {}),
  },
};
process.stdout.write(JSON.stringify(doc));
