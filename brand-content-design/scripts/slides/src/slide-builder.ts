/**
 * Slide builder — pure: turn one slide type's `LayoutSpec` entry into the
 * ordered `batchUpdate` request array that composes that type-slide.
 *
 * Sequence per element: create (shape/image, positioned via `elementProperties`)
 * → fill / token-mapper styling → `insertText` → text styling. Elements are
 * processed in z-order. No I/O, no SDK calls — the scaffolder applies them.
 *
 * Honours the full `LayoutElement` model: explicit colours, rounded rectangles,
 * ellipses, and per-element font family / size / weight / alignment.
 */
import type { slides_v1 } from 'googleapis';
import type {
  SlideTypeLayout,
  LayoutElement,
  TagInfo,
  FontRole,
} from './layout-spec.js';
import type { BrandTokens } from './token-mapper.js';
import {
  mapShapeFill,
  mapShapeOutline,
  mapShapeNoFill,
  mapLineProperties,
  mapTextColor,
  mapTextStyle,
  mapParagraphStyle,
} from './token-mapper.js';

/** The build product for one type-slide. */
export interface BuiltSlide {
  slideObjectId: string;
  requests: slides_v1.Schema$Request[];
  tags: Record<string, TagInfo>;
}

const UNIT = 'PT';

/** `align` → the Slides paragraph-alignment enum. */
const ALIGNMENT: Record<string, 'START' | 'CENTER' | 'END'> = {
  start: 'START',
  center: 'CENTER',
  end: 'END',
};

function elementProperties(
  pageObjectId: string,
  e: LayoutElement,
): slides_v1.Schema$PageElementProperties {
  return {
    pageObjectId,
    size: {
      width: { magnitude: e.w, unit: UNIT },
      height: { magnitude: e.h, unit: UNIT },
    },
    transform: {
      scaleX: 1,
      scaleY: 1,
      translateX: e.x,
      translateY: e.y,
      unit: UNIT,
    },
  };
}

/** Resolve a brand-token colour role to its hex value. */
function colorFor(tokens: BrandTokens, role: string | undefined): string | undefined {
  if (!role) return undefined;
  return (tokens.colors as Record<string, string | undefined>)[role];
}

/** Resolve a text element's font-family role to a concrete font name. */
function fontFor(tokens: BrandTokens, role: FontRole | undefined): string {
  if (role === 'body') return tokens.typography.bodyFont;
  if (role === 'mono') {
    return tokens.typography.monoFont ?? tokens.typography.bodyFont;
  }
  return tokens.typography.headingFont;
}

/** The Slides `createShape` `shapeType` for a layout element. */
function shapeTypeFor(e: LayoutElement): string {
  if (e.kind === 'text') return 'TEXT_BOX';
  if (e.kind === 'ellipse') return 'ELLIPSE';
  if (e.kind === 'shape' && e.rounded) return 'ROUND_RECTANGLE';
  return 'RECTANGLE';
}

/**
 * Build the request batch for one type-slide.
 *
 * @param layout          the slide type's element layout
 * @param tokens          brand tokens (colours + typography) for styling
 * @param fixedImageUrls  resolved URLs for fixed-image elements, keyed by
 *                        element id (the scaffolder uploads + supplies these)
 */
export function buildSlideRequests(
  layout: SlideTypeLayout,
  tokens: BrandTokens,
  fixedImageUrls: Record<string, string>,
): BuiltSlide {
  const slideObjectId = `slide_${layout.type}`;
  const requests: slides_v1.Schema$Request[] = [
    {
      createSlide: {
        objectId: slideObjectId,
        slideLayoutReference: { predefinedLayout: 'BLANK' },
      },
    },
  ];
  const tags: Record<string, TagInfo> = {};

  const ordered = [...layout.elements].sort((a, b) => a.zOrder - b.zOrder);
  for (const e of ordered) {
    const objectId = `${slideObjectId}_${e.id}`;
    if (objectId.length > 50) {
      throw new Error(
        `buildSlideRequests: generated objectId "${objectId}" exceeds the ` +
          `50-char Slides API limit — shorten the layout element id "${e.id}"`,
      );
    }
    const ep = elementProperties(slideObjectId, e);
    const isTag = !!e.content && 'tag' in e.content;
    const isFixed = !!e.content && 'fixed' in e.content;

    // Fixed image → createImage with the resolved URL.
    if (e.kind === 'image' && isFixed) {
      const url = fixedImageUrls[e.id];
      if (!url) {
        throw new Error(`buildSlideRequests: no resolved image URL for "${e.id}"`);
      }
      requests.push({ createImage: { objectId, url, elementProperties: ep } });
      continue;
    }

    // Line → createLine. The box's top-left→bottom-right diagonal is the line;
    // `lineFromBottomLeft` mirrors the box vertically for a bottom-left→top-right
    // line (arrowheads, rising connectors).
    if (e.kind === 'line') {
      const lineEp: slides_v1.Schema$PageElementProperties = {
        pageObjectId: slideObjectId,
        size: { width: { magnitude: e.w, unit: UNIT }, height: { magnitude: e.h, unit: UNIT } },
        transform: e.lineFromBottomLeft
          ? { scaleX: 1, scaleY: -1, translateX: e.x, translateY: e.y + e.h, unit: UNIT }
          : { scaleX: 1, scaleY: 1, translateX: e.x, translateY: e.y, unit: UNIT },
      };
      requests.push({
        createLine: { objectId, lineCategory: 'STRAIGHT', elementProperties: lineEp },
      });
      const hex = e.color ?? colorFor(tokens, e.styleRole) ?? tokens.colors.primary;
      requests.push(mapLineProperties(objectId, hex, e.outline?.weight ?? 2));
      continue;
    }

    // Everything else (text, shape, ellipse, tagged image placeholder) → a shape.
    requests.push({
      createShape: { objectId, shapeType: shapeTypeFor(e), elementProperties: ep },
    });

    // Shape / ellipse fill + outline — explicit colour wins over a style role.
    if (e.kind === 'shape' || e.kind === 'ellipse') {
      const hex = e.color ?? colorFor(tokens, e.styleRole);
      if (hex) {
        requests.push(mapShapeFill(objectId, hex));
      } else if (e.outline) {
        // Outline-only shape — remove the API's default fill.
        requests.push(mapShapeNoFill(objectId));
      }
      if (e.outline) {
        requests.push(mapShapeOutline(objectId, e.outline.color, e.outline.weight ?? 1));
      }
    }

    // Content text — the tag token, or fixed copy.
    const text =
      e.content && 'tag' in e.content
        ? e.content.tag
        : e.content && 'fixed' in e.content
          ? e.content.fixed
          : undefined;
    if (text) {
      requests.push({ insertText: { objectId, text, insertionIndex: 0 } });
      if (e.kind === 'text') {
        requests.push(
          mapTextStyle(objectId, {
            fontFamily: fontFor(tokens, e.fontFamily),
            fontSize: e.fontSize,
            weight: e.fontWeight,
          }),
        );
        const hex = e.color ?? colorFor(tokens, e.styleRole) ?? tokens.colors.textDark;
        requests.push(mapTextColor(objectId, hex));
        if (e.align) {
          requests.push(mapParagraphStyle(objectId, { alignment: ALIGNMENT[e.align] }));
        }
      }
    }

    if (isTag && e.content && 'tag' in e.content) {
      tags[e.content.tag] = { kind: e.kind === 'image' ? 'image' : 'text' };
    }
  }

  return { slideObjectId, requests, tags };
}
