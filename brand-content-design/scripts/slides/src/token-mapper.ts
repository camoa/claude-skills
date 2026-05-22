/**
 * Token-to-request mapper — pure functions translating brand design tokens
 * into Google Slides API styling request objects.
 *
 * See architecture.md (slides_token_mapper). No I/O, no SDK calls, no network —
 * every export is a deterministic function. The scaffolder imports this; it
 * passes target `objectId`s and token values, and gets back complete
 * `slides_v1.Schema$Request` objects with precise `fields` masks.
 */
import type { slides_v1 } from 'googleapis';

/** The brand token set — the documented input contract for the renderer. */
export interface BrandTokens {
  colors: {
    /** `#RRGGBB` */
    primary: string;
    background: string;
    /** text on light backgrounds */
    textLight: string;
    /** text on dark backgrounds */
    textDark: string;
    secondary?: string;
    accent?: string;
  };
  typography: {
    headingFont: string;
    bodyFont: string;
    /** Monospace font for code / technical text. Optional. */
    monoFont?: string;
    sizes?: { title?: number; heading?: number; body?: number; caption?: number };
  };
}

/** Typography values for a single text-style mapping. */
export interface Typography {
  fontFamily: string;
  /** points */
  fontSize?: number;
  bold?: boolean;
  /**
   * Font weight 100–900. When set, the request emits `weightedFontFamily`
   * (so e.g. Nunito Black renders at weight 900) instead of plain `fontFamily`.
   */
  weight?: number;
}

/** Paragraph spacing / alignment values for a single paragraph-style mapping. */
export interface Spacing {
  /** line spacing as a percentage — 100 = single */
  lineSpacing?: number;
  /** points */
  spaceAbove?: number;
  /** points */
  spaceBelow?: number;
  alignment?: 'START' | 'CENTER' | 'END' | 'JUSTIFIED';
}

/** An RGB colour in the Slides API's 0–1 float form. */
export interface RgbColor {
  red: number;
  green: number;
  blue: number;
}

const HEX_FULL = /^[0-9a-fA-F]{6}$/;
const HEX_SHORT = /^[0-9a-fA-F]{3}$/;

/**
 * Convert a hex colour (`#RGB` / `#RRGGBB`, with or without the leading `#`)
 * to the Slides API `rgbColor` form — `{red,green,blue}` floats 0–1.
 *
 * @throws {Error} on a malformed hex string — a bad brand token is a real
 *   defect and is surfaced, never silently coerced.
 */
export function hexToRgbColor(hex: string): RgbColor {
  const raw = hex.trim().replace(/^#/, '');
  let full: string;
  if (HEX_FULL.test(raw)) {
    full = raw;
  } else if (HEX_SHORT.test(raw)) {
    full = raw[0] + raw[0] + raw[1] + raw[1] + raw[2] + raw[2];
  } else {
    throw new Error(`Invalid hex colour: "${hex}"`);
  }
  return {
    red: parseInt(full.slice(0, 2), 16) / 255,
    green: parseInt(full.slice(2, 4), 16) / 255,
    blue: parseInt(full.slice(4, 6), 16) / 255,
  };
}

/**
 * Map a hex colour onto a shape's background — an `updateShapeProperties`
 * request with a solid fill.
 */
export function mapShapeFill(
  objectId: string,
  hex: string,
): slides_v1.Schema$Request {
  return {
    updateShapeProperties: {
      objectId,
      shapeProperties: {
        shapeBackgroundFill: {
          solidFill: { color: { rgbColor: hexToRgbColor(hex) } },
        },
      },
      fields: 'shapeBackgroundFill.solidFill.color',
    },
  };
}

/**
 * Map a shape outline — `updateShapeProperties` setting a solid-fill outline of
 * the given hex colour and weight (points). For window frames, rings, borders.
 */
export function mapShapeOutline(
  objectId: string,
  hex: string,
  weightPt: number,
): slides_v1.Schema$Request {
  return {
    updateShapeProperties: {
      objectId,
      shapeProperties: {
        outline: {
          outlineFill: { solidFill: { color: { rgbColor: hexToRgbColor(hex) } } },
          weight: { magnitude: weightPt, unit: 'PT' },
        },
      },
      fields: 'outline.outlineFill.solidFill.color,outline.weight',
    },
  };
}

/**
 * Remove a shape's background fill — `updateShapeProperties` with the fill
 * `NOT_RENDERED`. Pair with `mapShapeOutline` for an outline-only shape.
 */
export function mapShapeNoFill(objectId: string): slides_v1.Schema$Request {
  return {
    updateShapeProperties: {
      objectId,
      shapeProperties: { shapeBackgroundFill: { propertyState: 'NOT_RENDERED' } },
      fields: 'shapeBackgroundFill.propertyState',
    },
  };
}

/**
 * Style a line — `updateLineProperties` with a solid-fill colour and weight
 * (points). Applied to a `createLine` element.
 */
export function mapLineProperties(
  objectId: string,
  hex: string,
  weightPt: number,
): slides_v1.Schema$Request {
  return {
    updateLineProperties: {
      objectId,
      lineProperties: {
        lineFill: { solidFill: { color: { rgbColor: hexToRgbColor(hex) } } },
        weight: { magnitude: weightPt, unit: 'PT' },
      },
      fields: 'lineFill.solidFill.color,weight',
    },
  };
}

/**
 * Map a hex colour onto text — an `updateTextStyle` request setting
 * `foregroundColor`. `textRange` defaults to all text in the element.
 */
export function mapTextColor(
  objectId: string,
  hex: string,
  textRange?: slides_v1.Schema$Range,
): slides_v1.Schema$Request {
  return {
    updateTextStyle: {
      objectId,
      style: { foregroundColor: { opaqueColor: { rgbColor: hexToRgbColor(hex) } } },
      textRange: textRange ?? { type: 'ALL' },
      fields: 'foregroundColor',
    },
  };
}

/**
 * Map a hex colour onto a page background — an `updatePageProperties` request
 * with a solid fill.
 */
export function mapPageBackground(
  pageObjectId: string,
  hex: string,
): slides_v1.Schema$Request {
  return {
    updatePageProperties: {
      objectId: pageObjectId,
      pageProperties: {
        pageBackgroundFill: {
          solidFill: { color: { rgbColor: hexToRgbColor(hex) } },
        },
      },
      fields: 'pageBackgroundFill.solidFill.color',
    },
  };
}

/**
 * Map typography values onto text — an `updateTextStyle` request. The `fields`
 * mask names exactly the properties supplied. When `weight` is given the font
 * is emitted as `weightedFontFamily` (carrying the numeric weight); otherwise
 * as plain `fontFamily`. `fontSize` and `bold` are added only when given.
 * `textRange` defaults to all text.
 */
export function mapTextStyle(
  objectId: string,
  typography: Typography,
  textRange?: slides_v1.Schema$Range,
): slides_v1.Schema$Request {
  const style: slides_v1.Schema$TextStyle = {};
  const fields: string[] = [];
  if (typography.weight !== undefined) {
    style.weightedFontFamily = {
      fontFamily: typography.fontFamily,
      weight: typography.weight,
    };
    fields.push('weightedFontFamily');
  } else {
    style.fontFamily = typography.fontFamily;
    fields.push('fontFamily');
  }
  if (typography.fontSize !== undefined) {
    style.fontSize = { magnitude: typography.fontSize, unit: 'PT' };
    fields.push('fontSize');
  }
  if (typography.bold !== undefined) {
    style.bold = typography.bold;
    fields.push('bold');
  }
  return {
    updateTextStyle: {
      objectId,
      style,
      textRange: textRange ?? { type: 'ALL' },
      fields: fields.join(','),
    },
  };
}

/**
 * Map paragraph spacing / alignment onto text — an `updateParagraphStyle`
 * request. The `fields` mask names exactly the properties supplied. Spacing
 * magnitudes are emitted in points. Throws fail-fast if nothing is supplied —
 * a no-op styling request is a caller bug.
 */
export function mapParagraphStyle(
  objectId: string,
  spacing: Spacing,
  textRange?: slides_v1.Schema$Range,
): slides_v1.Schema$Request {
  const style: slides_v1.Schema$ParagraphStyle = {};
  const fields: string[] = [];
  if (spacing.lineSpacing !== undefined) {
    style.lineSpacing = spacing.lineSpacing;
    fields.push('lineSpacing');
  }
  if (spacing.spaceAbove !== undefined) {
    style.spaceAbove = { magnitude: spacing.spaceAbove, unit: 'PT' };
    fields.push('spaceAbove');
  }
  if (spacing.spaceBelow !== undefined) {
    style.spaceBelow = { magnitude: spacing.spaceBelow, unit: 'PT' };
    fields.push('spaceBelow');
  }
  if (spacing.alignment !== undefined) {
    style.alignment = spacing.alignment;
    fields.push('alignment');
  }
  if (fields.length === 0) {
    throw new Error(
      'mapParagraphStyle: at least one spacing/alignment value is required',
    );
  }
  return {
    updateParagraphStyle: {
      objectId,
      style,
      textRange: textRange ?? { type: 'ALL' },
      fields: fields.join(','),
    },
  };
}
