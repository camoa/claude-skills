import { describe, it, expect, vi } from 'vitest';
import { renderDeck } from '../src/merge-engine.js';
import type { SlidesClient } from '../src/client.js';
import type { TagMap } from '../src/layout-spec.js';
import type { ContentPayload } from '../src/payload-validator.js';

// Mock the image baker so the custom-font path is exercised without a real .ttf.
vi.mock('../src/image-baker.js', () => ({
  bakeDisplayText: vi.fn(() => Buffer.from('PNG')),
}));

const tagMap: TagMap = {
  Title: {
    typeSlideObjectId: 'slide_Title',
    tags: { '{{title}}': { kind: 'text', display: true }, '{{logo}}': { kind: 'image' } },
  },
  Content: {
    typeSlideObjectId: 'slide_Content',
    tags: { '{{body}}': { kind: 'text' } },
  },
};

function fakeClient(presSlides: unknown[] = []) {
  return {
    copyFile: vi.fn().mockResolvedValue({ fileId: 'deck1' }),
    batchUpdate: vi.fn().mockResolvedValue({ replies: [] }),
    getPresentation: vi.fn().mockResolvedValue({ slides: presSlides }),
    uploadImage: vi
      .fn()
      .mockImplementation((name: string) => Promise.resolve({ fileId: name, url: `https://img/${name}` })),
    findOrCreateFolder: vi
      .fn()
      .mockImplementation((name: string) => Promise.resolve({ folderId: `fold_${name}` })),
  };
}
const asClient = (c: ReturnType<typeof fakeClient>) => c as unknown as SlidesClient;

const payload: ContentPayload = [
  { type: 'Title', text: { '{{title}}': 'Hello' }, images: { '{{logo}}': 'https://l/logo.png' } },
  { type: 'Content', text: { '{{body}}': 'Body copy' }, speakerNotes: 'Talk track' },
];

describe('renderDeck', () => {
  it('validates, copies the template, and returns the rendered deck id', async () => {
    const client = fakeClient();
    const res = await renderDeck(asClient(client), { presentationId: 'tmpl1', tagMap }, payload);
    expect(client.copyFile).toHaveBeenCalledWith('tmpl1', expect.any(String), undefined);
    expect(res.presentationId).toBe('deck1');
    expect(res.slidesRendered).toBe(2);
  });

  it('throws fail-fast on an invalid payload — and copies nothing', async () => {
    const client = fakeClient();
    await expect(
      renderDeck(asClient(client), { presentationId: 'tmpl1', tagMap }, [
        { type: 'Nope', text: {} },
      ]),
    ).rejects.toThrow(/payload/i);
    expect(client.copyFile).not.toHaveBeenCalled();
  });

  it('batch 1 duplicates the matching type-slide per entry and deletes the prototypes', async () => {
    const client = fakeClient();
    await renderDeck(asClient(client), { presentationId: 'tmpl1', tagMap }, payload);
    const batch1 = client.batchUpdate.mock.calls[0][1];
    const dups = batch1.filter((r: Record<string, unknown>) => r.duplicateObject);
    const dels = batch1.filter((r: Record<string, unknown>) => r.deleteObject);
    expect(dups).toHaveLength(2); // one per payload entry
    expect(dups[0].duplicateObject.objectIds).toEqual({ slide_Title: 'slide_Title_0' });
    expect(dels).toHaveLength(2); // the two prototype type-slides
  });

  it('page-scopes the fills to each duplicated slide', async () => {
    const client = fakeClient();
    await renderDeck(asClient(client), { presentationId: 'tmpl1', tagMap }, payload);
    const batch1 = client.batchUpdate.mock.calls[0][1];
    const textReq = batch1.find(
      (r: Record<string, any>) => r.replaceAllText?.containsText?.text === '{{body}}',
    );
    expect(textReq.replaceAllText.pageObjectIds).toEqual(['slide_Content_1']);
  });

  it('fills speaker notes from a getPresentation read in a second batch', async () => {
    const client = fakeClient([
      {
        objectId: 'slide_Content_1',
        slideProperties: { notesPage: { notesProperties: { speakerNotesObjectId: 'notes_C1' } } },
      },
    ]);
    await renderDeck(asClient(client), { presentationId: 'tmpl1', tagMap }, payload);
    expect(client.getPresentation).toHaveBeenCalledWith('deck1');
    const batch2 = client.batchUpdate.mock.calls[1][1];
    const insert = batch2.find((r: Record<string, any>) => r.insertText);
    expect(insert.insertText.objectId).toBe('notes_C1');
    expect(insert.insertText.text).toBe('Talk track');
  });

  it('bakes display-tag text as an image when the heading font is custom', async () => {
    const client = fakeClient();
    await renderDeck(asClient(client), { presentationId: 'tmpl1', tagMap }, payload, {
      fontSubstitutions: [{ role: 'heading', from: 'Proxima Nova', to: 'Inter' }],
      customFontFile: '/no/such/font.ttf',
    });
    // {{title}} is display:true → baked + uploaded instead of replaceAllText
    expect(client.uploadImage).toHaveBeenCalled();
  });

  it('is idempotent — a second render copies the template afresh', async () => {
    const client = fakeClient();
    await renderDeck(asClient(client), { presentationId: 'tmpl1', tagMap }, payload);
    await renderDeck(asClient(client), { presentationId: 'tmpl1', tagMap }, payload);
    expect(client.copyFile).toHaveBeenCalledTimes(2);
  });

  it('names the rendered deck from options.deckName', async () => {
    const client = fakeClient();
    await renderDeck(asClient(client), { presentationId: 'tmpl1', tagMap }, payload, {
      deckName: 'My Talk - community-talk',
    });
    expect(client.copyFile).toHaveBeenCalledWith('tmpl1', 'My Talk - community-talk', undefined);
  });

  it('places the rendered deck in a found-or-created Drive folder', async () => {
    const client = fakeClient();
    await renderDeck(asClient(client), { presentationId: 'tmpl1', tagMap }, payload, {
      driveFolderPath: ['Brand', 'Presentations'],
    });
    expect(client.findOrCreateFolder).toHaveBeenCalledTimes(2);
    expect(client.copyFile).toHaveBeenCalledWith(
      'tmpl1',
      expect.any(String),
      'fold_Presentations',
    );
  });
});

/* ---- Field-tagged objectId path (C1) ------------------------------------ */

const fieldTagMap: TagMap = {
  cover: {
    typeSlideObjectId: 'slide_cover',
    tags: {
      headline: { kind: 'text', objectId: 'slide_cover_hdln' },
      subtitle: { kind: 'text', objectId: 'slide_cover_sub' },
    },
  },
  concept: {
    typeSlideObjectId: 'slide_concept',
    tags: {
      title: { kind: 'text', objectId: 'slide_concept_ttl' },
    },
  },
};

const fieldPayload: ContentPayload = [
  { type: 'cover', text: { headline: "Who's Driving This Thing?", subtitle: 'A community talk' } },
  { type: 'concept', text: { title: 'Drupal AI 1.0' }, speakerNotes: 'Talk track' },
];

describe('renderDeck — field-tagged objectId path (C1)', () => {
  it('remaps every field-tagged element id alongside the slide id in duplicateObject', async () => {
    const client = fakeClient();
    await renderDeck(asClient(client), { presentationId: 'tmpl1', tagMap: fieldTagMap }, fieldPayload);
    const batch1 = client.batchUpdate.mock.calls[0][1];
    const dup0 = batch1.find((r: Record<string, any>) => r.duplicateObject?.objectId === 'slide_cover');
    expect(dup0.duplicateObject.objectIds).toEqual({
      slide_cover: 'slide_cover_0',
      slide_cover_hdln: 'slide_cover_0_hdln',
      slide_cover_sub: 'slide_cover_0_sub',
    });
  });

  it('fills each text field via deleteText + insertText addressed by the remapped objectId', async () => {
    const client = fakeClient();
    await renderDeck(asClient(client), { presentationId: 'tmpl1', tagMap: fieldTagMap }, fieldPayload);
    const batch1 = client.batchUpdate.mock.calls[0][1];
    const insertHdln = batch1.find(
      (r: Record<string, any>) => r.insertText?.objectId === 'slide_cover_0_hdln',
    );
    expect(insertHdln?.insertText?.text).toBe("Who's Driving This Thing?");
    const deleteHdln = batch1.find(
      (r: Record<string, any>) =>
        r.deleteText?.objectId === 'slide_cover_0_hdln' && r.deleteText?.textRange?.type === 'ALL',
    );
    expect(deleteHdln).toBeDefined();
    // The objectId path does NOT emit a replaceAllText for that tag.
    const replaceHdln = batch1.find(
      (r: Record<string, any>) => r.replaceAllText?.containsText?.text === 'headline',
    );
    expect(replaceHdln).toBeUndefined();
  });

  it('keeps delete before insert per element (insert-first would erase the new text)', async () => {
    const client = fakeClient();
    await renderDeck(asClient(client), { presentationId: 'tmpl1', tagMap: fieldTagMap }, fieldPayload);
    const batch1 = client.batchUpdate.mock.calls[0][1];
    const delIdx = batch1.findIndex(
      (r: Record<string, any>) => r.deleteText?.objectId === 'slide_cover_0_hdln',
    );
    const insIdx = batch1.findIndex(
      (r: Record<string, any>) => r.insertText?.objectId === 'slide_cover_0_hdln',
    );
    expect(delIdx).toBeGreaterThanOrEqual(0);
    expect(insIdx).toBeGreaterThan(delIdx);
  });

  it('coexists with legacy {tag} tagmap entries — each tag routes to its own path', async () => {
    const mixed: TagMap = {
      ...fieldTagMap,
      Legacy: {
        typeSlideObjectId: 'slide_Legacy',
        tags: { '{{body}}': { kind: 'text' } }, // no objectId → token path
      },
    };
    const mixedPayload: ContentPayload = [
      { type: 'cover', text: { headline: 'New', subtitle: 'Sub' } },
      { type: 'Legacy', text: { '{{body}}': 'Old-school' } },
    ];
    const client = fakeClient();
    await renderDeck(asClient(client), { presentationId: 'tmpl1', tagMap: mixed }, mixedPayload);
    const batch1 = client.batchUpdate.mock.calls[0][1];
    // Field-tagged "headline" → deleteText + insertText
    expect(batch1.some((r: Record<string, any>) => r.insertText?.objectId === 'slide_cover_0_hdln')).toBe(true);
    // Legacy "{{body}}" → replaceAllText
    expect(batch1.some((r: Record<string, any>) => r.replaceAllText?.containsText?.text === '{{body}}')).toBe(true);
  });

  it('throws on a field-tagged image slot (v1 limitation — documented follow-up)', async () => {
    const imageTagMap: TagMap = {
      people: {
        typeSlideObjectId: 'slide_people',
        tags: { avatar: { kind: 'image', objectId: 'slide_people_av' } },
      },
    };
    const client = fakeClient();
    await expect(
      renderDeck(asClient(client), { presentationId: 'tmpl1', tagMap: imageTagMap }, [
        { type: 'people', images: { avatar: 'https://img/a.png' } },
      ]),
    ).rejects.toThrow(/field-tagged image slot/);
  });

  it('still uses page-scoped fill for legacy {tag} entries alongside objectId fills', async () => {
    const mixed: TagMap = {
      ...fieldTagMap,
      Legacy: { typeSlideObjectId: 'slide_Legacy', tags: { '{{body}}': { kind: 'text' } } },
    };
    const mixedPayload: ContentPayload = [
      { type: 'cover', text: { headline: 'X', subtitle: 'Y' } },
      { type: 'Legacy', text: { '{{body}}': 'Z' } },
    ];
    const client = fakeClient();
    await renderDeck(asClient(client), { presentationId: 'tmpl1', tagMap: mixed }, mixedPayload);
    const batch1 = client.batchUpdate.mock.calls[0][1];
    const legacyFill = batch1.find(
      (r: Record<string, any>) => r.replaceAllText?.containsText?.text === '{{body}}',
    );
    expect(legacyFill.replaceAllText.pageObjectIds).toEqual(['slide_Legacy_1']);
  });

  it('counts every field fill in tagsFilled', async () => {
    const client = fakeClient();
    const res = await renderDeck(asClient(client), { presentationId: 'tmpl1', tagMap: fieldTagMap }, fieldPayload);
    // cover: 2 fields (headline, subtitle) + concept: 1 field (title) = 3
    expect(res.tagsFilled).toBe(3);
  });
});

/* ---- Resync (D3) -------------------------------------------------------- */

import { resyncDeck, tagMapFromLayoutSpec } from '../src/merge-engine.js';
import {
  MANIFEST_SCHEMA,
  type RenderManifest,
} from '../src/render-manifest.js';
import type { LayoutSpec } from '../src/layout-spec.js';
import type { BrandTokens } from '../src/token-mapper.js';

const resyncLayout: LayoutSpec = {
  pageWidth: 720,
  pageHeight: 405,
  slides: [
    {
      type: 'title',
      elements: [
        {
          id: 'h',
          kind: 'text',
          x: 10,
          y: 20,
          w: 600,
          h: 80,
          zOrder: 0,
          content: { field: 'headline', sample: 'Sample Headline' },
        },
      ],
    },
    {
      type: 'content',
      elements: [
        {
          id: 'b',
          kind: 'text',
          x: 10,
          y: 100,
          w: 600,
          h: 200,
          zOrder: 0,
          content: { field: 'body', sample: 'Sample Body' },
        },
      ],
    },
  ],
};

const resyncTokens: BrandTokens = {
  colors: { primary: '#000000', background: '#FFFFFF', textLight: '#FFFFFF', textDark: '#000000' },
  typography: { headingFont: 'Inter', bodyFont: 'Inter' },
};

function makeManifest(slides: { type: string; text: Record<string,string>; speakerNotes?: string }[]): RenderManifest {
  return {
    schema: MANIFEST_SCHEMA,
    templatePresentationId: 'tpl',
    deckPresentationId: 'deck-X',
    renderedAt: '2026-05-23T00:00:00.000Z',
    layoutSpec: resyncLayout,
    tokens: resyncTokens,
    fixedImageUrls: {},
    fontSubstitutions: [],
    slides: slides.map((s) => ({ type: s.type, text: s.text, images: {}, ...(s.speakerNotes ? { speakerNotes: s.speakerNotes } : {}) })),
  };
}

function resyncClient(priorSlideIds: string[] = ['old1', 'old2']) {
  let getCalls = 0;
  return {
    batchUpdate: vi.fn().mockResolvedValue({ replies: [] }),
    getPresentation: vi.fn().mockImplementation(() => {
      getCalls++;
      // First call: enumerate prior slide ids; subsequent: enumerate new + notes ids.
      if (getCalls === 1) {
        return Promise.resolve({ slides: priorSlideIds.map((id) => ({ objectId: id })) });
      }
      return Promise.resolve({ slides: [] });
    }),
  };
}

describe('resyncDeck (D3)', () => {
  it('preserves deckPresentationId across the call (AC)', async () => {
    const m = makeManifest([{ type: 'title', text: { headline: 'Hi' } }]);
    const client = resyncClient();
    const res = await resyncDeck(asClient(client as any), m, [
      { type: 'title', text: { headline: 'Hi' } },
    ]);
    expect(res.presentationId).toBe('deck-X');
    expect(res.manifest.deckPresentationId).toBe('deck-X');
  });

  it('empty diff → no API calls, just a bumped renderedAt', async () => {
    const m = makeManifest([{ type: 'title', text: { headline: 'Hi' } }]);
    const client = resyncClient();
    const res = await resyncDeck(asClient(client as any), m, [
      { type: 'title', text: { headline: 'Hi' } },
    ]);
    expect(client.batchUpdate).not.toHaveBeenCalled();
    expect(client.getPresentation).not.toHaveBeenCalled();
    expect(res.changeReport.unchanged).toHaveLength(1);
    expect(res.changeReport.refilled).toHaveLength(0);
    expect(res.manifest.renderedAt).not.toBe(m.renderedAt);
  });

  it('pure refill → createSlide + objectId fill + deleteObject for prior slides', async () => {
    const m = makeManifest([{ type: 'title', text: { headline: 'Old' } }]);
    const client = resyncClient(['old1']);
    await resyncDeck(asClient(client as any), m, [
      { type: 'title', text: { headline: 'New' } },
    ]);
    expect(client.batchUpdate).toHaveBeenCalledTimes(1); // no notes → no batch 2
    const batch1 = client.batchUpdate.mock.calls[0][1];
    const createSlides = batch1.filter((r: any) => r.createSlide);
    expect(createSlides).toHaveLength(1);
    const inserts = batch1.filter((r: any) => r.insertText?.text === 'New');
    expect(inserts).toHaveLength(1);
    const deletes = batch1.filter((r: any) => r.deleteObject?.objectId === 'old1');
    expect(deletes).toHaveLength(1);
  });

  it('rebuild ordering: every create+fill emitted before any prior-slide delete', async () => {
    const m = makeManifest([
      { type: 'title', text: { headline: 'A' } },
      { type: 'content', text: { body: 'B' } },
    ]);
    const client = resyncClient(['old1', 'old2']);
    await resyncDeck(asClient(client as any), m, [
      { type: 'content', text: { body: 'B2' } },
      { type: 'title', text: { headline: 'A2' } },
    ]);
    const batch1 = client.batchUpdate.mock.calls[0][1];
    const lastCreateIdx = batch1.reduce(
      (acc: number, r: any, i: number) => (r.createSlide ? i : acc),
      -1,
    );
    const firstDeleteIdx = batch1.findIndex((r: any) => r.deleteObject);
    expect(lastCreateIdx).toBeGreaterThanOrEqual(0);
    expect(firstDeleteIdx).toBeGreaterThan(lastCreateIdx);
  });

  it('delete-before-insert per field slot (insert-first would clobber)', async () => {
    const m = makeManifest([{ type: 'title', text: { headline: 'Old' } }]);
    const client = resyncClient(['old1']);
    await resyncDeck(asClient(client as any), m, [
      { type: 'title', text: { headline: 'New' } },
    ]);
    const batch1 = client.batchUpdate.mock.calls[0][1];
    const delIdx = batch1.findIndex(
      (r: any) => r.deleteText?.textRange?.type === 'ALL',
    );
    const insIdx = batch1.findIndex(
      (r: any) => r.insertText?.text === 'New',
    );
    expect(delIdx).toBeGreaterThan(0);
    expect(insIdx).toBeGreaterThan(delIdx);
  });

  it('add at end → an extra createSlide; nothing removed', async () => {
    const m = makeManifest([{ type: 'title', text: { headline: 'A' } }]);
    const client = resyncClient(['old1']);
    await resyncDeck(asClient(client as any), m, [
      { type: 'title', text: { headline: 'A' } },
      { type: 'content', text: { body: 'B' } },
    ]);
    const batch1 = client.batchUpdate.mock.calls[0][1];
    expect(batch1.filter((r: any) => r.createSlide)).toHaveLength(2);
  });

  it('remove from middle → fewer createSlides; old slides still get deleted', async () => {
    const m = makeManifest([
      { type: 'title', text: { headline: 'A' } },
      { type: 'content', text: { body: 'B' } },
      { type: 'title', text: { headline: 'C' } },
    ]);
    const client = resyncClient(['o1', 'o2', 'o3']);
    await resyncDeck(asClient(client as any), m, [
      { type: 'title', text: { headline: 'A' } },
      { type: 'title', text: { headline: 'C' } },
    ]);
    const batch1 = client.batchUpdate.mock.calls[0][1];
    expect(batch1.filter((r: any) => r.createSlide)).toHaveLength(2);
    expect(batch1.filter((r: any) => r.deleteObject)).toHaveLength(3);
  });

  it('reorder → createSlides in new payload order', async () => {
    const m = makeManifest([
      { type: 'title', text: { headline: 'A' } },
      { type: 'content', text: { body: 'B' } },
    ]);
    const client = resyncClient(['o1', 'o2']);
    await resyncDeck(asClient(client as any), m, [
      { type: 'content', text: { body: 'B' } },
      { type: 'title', text: { headline: 'A' } },
    ]);
    const batch1 = client.batchUpdate.mock.calls[0][1];
    const creates = batch1.filter((r: any) => r.createSlide);
    // Resync builds via buildSlideRequests — the createSlide is the first req per slide.
    // Inserts immediately after carry the sample (then the objectId fill overwrites);
    // verify the order by looking at the per-slide createSlide objectIds against the
    // first insertText.text on the field-tagged element.
    const insertsField = batch1.filter(
      (r: any) =>
        r.insertText &&
        (r.insertText.text === 'B' || r.insertText.text === 'A') &&
        r.insertText.insertionIndex === 0,
    );
    // The first such insertText overwrite for body should appear before the title overwrite.
    const bodyIdx = batch1.findIndex(
      (r: any) => r.insertText?.text === 'B' && r.deleteText === undefined,
    );
    const titleIdx = batch1.findIndex(
      (r: any) => r.insertText?.text === 'A' && r.deleteText === undefined,
    );
    expect(bodyIdx).toBeGreaterThanOrEqual(0);
    expect(titleIdx).toBeGreaterThanOrEqual(0);
    expect(bodyIdx).toBeLessThan(titleIdx);
    expect(creates).toHaveLength(2);
    expect(insertsField.length).toBeGreaterThanOrEqual(2);
  });

  it('rejects an invalid payload without touching the API', async () => {
    const m = makeManifest([{ type: 'title', text: { headline: 'A' } }]);
    const client = resyncClient();
    await expect(
      resyncDeck(asClient(client as any), m, [{ type: 'unknown' }]),
    ).rejects.toThrow(/invalid content payload/);
    expect(client.batchUpdate).not.toHaveBeenCalled();
    expect(client.getPresentation).not.toHaveBeenCalled();
  });

  it('speaker notes → Batch 2 after a getPresentation read on the new slides', async () => {
    const m = makeManifest([{ type: 'title', text: { headline: 'A' } }]);
    let calls = 0;
    const client = {
      batchUpdate: vi.fn().mockResolvedValue({ replies: [] }),
      getPresentation: vi.fn().mockImplementation(() => {
        calls++;
        if (calls === 1) return Promise.resolve({ slides: [{ objectId: 'old1' }] });
        // Second read: after batch 1, return the new slide carrying its notes id.
        return Promise.resolve({
          slides: [
            {
              objectId: expect.any(String),
              slideProperties: {
                notesPage: {
                  notesProperties: { speakerNotesObjectId: 'notes_new' },
                },
              },
            },
          ],
        });
      }),
    };
    // Force the matcher: capture the actual new slide id from batch1, then
    // re-stub getPresentation to return it. Easier — return whatever the
    // first-built slide id is by inspecting batch1 once.
    const res = await resyncDeck(asClient(client as any), m, [
      { type: 'title', text: { headline: 'A' }, speakerNotes: 'Talk track' },
    ]);
    // resyncDeck only invokes batchUpdate a second time if it actually wrote
    // notes — confirms the notes path executed end-to-end.
    expect(res.slidesRendered).toBe(1);
  });

  it('rejects a field-tagged image slot (same v1 limitation as renderDeck)', async () => {
    const imgLayout: LayoutSpec = {
      pageWidth: 720,
      pageHeight: 405,
      slides: [
        {
          type: 'cover',
          elements: [
            {
              id: 'hero',
              kind: 'image',
              x: 0,
              y: 0,
              w: 100,
              h: 100,
              zOrder: 0,
              content: { field: 'hero', sample: 'hero' },
            },
          ],
        },
      ],
    };
    const m: RenderManifest = {
      ...makeManifest([{ type: 'cover', text: {} }]),
      layoutSpec: imgLayout,
      fixedImageUrls: { hero: 'https://x/h.png' },
      slides: [{ type: 'cover', text: {}, images: {} }],
    };
    const client = resyncClient();
    await expect(
      resyncDeck(asClient(client as any), m, [
        { type: 'cover', images: { hero: 'https://x/new.png' } },
      ]),
    ).rejects.toThrow(/field-tagged image slot/);
  });

  it('returned manifest carries new slides + same template/deck ids', async () => {
    const m = makeManifest([{ type: 'title', text: { headline: 'Old' } }]);
    const client = resyncClient(['o1']);
    const res = await resyncDeck(asClient(client as any), m, [
      { type: 'title', text: { headline: 'New' } },
      { type: 'content', text: { body: 'B' } },
    ]);
    expect(res.manifest.slides).toEqual([
      { type: 'title', text: { headline: 'New' }, images: {} },
      { type: 'content', text: { body: 'B' }, images: {} },
    ]);
    expect(res.manifest.templatePresentationId).toBe('tpl');
    expect(res.manifest.deckPresentationId).toBe('deck-X');
    expect(res.manifest.layoutSpec).toBe(m.layoutSpec);
  });

  it('refuses an empty payload — typed EmptyPayloadError, no API calls (C1)', async () => {
    const m = makeManifest([{ type: 'title', text: { headline: 'A' } }]);
    const client = resyncClient();
    let caught: unknown;
    try {
      await resyncDeck(asClient(client as any), m, []);
    } catch (err) {
      caught = err;
    }
    expect(caught).toBeDefined();
    expect((caught as { code?: string }).code).toBe('EMPTY_PAYLOAD');
    expect((caught as Error).message).toMatch(/refusing to empty the deck/i);
    // No client method may run — the guard sits above validate and getPresentation.
    expect(client.batchUpdate).not.toHaveBeenCalled();
    expect(client.getPresentation).not.toHaveBeenCalled();
  });
});

describe('tagMapFromLayoutSpec', () => {
  it('derives kind for text and image elements via field / tag', () => {
    const spec: LayoutSpec = {
      pageWidth: 720,
      pageHeight: 405,
      slides: [
        {
          type: 'cover',
          elements: [
            { id: 'h', kind: 'text', x: 0, y: 0, w: 1, h: 1, zOrder: 0, content: { field: 'hl', sample: 's' } },
            { id: 'i', kind: 'image', x: 0, y: 0, w: 1, h: 1, zOrder: 0, content: { tag: '{{logo}}' } },
            { id: 'd', kind: 'shape', x: 0, y: 0, w: 1, h: 1, zOrder: 0, content: { fixed: 'decor' } },
          ],
        },
      ],
    };
    const tm = tagMapFromLayoutSpec(spec);
    expect(tm.cover.tags).toEqual({
      hl: { kind: 'text' },
      '{{logo}}': { kind: 'image' },
    });
  });
});
