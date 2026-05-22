#!/usr/bin/env node
/**
 * Example — emit the `scaffoldTemplate` command document for the
 * `community-talk` template, ready to pipe into the Slides CLI.
 *
 *   node examples/render-community-talk.mjs <logo.png> [driveFolder] \
 *     | node dist/cli.js
 *
 * Requires the package to be built (`npm run build`) and the BCD_SLIDES_OAUTH_*
 * (or BCD_SLIDES_SA_KEY_FILE) credentials in the environment. The CLI prints a
 * result envelope; `result.presentationId` is the rendered Google Slides
 * template. See references/slides-api-guide.md for the model.
 */
import { buildCommunityTalkLayout, communityTalkGradient, palceraTokens }
  from '../dist/community-talk-layout.js';

const logoPath = process.argv[2];
if (!logoPath) {
  process.stderr.write('usage: render-community-talk.mjs <logo.png> [driveFolder]\n');
  process.exit(2);
}
const driveFolder = process.argv[3];

const doc = {
  command: 'scaffoldTemplate',
  args: {
    tokens: palceraTokens,
    layoutSpec: buildCommunityTalkLayout(),
    imagePaths: { logo: logoPath },
    gradients: { grad: communityTalkGradient() },
    presentationName: 'community-talk Template',
    ...(driveFolder ? { driveFolderPath: [driveFolder] } : {}),
  },
};
process.stdout.write(JSON.stringify(doc));
