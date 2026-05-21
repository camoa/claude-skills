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
    expect(client.copyFile).toHaveBeenCalledWith('tmpl1', expect.any(String));
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
    expect(dups[0].duplicateObject.objectIds).toEqual({ slide_Title: 'Title_0' });
    expect(dels).toHaveLength(2); // the two prototype type-slides
  });

  it('page-scopes the fills to each duplicated slide', async () => {
    const client = fakeClient();
    await renderDeck(asClient(client), { presentationId: 'tmpl1', tagMap }, payload);
    const batch1 = client.batchUpdate.mock.calls[0][1];
    const textReq = batch1.find(
      (r: Record<string, any>) => r.replaceAllText?.containsText?.text === '{{body}}',
    );
    expect(textReq.replaceAllText.pageObjectIds).toEqual(['Content_1']);
  });

  it('fills speaker notes from a getPresentation read in a second batch', async () => {
    const client = fakeClient([
      {
        objectId: 'Content_1',
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
});
