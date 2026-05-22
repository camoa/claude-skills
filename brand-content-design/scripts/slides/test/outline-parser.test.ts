import { describe, it, expect } from 'vitest';
import { parseOutline, toContentPayload } from '../src/outline-parser.js';
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

const OUTLINE = `# Presentation Outline: Demo

## Slide 1: Title
**Purpose:** Open the talk

- Title: Hello World
- **Logo**: logo.png
- Speaker notes: Welcome everyone

## Slide 2: Content
**Purpose:** One key idea

- Body: The main point
- Subtitle: ___
`;

describe('parseOutline', () => {
  it('parses slide headers, types, and filled bullets', () => {
    const slides = parseOutline(OUTLINE);
    expect(slides).toHaveLength(2);
    expect(slides[0].type).toBe('Title');
    expect(slides[0].fields).toEqual({ Title: 'Hello World', Logo: 'logo.png' });
  });

  it('strips **bold** markdown from bullet labels', () => {
    expect(parseOutline(OUTLINE)[0].fields).toHaveProperty('Logo');
  });

  it('captures speaker notes separately from fields', () => {
    const slides = parseOutline(OUTLINE);
    expect(slides[0].speakerNotes).toBe('Welcome everyone');
    expect(slides[0].fields).not.toHaveProperty('Speaker notes');
  });

  it('skips unfilled (___) bullets', () => {
    const slides = parseOutline(OUTLINE);
    expect(slides[1].fields).toEqual({ Body: 'The main point' });
  });

  it('throws when no slides are found', () => {
    expect(() => parseOutline('# Just a title\n\nsome prose')).toThrow(/no slides/i);
  });
});

describe('toContentPayload', () => {
  it('maps field labels to tag tokens by normalized match', () => {
    const payload = toContentPayload(parseOutline(OUTLINE), tagMap);
    expect(payload[0].text).toEqual({ '{{title}}': 'Hello World' });
    expect(payload[1].text).toEqual({ '{{body}}': 'The main point' });
  });

  it('routes image-kind tags into images, text-kind into text', () => {
    const payload = toContentPayload(parseOutline(OUTLINE), tagMap);
    expect(payload[0].images).toEqual({ '{{logo}}': 'logo.png' });
  });

  it('passes speaker notes through to the content payload', () => {
    const payload = toContentPayload(parseOutline(OUTLINE), tagMap);
    expect(payload[0].speakerNotes).toBe('Welcome everyone');
  });

  it('throws fail-fast on an unknown slide type', () => {
    const parsed = parseOutline('## Slide 1: Bogus\n- Title: x');
    expect(() => toContentPayload(parsed, tagMap)).toThrow(/unknown slide type/i);
  });

  it('throws fail-fast on a field label that matches no tag', () => {
    const parsed = parseOutline('## Slide 1: Title\n- Nonsense: x');
    expect(() => toContentPayload(parsed, tagMap)).toThrow(/no tag matches field/i);
  });
});
