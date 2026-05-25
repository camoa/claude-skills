#!/usr/bin/env node
/**
 * CLI entry point — a thin stdin-JSON → stdout-envelope adapter over
 * {@link SlidesClient}. No business logic lives here: `dispatch` routes a
 * command to a client method, `handleCommand` wraps the outcome in a
 * {@link ResultEnvelope}, and `main` is stream/credential plumbing.
 *
 * Input  (stdin):  { "command": "<name>", "args": { ... } }
 * Output (stdout): { "ok": true, "result": ... }
 *                | { "ok": false, "error": { code, message, failedRequest? } }
 */
import { pathToFileURL } from 'node:url';
import { google, type slides_v1 } from 'googleapis';
import type {
  CommandDoc,
  ResultEnvelope,
  TagMap,
  ExportMimeType,
  SlidesServices,
} from './types.js';
import { readFileSync } from 'node:fs';
import { SlidesClient } from './client.js';
import { resolveAuthConfig, createAuthClient } from './auth.js';
import { normalizeError } from './errors.js';
import type { BrandTokens } from './token-mapper.js';
import type { LayoutSpec, TagMap as LayoutTagMap } from './layout-spec.js';
import type { GradientSpec } from './image-baker.js';
import type { ContentPayload } from './payload-validator.js';
import type { FontSubstitution } from './merge-engine.js';
import { scaffoldTemplate } from './scaffolder.js';
import {
  renderDeck,
  resyncDeck,
  tagMapFromLayoutSpec,
} from './merge-engine.js';
import { buildDefaultLayout } from './default-layout.js';
import { parseOutline, toContentPayload } from './outline-parser.js';
import {
  readManifest,
  writeManifest,
  slideFromPayload,
  MANIFEST_SCHEMA,
  type RenderManifest,
} from './render-manifest.js';
import { confineManifestPath, confineReadPath } from './path-guard.js';

/** A bad command document or argument. Carries a stable `code`. */
class CommandError extends Error {
  readonly code = 'BAD_COMMAND';
  constructor(message: string) {
    super(message);
    this.name = 'CommandError';
  }
}

/** Parse + shape-check a raw stdin string into a {@link CommandDoc}. */
export function parseCommandDoc(raw: string): CommandDoc {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new CommandError('Command input is not valid JSON.');
  }
  if (!parsed || typeof parsed !== 'object') {
    throw new CommandError('Command input must be a JSON object.');
  }
  const obj = parsed as Record<string, unknown>;
  if (typeof obj.command !== 'string' || obj.command === '') {
    throw new CommandError('Command document is missing a "command" string.');
  }
  if (
    obj.args !== undefined &&
    (typeof obj.args !== 'object' || obj.args === null || Array.isArray(obj.args))
  ) {
    throw new CommandError('Command "args" must be an object when present.');
  }
  return {
    command: obj.command,
    args: (obj.args as Record<string, unknown> | undefined) ?? {},
  };
}

/* --- argument validators (all throw CommandError on bad input) --- */

function reqString(args: Record<string, unknown>, key: string): string {
  const v = args[key];
  if (typeof v !== 'string' || v === '') {
    throw new CommandError(`Missing or invalid string argument "${key}".`);
  }
  return v;
}

function optString(
  args: Record<string, unknown>,
  key: string,
): string | undefined {
  const v = args[key];
  if (v === undefined) return undefined;
  if (typeof v !== 'string') {
    throw new CommandError(`Argument "${key}" must be a string when present.`);
  }
  return v;
}

function optStringArray(
  args: Record<string, unknown>,
  key: string,
): string[] | undefined {
  const v = args[key];
  if (v === undefined) return undefined;
  if (!Array.isArray(v) || !v.every((x) => typeof x === 'string')) {
    throw new CommandError(
      `Argument "${key}" must be an array of strings when present.`,
    );
  }
  return v as string[];
}

function reqArray(
  args: Record<string, unknown>,
  key: string,
): slides_v1.Schema$Request[] {
  const v = args[key];
  if (!Array.isArray(v)) {
    throw new CommandError(`Missing or invalid array argument "${key}".`);
  }
  return v as slides_v1.Schema$Request[];
}

function reqTagMap(args: Record<string, unknown>, key: string): TagMap {
  const v = args[key];
  if (!v || typeof v !== 'object' || Array.isArray(v)) {
    throw new CommandError(`Missing or invalid object argument "${key}".`);
  }
  for (const [tag, value] of Object.entries(v)) {
    if (typeof value !== 'string') {
      throw new CommandError(
        `Tag map "${key}" values must be strings ("${tag}" is not).`,
      );
    }
  }
  return v as TagMap;
}

function reqExportMime(
  args: Record<string, unknown>,
  key: string,
): ExportMimeType {
  const v = reqString(args, key);
  if (v !== 'application/pdf' && v !== 'image/png') {
    throw new CommandError(
      `Argument "${key}" must be "application/pdf" or "image/png".`,
    );
  }
  return v;
}

/** Require an object-valued argument (not array, not null). */
function reqObject(
  args: Record<string, unknown>,
  key: string,
): Record<string, unknown> {
  const v = args[key];
  if (!v || typeof v !== 'object' || Array.isArray(v)) {
    throw new CommandError(`Missing or invalid object argument "${key}".`);
  }
  return v as Record<string, unknown>;
}

/** Optional object-valued argument. */
function optObject(
  args: Record<string, unknown>,
  key: string,
): Record<string, unknown> | undefined {
  if (args[key] === undefined) return undefined;
  return reqObject(args, key);
}

/** Optional `Record<string,string>` argument (e.g. element id → file path). */
function optStringMap(
  args: Record<string, unknown>,
  key: string,
): Record<string, string> | undefined {
  const v = optObject(args, key);
  if (v === undefined) return undefined;
  for (const [k, val] of Object.entries(v)) {
    if (typeof val !== 'string') {
      throw new CommandError(
        `Argument "${key}" values must be strings ("${k}" is not).`,
      );
    }
  }
  return v as Record<string, string>;
}

/** Require an array argument of unknown element type. */
function reqUnknownArray(args: Record<string, unknown>, key: string): unknown[] {
  const v = args[key];
  if (!Array.isArray(v)) {
    throw new CommandError(`Missing or invalid array argument "${key}".`);
  }
  return v;
}

/** Optional array-of-objects argument. */
function optObjectArray(
  args: Record<string, unknown>,
  key: string,
): Record<string, unknown>[] | undefined {
  const v = args[key];
  if (v === undefined) return undefined;
  if (
    !Array.isArray(v) ||
    !v.every((x) => !!x && typeof x === 'object' && !Array.isArray(x))
  ) {
    throw new CommandError(
      `Argument "${key}" must be an array of objects when present.`,
    );
  }
  return v as Record<string, unknown>[];
}

/** Route a command document to the matching SlidesClient method. */
async function dispatch(client: SlidesClient, doc: CommandDoc): Promise<unknown> {
  const a = doc.args;
  switch (doc.command) {
    case 'createPresentation':
      return client.createPresentation(reqString(a, 'title'));
    case 'getPresentation':
      return client.getPresentation(reqString(a, 'presentationId'));
    case 'batchUpdate':
      return client.batchUpdate(reqString(a, 'presentationId'), reqArray(a, 'requests'));
    case 'copyFile':
      return client.copyFile(
        reqString(a, 'fileId'),
        reqString(a, 'newName'),
        optString(a, 'parentId'),
      );
    case 'exportFile': {
      const buf = await client.exportFile(
        reqString(a, 'fileId'),
        reqExportMime(a, 'mimeType'),
      );
      return { base64: buf.toString('base64') };
    }
    case 'getPageThumbnail':
      return client.getPageThumbnail(
        reqString(a, 'presentationId'),
        reqString(a, 'pageObjectId'),
      );
    case 'replaceAllText':
      return client.replaceAllText(
        reqString(a, 'presentationId'),
        reqTagMap(a, 'tagMap'),
        optStringArray(a, 'pageObjectIds'),
      );
    case 'replaceAllShapesWithImage':
      return client.replaceAllShapesWithImage(
        reqString(a, 'presentationId'),
        reqTagMap(a, 'tagImageMap'),
        optStringArray(a, 'pageObjectIds'),
      );
    case 'scaffoldTemplate': {
      const tokens = reqObject(a, 'tokens') as unknown as BrandTokens;
      const layoutSpec =
        (optObject(a, 'layoutSpec') as unknown as LayoutSpec | undefined) ??
        buildDefaultLayout();
      const imagePaths = optStringMap(a, 'imagePaths');
      const images = imagePaths
        ? Object.fromEntries(
            Object.entries(imagePaths).map(([id, p]) => [
              id,
              readFileSync(confineReadPath(p, `imagePaths["${id}"]`)),
            ]),
          )
        : undefined;
      const gradients = optObject(a, 'gradients') as unknown as
        | Record<string, GradientSpec>
        | undefined;
      return scaffoldTemplate(
        client,
        tokens,
        layoutSpec,
        { images, gradients },
        {
          driveFolderPath: optStringArray(a, 'driveFolderPath'),
          presentationName: optString(a, 'presentationName'),
        },
      );
    }
    case 'outlineToPayload': {
      // Parse a filled `/outline` markdown into a renderDeck-ready payload.
      const tagMap = reqObject(a, 'tagMap') as unknown as LayoutTagMap;
      return toContentPayload(
        parseOutline(reqString(a, 'outlineMarkdown')),
        tagMap,
      );
    }
    case 'renderDeck': {
      const tagMap = reqObject(a, 'tagMap') as unknown as LayoutTagMap;
      const payload = reqUnknownArray(a, 'payload') as unknown as ContentPayload;
      const fontSubstitutions = optObjectArray(a, 'fontSubstitutions') as
        | FontSubstitution[]
        | undefined;
      const templatePresentationId = reqString(a, 'templatePresentationId');
      // Confine user-controlled paths BEFORE any API write — if the path is
      // invalid, the deck never gets duplicated. (`renderDeck` is otherwise
      // not idempotent at this layer; rejecting late would leave orphan files.)
      const rawCustomFontFile = optString(a, 'customFontFile');
      const customFontFile =
        rawCustomFontFile !== undefined
          ? confineReadPath(rawCustomFontFile, 'customFontFile')
          : undefined;
      const rawManifestPath = optString(a, 'manifestPath');
      const manifestPath =
        rawManifestPath !== undefined ? confineManifestPath(rawManifestPath) : undefined;
      const result = await renderDeck(
        client,
        { presentationId: templatePresentationId, tagMap },
        payload,
        {
          fontSubstitutions,
          customFontFile,
          deckName: optString(a, 'deckName'),
          driveFolderPath: optStringArray(a, 'driveFolderPath'),
        },
      );
      // Manifest write (D-block, post-renderDeck) — when the caller supplies
      // `manifestPath`, also supplying `layoutSpec`, `tokens`, and
      // `fixedImageUrls` lets us persist the sidecar so future `resyncDeck`
      // calls can rebuild in place on the same deckPresentationId.
      if (manifestPath !== undefined) {
        const layoutSpec = reqObject(a, 'layoutSpec') as unknown as LayoutSpec;
        const tokens = reqObject(a, 'tokens') as unknown as BrandTokens;
        const fixedImageUrlsRaw = optStringMap(a, 'fixedImageUrls') ?? {};
        const manifest: RenderManifest = {
          schema: MANIFEST_SCHEMA,
          templatePresentationId,
          deckPresentationId: result.presentationId,
          renderedAt: new Date().toISOString(),
          layoutSpec,
          tokens,
          fixedImageUrls: fixedImageUrlsRaw,
          fontSubstitutions: fontSubstitutions ?? [],
          slides: payload.map(slideFromPayload),
        };
        writeManifest(manifestPath, manifest);
        return { ...result, manifestPath };
      }
      return result;
    }
    case 'resyncDeck': {
      // The manifest carries every input resync needs (layoutSpec, tokens,
      // fixedImageUrls, fontSubstitutions, deckPresentationId, prior slides).
      // The caller supplies the manifest path + the new outline markdown;
      // we parse → payload → resync → rewrite the manifest in place.
      const manifestPath = confineManifestPath(reqString(a, 'manifestPath'));
      const outlineMarkdown = reqString(a, 'outlineMarkdown');
      const manifest = readManifest(manifestPath);
      if (!manifest) {
        throw new CommandError(
          `resyncDeck: no render manifest at "${manifestPath}" — ` +
            `run renderDeck first to produce one.`,
        );
      }
      const tagMap = tagMapFromLayoutSpec(manifest.layoutSpec);
      const payload = toContentPayload(parseOutline(outlineMarkdown), tagMap);
      const res = await resyncDeck(client, manifest, payload);
      writeManifest(manifestPath, res.manifest);
      return {
        presentationId: res.presentationId,
        slidesRendered: res.slidesRendered,
        changeReport: res.changeReport,
        manifestPath,
      };
    }
    default:
      throw new CommandError(`Unknown command: ${doc.command}`);
  }
}

/** Dispatch a command and wrap the outcome in a result envelope. */
export async function handleCommand(
  client: SlidesClient,
  doc: CommandDoc,
): Promise<ResultEnvelope> {
  try {
    return { ok: true, result: await dispatch(client, doc) };
  } catch (err) {
    return { ok: false, error: normalizeError(err) };
  }
}

/** Read all of stdin as a UTF-8 string. */
async function readStdin(): Promise<string> {
  const chunks: Buffer[] = [];
  for await (const chunk of process.stdin) {
    chunks.push(chunk as Buffer);
  }
  return Buffer.concat(chunks).toString('utf8');
}

/** Process entry: stdin → credentials → client → command → stdout envelope. */
async function main(): Promise<void> {
  let envelope: ResultEnvelope;
  try {
    const doc = parseCommandDoc(await readStdin());
    const auth = createAuthClient(resolveAuthConfig(process.env));
    const services: SlidesServices = {
      slides: google.slides({ version: 'v1', auth }),
      drive: google.drive({ version: 'v3', auth }),
    };
    envelope = await handleCommand(new SlidesClient(services), doc);
  } catch (err) {
    envelope = { ok: false, error: normalizeError(err) };
  }
  process.stdout.write(`${JSON.stringify(envelope)}\n`);
  process.exitCode = envelope.ok ? 0 : 1;
}

// Run main() only when executed directly — not when imported by tests.
if (
  process.argv[1] !== undefined &&
  import.meta.url === pathToFileURL(process.argv[1]).href
) {
  void main();
}
