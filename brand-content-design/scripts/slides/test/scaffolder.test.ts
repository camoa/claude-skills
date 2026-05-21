import { describe, it, expect, vi } from 'vitest';
import { scaffoldTemplate } from '../src/scaffolder.js';
import type { SlidesClient } from '../src/client.js';
import type { BrandTokens } from '../src/token-mapper.js';
import type { LayoutSpec } from '../src/layout-spec.js';

function fakeClient() {
  return {
    createPresentation: vi.fn().mockResolvedValue({ presentationId: 'pres1' }),
    uploadImage: vi
      .fn()
      .mockImplementation((name: string) =>
        Promise.resolve({ fileId: name, url: `https://img/${name}` }),
      ),
    batchUpdate: vi.fn().mockResolvedValue({ replies: [] }),
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

  it('applies one batchUpdate per slide type and records the tag map', async () => {
    const client = fakeClient();
    const res = await scaffoldTemplate(asClient(client), tokens, layoutSpec);
    expect(client.batchUpdate).toHaveBeenCalledTimes(2);
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
});
