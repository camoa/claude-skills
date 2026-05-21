import { describe, it, expect } from 'vitest';
import { validatePayload, type ContentPayload } from '../src/payload-validator.js';
import type { TagMap } from '../src/layout-spec.js';

const tagMap: TagMap = {
  Title: {
    typeSlideObjectId: 'slide_Title',
    tags: { '{{title}}': { kind: 'text' }, '{{logo}}': { kind: 'image' } },
  },
  Content: {
    typeSlideObjectId: 'slide_Content',
    tags: { '{{body}}': { kind: 'text' } },
  },
};

describe('validatePayload', () => {
  it('accepts a payload whose tags all match the tag map', () => {
    const payload: ContentPayload = [
      { type: 'Title', text: { '{{title}}': 'Hi' }, images: { '{{logo}}': 'u' } },
      { type: 'Content', text: { '{{body}}': 'Body' } },
    ];
    expect(validatePayload(payload, tagMap)).toEqual({ ok: true, errors: [] });
  });

  it('flags an unknown slide type', () => {
    const r = validatePayload([{ type: 'Sidebar', text: {} }], tagMap);
    expect(r.ok).toBe(false);
    expect(r.errors[0].unknownType).toBe(true);
  });

  it('flags a missing tag', () => {
    const r = validatePayload([{ type: 'Title', text: { '{{title}}': 'Hi' } }], tagMap);
    expect(r.ok).toBe(false);
    expect(r.errors[0].missingTags).toEqual(['{{logo}}']);
  });

  it('flags an unknown tag', () => {
    const r = validatePayload(
      [{ type: 'Content', text: { '{{body}}': 'x', '{{extra}}': 'y' } }],
      tagMap,
    );
    expect(r.ok).toBe(false);
    expect(r.errors[0].unknownTags).toEqual(['{{extra}}']);
  });

  it('flags a kind mismatch — a text value supplied for an image tag', () => {
    const r = validatePayload(
      [{ type: 'Title', text: { '{{title}}': 'Hi', '{{logo}}': 'oops' } }],
      tagMap,
    );
    expect(r.ok).toBe(false);
    expect(r.errors[0].kindMismatches).toEqual(['{{logo}}']);
  });

  it('reports errors per slide index across a multi-slide payload', () => {
    const r = validatePayload(
      [
        { type: 'Title', text: { '{{title}}': 'Hi' }, images: { '{{logo}}': 'u' } }, // ok
        { type: 'Content', text: {} }, // missing {{body}}
      ],
      tagMap,
    );
    expect(r.ok).toBe(false);
    expect(r.errors).toHaveLength(1);
    expect(r.errors[0].slideIndex).toBe(1);
    expect(r.errors[0].missingTags).toEqual(['{{body}}']);
  });
});
