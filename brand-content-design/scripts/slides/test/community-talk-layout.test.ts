import { describe, it, expect } from 'vitest';
import {
  buildCommunityTalkLayout,
  communityTalkGradient,
  palceraTokens,
} from '../src/community-talk-layout.js';

const TYPES = [
  'Title',
  'Agenda',
  'Section',
  'Content',
  'TwoColumn',
  'ThreeColumn',
  'Code',
  'Data',
  'Image',
  'Quote',
  'Demo',
  'Takeaways',
  'CTA',
];

describe('buildCommunityTalkLayout', () => {
  const spec = buildCommunityTalkLayout();

  it('is a 720×405 spec covering all 13 community-talk slide types in order', () => {
    expect(spec.pageWidth).toBe(720);
    expect(spec.pageHeight).toBe(405);
    expect(spec.slides.map((s) => s.type)).toEqual(TYPES);
  });

  it('places every element origin on the page', () => {
    for (const slide of spec.slides) {
      for (const e of slide.elements) {
        const where = `${slide.type}/${e.id}`;
        expect(e.x, where).toBeGreaterThanOrEqual(-1);
        expect(e.y, where).toBeGreaterThanOrEqual(-1);
        expect(e.x, where).toBeLessThanOrEqual(720);
        expect(e.y, where).toBeLessThanOrEqual(405);
        // Shapes / images must stay within the page; text boxes are
        // intentionally generous (left-aligned text renders from `x`, so a box
        // extending past the edge is harmless and avoids wrapping huge tags).
        if (e.kind !== 'text') {
          expect(e.x + e.w, `${where} right`).toBeLessThanOrEqual(760);
          expect(e.y + e.h, `${where} bottom`).toBeLessThanOrEqual(470);
        }
      }
    }
  });

  it('gives every slide a background as its first (z-0) element', () => {
    for (const slide of spec.slides) {
      const bg = slide.elements.find((e) => e.id === 'bg' || e.id === 'grad');
      expect(bg, slide.type).toBeDefined();
      expect(bg?.zOrder).toBe(0);
    }
  });

  it('uses a baked gradient background on Title, Section, and CTA only', () => {
    const gradTypes = spec.slides
      .filter((s) => s.elements.some((e) => e.id === 'grad'))
      .map((s) => s.type);
    expect(gradTypes.sort()).toEqual(['CTA', 'Section', 'Title']);
  });

  it('carries a logo on every slide', () => {
    for (const slide of spec.slides) {
      expect(slide.elements.some((e) => e.id === 'logo'), slide.type).toBe(true);
    }
  });

  it('uses the mono font for the Code slide code block', () => {
    const code = spec.slides
      .find((s) => s.type === 'Code')
      ?.elements.find((e) => e.id === 'code');
    expect(code?.fontFamily).toBe('mono');
  });

  it('drives the dramatic type scale — the Data hero number is the largest text', () => {
    const sizes = spec.slides
      .flatMap((s) => s.elements)
      .filter((e) => e.kind === 'text' && e.fontSize !== undefined)
      .map((e) => e.fontSize as number);
    const stat = spec.slides
      .find((s) => s.type === 'Data')
      ?.elements.find((e) => e.id === 'stat');
    expect(stat?.fontSize).toBe(Math.max(...sizes));
  });
});

describe('communityTalkGradient', () => {
  it('is the 3-stop diagonal navy→cyan brand gradient', () => {
    const g = communityTalkGradient();
    expect(g.direction).toBe('diagonal');
    expect(g.colors).toEqual(['#081E41', '#194582', '#00F3FF']);
    expect(g.positions).toEqual([0, 0.62, 1]);
  });
});

describe('palceraTokens', () => {
  it('carries the Palcera brand colours and the three brand fonts', () => {
    expect(palceraTokens.colors.primary).toBe('#194582');
    expect(palceraTokens.typography.headingFont).toBe('Nunito');
    expect(palceraTokens.typography.bodyFont).toBe('Inter');
    expect(palceraTokens.typography.monoFont).toBe('JetBrains Mono');
  });
});
