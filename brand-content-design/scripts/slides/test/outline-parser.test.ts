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

  it('aggregates errors across slides into one fail-fast message', () => {
    const parsed = parseOutline(
      '## Slide 1: Bogus\n- Title: x\n\n## Slide 2: Title\n- Nonsense: y',
    );
    expect(() => toContentPayload(parsed, tagMap)).toThrow(/slide 1.*slide 2/s);
  });

  it('resolves natural-language type labels via normalized-name lookup', () => {
    // tagMap has keys 'Title' and 'Content'; an outline using "title" or
    // "Title Slide" should still resolve to the stable id.
    const lowerCased = parseOutline('## Slide 1: title\n- Title: Hello');
    expect(toContentPayload(lowerCased, tagMap)[0].type).toBe('Title');

    // Multi-word with separators normalizes to the same alphanumeric token.
    const fieldStyle: TagMap = {
      getinvolved: { typeSlideObjectId: 'slide_g', tags: { headline: { kind: 'text' } } },
    };
    const parsed = parseOutline('## Slide 1: Get Involved\n- headline: Take what is useful');
    expect(toContentPayload(parsed, fieldStyle)[0].type).toBe('getinvolved');
  });

  it('still throws on an unknown type when neither exact nor normalized match', () => {
    const parsed = parseOutline('## Slide 1: TotallyMadeUp\n- Title: x');
    expect(() => toContentPayload(parsed, tagMap)).toThrow(/unknown slide type/i);
  });

  it('strips trailing parenthetical hints from bullet labels before normalize-match', () => {
    // Worksheets author labels like `Talk title (≤10 words)` for human guidance;
    // matching binds to the bare field id (`talk_title`) after the hint is stripped.
    const titleMap: TagMap = {
      Title: {
        typeSlideObjectId: 'slide_Title',
        tags: {
          '{{talk_title}}': { kind: 'text' },
          '{{event_name_date}}': { kind: 'text' },
        },
      },
    };
    const parsed = parseOutline(
      [
        '## Slide 1: Title',
        '- Talk title (≤10 words): Hello World',
        '- Event name + date (≤8 words): Drupal AI Club, May 22, 2026',
      ].join('\n'),
    );
    const payload = toContentPayload(parsed, titleMap);
    expect(payload[0].text).toEqual({
      '{{talk_title}}': 'Hello World',
      '{{event_name_date}}': 'Drupal AI Club, May 22, 2026',
    });
  });

  it('only strips a parenthetical that sits at the end of the label', () => {
    // A parenthetical mid-label (rare, but possible) must not be stripped —
    // only a trailing hint is editorial noise.
    const map: TagMap = {
      T: {
        typeSlideObjectId: 'slide_T',
        tags: { '{{footnote_a}}': { kind: 'text' } },
      },
    };
    // Label `Footnote (a)` is the canonical form; the field is `footnote_a`.
    const parsed = parseOutline('## Slide 1: T\n- Footnote (a): see appendix');
    // Trailing `(a)` IS stripped → label becomes `Footnote`, which won't bind
    // to `footnote_a`. This documents the trade-off: trailing parens are always
    // treated as hints. The author can disambiguate by inlining the letter
    // (`Footnote a`).
    expect(() => toContentPayload(parsed, map)).toThrow(/no tag matches field/i);
  });

  describe('size caps (C3)', () => {
    it('rejects an outline source over the byte cap', () => {
      process.env.BCD_SLIDES_MAX_OUTLINE_BYTES = '128';
      try {
        const big = '## Slide 1: Title\n' + '- Title: ' + 'x'.repeat(200) + '\n';
        let caught: unknown;
        try {
          parseOutline(big);
        } catch (e) {
          caught = e;
        }
        expect(caught).toBeDefined();
        expect((caught as { code?: string }).code).toBe('OUTLINE_TOO_LARGE');
        expect((caught as Error).message).toMatch(/bytes/);
      } finally {
        delete process.env.BCD_SLIDES_MAX_OUTLINE_BYTES;
      }
    });

    it('rejects an outline that declares more slides than the count cap', () => {
      process.env.BCD_SLIDES_MAX_SLIDES = '3';
      try {
        const headers = Array.from(
          { length: 5 },
          (_, i) => `## Slide ${i + 1}: Title\n- Title: x`,
        ).join('\n\n');
        let caught: unknown;
        try {
          parseOutline(headers);
        } catch (e) {
          caught = e;
        }
        expect(caught).toBeDefined();
        expect((caught as { code?: string }).code).toBe('OUTLINE_TOO_LARGE');
        expect((caught as Error).message).toMatch(/more than 3 slides/);
      } finally {
        delete process.env.BCD_SLIDES_MAX_SLIDES;
      }
    });

    it('accepts an outline exactly at the slide count limit', () => {
      process.env.BCD_SLIDES_MAX_SLIDES = '2';
      try {
        const outline = [
          '## Slide 1: Title\n- Title: a',
          '## Slide 2: Title\n- Title: b',
        ].join('\n\n');
        const parsed = parseOutline(outline);
        expect(parsed).toHaveLength(2);
      } finally {
        delete process.env.BCD_SLIDES_MAX_SLIDES;
      }
    });
  });
});
