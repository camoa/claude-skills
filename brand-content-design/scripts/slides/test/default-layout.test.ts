import { describe, it, expect } from 'vitest';
import { buildDefaultLayout } from '../src/default-layout.js';
import type { SlideType } from '../src/layout-spec.js';

const ALL_TYPES: SlideType[] = [
  'Title',
  'Content',
  'Image',
  'Data',
  'Quote',
  'CTA',
  'Transition',
];

describe('buildDefaultLayout', () => {
  const spec = buildDefaultLayout();

  it('is 16:9 — 720 × 405 points', () => {
    expect(spec.pageWidth).toBe(720);
    expect(spec.pageHeight).toBe(405);
  });

  it('covers all seven slide types exactly once', () => {
    const types = spec.slides.map((s) => s.type).sort();
    expect(types).toEqual([...ALL_TYPES].sort());
  });

  it('gives every slide a full-bleed background at paint order 0', () => {
    for (const slide of spec.slides) {
      const bg = slide.elements.find((e) => e.id === 'bg');
      expect(bg, slide.type).toBeDefined();
      expect(bg).toMatchObject({ kind: 'shape', x: 0, y: 0, w: 720, h: 405, zOrder: 0 });
    }
  });

  it('makes every text and image element a tagged merge placeholder', () => {
    for (const slide of spec.slides) {
      for (const el of slide.elements) {
        if (el.kind === 'shape') continue;
        expect(el.content, `${slide.type}/${el.id}`).toBeDefined();
        expect(el.content && 'tag' in el.content).toBe(true);
      }
    }
  });

  it('keeps element ids unique within each slide', () => {
    for (const slide of spec.slides) {
      const ids = slide.elements.map((e) => e.id);
      expect(new Set(ids).size, slide.type).toBe(ids.length);
    }
  });
});
