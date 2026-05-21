import { describe, it, expect, vi } from 'vitest';
import { SlidesClient } from '../src/client.js';
import type { SlidesServices } from '../src/types.js';

/** Build a fake SlidesServices; each method is a vi.fn() the test configures. */
function fakeServices() {
  return {
    slides: {
      presentations: {
        create: vi.fn(),
        get: vi.fn(),
        batchUpdate: vi.fn(),
        pages: { getThumbnail: vi.fn() },
      },
    },
    drive: {
      files: { copy: vi.fn(), export: vi.fn(), create: vi.fn() },
      permissions: { create: vi.fn() },
    },
  };
}

/** A SlidesClient over fakes, with a no-op sleep so retry paths never wait. */
function client(services: ReturnType<typeof fakeServices>) {
  return new SlidesClient(services as unknown as SlidesServices, {
    sleep: vi.fn().mockResolvedValue(undefined),
  });
}

describe('SlidesClient.createPresentation', () => {
  it('creates and returns the presentationId', async () => {
    const s = fakeServices();
    s.slides.presentations.create.mockResolvedValue({ data: { presentationId: 'p1' } });
    await expect(client(s).createPresentation('Deck')).resolves.toEqual({
      presentationId: 'p1',
    });
    expect(s.slides.presentations.create).toHaveBeenCalledWith({
      requestBody: { title: 'Deck' },
    });
  });

  it('throws when the API returns no presentationId', async () => {
    const s = fakeServices();
    s.slides.presentations.create.mockResolvedValue({ data: {} });
    await expect(client(s).createPresentation('Deck')).rejects.toThrow();
  });
});

describe('SlidesClient.getPresentation', () => {
  it('returns the presentation resource', async () => {
    const s = fakeServices();
    s.slides.presentations.get.mockResolvedValue({ data: { presentationId: 'p1', slides: [] } });
    await expect(client(s).getPresentation('p1')).resolves.toEqual({
      presentationId: 'p1',
      slides: [],
    });
  });
});

describe('SlidesClient.batchUpdate', () => {
  it('passes requests through and returns replies', async () => {
    const s = fakeServices();
    s.slides.presentations.batchUpdate.mockResolvedValue({ data: { replies: [{}, {}] } });
    const reqs = [{ createSlide: {} }];
    await expect(client(s).batchUpdate('p1', reqs)).resolves.toEqual({ replies: [{}, {}] });
    expect(s.slides.presentations.batchUpdate).toHaveBeenCalledWith({
      presentationId: 'p1',
      requestBody: { requests: reqs },
    });
  });

  it('defaults replies to [] when the API omits them', async () => {
    const s = fakeServices();
    s.slides.presentations.batchUpdate.mockResolvedValue({ data: {} });
    await expect(client(s).batchUpdate('p1', [])).resolves.toEqual({ replies: [] });
  });

  it('propagates an API rejection (atomic failure)', async () => {
    const s = fakeServices();
    s.slides.presentations.batchUpdate.mockRejectedValue(
      Object.assign(new Error('Invalid requests[0]'), { response: { status: 400 } }),
    );
    await expect(client(s).batchUpdate('p1', [{}])).rejects.toThrow('Invalid requests[0]');
  });
});

describe('SlidesClient.copyFile', () => {
  it('copies a file and returns the new id', async () => {
    const s = fakeServices();
    s.drive.files.copy.mockResolvedValue({ data: { id: 'f2' } });
    await expect(client(s).copyFile('f1', 'Copy')).resolves.toEqual({ fileId: 'f2' });
    expect(s.drive.files.copy).toHaveBeenCalledWith({
      fileId: 'f1',
      requestBody: { name: 'Copy' },
    });
  });

  it('passes a parent folder when supplied', async () => {
    const s = fakeServices();
    s.drive.files.copy.mockResolvedValue({ data: { id: 'f2' } });
    await client(s).copyFile('f1', 'Copy', 'folder1');
    expect(s.drive.files.copy).toHaveBeenCalledWith({
      fileId: 'f1',
      requestBody: { name: 'Copy', parents: ['folder1'] },
    });
  });
});

describe('SlidesClient.exportFile', () => {
  it('exports to a Buffer', async () => {
    const s = fakeServices();
    s.drive.files.export.mockResolvedValue({ data: new TextEncoder().encode('PDF').buffer });
    const buf = await client(s).exportFile('f1', 'application/pdf');
    expect(Buffer.isBuffer(buf)).toBe(true);
    expect(buf.toString()).toBe('PDF');
  });
});

describe('SlidesClient.getPageThumbnail', () => {
  it('returns the thumbnail contentUrl', async () => {
    const s = fakeServices();
    s.slides.presentations.pages.getThumbnail.mockResolvedValue({
      data: { contentUrl: 'https://thumb/1.png' },
    });
    await expect(client(s).getPageThumbnail('p1', 'slide1')).resolves.toEqual({
      contentUrl: 'https://thumb/1.png',
    });
  });
});

describe('SlidesClient.replaceAllText', () => {
  it('maps occurrencesChanged back to each tag by request order', async () => {
    const s = fakeServices();
    s.slides.presentations.batchUpdate.mockResolvedValue({
      data: {
        replies: [
          { replaceAllText: { occurrencesChanged: 2 } },
          { replaceAllText: { occurrencesChanged: 0 } },
        ],
      },
    });
    await expect(
      client(s).replaceAllText('p1', { '{{a}}': 'A', '{{b}}': 'B' }),
    ).resolves.toEqual({ occurrencesByTag: { '{{a}}': 2, '{{b}}': 0 } });
  });

  it('skips the API call entirely for an empty tag map', async () => {
    const s = fakeServices();
    await expect(client(s).replaceAllText('p1', {})).resolves.toEqual({
      occurrencesByTag: {},
    });
    expect(s.slides.presentations.batchUpdate).not.toHaveBeenCalled();
  });

  it('forwards pageObjectIds into the batchUpdate request (per-slide-instance fill)', async () => {
    const s = fakeServices();
    s.slides.presentations.batchUpdate.mockResolvedValue({
      data: { replies: [{ replaceAllText: { occurrencesChanged: 1 } }] },
    });
    await client(s).replaceAllText('p1', { '{{body}}': 'B' }, ['slide3']);
    const sent = s.slides.presentations.batchUpdate.mock.calls[0][0];
    expect(sent.requestBody.requests[0].replaceAllText.pageObjectIds).toEqual(['slide3']);
  });
});

describe('SlidesClient.replaceAllShapesWithImage', () => {
  it('maps occurrencesChanged from replaceAllShapesWithImage replies', async () => {
    const s = fakeServices();
    s.slides.presentations.batchUpdate.mockResolvedValue({
      data: { replies: [{ replaceAllShapesWithImage: { occurrencesChanged: 1 } }] },
    });
    await expect(
      client(s).replaceAllShapesWithImage('p1', { '{{logo}}': 'https://img/l.png' }),
    ).resolves.toEqual({ occurrencesByTag: { '{{logo}}': 1 } });
  });
});

describe('SlidesClient.uploadImage', () => {
  it('uploads bytes to Drive, makes the file link-readable, returns a fetch URL', async () => {
    const s = fakeServices();
    s.drive.files.create.mockResolvedValue({ data: { id: 'img1' } });
    s.drive.permissions.create.mockResolvedValue({ data: {} });
    const res = await client(s).uploadImage('logo.png', Buffer.from('PNG'));
    expect(res).toEqual({
      fileId: 'img1',
      url: 'https://drive.google.com/uc?export=view&id=img1',
    });
    expect(s.drive.permissions.create).toHaveBeenCalledWith({
      fileId: 'img1',
      requestBody: { role: 'reader', type: 'anyone' },
    });
  });

  it('throws when Drive returns no file id for the upload', async () => {
    const s = fakeServices();
    s.drive.files.create.mockResolvedValue({ data: {} });
    await expect(client(s).uploadImage('x.png', Buffer.from('x'))).rejects.toThrow();
  });
});

describe('SlidesClient retry integration', () => {
  it('retries a 429 then succeeds', async () => {
    const s = fakeServices();
    s.slides.presentations.create
      .mockRejectedValueOnce(Object.assign(new Error('429'), { response: { status: 429 } }))
      .mockResolvedValue({ data: { presentationId: 'p1' } });
    await expect(client(s).createPresentation('Deck')).resolves.toEqual({
      presentationId: 'p1',
    });
    expect(s.slides.presentations.create).toHaveBeenCalledTimes(2);
  });
});
