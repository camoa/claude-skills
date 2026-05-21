/**
 * Font classification — decide whether a brand font is renderable natively in
 * Google Slides (a Google Fonts catalogue family) or is custom and must have
 * its display text baked as an image.
 */
import type { BrandTokens } from './token-mapper.js';
import { GOOGLE_FONTS } from './data/google-fonts.js';

const FAMILY_SET = new Set(GOOGLE_FONTS.map((f) => f.toLowerCase()));

/** A font is either renderable natively in Slides, or custom (must be baked). */
export type FontClass = 'native' | 'custom';

/**
 * True if `family` is in the bundled Google Fonts catalogue snapshot.
 * Case- and surrounding-whitespace-insensitive.
 */
export function isGoogleFont(family: string): boolean {
  return FAMILY_SET.has(family.trim().toLowerCase());
}

/**
 * Classify a brand token set's heading and body fonts independently. A
 * `custom` result means that font's display text is baked as an image
 * (heading) or substituted with the nearest catalogue family (body).
 */
export function classifyFonts(tokens: BrandTokens): {
  heading: FontClass;
  body: FontClass;
} {
  return {
    heading: isGoogleFont(tokens.typography.headingFont) ? 'native' : 'custom',
    body: isGoogleFont(tokens.typography.bodyFont) ? 'native' : 'custom',
  };
}
