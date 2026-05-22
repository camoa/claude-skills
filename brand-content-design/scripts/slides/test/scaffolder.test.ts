import { describe, it, expect, vi } from 'vitest';
import { scaffoldTemplate } from '../src/scaffolder.js';
import type { SlidesClient } from '../src/client.js';
import type { BrandTokens } from '../src/token-mapper.js';
import type { LayoutSpec } from '../src/layout-spec.js';

function fakeClient() {
  return {
    createPresentation: vi.fn().mockResolvedValue({ presentationId: 'pres1' }),
    getPresentation: vi.fn().mockResolvedValue({ slides: [{ objectId: 'p_default' }] }),
    uploadImage: vi
      .fn()
      .mockImplementation((name: string) =>
        Promise.resolve({ fileId: name, url: `https://img/${name}` }),
      ),
    batchUpdate: vi.fn().mockResolvedValue({ replies: [] }),
    findOrCreateFolder: vi
      .fn()
      .mockImplementation((name: string) => Promise.resolve({ folderId: `fold_${name}` })),
    moveFileToFolder: vi.fn().mockResolvedValue(undefined),
  };
}

const tokens: BrandTokens = {
  colors: { primary: '#123456', background: '#FFFFFF', textLight: '#111111', textDark: '#EEEEEE' },
  typography: { headingFont: 'Inter', bodyFont: 'Lora' },
};

const layoutSpec: LayoutSpec = {
  pageWidth: 720,
  pageHeight: 405,
  slides: [
    {
      type: 'Title',
      elements: [
        { id: 't', kind: 'text', x: 60, y: 150, w: 600, h: 100, zOrder: 0, content: { tag: '{{title}}' } },
      ],
    },
    {
      type: 'Content',
      elements: [
        { id: 'b', kind: 'text', x: 60, y: 120, w: 600, h: 200, zOrder: 0, content: { tag: '{{body}}' } },
      ],
    },
  ],
};

const asClient = (c: ReturnType<typeof fakeClient>) => c as unknown as SlidesClient;

describe('scaffoldTemplate', () => {
  it('creates a presentation and returns its id', async () => {
    const client = fakeClient();
    const res = await scaffoldTemplate(asClient(client), tokens, layoutSpec);
    expect(res.presentationId).toBe('pres1');
    expect(client.createPresentation).toHaveBeenCalledOnce();
  });

  it('applies one batchUpdate per slide type plus a cleanup, and records the tag map', async () => {
    const client = fakeClient();
    const res = await scaffoldTemplate(asClient(client), tokens, layoutSpec);
    // 2 slide types + 1 trailing deleteObject cleanup of the seeded blank slide
    expect(client.batchUpdate).toHaveBeenCalledTimes(3);
    expect(res.tagMap.Title).toEqual({
      typeSlideObjectId: 'slide_Title',
      tags: { '{{title}}': { kind: 'text' } },
    });
    expect(res.tagMap.Content.tags).toEqual({ '{{body}}': { kind: 'text' } });
  });

  it('uploads provided images and bakes + uploads gradients', async () => {
    const client = fakeClient();
    await scaffoldTemplate(asClient(client), tokens, layoutSpec, {
      images: { logo: Buffer.from('LOGO') },
      gradients: { bg: { width: 100, height: 50, colors: ['#000000', '#FFFFFF'] } },
    });
    expect(client.uploadImage).toHaveBeenCalledTimes(2); // logo + baked gradient
  });

  it('reports a font substitution for a custom heading font', async () => {
    const client = fakeClient();
    const custom: BrandTokens = {
      ...tokens,
      typography: { headingFont: 'Proxima Nova', bodyFont: 'Lora' },
    };
    const res = await scaffoldTemplate(asClient(client), custom, layoutSpec);
    expect(res.fontSubstitutions).toEqual([
      { role: 'heading', from: 'Proxima Nova', to: 'Inter' },
    ]);
  });

  it('reports no substitutions when both brand fonts are Google Fonts', async () => {
    const res = await scaffoldTemplate(asClient(fakeClient()), tokens, layoutSpec);
    expect(res.fontSubstitutions).toEqual([]);
  });

  it('organises output into a nested Drive folder path when given', async () => {
    const client = fakeClient();
    const res = await scaffoldTemplate(asClient(client), tokens, layoutSpec, {}, {
      driveFolderPath: ['BrandX', 'templates'],
    });
    expect(client.findOrCreateFolder).toHaveBeenCalledTimes(2);
    expect(client.findOrCreateFolder).toHaveBeenNthCalledWith(1, 'BrandX', undefined);
    expect(client.findOrCreateFolder).toHaveBeenNthCalledWith(2, 'templates', 'fold_BrandX');
    expect(client.moveFileToFolder).toHaveBeenCalledWith('pres1', 'fold_templates');
    expect(res.folderId).toBe('fold_templates');
  });

  it('deletes the API-seeded blank default slide once the typed slides exist', async () => {
    const client = fakeClient();
    await scaffoldTemplate(asClient(client), tokens, layoutSpec);
    const calls = client.batchUpdate.mock.calls;
    expect(calls[calls.length - 1][1]).toEqual([
      { deleteObject: { objectId: 'p_default' } },
    ]);
  });

  it('names the created presentation from options.presentationName', async () => {
    const client = fakeClient();
    await scaffoldTemplate(asClient(client), tokens, layoutSpec, {}, {
      presentationName: 'tech-talk — Slides template',
    });
    expect(client.createPresentation).toHaveBeenCalledWith('tech-talk — Slides template');
  });

  it('leaves files in Drive root when no folder path is given', async () => {
    const client = fakeClient();
    const res = await scaffoldTemplate(asClient(client), tokens, layoutSpec);
    expect(client.findOrCreateFolder).not.toHaveBeenCalled();
    expect(client.moveFileToFolder).not.toHaveBeenCalled();
    expect(res.folderId).toBeUndefined();
  });
});
