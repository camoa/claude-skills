/**
 * Image baker — renders effects the Slides API cannot express natively
 * (gradients, custom-font display text) into PNG buffers, at scaffold time.
 *
 * The Slides API has no gradient fill and cannot embed custom fonts, so a
 * gradient backdrop or a heading in a non-Google-Fonts brand face must be a
 * raster image placed by URL. Uses `@napi-rs/canvas` (prebuilt native Canvas).
 *
 * Note: shadow baking is intentionally not a separate export — a shadowed
 * element is baked whole as part of its own image when needed; a standalone
 * "shadow image" has no single well-defined meaning.
 */
import { existsSync } from 'node:fs';
import { createCanvas, GlobalFonts } from '@napi-rs/canvas';

export interface GradientSpec {
  /** Pixel dimensions of the baked image. */
  width: number;
  height: number;
  /** Two or more CSS colour stops. Evenly distributed unless `positions` is set. */
  colors: string[];
  direction?: 'horizontal' | 'vertical' | 'diagonal';
  /**
   * Optional stop offsets in `[0,1]`, one per colour, for an uneven gradient
   * (e.g. a colour that holds longer before the next blooms). When omitted the
   * colours are spread evenly. Length must match `colors`.
   */
  positions?: number[];
}

/** Bake a linear-gradient fill into a PNG buffer. */
export function bakeGradient(spec: GradientSpec): Buffer {
  const { width, height, colors, direction = 'vertical', positions } = spec;
  if (width <= 0 || height <= 0) {
    throw new Error('bakeGradient: width and height must be positive');
  }
  if (colors.length < 2) {
    throw new Error('bakeGradient: at least two colour stops are required');
  }
  if (positions && positions.length !== colors.length) {
    throw new Error('bakeGradient: positions length must match colors length');
  }
  const canvas = createCanvas(width, height);
  const ctx = canvas.getContext('2d');
  const [x1, y1, x2, y2] =
    direction === 'horizontal'
      ? [0, 0, width, 0]
      : direction === 'diagonal'
        ? [0, 0, width, height]
        : [0, 0, 0, height];
  const grad = ctx.createLinearGradient(x1, y1, x2, y2);
  colors.forEach((c, i) =>
    grad.addColorStop(positions ? positions[i] : i / (colors.length - 1), c),
  );
  ctx.fillStyle = grad;
  ctx.fillRect(0, 0, width, height);
  return canvas.toBuffer('image/png');
}

export interface DisplayTextSpec {
  text: string;
  /** Family name. If `fontFile` is given it is registered under this name. */
  fontFamily: string;
  fontSizePx: number;
  /** CSS colour for the text. */
  color: string;
  /** Optional path to a `.ttf`/`.otf` to register (custom brand fonts). */
  fontFile?: string;
  /** Transparent padding around the glyphs, in px. */
  padding?: number;
}

/**
 * Bake a single line of display text — in a custom font if `fontFile` is
 * supplied — into a transparent-background PNG sized to the glyphs.
 */
export function bakeDisplayText(spec: DisplayTextSpec): Buffer {
  const { text, fontFamily, fontSizePx, color, fontFile, padding = 0 } = spec;
  if (text === '') {
    throw new Error('bakeDisplayText: text must not be empty');
  }
  if (fontFile) {
    if (!existsSync(fontFile)) {
      throw new Error(`bakeDisplayText: font file not found: "${fontFile}"`);
    }
    GlobalFonts.registerFromPath(fontFile, fontFamily);
  }
  const font = `${fontSizePx}px "${fontFamily}"`;

  // Measure first so the canvas is sized to the text.
  const measure = createCanvas(8, 8).getContext('2d');
  measure.font = font;
  const textWidth = Math.ceil(measure.measureText(text).width);

  const width = textWidth + padding * 2;
  const height = Math.ceil(fontSizePx * 1.4) + padding * 2;
  const canvas = createCanvas(Math.max(width, 1), Math.max(height, 1));
  const ctx = canvas.getContext('2d');
  ctx.font = font;
  ctx.fillStyle = color;
  ctx.textBaseline = 'top';
  ctx.fillText(text, padding, padding);
  return canvas.toBuffer('image/png');
}
