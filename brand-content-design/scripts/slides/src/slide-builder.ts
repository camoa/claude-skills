/**
 * Slide builder — pure: turn one slide type's `LayoutSpec` entry into the
 * ordered `batchUpdate` request array that composes that type-slide.
 *
 * Sequence per element: create (shape/image, positioned via `elementProperties`)
 * → token-mapper styling → `insertText`. Elements are processed in z-order.
 * No I/O, no SDK calls — the scaffolder applies the requests.
 */
import type { slides_v1 } from 'googleapis';
import type { SlideTypeLayout, LayoutElement, TagInfo } from './layout-spec.js';
import type { BrandTokens } from './token-mapper.js';
import { mapShapeFill, mapTextColor, mapTextStyle } from './token-mapper.js';

/** The build product for one type-slide. */
export interface BuiltSlide {
  slideObjectId: string;
  requests: slides_v1.Schema$Request[];
  tags: Record<string, TagInfo>;
}

const UNIT = 'PT';

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

function colorFor(tokens: BrandTokens, role: string | undefined): string | undefined {
  if (!role) return undefined;
  return (tokens.colors as Record<string, string | undefined>)[role];
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

    // Everything else (text, shape, tagged image placeholder) → a shape.
    const shapeType = e.kind === 'text' ? 'TEXT_BOX' : 'RECTANGLE';
    requests.push({ createShape: { objectId, shapeType, elementProperties: ep } });

    // Shape fill from the element's style role.
    if (e.kind === 'shape') {
      const hex = colorFor(tokens, e.styleRole);
      if (hex) requests.push(mapShapeFill(objectId, hex));
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
        requests.push(mapTextStyle(objectId, { fontFamily: tokens.typography.headingFont }));
        const hex = colorFor(tokens, e.styleRole) ?? tokens.colors.textDark;
        requests.push(mapTextColor(objectId, hex));
      }
    }

    if (isTag && e.content && 'tag' in e.content) {
      tags[e.content.tag] = { kind: e.kind === 'image' ? 'image' : 'text' };
    }
  }

  return { slideObjectId, requests, tags };
}
