import { describe, it, expect } from 'vitest';
import {
  buildReplaceAllTextRequests,
  buildReplaceAllShapesWithImageRequests,
  buildSetSpeakerNotesRequests,
  buildObjectIdTextFillRequests,
} from '../src/requests.js';

describe('buildReplaceAllTextRequests', () => {
  it('returns an empty array for an empty tag map', () => {
    expect(buildReplaceAllTextRequests({})).toEqual([]);
  });

  it('builds one replaceAllText request per tag, matchCase true', () => {
    const reqs = buildReplaceAllTextRequests({ '{{title}}': 'Q3 Results' });
    expect(reqs).toEqual([
      {
        replaceAllText: {
          containsText: { text: '{{title}}', matchCase: true },
          replaceText: 'Q3 Results',
        },
      },
    ]);
  });

  it('preserves tag order across multiple tags', () => {
    const reqs = buildReplaceAllTextRequests({ '{{a}}': '1', '{{b}}': '2' });
    expect(reqs).toHaveLength(2);
    expect(reqs[0].replaceAllText?.containsText?.text).toBe('{{a}}');
    expect(reqs[1].replaceAllText?.replaceText).toBe('2');
  });

  it('treats an empty replacement value as a valid (clearing) replacement', () => {
    const reqs = buildReplaceAllTextRequests({ '{{subtitle}}': '' });
    expect(reqs[0].replaceAllText?.replaceText).toBe('');
  });

  it('scopes requests to pageObjectIds when supplied (one repeated type per slide)', () => {
    const reqs = buildReplaceAllTextRequests({ '{{body}}': 'Slide 3 body' }, ['slide3']);
    expect(reqs[0].replaceAllText?.pageObjectIds).toEqual(['slide3']);
  });

  it('omits pageObjectIds when the scope array is empty (presentation-wide)', () => {
    const reqs = buildReplaceAllTextRequests({ '{{body}}': 'x' }, []);
    expect('pageObjectIds' in (reqs[0].replaceAllText ?? {})).toBe(false);
  });
});

describe('buildReplaceAllShapesWithImageRequests', () => {
  it('returns an empty array for an empty map', () => {
    expect(buildReplaceAllShapesWithImageRequests({})).toEqual([]);
  });

  it('builds one replaceAllShapesWithImage request per tag, CENTER_INSIDE', () => {
    const reqs = buildReplaceAllShapesWithImageRequests({
      '{{logo}}': 'https://example.com/logo.png',
    });
    expect(reqs).toEqual([
      {
        replaceAllShapesWithImage: {
          containsText: { text: '{{logo}}', matchCase: true },
          imageUrl: 'https://example.com/logo.png',
          imageReplaceMethod: 'CENTER_INSIDE',
        },
      },
    ]);
  });

  it('builds one request per tag for multiple image tags', () => {
    const reqs = buildReplaceAllShapesWithImageRequests({
      '{{img1}}': 'https://example.com/1.png',
      '{{img2}}': 'https://example.com/2.png',
    });
    expect(reqs).toHaveLength(2);
  });

  it('scopes image requests to pageObjectIds when supplied', () => {
    const reqs = buildReplaceAllShapesWithImageRequests(
      { '{{logo}}': 'https://example.com/l.png' },
      ['slide2'],
    );
    expect(reqs[0].replaceAllShapesWithImage?.pageObjectIds).toEqual(['slide2']);
  });
});

describe('buildSetSpeakerNotesRequests', () => {
  it('builds an insertText request targeting the speaker-notes shape', () => {
    expect(buildSetSpeakerNotesRequests('notes123', 'Talk track for slide 3')).toEqual([
      {
        insertText: {
          objectId: 'notes123',
          text: 'Talk track for slide 3',
          insertionIndex: 0,
        },
      },
    ]);
  });

  it('returns no requests for empty notes text', () => {
    expect(buildSetSpeakerNotesRequests('notes123', '')).toEqual([]);
  });

  it('preserves multi-paragraph notes text', () => {
    const reqs = buildSetSpeakerNotesRequests('n1', 'Line one\nLine two');
    expect(reqs[0].insertText?.text).toBe('Line one\nLine two');
  });
});

describe('buildObjectIdTextFillRequests', () => {
  it('returns no requests for empty fills', () => {
    expect(buildObjectIdTextFillRequests([])).toEqual([]);
  });

  it('emits deleteText (range=ALL) before insertText (index=0) per fill', () => {
    const reqs = buildObjectIdTextFillRequests([
      { objectId: 'slide_cover_0_hdln', text: "Who's Driving This Thing?" },
    ]);
    expect(reqs).toEqual([
      { deleteText: { objectId: 'slide_cover_0_hdln', textRange: { type: 'ALL' } } },
      {
        insertText: {
          objectId: 'slide_cover_0_hdln',
          text: "Who's Driving This Thing?",
          insertionIndex: 0,
        },
      },
    ]);
  });

  it('orders requests per-element (delete N, insert N, delete N+1, insert N+1)', () => {
    const reqs = buildObjectIdTextFillRequests([
      { objectId: 'A', text: 'one' },
      { objectId: 'B', text: 'two' },
    ]);
    expect(reqs.map((r) =>
      r.deleteText ? `D:${r.deleteText.objectId}` : `I:${r.insertText?.objectId}`,
    )).toEqual(['D:A', 'I:A', 'D:B', 'I:B']);
  });

  it('preserves multi-line and special-character text payloads', () => {
    const reqs = buildObjectIdTextFillRequests([
      { objectId: 'X', text: 'Line 1\nLine 2 — "quoted"' },
    ]);
    expect(reqs[1].insertText?.text).toBe('Line 1\nLine 2 — "quoted"');
  });
});
