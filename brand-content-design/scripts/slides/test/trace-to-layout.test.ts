/**
 * Tests for the post-Template-Generator-Contract `trace-to-layout` (B2).
 *
 * The tracer (sibling, Python) emits per-page `{ type, ops }` with hex colors
 * and explicit text widths in 1920×1080 px bottom-left-origin space. This
 * test asserts that:
 *
 *   - field-tagged text becomes `{ field, sample }` LayoutElement content;
 *   - untagged text becomes `{ fixed }`;
 *   - per-page `type` propagates to `SlideTypeLayout.type` (not `p1`/`p2`);
 *   - shape geometry converts (bottom-left → top-left, px → pt @ 0.375×);
 *   - text y is the box top (not a baseline);
 *   - gradient registers in `gradients[]` with a `{ fixed: 'gradient' }`
 *     placeholder element on the page;
 *   - the renderer's `align` vocabulary maps from the generator's
 *     (`left`/`center`/`right` → `start`/`center`/`end`).
 */
import { describe, it, expect } from 'vitest';
import { traceToLayoutSpec, type TemplateTrace } from '../src/trace-to-layout.js';

const trace: TemplateTrace = {
  pageSize: [1920, 1080],
  pages: [
    {
      type: 'title',
      ops: [
        { op: 'solid', color: '#101010' },
        // A rect: bottom-left at (100, 980) in src space → top edge is 1080-980-8=92 (src) → 92*0.375=34.5 (pt).
        { op: 'rect', x: 100, y: 980, w: 200, h: 8, color: '#FF00FF' },
        // A field-tagged text: top edge at y=800 → top-left y = (1080-800)*0.375 = 105.
        {
          op: 'text', x: 200, y: 800, w: 1500,
          text: 'Hello world', field: 'headline',
          font: 'Inter Black', size: 60, color: '#FFFFFF',
          align: 'left', valign: 'top',
        },
        // Static chrome — no field.
        {
          op: 'text', x: 100, y: 60, w: 200,
          text: 'palcera', field: null,
          font: 'Inter', size: 14, color: '#888888',
          align: 'left', valign: 'top',
        },
      ],
    },
    {
      type: 'quote',
      ops: [
        { op: 'gradient', stops: [[0, '#FF0000'], [1, '#0000FF']] },
        { op: 'circle', cx: 960, cy: 540, r: 200, fill: '#00FF00', stroke: null, strokeW: 0 },
        {
          op: 'text', x: 200, y: 800, w: 1500,
          text: 'Quote text', field: 'quote',
          font: 'Inter Semibold', size: 50, color: '#FFFFFF',
          align: 'center', valign: 'top',
        },
      ],
    },
  ],
};

describe('traceToLayoutSpec — post-generator-contract', () => {
  const { layoutSpec, gradients, imagePaths, skipped } = traceToLayoutSpec(trace);

  it('produces a 720×405 page in the renderer space', () => {
    expect(layoutSpec.pageWidth).toBe(720);
    expect(layoutSpec.pageHeight).toBe(405);
    expect(layoutSpec.slides).toHaveLength(2);
    expect(skipped).toEqual([]);
  });

  it('propagates the per-page type id (not a generated p<N>)', () => {
    expect(layoutSpec.slides[0].type).toBe('title');
    expect(layoutSpec.slides[1].type).toBe('quote');
  });

  it('emits { field, sample } for a field-tagged text element', () => {
    const heading = layoutSpec.slides[0].elements.find((e) => e.kind === 'text' && e.zOrder === 2);
    expect(heading?.content).toEqual({ field: 'headline', sample: 'Hello world' });
  });

  it('emits { fixed } for untagged static-chrome text', () => {
    const logo = layoutSpec.slides[0].elements.find((e) => e.kind === 'text' && e.zOrder === 3);
    expect(logo?.content).toEqual({ fixed: 'palcera' });
  });

  it('converts shape geometry from bottom-left px to top-left pt @ 0.375×', () => {
    // rect: src (x=100, y_bottom=980, w=200, h=8) → top = (1080 - 980 - 8) * 0.375 = 34.5
    const rect = layoutSpec.slides[0].elements.find((e) => e.kind === 'shape' && e.zOrder === 1);
    expect(rect).toBeDefined();
    expect(rect!.x).toBeCloseTo(100 * 0.375);
    expect(rect!.y).toBeCloseTo(34.5);
    expect(rect!.w).toBeCloseTo(200 * 0.375);
    expect(rect!.h).toBeCloseTo(8 * 0.375);
    expect(rect!.color).toBe('#FF00FF');
  });

  it('places text by its box top (no baseline fudge)', () => {
    // text at y_top_src=800 → top-left y = (1080 - 800) * 0.375 = 105
    const heading = layoutSpec.slides[0].elements.find((e) => e.kind === 'text' && e.zOrder === 2);
    expect(heading!.y).toBeCloseTo(105);
    // h = size * 1.4 * S = 60 * 1.4 * 0.375 = 31.5
    expect(heading!.h).toBeCloseTo(31.5);
  });

  it('maps generator align vocabulary to renderer align vocabulary', () => {
    const heading = layoutSpec.slides[0].elements.find((e) => e.kind === 'text' && e.zOrder === 2);
    expect(heading!.align).toBe('start');
    const quote = layoutSpec.slides[1].elements.find((e) => e.kind === 'text');
    expect(quote!.align).toBe('center');
  });

  it('registers a gradient and emits a fixed-image placeholder for it', () => {
    expect(Object.keys(gradients)).toEqual(['grad1']);
    expect(gradients.grad1.colors).toEqual(['#FF0000', '#0000FF']);
    expect(gradients.grad1.positions).toEqual([0, 1]);
    const placeholder = layoutSpec.slides[1].elements.find((e) => e.kind === 'image');
    expect(placeholder?.content).toEqual({ fixed: 'gradient' });
  });

  it('converts a circle to an ELLIPSE-bound box', () => {
    const circ = layoutSpec.slides[1].elements.find((e) => e.kind === 'ellipse');
    expect(circ).toBeDefined();
    // src center (960, 540), r=200 → bbox left = (960-200)*0.375 = 285, top = (1080 - (540-200) - 400)*0.375 = (1080-340-400)*0.375 = 127.5
    expect(circ!.x).toBeCloseTo(285);
    expect(circ!.y).toBeCloseTo(127.5);
    expect(circ!.w).toBeCloseTo(150);
    expect(circ!.h).toBeCloseTo(150);
    expect(circ!.color).toBe('#00FF00');
  });

  it('does not register any image paths when no image ops are present', () => {
    expect(Object.keys(imagePaths)).toEqual([]);
  });

  it('derives font role + weight from the font name', () => {
    const heading = layoutSpec.slides[0].elements.find((e) => e.kind === 'text' && e.zOrder === 2);
    // "Inter Black": any Inter variant maps to `body` family (existing
    // heuristic — Inter is the canonical body font); weight comes from the
    // variant suffix.
    expect(heading!.fontFamily).toBe('body');
    expect(heading!.fontWeight).toBe(900);
    expect(heading!.fontSize).toBeCloseTo(60 * 0.375);

    const quote = layoutSpec.slides[1].elements.find((e) => e.kind === 'text');
    expect(quote!.fontWeight).toBe(600); // "Semibold"
  });
});
