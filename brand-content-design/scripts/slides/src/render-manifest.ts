/**
 * Render manifest — sidecar JSON beside the outline source recording what was
 * rendered and the inputs needed to resync it in place on the same deck.
 *
 * The manifest is the resync layer's source of truth. A `resyncDeck` call
 * reads the prior manifest, diffs it against the new payload, rebuilds slides
 * on the **same** `deckPresentationId` (the user-visible file/URL is
 * preserved), and rewrites the manifest.
 *
 * Pure I/O: `readManifest` + `writeManifest`. Atomic write via temp-file +
 * rename so a crash mid-write never leaves a half-written manifest.
 */
import {
  readFileSync,
  writeFileSync,
  renameSync,
  existsSync,
  unlinkSync,
} from 'node:fs';
import { dirname, basename, join } from 'node:path';
import type { LayoutSpec } from './layout-spec.js';
import type { BrandTokens } from './token-mapper.js';
import type { ContentSlide } from './payload-validator.js';
import type { FontSubstitution } from './merge-engine.js';

/** The current manifest schema version. Bump on any breaking shape change. */
export const MANIFEST_SCHEMA = 1;

/** One slide as recorded in the manifest. Splits payload `ContentSlide`. */
export interface ManifestSlide {
  /** `SlideType` — same vocabulary as the tag map and outline parser. */
  type: string;
  /** Field tag → text value. Empty `{}` is fine. */
  text: Record<string, string>;
  /** Field tag → image URL. Empty `{}` is fine. */
  images: Record<string, string>;
  /** Speaker-notes body, when present. */
  speakerNotes?: string;
}

/**
 * The full render manifest. `layoutSpec`, `tokens`, and `fixedImageUrls` are
 * everything resync needs to rebuild a slide in place via `buildSlideRequests`
 * — the resync code path does NOT have the template to duplicate from, so it
 * has to reconstruct from these inputs.
 */
export interface RenderManifest {
  schema: typeof MANIFEST_SCHEMA;
  /** Template the deck was originally rendered from (informational; not used at resync). */
  templatePresentationId: string;
  /** The deck — preserved across resyncs so the user-visible URL is stable. */
  deckPresentationId: string;
  /** ISO-8601 timestamp of the last render or resync. */
  renderedAt: string;
  /** The layout IR used at render time. */
  layoutSpec: LayoutSpec;
  /** Brand tokens used at render time. */
  tokens: BrandTokens;
  /**
   * Resolved URLs for fixed (chrome) image elements, keyed by layout element
   * id. `buildSlideRequests` needs these at resync time.
   */
  fixedImageUrls: Record<string, string>;
  /** Font substitutions carried from the scaffolder (empty array OK). */
  fontSubstitutions: FontSubstitution[];
  /** The rendered outline, slide by slide. */
  slides: ManifestSlide[];
}

/** Manifest path convention: `<outline>.render-manifest.json` beside the source. */
export function manifestPathFor(outlinePath: string): string {
  return join(dirname(outlinePath), `${basename(outlinePath)}.render-manifest.json`);
}

/** A typed corrupt-manifest error so callers can distinguish from `null`. */
export class ManifestCorruptError extends Error {
  readonly code = 'MANIFEST_CORRUPT';
  constructor(
    readonly path: string,
    readonly reason: string,
  ) {
    super(`Render manifest at ${path} is corrupt: ${reason}`);
    this.name = 'ManifestCorruptError';
  }
}

/**
 * Read a manifest from disk. Returns `null` when the file does not exist
 * (first render); throws {@link ManifestCorruptError} when the file exists
 * but cannot be parsed into a valid {@link RenderManifest}.
 */
export function readManifest(path: string): RenderManifest | null {
  if (!existsSync(path)) return null;
  let raw: string;
  try {
    raw = readFileSync(path, 'utf8');
  } catch (err) {
    throw new ManifestCorruptError(path, `unreadable (${(err as Error).message})`);
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch (err) {
    throw new ManifestCorruptError(path, `not valid JSON (${(err as Error).message})`);
  }
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw new ManifestCorruptError(path, 'top-level value is not an object');
  }
  const m = parsed as Record<string, unknown>;
  if (m.schema !== MANIFEST_SCHEMA) {
    throw new ManifestCorruptError(
      path,
      `schema version ${String(m.schema)} (expected ${MANIFEST_SCHEMA})`,
    );
  }
  for (const key of [
    'templatePresentationId',
    'deckPresentationId',
    'renderedAt',
  ] as const) {
    if (typeof m[key] !== 'string' || m[key] === '') {
      throw new ManifestCorruptError(path, `missing/invalid string "${key}"`);
    }
  }
  if (!m.layoutSpec || typeof m.layoutSpec !== 'object') {
    throw new ManifestCorruptError(path, 'missing/invalid "layoutSpec"');
  }
  if (!m.tokens || typeof m.tokens !== 'object') {
    throw new ManifestCorruptError(path, 'missing/invalid "tokens"');
  }
  if (!m.fixedImageUrls || typeof m.fixedImageUrls !== 'object') {
    throw new ManifestCorruptError(path, 'missing/invalid "fixedImageUrls"');
  }
  if (!Array.isArray(m.fontSubstitutions)) {
    throw new ManifestCorruptError(path, '"fontSubstitutions" must be an array');
  }
  if (!Array.isArray(m.slides)) {
    throw new ManifestCorruptError(path, '"slides" must be an array');
  }
  for (let i = 0; i < m.slides.length; i++) {
    const s = m.slides[i] as Record<string, unknown> | undefined;
    if (!s || typeof s !== 'object') {
      throw new ManifestCorruptError(path, `slides[${i}] is not an object`);
    }
    if (typeof s.type !== 'string' || s.type === '') {
      throw new ManifestCorruptError(path, `slides[${i}].type missing`);
    }
    if (!s.text || typeof s.text !== 'object') {
      throw new ManifestCorruptError(path, `slides[${i}].text missing`);
    }
    if (!s.images || typeof s.images !== 'object') {
      throw new ManifestCorruptError(path, `slides[${i}].images missing`);
    }
  }
  return parsed as RenderManifest;
}

/**
 * Write a manifest atomically: write to `<path>.tmp` then rename onto `path`.
 * `rename` is atomic on POSIX, so an interrupted write leaves the prior
 * manifest intact instead of a half-written file.
 */
export function writeManifest(path: string, manifest: RenderManifest): void {
  const tmp = `${path}.tmp`;
  const body = `${JSON.stringify(manifest, null, 2)}\n`;
  writeFileSync(tmp, body, 'utf8');
  try {
    renameSync(tmp, path);
  } catch (err) {
    // Best-effort cleanup; surface the rename failure.
    try {
      unlinkSync(tmp);
    } catch {
      /* ignore */
    }
    throw err;
  }
}

/** Compose a fresh `ManifestSlide` from a payload entry. */
export function slideFromPayload(slide: ContentSlide): ManifestSlide {
  return {
    type: slide.type,
    text: { ...(slide.text ?? {}) },
    images: { ...(slide.images ?? {}) },
    ...(slide.speakerNotes !== undefined
      ? { speakerNotes: slide.speakerNotes }
      : {}),
  };
}
