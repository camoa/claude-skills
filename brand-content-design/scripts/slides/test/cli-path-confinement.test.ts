/**
 * Path confinement tests for the CLI (C2).
 *
 * Verifies that user-controlled paths flowing through stdin JSON cannot
 * write outside the workspace root nor read arbitrary files. Each case
 * exercises {@link confineManifestPath} / {@link confineReadPath} via the
 * real CLI dispatch (`handleCommand`), so the wiring is also covered.
 */
import { describe, it, expect, vi, afterEach } from 'vitest';
import { mkdtempSync, rmSync, mkdirSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

vi.mock('../src/scaffolder.js', () => ({ scaffoldTemplate: vi.fn() }));
vi.mock('../src/merge-engine.js', () => ({
  renderDeck: vi.fn(),
  resyncDeck: vi.fn(),
  tagMapFromLayoutSpec: vi.fn(() => ({})),
}));

import { handleCommand } from '../src/cli.js';
import { renderDeck } from '../src/merge-engine.js';
import type { SlidesClient } from '../src/client.js';
import {
  confineManifestPath,
  confineReadPath,
} from '../src/path-guard.js';

function fakeClient(): SlidesClient {
  return {
    createPresentation: vi.fn(),
    getPresentation: vi.fn(),
    batchUpdate: vi.fn(),
    copyFile: vi.fn(),
    exportFile: vi.fn(),
    getPageThumbnail: vi.fn(),
    replaceAllText: vi.fn(),
    replaceAllShapesWithImage: vi.fn(),
  } as unknown as SlidesClient;
}

afterEach(() => {
  delete process.env.BCD_SLIDES_WORKSPACE;
});

describe('confineManifestPath (unit)', () => {
  it('rejects a path with the wrong extension', () => {
    const dir = mkdtempSync(join(tmpdir(), 'pg-ext-'));
    process.env.BCD_SLIDES_WORKSPACE = dir;
    expect(() => confineManifestPath(join(dir, 'outline.md.json'))).toThrow(
      /INVALID_PATH|render-manifest\.json/,
    );
    rmSync(dir, { recursive: true, force: true });
  });

  it('rejects path traversal that escapes the workspace', () => {
    const ws = mkdtempSync(join(tmpdir(), 'pg-ws-'));
    const outside = mkdtempSync(join(tmpdir(), 'pg-outside-'));
    process.env.BCD_SLIDES_WORKSPACE = ws;
    // .. from ws lands in tmpdir, then into a sibling outside dir.
    const escape = join(ws, '..', outside.split('/').pop()!, 'x.render-manifest.json');
    expect(() => confineManifestPath(escape)).toThrow(/outside the workspace root/);
    rmSync(ws, { recursive: true, force: true });
    rmSync(outside, { recursive: true, force: true });
  });

  it('rejects a symlinked parent dir that escapes the workspace', () => {
    const ws = mkdtempSync(join(tmpdir(), 'pg-symws-'));
    const outside = mkdtempSync(join(tmpdir(), 'pg-symout-'));
    process.env.BCD_SLIDES_WORKSPACE = ws;
    const linkPath = join(ws, 'sneaky');
    symlinkSync(outside, linkPath);
    expect(() =>
      confineManifestPath(join(linkPath, 'm.render-manifest.json')),
    ).toThrow(/outside the workspace root/);
    rmSync(ws, { recursive: true, force: true });
    rmSync(outside, { recursive: true, force: true });
  });

  it('accepts a path under the workspace whose file does not yet exist', () => {
    const ws = mkdtempSync(join(tmpdir(), 'pg-ok-'));
    process.env.BCD_SLIDES_WORKSPACE = ws;
    const p = join(ws, 'new.render-manifest.json');
    expect(() => confineManifestPath(p)).not.toThrow();
    rmSync(ws, { recursive: true, force: true });
  });

  it('rejects when the parent dir does not exist', () => {
    const ws = mkdtempSync(join(tmpdir(), 'pg-noparent-'));
    process.env.BCD_SLIDES_WORKSPACE = ws;
    expect(() =>
      confineManifestPath(join(ws, 'missing', 'sub', 'x.render-manifest.json')),
    ).toThrow(/parent directory/);
    rmSync(ws, { recursive: true, force: true });
  });
});

describe('confineReadPath (unit)', () => {
  it('rejects a file that does not exist', () => {
    const ws = mkdtempSync(join(tmpdir(), 'pg-read-noent-'));
    process.env.BCD_SLIDES_WORKSPACE = ws;
    expect(() =>
      confineReadPath(join(ws, 'nope.png'), 'imagePaths["logo"]'),
    ).toThrow(/does not exist/);
    rmSync(ws, { recursive: true, force: true });
  });

  it('rejects a real file that resolves outside the workspace', () => {
    const ws = mkdtempSync(join(tmpdir(), 'pg-read-ws-'));
    const outside = mkdtempSync(join(tmpdir(), 'pg-read-out-'));
    process.env.BCD_SLIDES_WORKSPACE = ws;
    const f = join(outside, 'evil.png');
    writeFileSync(f, 'x');
    expect(() => confineReadPath(f, 'customFontFile')).toThrow(
      /outside the workspace root/,
    );
    rmSync(ws, { recursive: true, force: true });
    rmSync(outside, { recursive: true, force: true });
  });

  it('accepts a file under the workspace', () => {
    const ws = mkdtempSync(join(tmpdir(), 'pg-read-ok-'));
    process.env.BCD_SLIDES_WORKSPACE = ws;
    const f = join(ws, 'logo.png');
    writeFileSync(f, 'x');
    expect(confineReadPath(f, 'imagePaths["logo"]')).toBe(f);
    rmSync(ws, { recursive: true, force: true });
  });
});

describe('CLI dispatch — INVALID_PATH envelope (C2)', () => {
  it('renderDeck rejects an out-of-workspace manifestPath', async () => {
    const ws = mkdtempSync(join(tmpdir(), 'cli-pg-ws-'));
    const outside = mkdtempSync(join(tmpdir(), 'cli-pg-out-'));
    process.env.BCD_SLIDES_WORKSPACE = ws;
    const env = await handleCommand(fakeClient(), {
      command: 'renderDeck',
      args: {
        templatePresentationId: 'tpl',
        tagMap: { t: { typeSlideObjectId: 's', tags: {} } },
        payload: [{ type: 't', text: {} }],
        manifestPath: join(outside, 'x.render-manifest.json'),
        layoutSpec: { pageWidth: 0, pageHeight: 0, slides: [] },
        tokens: {
          colors: { primary: '#0', background: '#f', textLight: '#f', textDark: '#0' },
          typography: { headingFont: 'I', bodyFont: 'I' },
        },
        fixedImageUrls: {},
      },
    });
    expect(env.ok).toBe(false);
    if (!env.ok) expect(env.error.code).toBe('INVALID_PATH');
    // renderDeck must NOT be called when path confinement rejects.
    expect(renderDeck).not.toHaveBeenCalled();
    rmSync(ws, { recursive: true, force: true });
    rmSync(outside, { recursive: true, force: true });
  });

  it('renderDeck rejects a manifestPath with the wrong extension', async () => {
    const ws = mkdtempSync(join(tmpdir(), 'cli-pg-ext-'));
    process.env.BCD_SLIDES_WORKSPACE = ws;
    const env = await handleCommand(fakeClient(), {
      command: 'renderDeck',
      args: {
        templatePresentationId: 'tpl',
        tagMap: { t: { typeSlideObjectId: 's', tags: {} } },
        payload: [{ type: 't', text: {} }],
        manifestPath: join(ws, 'wrong.json'),
        layoutSpec: { pageWidth: 0, pageHeight: 0, slides: [] },
        tokens: {
          colors: { primary: '#0', background: '#f', textLight: '#f', textDark: '#0' },
          typography: { headingFont: 'I', bodyFont: 'I' },
        },
        fixedImageUrls: {},
      },
    });
    expect(env.ok).toBe(false);
    if (!env.ok) expect(env.error.code).toBe('INVALID_PATH');
    rmSync(ws, { recursive: true, force: true });
  });

  it('scaffoldTemplate rejects an out-of-workspace imagePath value', async () => {
    const ws = mkdtempSync(join(tmpdir(), 'cli-pg-img-ws-'));
    const outside = mkdtempSync(join(tmpdir(), 'cli-pg-img-out-'));
    process.env.BCD_SLIDES_WORKSPACE = ws;
    const evilFile = join(outside, 'evil.png');
    writeFileSync(evilFile, 'x');
    const env = await handleCommand(fakeClient(), {
      command: 'scaffoldTemplate',
      args: {
        tokens: {
          colors: { primary: '#0', background: '#f', textLight: '#f', textDark: '#0' },
          typography: { headingFont: 'I', bodyFont: 'I' },
        },
        imagePaths: { logo: evilFile },
      },
    });
    expect(env.ok).toBe(false);
    if (!env.ok) expect(env.error.code).toBe('INVALID_PATH');
    rmSync(ws, { recursive: true, force: true });
    rmSync(outside, { recursive: true, force: true });
  });
});
