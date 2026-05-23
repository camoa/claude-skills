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
