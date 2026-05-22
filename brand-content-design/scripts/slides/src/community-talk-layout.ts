/**
 * community-talk template — a **worked-example** `LayoutSpec`.
 *
 * This is NOT how templates are normally turned into Slides decks. The generic
 * mechanism is the `slides-renderer` skill, which *composes* a `LayoutSpec` from
 * any template's `canvas-philosophy.md` + `template.md` — exactly as
 * `visual-content` composes a PDF. This file is one such composition captured in
 * code: the `community-talk` template (13 typed slides, Pitch-Velocity, Palcera)
 * translated from its `generate_sample.py` design source.
 *
 * It is kept for two reasons: (1) a reference the `slides-renderer` skill points
 * at to show the target schema + quality, and (2) a tested fixture proving the
 * extended renderer carries a faithful design — per-element font size / weight /
 * colour, rounded cards, number-badge circles, a mono code font, gradients.
 * Geometry is converted from the script's 1920×1080 bottom-left reportlab space
 * into the renderer's 720×405 top-left point space by the helpers below.
 */
import type { LayoutSpec, SlideTypeLayout, LayoutElement } from './layout-spec.js';
import type { GradientSpec } from './image-baker.js';
import type { BrandTokens } from './token-mapper.js';

/* ---- brand palette (matches generate_sample.py) ---- */
const NAVY = '#194582';
const NAVY_DEEP = '#081E41';
const CYAN = '#00F3FF';
const SEA = '#00FFBE';
const CHARCOAL = '#1E1E1E';
const WHITE = '#FFFFFF';
const PALE = '#BDE6FF';
const INK = '#081E41';
const CODE_BAR = '#2A2A2A';
const CODE_FG = '#E6E6E6';

/* ---- coordinate conversion: 1920×1080 reportlab → 720×405 top-left ---- */
const SCALE = 720 / 1920; // 0.375
const SRC_H = 1080;
/** Aspect ratio of the Palcera logo asset (source is 2024×1024 px). */
const LOGO_ASPECT = 2024 / 1024;

interface TxtOpts {
  id: string;
  x: number; // source x (left)
  base: number; // source baseline y (from bottom)
  size: number; // source font size
  w: number; // source box width
  color: string;
  weight: number;
  family?: 'heading' | 'body' | 'mono';
  tag?: string;
  fixed?: string;
  lines?: number; // box height = size * 1.4 * lines
  z?: number;
  align?: 'start' | 'center' | 'end';
}

/** A text element authored in source coordinates. */
function txt(o: TxtOpts): LayoutElement {
  const lines = o.lines ?? 1;
  return {
    id: o.id,
    kind: 'text',
    x: o.x * SCALE,
    y: (SRC_H - o.base - o.size) * SCALE,
    w: o.w * SCALE,
    h: o.size * 1.4 * lines * SCALE,
    zOrder: o.z ?? 5,
    color: o.color,
    fontSize: o.size * SCALE,
    fontWeight: o.weight,
    fontFamily: o.family ?? 'heading',
    align: o.align,
    content: o.tag ? { tag: o.tag } : { fixed: o.fixed ?? '' },
  };
}

interface RectOpts {
  id: string;
  x: number;
  bottom: number; // source y of the bottom edge
  w: number;
  h: number;
  color: string;
  rounded?: boolean;
  z?: number;
}

/** A rectangle (optionally rounded) authored in source coordinates. */
function rect(o: RectOpts): LayoutElement {
  return {
    id: o.id,
    kind: 'shape',
    x: o.x * SCALE,
    y: (SRC_H - o.bottom - o.h) * SCALE,
    w: o.w * SCALE,
    h: o.h * SCALE,
    zOrder: o.z ?? 1,
    color: o.color,
    rounded: o.rounded,
  };
}

/** A circle (ellipse) authored by centre + radius in source coordinates. */
function circ(o: { id: string; cx: number; cy: number; r: number; color: string; z?: number }): LayoutElement {
  return {
    id: o.id,
    kind: 'ellipse',
    x: (o.cx - o.r) * SCALE,
    y: (SRC_H - o.cy - o.r) * SCALE,
    w: o.r * 2 * SCALE,
    h: o.r * 2 * SCALE,
    zOrder: o.z ?? 3,
    color: o.color,
  };
}

/** The Pitch-Velocity double accent dash — cyan bar + sea-green bar. */
function bars(prefix: string, x: number, bottom: number): LayoutElement[] {
  return [
    rect({ id: `${prefix}a`, x, bottom, w: 120, h: 13, color: CYAN, z: 2 }),
    rect({ id: `${prefix}b`, x: x + 138, bottom, w: 54, h: 13, color: SEA, z: 2 }),
  ];
}

/** Full-bleed solid background. */
function solidBg(color: string): LayoutElement {
  return { id: 'bg', kind: 'shape', x: 0, y: 0, w: 720, h: 405, zOrder: 0, color };
}

/** Full-bleed baked-gradient background (resolved via ScaffoldAssets.gradients). */
function gradientBg(): LayoutElement {
  return { id: 'grad', kind: 'image', x: 0, y: 0, w: 720, h: 405, zOrder: 0, content: { fixed: 'gradient' } };
}

/** A tagged image placeholder authored in source coordinates (bottom-edge y). */
function imgBox(o: { id: string; x: number; bottom: number; w: number; h: number; tag: string; z?: number }): LayoutElement {
  return {
    id: o.id,
    kind: 'image',
    x: o.x * SCALE,
    y: (SRC_H - o.bottom - o.h) * SCALE,
    w: o.w * SCALE,
    h: o.h * SCALE,
    zOrder: o.z ?? 2,
    content: { tag: o.tag },
  };
}

/** Brand logo, bottom-right (fixed image — resolved via ScaffoldAssets.images). */
function logo(srcX = 1690, srcBottom = 58, srcW = 150): LayoutElement {
  const h = srcW / LOGO_ASPECT;
  return {
    id: 'logo',
    kind: 'image',
    x: srcX * SCALE,
    y: (SRC_H - srcBottom - h) * SCALE,
    w: srcW * SCALE,
    h: h * SCALE,
    zOrder: 9,
    content: { fixed: 'logo' },
  };
}

/* ---- the 13 typed slides ---- */

const HEAD = 930; // headline baseline (reportlab HEIGHT-150)

/** Title — gradient, two-tone hero headline, speaker + event. */
const TITLE: SlideTypeLayout = {
  type: 'Title',
  elements: [
    gradientBg(),
    txt({ id: 'title', x: 130, base: 690, size: 138, w: 1500, color: WHITE, weight: 900, tag: '{{title}}', lines: 2 }),
    ...bars('bar', 138, 470),
    txt({ id: 'sub', x: 138, base: 390, size: 34, w: 1400, color: PALE, weight: 500, family: 'body', tag: '{{subtitle}}' }),
    txt({ id: 'spk', x: 138, base: 200, size: 30, w: 1400, color: WHITE, weight: 700, tag: '{{speaker}}' }),
    txt({ id: 'evt', x: 138, base: 156, size: 24, w: 1500, color: PALE, weight: 300, family: 'body', tag: '{{event}}' }),
    logo(),
  ],
};

/** Agenda / Roadmap — numbered list stepping down-right. */
const AGENDA: SlideTypeLayout = {
  type: 'Agenda',
  elements: [
    solidBg(WHITE),
    txt({ id: 'title', x: 130, base: HEAD, size: 78, w: 1400, color: NAVY, weight: 900, tag: '{{title}}' }),
    ...bars('bar', 130, 858),
    ...[0, 1, 2, 3].flatMap((i) => {
      const x = 150 + i * 70;
      const y = 680 - i * 138;
      const n = ['01', '02', '03', '04'][i];
      return [
        txt({ id: `n${i}`, x, base: y, size: 52, w: 110, color: CYAN, weight: 900, fixed: n }),
        txt({ id: `t${i}`, x: x + 130, base: y + 4, size: 40, w: 1300, color: NAVY, weight: 800, tag: `{{item${i + 1}}}` }),
      ];
    }),
    logo(),
  ],
};

/** Section Divider — huge cyan number, section title, gradient. */
const SECTION: SlideTypeLayout = {
  type: 'Section',
  elements: [
    gradientBg(),
    // Wide box: a huge-display tag must not wrap; real content ("01") is short
    // and left-aligned, so the box extending past the page edge is harmless.
    txt({ id: 'num', x: 150, base: 500, size: 320, w: 2200, color: CYAN, weight: 900, tag: '{{number}}' }),
    txt({ id: 'title', x: 162, base: 390, size: 76, w: 1500, color: WHITE, weight: 900, tag: '{{title}}' }),
    ...bars('bar', 170, 330),
    logo(),
  ],
};

/** Single-Column Content — headline + up to 4 cyan-marker bullets. */
const CONTENT: SlideTypeLayout = {
  type: 'Content',
  elements: [
    solidBg(WHITE),
    txt({ id: 'title', x: 130, base: HEAD, size: 72, w: 1400, color: NAVY, weight: 900, tag: '{{title}}' }),
    ...bars('bar', 130, 858),
    ...[0, 1, 2, 3].flatMap((i) => {
      const y = 758 - i * 104;
      return [
        rect({ id: `m${i}`, x: 150, bottom: y, w: 26, h: 26, color: CYAN, z: 2 }),
        txt({ id: `b${i}`, x: 210, base: y, size: 34, w: 1500, color: INK, weight: 600, tag: `{{bullet${i + 1}}}` }),
      ];
    }),
    logo(),
  ],
};

/** Two-Column — two bold rounded cards, asymmetric. */
function column(prefix: string, x: number, y: number, fill: string, txtc: string, headTag: string, lineTags: string[]): LayoutElement[] {
  const els: LayoutElement[] = [
    rect({ id: `${prefix}c`, x, bottom: y, w: 760, h: 470, color: fill, rounded: true, z: 1 }),
    txt({ id: `${prefix}h`, x: x + 50, base: y + 470 - 90, size: 48, w: 660, color: txtc, weight: 900, tag: headTag, z: 5 }),
  ];
  lineTags.forEach((tag, i) => {
    els.push(txt({ id: `${prefix}l${i}`, x: x + 50, base: y + 470 - 180 - i * 62, size: 27, w: 660, color: txtc, weight: 500, family: 'body', tag, z: 5 }));
  });
  return els;
}

const TWO_COLUMN: SlideTypeLayout = {
  type: 'TwoColumn',
  elements: [
    solidBg(WHITE),
    txt({ id: 'title', x: 130, base: HEAD, size: 68, w: 1500, color: NAVY, weight: 900, tag: '{{title}}' }),
    ...bars('bar', 130, 858),
    ...column('A', 150, 250, NAVY, WHITE, '{{colA_head}}', ['{{colA_1}}', '{{colA_2}}', '{{colA_3}}']),
    ...column('B', 1010, 200, CYAN, INK, '{{colB_head}}', ['{{colB_1}}', '{{colB_2}}', '{{colB_3}}']),
    logo(),
  ],
};

/** Three-Column — three bold cards with number badges, stepping diagonally. */
const THREE_COLUMN: SlideTypeLayout = {
  type: 'ThreeColumn',
  elements: [
    solidBg(WHITE),
    txt({ id: 'title', x: 130, base: HEAD, size: 68, w: 1500, color: NAVY, weight: 900, tag: '{{title}}' }),
    ...bars('bar', 130, 858),
    ...[
      { x: 150, y: 250, fill: NAVY, fg: WHITE, badge: WHITE, bf: NAVY },
      { x: 760, y: 200, fill: CYAN, fg: INK, badge: NAVY, bf: WHITE },
      { x: 1370, y: 150, fill: SEA, fg: INK, badge: NAVY, bf: WHITE },
    ].flatMap((col, i) => [
      rect({ id: `c${i}`, x: col.x, bottom: col.y, w: 470, h: 430, color: col.fill, rounded: true, z: 1 }),
      circ({ id: `b${i}`, cx: col.x + 78, cy: col.y + 342, r: 44, color: col.badge, z: 3 }),
      txt({ id: `n${i}`, x: col.x + 30, base: col.y + 304, size: 44, w: 96, color: col.bf, weight: 900, fixed: String(i + 1), align: 'center', z: 5 }),
      txt({ id: `l${i}`, x: col.x + 48, base: col.y + 220, size: 42, w: 380, color: col.fg, weight: 900, tag: `{{col${i + 1}_label}}`, z: 5 }),
      txt({ id: `p${i}`, x: col.x + 48, base: col.y + 160, size: 25, w: 380, color: col.fg, weight: 500, family: 'body', tag: `{{col${i + 1}_line}}`, lines: 2, z: 5 }),
    ]),
    logo(),
  ],
};

/** Code / Technical — charcoal, filename caption, mono code block. */
const CODE: SlideTypeLayout = {
  type: 'Code',
  elements: [
    solidBg(CHARCOAL),
    rect({ id: 'topbar', x: 0, bottom: 1016, w: 1920, h: 64, color: CODE_BAR, z: 1 }),
    txt({ id: 'file', x: 130, base: 1036, size: 20, w: 1600, color: '#9AA0A6', weight: 400, family: 'mono', tag: '{{filename}}', z: 5 }),
    txt({ id: 'code', x: 130, base: 910, size: 30, w: 1660, color: CODE_FG, weight: 400, family: 'mono', tag: '{{code}}', lines: 9, z: 5 }),
    logo(),
  ],
};

/** Data / Insight — navy, two-line headline, hero number, caption. */
const DATA: SlideTypeLayout = {
  type: 'Data',
  elements: [
    solidBg(NAVY_DEEP),
    txt({ id: 'head', x: 130, base: 850, size: 56, w: 1100, color: WHITE, weight: 800, tag: '{{headline}}', lines: 2 }),
    ...bars('bar', 138, 730),
    // Wide box — see Section `num`: the 460pt hero number must never wrap.
    txt({ id: 'stat', x: 820, base: 360, size: 460, w: 2100, color: CYAN, weight: 900, tag: '{{stat}}' }),
    txt({ id: 'cap', x: 138, base: 220, size: 30, w: 1400, color: PALE, weight: 300, family: 'body', tag: '{{caption}}' }),
    logo(),
  ],
};

/** Image / Visual — split: text left, image panel right. */
const IMAGE: SlideTypeLayout = {
  type: 'Image',
  elements: [
    solidBg(NAVY_DEEP),
    txt({ id: 'head', x: 130, base: 760, size: 96, w: 700, color: WHITE, weight: 900, tag: '{{headline}}', lines: 2 }),
    ...bars('bar', 138, 590),
    txt({ id: 'cap', x: 138, base: 500, size: 28, w: 600, color: PALE, weight: 300, family: 'body', tag: '{{caption}}', lines: 3 }),
    rect({ id: 'panel', x: 820, bottom: 150, w: 950, h: 780, color: NAVY, rounded: true, z: 1 }),
    imgBox({ id: 'img', x: 820, bottom: 150, w: 950, h: 780, tag: '{{image}}', z: 2 }),
    logo(),
  ],
};

/** Quote / Insight — navy, big cyan quote mark, quote + attribution. */
const QUOTE: SlideTypeLayout = {
  type: 'Quote',
  elements: [
    solidBg(NAVY),
    txt({ id: 'mark', x: 150, base: 720, size: 300, w: 400, color: CYAN, weight: 900, fixed: '"' }),
    txt({ id: 'quote', x: 170, base: 630, size: 58, w: 1500, color: WHITE, weight: 800, tag: '{{quote}}', lines: 4 }),
    txt({ id: 'attr', x: 172, base: 320, size: 26, w: 1400, color: PALE, weight: 300, family: 'body', tag: '{{attribution}}' }),
    logo(),
  ],
};

/** Demo Placeholder — navy, terminal motif, big "LIVE DEMO". */
const DEMO: SlideTypeLayout = {
  type: 'Demo',
  elements: [
    solidBg(NAVY_DEEP),
    rect({ id: 'term', x: 1140, bottom: 610, w: 480, h: 320, color: NAVY, rounded: true, z: 1 }),
    rect({ id: 'termbar', x: 1140, bottom: 878, w: 480, h: 52, color: CYAN, z: 2 }),
    rect({ id: 'cursor', x: 1180, bottom: 760, w: 20, h: 40, color: WHITE, z: 2 }),
    txt({ id: 'live', x: 130, base: 600, size: 200, w: 900, color: WHITE, weight: 900, fixed: 'LIVE', z: 5 }),
    txt({ id: 'demo', x: 130, base: 390, size: 200, w: 900, color: CYAN, weight: 900, fixed: 'DEMO', z: 5 }),
    ...bars('bar', 140, 320),
    txt({ id: 'cap', x: 140, base: 230, size: 30, w: 1400, color: PALE, weight: 300, family: 'body', tag: '{{caption}}' }),
    logo(),
  ],
};

/** Key Takeaways — white, numbered list. */
const TAKEAWAYS: SlideTypeLayout = {
  type: 'Takeaways',
  elements: [
    solidBg(WHITE),
    txt({ id: 'title', x: 130, base: HEAD, size: 78, w: 1400, color: NAVY, weight: 900, tag: '{{title}}' }),
    ...bars('bar', 130, 858),
    ...[0, 1, 2].flatMap((i) => {
      const y = 680 - i * 150;
      return [
        txt({ id: `n${i}`, x: 150, base: y, size: 56, w: 120, color: CYAN, weight: 900, fixed: ['01', '02', '03'][i] }),
        txt({ id: `t${i}`, x: 290, base: y + 6, size: 34, w: 1360, color: INK, weight: 600, tag: `{{take${i + 1}}}`, lines: 2 }),
      ];
    }),
    logo(),
  ],
};

/** CTA / Closing — gradient, closing headline, contact. */
const CTA: SlideTypeLayout = {
  type: 'CTA',
  elements: [
    gradientBg(),
    txt({ id: 'head', x: 130, base: 710, size: 130, w: 1500, color: WHITE, weight: 900, tag: '{{headline}}', lines: 2 }),
    ...bars('bar', 138, 510),
    txt({ id: 'contact', x: 138, base: 410, size: 30, w: 1500, color: WHITE, weight: 700, tag: '{{contact}}' }),
    txt({ id: 'url', x: 138, base: 355, size: 26, w: 1400, color: PALE, weight: 300, family: 'body', tag: '{{url}}' }),
    logo(1620, 70, 210),
  ],
};

/** The diagonal 3-stop brand gradient used by Title, Section, and CTA. */
export function communityTalkGradient(): GradientSpec {
  return {
    width: 1920,
    height: 1080,
    colors: [NAVY_DEEP, NAVY, CYAN],
    direction: 'diagonal',
    positions: [0, 0.62, 1],
  };
}

/** Palcera brand tokens for the community-talk template. */
export const palceraTokens: BrandTokens = {
  colors: {
    primary: NAVY,
    background: WHITE,
    textLight: INK, // text on light backgrounds
    textDark: WHITE, // text on dark backgrounds
    secondary: CYAN,
    accent: SEA,
  },
  typography: {
    headingFont: 'Nunito',
    bodyFont: 'Inter',
    monoFont: 'JetBrains Mono',
  },
};

/** Build the full 13-type community-talk `LayoutSpec`. */
export function buildCommunityTalkLayout(): LayoutSpec {
  return {
    pageWidth: 720,
    pageHeight: 405,
    slides: [
      TITLE,
      AGENDA,
      SECTION,
      CONTENT,
      TWO_COLUMN,
      THREE_COLUMN,
      CODE,
      DATA,
      IMAGE,
      QUOTE,
      DEMO,
      TAKEAWAYS,
      CTA,
    ],
  };
}
