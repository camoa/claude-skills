import { describe, it, expect } from 'vitest';
import { buildSlideRequests } from '../src/slide-builder.js';
import type { SlideTypeLayout } from '../src/layout-spec.js';
import type { BrandTokens } from '../src/token-mapper.js';

const tokens: BrandTokens = {
  colors: {
    primary: '#2266FF',
    background: '#FFFFFF',
    textLight: '#111111',
    textDark: '#EEEEEE',
  },
  typography: { headingFont: 'Inter', bodyFont: 'Lora' },
};

const monoTokens: BrandTokens = {
  ...tokens,
  typography: { ...tokens.typography, monoFont: 'JetBrains Mono' },
};

const titleLayout: SlideTypeLayout = {
  type: 'Title',
  elements: [
    { id: 'accent', kind: 'shape', x: 0, y: 0, w: 720, h: 12, zOrder: 0, styleRole: 'primary' },
    {
      id: 'title',
      kind: 'text',
      x: 60,
      y: 150,
      w: 600,
      h: 100,
      zOrder: 2,
      styleRole: 'textLight',
      content: { tag: '{{title}}' },
    },
    { id: 'logo', kind: 'image', x: 620, y: 360, w: 80, h: 30, zOrder: 1, content: { fixed: 'logo' } },
  ],
};

describe('buildSlideRequests', () => {
  it('starts with a createSlide carrying a deterministic objectId', () => {
    const built = buildSlideRequests(titleLayout, tokens, { logo: 'https://img/logo.png' });
    expect(built.slideObjectId).toBe('slide_Title');
    expect(built.requests[0]).toEqual({
      createSlide: {
        objectId: 'slide_Title',
        slideLayoutReference: { predefinedLayout: 'BLANK' },
      },
    });
  });

  it('processes elements in z-order and creates one element per layout entry', () => {
    const built = buildSlideRequests(titleLayout, tokens, { logo: 'https://img/logo.png' });
    const created = built.requests.filter((r) => r.createShape || r.createImage);
    expect(created).toHaveLength(3);
    // z-order: accent(0) shape → logo(1) image → title(2) text box
    expect(created[0].createShape?.shapeType).toBe('RECTANGLE');
    expect(created[1].createImage).toBeDefined();
    expect(created[2].createShape?.shapeType).toBe('TEXT_BOX');
  });

  it('positions each element from the layout geometry (points)', () => {
    const built = buildSlideRequests(titleLayout, tokens, { logo: 'https://img/logo.png' });
    const accent = built.requests[1].createShape;
    expect(accent?.elementProperties?.size).toEqual({
      width: { magnitude: 720, unit: 'PT' },
      height: { magnitude: 12, unit: 'PT' },
    });
    expect(accent?.elementProperties?.transform).toEqual({
      scaleX: 1,
      scaleY: 1,
      translateX: 0,
      translateY: 0,
      unit: 'PT',
    });
  });

  it('creates a fixed image via createImage with the resolved URL', () => {
    const built = buildSlideRequests(titleLayout, tokens, { logo: 'https://img/logo.png' });
    const img = built.requests.find((r) => r.createImage)?.createImage;
    expect(img?.url).toBe('https://img/logo.png');
  });

  it('inserts the tag token text into a tagged text element and records the tag map', () => {
    const built = buildSlideRequests(titleLayout, tokens, { logo: 'https://img/logo.png' });
    const insert = built.requests.find((r) => r.insertText)?.insertText;
    expect(insert?.text).toBe('{{title}}');
    expect(built.tags).toEqual({ '{{title}}': { kind: 'text' } });
  });

  it('throws when a fixed image has no resolved URL', () => {
    expect(() => buildSlideRequests(titleLayout, tokens, {})).toThrow(/logo/);
  });

  it('emits insertText before updateTextStyle for a text element', () => {
    const built = buildSlideRequests(titleLayout, tokens, { logo: 'https://img/logo.png' });
    const insertIdx = built.requests.findIndex((r) => r.insertText);
    const styleIdx = built.requests.findIndex((r) => r.updateTextStyle);
    expect(insertIdx).toBeGreaterThanOrEqual(0);
    expect(styleIdx).toBeGreaterThan(insertIdx);
  });

  it('makes a tagged image element a RECTANGLE placeholder, not a createImage', () => {
    const imageLayout: SlideTypeLayout = {
      type: 'Image',
      elements: [
        {
          id: 'img',
          kind: 'image',
          x: 0,
          y: 0,
          w: 720,
          h: 405,
          zOrder: 0,
          content: { tag: '{{image}}' },
        },
      ],
    };
    const built = buildSlideRequests(imageLayout, tokens, {});
    expect(built.requests.some((r) => r.createImage)).toBe(false);
    expect(built.requests[1].createShape?.shapeType).toBe('RECTANGLE');
    expect(built.requests.find((r) => r.insertText)?.insertText?.text).toBe('{{image}}');
    expect(built.tags).toEqual({ '{{image}}': { kind: 'image' } });
  });

  it('builds an `ellipse` element as an ELLIPSE shape with its fill', () => {
    const layout: SlideTypeLayout = {
      type: 'X',
      elements: [{ id: 'badge', kind: 'ellipse', x: 10, y: 10, w: 40, h: 40, zOrder: 0, color: '#00F3FF' }],
    };
    const built = buildSlideRequests(layout, tokens, {});
    expect(built.requests[1].createShape?.shapeType).toBe('ELLIPSE');
    expect(built.requests.some((r) => r.updateShapeProperties)).toBe(true);
  });

  it('builds a `rounded` shape as a ROUND_RECTANGLE', () => {
    const layout: SlideTypeLayout = {
      type: 'X',
      elements: [{ id: 'card', kind: 'shape', x: 0, y: 0, w: 100, h: 80, zOrder: 0, color: '#194582', rounded: true }],
    };
    const built = buildSlideRequests(layout, tokens, {});
    expect(built.requests[1].createShape?.shapeType).toBe('ROUND_RECTANGLE');
  });

  it('uses an explicit element colour over its style role for a shape fill', () => {
    const layout: SlideTypeLayout = {
      type: 'X',
      elements: [{ id: 's', kind: 'shape', x: 0, y: 0, w: 10, h: 10, zOrder: 0, styleRole: 'primary', color: '#00FFBE' }],
    };
    const built = buildSlideRequests(layout, tokens, {});
    const fill = built.requests.find((r) => r.updateShapeProperties)?.updateShapeProperties;
    expect(fill?.shapeProperties?.shapeBackgroundFill?.solidFill?.color?.rgbColor).toEqual({
      red: 0,
      green: 1,
      blue: 190 / 255,
    });
  });

  it('applies per-element font size, weight, family and alignment to text', () => {
    const layout: SlideTypeLayout = {
      type: 'X',
      elements: [
        {
          id: 'h',
          kind: 'text',
          x: 0,
          y: 0,
          w: 400,
          h: 60,
          zOrder: 0,
          content: { fixed: 'Hi' },
          fontSize: 52,
          fontWeight: 900,
          fontFamily: 'mono',
          align: 'center',
          color: '#194582',
        },
      ],
    };
    const built = buildSlideRequests(layout, monoTokens, {});
    const style = built.requests.find((r) => r.updateTextStyle?.style?.weightedFontFamily)?.updateTextStyle;
    expect(style?.style?.weightedFontFamily).toEqual({ fontFamily: 'JetBrains Mono', weight: 900 });
    expect(style?.style?.fontSize).toEqual({ magnitude: 52, unit: 'PT' });
    expect(built.requests.some((r) => r.updateParagraphStyle?.style?.alignment === 'CENTER')).toBe(true);
  });

  it('falls back to the body font when a `mono` element has no monoFont token', () => {
    const layout: SlideTypeLayout = {
      type: 'X',
      elements: [
        { id: 'c', kind: 'text', x: 0, y: 0, w: 200, h: 30, zOrder: 0, content: { fixed: 'x' }, fontFamily: 'mono', fontWeight: 400 },
      ],
    };
    // `tokens` has no monoFont — `fontFor` must fall back to the body font.
    const built = buildSlideRequests(layout, tokens, {});
    const style = built.requests.find((r) => r.updateTextStyle?.style?.weightedFontFamily)?.updateTextStyle;
    expect(style?.style?.weightedFontFamily?.fontFamily).toBe('Lora');
  });

  it('inserts the sample text and records field→objectId for a {field,sample} element', () => {
    const layout: SlideTypeLayout = {
      type: 'cover',
      elements: [
        { id: 'bg', kind: 'shape', x: 0, y: 0, w: 720, h: 405, zOrder: 0, color: '#101010' },
        {
          id: 'hdln',
          kind: 'text',
          x: 60, y: 80, w: 600, h: 90,
          zOrder: 1,
          color: '#FFFFFF',
          fontSize: 48, fontWeight: 900, fontFamily: 'heading',
          align: 'start',
          content: { field: 'headline', sample: 'Meet field_pulse' },
        },
      ],
    };
    const built = buildSlideRequests(layout, tokens, {});
    // The type-slide displays the SAMPLE text, not a {{token}}.
    const insert = built.requests.find((r) => r.insertText)?.insertText;
    expect(insert?.text).toBe('Meet field_pulse');
    // The tag map records field→objectId so the merge engine can target the
    // placed element by id (not by token-text match).
    expect(built.tags).toEqual({
      headline: { kind: 'text', objectId: 'slide_cover_hdln' },
    });
  });

  it('records objectId on a {field,sample} image element (kind=image)', () => {
    const layout: SlideTypeLayout = {
      type: 'people',
      elements: [
        {
          id: 'avtr',
          kind: 'image',
          x: 100, y: 100, w: 120, h: 120,
          zOrder: 0,
          content: { field: 'avatar', sample: 'avatar' },
        },
      ],
    };
    const built = buildSlideRequests(layout, tokens, {});
    expect(built.tags).toEqual({
      avatar: { kind: 'image', objectId: 'slide_people_avtr' },
    });
    // A {field}-image is treated like a tagged image — placeholder shape, not a createImage.
    expect(built.requests.some((r) => r.createImage)).toBe(false);
  });

  it('throws when a generated objectId would exceed the 50-char API limit', () => {
    const longLayout: SlideTypeLayout = {
      type: 'Content',
      elements: [
        {
          id: 'x'.repeat(60),
          kind: 'text',
          x: 0,
          y: 0,
          w: 10,
          h: 10,
          zOrder: 0,
          content: { tag: '{{t}}' },
        },
      ],
    };
    expect(() => buildSlideRequests(longLayout, tokens, {})).toThrow(/objectId/i);
  });
});
