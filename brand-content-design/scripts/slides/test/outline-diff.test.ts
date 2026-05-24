import { describe, it, expect } from 'vitest';
import { diffOutline, isEmptyDiff } from '../src/outline-diff.js';
import {
  MANIFEST_SCHEMA,
  type RenderManifest,
  type ManifestSlide,
} from '../src/render-manifest.js';
import type { ContentPayload } from '../src/payload-validator.js';
import type { LayoutSpec } from '../src/layout-spec.js';
import type { BrandTokens } from '../src/token-mapper.js';

const layoutSpec: LayoutSpec = { pageWidth: 720, pageHeight: 405, slides: [] };
const tokens: BrandTokens = {
  colors: { primary: '#000', background: '#fff', textLight: '#fff', textDark: '#000' },
  typography: { headingFont: 'I', bodyFont: 'I' },
};

function manifest(slides: ManifestSlide[]): RenderManifest {
  return {
    schema: MANIFEST_SCHEMA,
    templatePresentationId: 't',
    deckPresentationId: 'd',
    renderedAt: '2026-05-24T00:00:00.000Z',
    layoutSpec,
    tokens,
    fixedImageUrls: {},
    fontSubstitutions: [],
    slides,
  };
}

describe('diffOutline', () => {
  it('empty diff on byte-equivalent re-run', () => {
    const slides: ManifestSlide[] = [
      { type: 'title', text: { title: 'Hi' }, images: {}, speakerNotes: 'n' },
      { type: 'agenda', text: { items: 'a,b' }, images: {} },
    ];
    const payload: ContentPayload = [
      { type: 'title', text: { title: 'Hi' }, speakerNotes: 'n' },
      { type: 'agenda', text: { items: 'a,b' } },
    ];
    const d = diffOutline(manifest(slides), payload);
    expect(d.unchanged).toHaveLength(2);
    expect(d.refilled).toHaveLength(0);
    expect(d.added).toHaveLength(0);
    expect(d.removed).toHaveLength(0);
    expect(d.reordered).toBe(false);
    expect(isEmptyDiff(d)).toBe(true);
  });

  it('flags a pure text refill', () => {
    const d = diffOutline(
      manifest([{ type: 'title', text: { title: 'Old' }, images: {} }]),
      [{ type: 'title', text: { title: 'New' } }],
    );
    expect(d.refilled).toEqual([
      { index: 0, type: 'title', changedFields: ['title'] },
    ]);
    expect(d.unchanged).toHaveLength(0);
    expect(isEmptyDiff(d)).toBe(false);
  });

  it('flags an image-tag refill', () => {
    const d = diffOutline(
      manifest([{ type: 'cover', text: {}, images: { hero: 'u1' } }]),
      [{ type: 'cover', images: { hero: 'u2' } }],
    );
    expect(d.refilled[0].changedFields).toEqual(['hero']);
  });

  it('flags speakerNotes change as a refill with key "speakerNotes"', () => {
    const d = diffOutline(
      manifest([{ type: 't', text: {}, images: {}, speakerNotes: 'a' }]),
      [{ type: 't', speakerNotes: 'b' }],
    );
    expect(d.refilled[0].changedFields).toEqual(['speakerNotes']);
  });

  it('flags an addition at the end', () => {
    const d = diffOutline(
      manifest([{ type: 'a', text: {}, images: {} }]),
      [
        { type: 'a' },
        { type: 'b' },
      ],
    );
    expect(d.added).toEqual([{ index: 1, type: 'b' }]);
    expect(d.unchanged).toEqual([{ index: 0, type: 'a' }]);
    expect(d.removed).toHaveLength(0);
  });

  it('flags a removal from the middle as remove + position shift', () => {
    const d = diffOutline(
      manifest([
        { type: 'a', text: {}, images: {} },
        { type: 'mid', text: {}, images: {} },
        { type: 'c', text: {}, images: {} },
      ]),
      [
        { type: 'a' },
        { type: 'c' },
      ],
    );
    // Index 1: prev=mid, next=c → mismatch counts as remove(mid) + add(c).
    expect(d.added.map((s) => s.type)).toEqual(['c']);
    expect(d.removed.map((s) => s.type)).toEqual(['mid', 'c']);
    expect(d.reordered).toBe(false);
  });

  it('detects reorder (same multiset, different order)', () => {
    const d = diffOutline(
      manifest([
        { type: 'a', text: {}, images: {} },
        { type: 'b', text: {}, images: {} },
      ]),
      [
        { type: 'b' },
        { type: 'a' },
      ],
    );
    expect(d.reordered).toBe(true);
  });

  it('does not mark reorder when lengths differ', () => {
    const d = diffOutline(
      manifest([
        { type: 'a', text: {}, images: {} },
        { type: 'b', text: {}, images: {} },
      ]),
      [{ type: 'a' }],
    );
    expect(d.reordered).toBe(false);
  });

  it('mixed: one unchanged, one refilled, one added, one removed', () => {
    const d = diffOutline(
      manifest([
        { type: 'a', text: { t: 'A' }, images: {} },
        { type: 'b', text: { t: 'B' }, images: {} },
        { type: 'c', text: {}, images: {} },
      ]),
      [
        { type: 'a', text: { t: 'A' } },
        { type: 'b', text: { t: 'B-prime' } },
        { type: 'd' },
      ],
    );
    expect(d.unchanged.map((s) => s.type)).toEqual(['a']);
    expect(d.refilled.map((s) => s.type)).toEqual(['b']);
    // index 2: prev=c, next=d → mismatch
    expect(d.removed.map((s) => s.type)).toEqual(['c']);
    expect(d.added.map((s) => s.type)).toEqual(['d']);
  });

  it('treats undefined and empty-string speakerNotes as equal', () => {
    const d = diffOutline(
      manifest([{ type: 't', text: {}, images: {} }]),
      [{ type: 't', speakerNotes: '' }],
    );
    expect(isEmptyDiff(d)).toBe(true);
  });
});
