import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { mkdtempSync, rmSync, writeFileSync, existsSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  readManifest,
  writeManifest,
  manifestPathFor,
  slideFromPayload,
  ManifestCorruptError,
  MANIFEST_SCHEMA,
  type RenderManifest,
} from '../src/render-manifest.js';
import type { LayoutSpec } from '../src/layout-spec.js';
import type { BrandTokens } from '../src/token-mapper.js';

const layoutSpec: LayoutSpec = {
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
          w: 300,
          h: 60,
          zOrder: 0,
          content: { field: 'title', sample: 'Sample Title' },
        },
      ],
    },
  ],
};

const tokens: BrandTokens = {
  colors: {
    primary: '#112233',
    background: '#FFFFFF',
    textLight: '#FFFFFF',
    textDark: '#000000',
  },
  typography: { headingFont: 'Inter', bodyFont: 'Inter' },
};

function makeManifest(): RenderManifest {
  return {
    schema: MANIFEST_SCHEMA,
    templatePresentationId: 'tpl_1',
    deckPresentationId: 'deck_1',
    renderedAt: '2026-05-24T12:00:00.000Z',
    layoutSpec,
    tokens,
    fixedImageUrls: { logo: 'https://example.com/logo.png' },
    fontSubstitutions: [],
    slides: [
      {
        type: 'title',
        text: { title: 'Hello' },
        images: {},
        speakerNotes: 'A note',
      },
    ],
  };
}

describe('render-manifest', () => {
  let dir: string;

  beforeEach(() => {
    dir = mkdtempSync(join(tmpdir(), 'render-manifest-'));
  });

  afterEach(() => {
    rmSync(dir, { recursive: true, force: true });
  });

  it('round-trips a manifest through writeManifest + readManifest', () => {
    const path = join(dir, 'outline.md.render-manifest.json');
    const m = makeManifest();
    writeManifest(path, m);
    expect(readManifest(path)).toEqual(m);
  });

  it('returns null when the manifest file does not exist', () => {
    expect(readManifest(join(dir, 'missing.json'))).toBeNull();
  });

  it('throws ManifestCorruptError on invalid JSON', () => {
    const path = join(dir, 'corrupt.json');
    writeFileSync(path, '{not json', 'utf8');
    expect(() => readManifest(path)).toThrow(ManifestCorruptError);
  });

  it('throws ManifestCorruptError on a wrong schema version', () => {
    const path = join(dir, 'wrong-schema.json');
    writeFileSync(path, JSON.stringify({ ...makeManifest(), schema: 999 }), 'utf8');
    expect(() => readManifest(path)).toThrow(/schema version 999/);
  });

  it('throws ManifestCorruptError when slides is not an array', () => {
    const path = join(dir, 'bad-slides.json');
    writeFileSync(
      path,
      JSON.stringify({ ...makeManifest(), slides: 'oops' }),
      'utf8',
    );
    expect(() => readManifest(path)).toThrow(/"slides" must be an array/);
  });

  it('throws ManifestCorruptError when a slide is missing required keys', () => {
    const m = makeManifest() as unknown as { slides: unknown[] };
    m.slides = [{ type: 'title' }]; // no text/images
    const path = join(dir, 'bad-slide.json');
    writeFileSync(path, JSON.stringify(m), 'utf8');
    expect(() => readManifest(path)).toThrow(/slides\[0\]\.text missing/);
  });

  it('writes atomically — no .tmp file remains after a successful write', () => {
    const path = join(dir, 'atomic.json');
    writeManifest(path, makeManifest());
    expect(existsSync(path)).toBe(true);
    expect(existsSync(`${path}.tmp`)).toBe(false);
  });

  it('manifestPathFor places the sidecar beside the outline', () => {
    expect(manifestPathFor('/a/b/outline.md')).toBe(
      '/a/b/outline.md.render-manifest.json',
    );
  });

  it('slideFromPayload copies text/images and preserves speakerNotes when present', () => {
    expect(
      slideFromPayload({
        type: 't',
        text: { a: 'A' },
        images: { i: 'u' },
        speakerNotes: 'n',
      }),
    ).toEqual({
      type: 't',
      text: { a: 'A' },
      images: { i: 'u' },
      speakerNotes: 'n',
    });
  });

  it('slideFromPayload omits speakerNotes when absent', () => {
    expect(slideFromPayload({ type: 't' })).toEqual({
      type: 't',
      text: {},
      images: {},
    });
  });

  it('produces stable, pretty-printed JSON', () => {
    const path = join(dir, 'pretty.json');
    writeManifest(path, makeManifest());
    const body = readFileSync(path, 'utf8');
    expect(body.endsWith('\n')).toBe(true);
    expect(body).toContain('\n  "schema":');
  });
});
