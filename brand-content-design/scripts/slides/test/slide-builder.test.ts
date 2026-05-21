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
});
