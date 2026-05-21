import { describe, it, expect, vi } from 'vitest';
import { handleCommand, parseCommandDoc } from '../src/cli.js';
import type { SlidesClient } from '../src/client.js';

/** A fake SlidesClient — every method a vi.fn(), overridable per test. */
function fakeClient(overrides: Record<string, unknown> = {}): SlidesClient {
  return {
    createPresentation: vi.fn(),
    getPresentation: vi.fn(),
    batchUpdate: vi.fn(),
    copyFile: vi.fn(),
    exportFile: vi.fn(),
    getPageThumbnail: vi.fn(),
    replaceAllText: vi.fn(),
    replaceAllShapesWithImage: vi.fn(),
    ...overrides,
  } as unknown as SlidesClient;
}

describe('parseCommandDoc', () => {
  it('parses a valid command document', () => {
    expect(
      parseCommandDoc('{"command":"getPresentation","args":{"presentationId":"p1"}}'),
    ).toEqual({ command: 'getPresentation', args: { presentationId: 'p1' } });
  });

  it('defaults args to {} when omitted', () => {
    expect(parseCommandDoc('{"command":"createPresentation"}')).toEqual({
      command: 'createPresentation',
      args: {},
    });
  });

  it('throws on invalid JSON', () => {
    expect(() => parseCommandDoc('not json')).toThrow();
  });

  it('throws when the command field is missing', () => {
    expect(() => parseCommandDoc('{"args":{}}')).toThrow();
  });
});

describe('handleCommand', () => {
  it('dispatches createPresentation and wraps the result in an ok envelope', async () => {
    const client = fakeClient({
      createPresentation: vi.fn().mockResolvedValue({ presentationId: 'p1' }),
    });
    const env = await handleCommand(client, {
      command: 'createPresentation',
      args: { title: 'Deck' },
    });
    expect(env).toEqual({ ok: true, result: { presentationId: 'p1' } });
    expect(client.createPresentation).toHaveBeenCalledWith('Deck');
  });

  it('returns a BAD_COMMAND envelope for an unknown command', async () => {
    const env = await handleCommand(fakeClient(), { command: 'frobnicate', args: {} });
    expect(env.ok).toBe(false);
    if (!env.ok) expect(env.error.code).toBe('BAD_COMMAND');
  });

  it('returns a BAD_COMMAND envelope when a required arg is missing', async () => {
    const env = await handleCommand(fakeClient(), {
      command: 'createPresentation',
      args: {},
    });
    expect(env.ok).toBe(false);
    if (!env.ok) expect(env.error.code).toBe('BAD_COMMAND');
  });

  it('normalizes a client failure into an error envelope', async () => {
    const client = fakeClient({
      batchUpdate: vi.fn().mockRejectedValue(
        Object.assign(new Error('Invalid requests[0]'), {
          response: {
            status: 400,
            data: { error: { status: 'INVALID_ARGUMENT', message: 'bad request' } },
          },
        }),
      ),
    });
    const env = await handleCommand(client, {
      command: 'batchUpdate',
      args: { presentationId: 'p1', requests: [{}] },
    });
    expect(env.ok).toBe(false);
    if (!env.ok) {
      expect(env.error.code).toBe('INVALID_ARGUMENT');
      expect(env.error.message).toBe('bad request');
    }
  });

  it('base64-encodes exportFile output for the JSON envelope', async () => {
    const client = fakeClient({
      exportFile: vi.fn().mockResolvedValue(Buffer.from('PDFDATA')),
    });
    const env = await handleCommand(client, {
      command: 'exportFile',
      args: { fileId: 'f1', mimeType: 'application/pdf' },
    });
    expect(env).toEqual({
      ok: true,
      result: { base64: Buffer.from('PDFDATA').toString('base64') },
    });
  });

  it('rejects a mimeType outside the allowed export set', async () => {
    const env = await handleCommand(fakeClient(), {
      command: 'exportFile',
      args: { fileId: 'f1', mimeType: 'text/plain' },
    });
    expect(env.ok).toBe(false);
    if (!env.ok) expect(env.error.code).toBe('BAD_COMMAND');
  });

  it('dispatches replaceAllText with its tag map (no scope → undefined)', async () => {
    const client = fakeClient({
      replaceAllText: vi.fn().mockResolvedValue({ occurrencesByTag: { '{{a}}': 1 } }),
    });
    await handleCommand(client, {
      command: 'replaceAllText',
      args: { presentationId: 'p1', tagMap: { '{{a}}': 'A' } },
    });
    expect(client.replaceAllText).toHaveBeenCalledWith('p1', { '{{a}}': 'A' }, undefined);
  });

  it('forwards pageObjectIds to replaceAllText for per-slide-instance fills', async () => {
    const client = fakeClient({
      replaceAllText: vi.fn().mockResolvedValue({ occurrencesByTag: {} }),
    });
    await handleCommand(client, {
      command: 'replaceAllText',
      args: { presentationId: 'p1', tagMap: { '{{a}}': 'A' }, pageObjectIds: ['s1'] },
    });
    expect(client.replaceAllText).toHaveBeenCalledWith('p1', { '{{a}}': 'A' }, ['s1']);
  });

  it('rejects a pageObjectIds that is not an array of strings', async () => {
    const env = await handleCommand(fakeClient(), {
      command: 'replaceAllText',
      args: { presentationId: 'p1', tagMap: { '{{a}}': 'A' }, pageObjectIds: 's1' },
    });
    expect(env.ok).toBe(false);
    if (!env.ok) expect(env.error.code).toBe('BAD_COMMAND');
  });

  it('rejects a tag map whose values are not all strings', async () => {
    const env = await handleCommand(fakeClient(), {
      command: 'replaceAllText',
      args: { presentationId: 'p1', tagMap: { '{{a}}': 42 } },
    });
    expect(env.ok).toBe(false);
    if (!env.ok) expect(env.error.code).toBe('BAD_COMMAND');
  });
});
