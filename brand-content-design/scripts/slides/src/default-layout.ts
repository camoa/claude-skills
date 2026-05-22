/**
 * Default layout spec — the Slides-side layout IR.
 *
 * `buildDefaultLayout` produces a `LayoutSpec` with sensible 16:9 geometry for
 * all seven slide types, so the scaffolder is usable without hand-authored
 * geometry. This is the integration child's resolution of the epic's open
 * "shared layout IR" question: there is one IR on the Slides side; PDF↔Slides
 * parity is enforced by the visual-diff gate, not by a runtime-shared object.
 * See research.md Q5.
 */
import type { LayoutSpec, LayoutElement, SlideTypeLayout } from './layout-spec.js';

/** Slide dimensions in points — 16:9, the API default (10in × 5.625in). */
const PAGE_W = 720;
const PAGE_H = 405;

/** A full-bleed background shape — paint order 0, behind everything. */
function background(styleRole = 'background'): LayoutElement {
  return { id: 'bg', kind: 'shape', x: 0, y: 0, w: PAGE_W, h: PAGE_H, zOrder: 0, styleRole };
}

/** A tagged text element. */
function text(
  id: string,
  tag: string,
  box: { x: number; y: number; w: number; h: number },
  styleRole: string,
): LayoutElement {
  return { id, kind: 'text', ...box, zOrder: 2, styleRole, content: { tag } };
}

/** A tagged image element. */
function image(
  id: string,
  tag: string,
  box: { x: number; y: number; w: number; h: number },
): LayoutElement {
  return { id, kind: 'image', ...box, zOrder: 1, content: { tag } };
}

/** The seven typed layouts. */
const SLIDES: SlideTypeLayout[] = [
  {
    type: 'Title',
    elements: [
      background(),
      { id: 'accent', kind: 'shape', x: 60, y: 150, w: 80, h: 8, zOrder: 1, styleRole: 'accent' },
      image('logo', '{{logo}}', { x: 60, y: 40, w: 120, h: 40 }),
      text('title', '{{title}}', { x: 60, y: 170, w: 600, h: 80 }, 'textLight'),
      text('subtitle', '{{subtitle}}', { x: 60, y: 260, w: 600, h: 40 }, 'textLight'),
    ],
  },
  {
    type: 'Content',
    elements: [
      background(),
      text('title', '{{title}}', { x: 60, y: 50, w: 600, h: 60 }, 'textLight'),
      text('body', '{{body}}', { x: 60, y: 130, w: 600, h: 220 }, 'textLight'),
    ],
  },
  {
    type: 'Image',
    elements: [
      background(),
      image('image', '{{image}}', { x: 0, y: 0, w: PAGE_W, h: 300 }),
      text('caption', '{{caption}}', { x: 60, y: 320, w: 600, h: 50 }, 'textLight'),
    ],
  },
  {
    type: 'Data',
    elements: [
      background(),
      text('title', '{{title}}', { x: 60, y: 40, w: 600, h: 50 }, 'textLight'),
      image('chart', '{{chart}}', { x: 60, y: 100, w: 400, h: 260 }),
      text('insight', '{{insight}}', { x: 490, y: 100, w: 180, h: 260 }, 'textLight'),
    ],
  },
  {
    type: 'Quote',
    elements: [
      background(),
      text('quote', '{{quote}}', { x: 90, y: 120, w: 540, h: 140 }, 'textLight'),
      text('attribution', '{{attribution}}', { x: 90, y: 270, w: 540, h: 40 }, 'textLight'),
    ],
  },
  {
    type: 'CTA',
    elements: [
      background('primary'),
      text('headline', '{{headline}}', { x: 60, y: 140, w: 600, h: 80 }, 'textDark'),
      text('action', '{{action}}', { x: 60, y: 230, w: 600, h: 50 }, 'textDark'),
    ],
  },
  {
    type: 'Transition',
    elements: [
      background('primary'),
      text('section', '{{section}}', { x: 60, y: 170, w: 600, h: 80 }, 'textDark'),
    ],
  },
];

/**
 * Build the default layout spec — all seven slide types, 16:9. Every text and
 * image element is a merge placeholder; the scaffolder records its tag token.
 */
export function buildDefaultLayout(): LayoutSpec {
  return { pageWidth: PAGE_W, pageHeight: PAGE_H, slides: SLIDES };
}
