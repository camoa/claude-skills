/**
 * Integration spike — env-gated, MANUAL, never run in CI.
 *
 * Exercises the real Slides + Drive APIs end to end:
 *   copy template → replaceAllText → replaceAllShapesWithImage → export PDF.
 *
 * Prerequisites:
 *   1. `npm install && npm run build` (this imports the compiled client).
 *   2. Auth env vars set — see README (service account OR OAuth trio).
 *   3. BCD_SLIDES_SPIKE_TEMPLATE_ID — id of a Slides file the credentials
 *      can read. For a faithful run it should contain the text `{{title}}`
 *      and a shape containing `{{image}}`.
 *   4. (optional) BCD_SLIDES_SPIKE_IMAGE_URL — a public image URL.
 *
 * Run:  node spike/run.mjs
 */
import { writeFileSync } from 'node:fs';
import { google } from 'googleapis';
import { resolveAuthConfig, createAuthClient } from '../dist/auth.js';
import { SlidesClient } from '../dist/client.js';

const templateId = process.env.BCD_SLIDES_SPIKE_TEMPLATE_ID;
if (!templateId) {
  console.error(
    'Spike skipped.\n' +
      'Set BCD_SLIDES_SPIKE_TEMPLATE_ID to a Slides file id the credentials can\n' +
      'read, set the auth env vars (see README), then re-run `node spike/run.mjs`.',
  );
  process.exit(0);
}

const auth = createAuthClient(resolveAuthConfig(process.env));
const client = new SlidesClient({
  slides: google.slides({ version: 'v1', auth }),
  drive: google.drive({ version: 'v3', auth }),
});

console.log('1/4  copy template …');
const { fileId } = await client.copyFile(templateId, `slides-api-spike-${Date.now()}`);
console.log(`     copied → ${fileId}`);

console.log('2/4  replaceAllText …');
const text = await client.replaceAllText(fileId, { '{{title}}': 'Spike OK' });
console.log(`     occurrences: ${JSON.stringify(text.occurrencesByTag)}`);

console.log('3/4  replaceAllShapesWithImage …');
const imageUrl = process.env.BCD_SLIDES_SPIKE_IMAGE_URL;
if (imageUrl) {
  const img = await client.replaceAllShapesWithImage(fileId, { '{{image}}': imageUrl });
  console.log(`     occurrences: ${JSON.stringify(img.occurrencesByTag)}`);
} else {
  console.log('     skipped (set BCD_SLIDES_SPIKE_IMAGE_URL to exercise)');
}

console.log('4/4  export PDF …');
const pdf = await client.exportFile(fileId, 'application/pdf');
const outFile = `slides-api-spike-${fileId}.pdf`;
writeFileSync(outFile, pdf);
console.log(`     wrote ${outFile} (${pdf.length} bytes)`);

console.log(`\nSpike complete. Remember to delete the copied file: ${fileId}`);
