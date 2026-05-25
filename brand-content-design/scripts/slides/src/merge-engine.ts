/**
 * Merge engine — the runtime renderer. Given a scaffolded template
 * (presentation id + tag map) and a content payload, it copies the template
 * and renders a finished deck: per outline entry it duplicates the matching
 * type-slide and page-scoped-fills content + speaker notes.
 *
 * Render shape (research Q6): validate → `files.copy` → Batch 1 (duplicate +
 * page-scoped fills + delete prototypes) → `getPresentation` (notes ids) →
 * Batch 2 (notes). Idempotent — every render starts from a fresh copy.
 */
import type { slides_v1 } from 'googleapis';
import type { SlidesClient } from './client.js';
import type {
  TagMap,
  TagInfo,
  SlideTypeLayout,
  LayoutSpec,
} from './layout-spec.js';
import { validatePayload, type ContentPayload } from './payload-validator.js';
import {
  buildReplaceAllTextRequests,
  buildReplaceAllShapesWithImageRequests,
  buildSetSpeakerNotesRequests,
  buildObjectIdTextFillRequests,
} from './requests.js';
import { bakeDisplayText } from './image-baker.js';
import { buildSlideRequests } from './slide-builder.js';
import {
  type RenderManifest,
  slideFromPayload,
  MANIFEST_SCHEMA,
} from './render-manifest.js';
import { diffOutline, isEmptyDiff, type OutlineDiff } from './outline-diff.js';
import { EmptyPayloadError } from './errors.js';

export type { ContentSlide, ContentPayload } from './payload-validator.js';

/** A custom-brand-font substitution carried from the scaffolder. */
export interface FontSubstitution {
  role: string;
  from: string;
  to: string;
}

/** What `renderDeck` returns. */
export interface RenderResult {
  /** The rendered deck — a copy; the template is never mutated. */
  presentationId: string;
  slidesRendered: number;
  /** Count of tags dispatched for fill (text + image). Whether each actually
   * matched a shape is confirmed by the visual-diff gate, not here. */
  tagsFilled: number;
  fontSubstitutions: FontSubstitution[];
}

/** Optional render behaviour. */
export interface RenderOptions {
  /** Font substitutions from the scaffolder; a `heading` entry triggers display baking. */
  fontSubstitutions?: FontSubstitution[];
  /** Path to the custom brand font file — required to bake display text. */
  customFontFile?: string;
  /**
   * Name for the rendered deck in Drive. Convention: `"<presentation title> -
   * <template name>"`. Defaults to a timestamped name when omitted.
   */
  deckName?: string;
  /**
   * Drive folder path (segment names, outermost first) for the rendered deck
   * and any baked images. Each segment is found-or-created under the previous.
   * Omit to leave the deck in My Drive root.
   */
  driveFolderPath?: string[];
}

const DISPLAY_BAKE_FONT_PX = 96;

/**
 * Append per-slide fill requests (objectId-targeted text, legacy page-scoped
 * text, page-scoped image swaps) to a batch and return the count of tags
 * dispatched. The shape is identical in renderDeck and resyncDeck once the
 * three buckets have been classified — only the *classification* differs
 * (renderDeck consults `TagMap` + `info.objectId` + display-bake; resyncDeck
 * scans `LayoutSpec.elements`). Extracting only the emission step keeps the
 * helper honest — a flag-driven classifier would be two functions glued
 * together.
 */
function appendSlideFillRequests(
  batch: slides_v1.Schema$Request[],
  slideObjectId: string,
  objectIdFills: { objectId: string; text: string }[],
  normalText: Record<string, string>,
  images: Record<string, string>,
): number {
  batch.push(...buildObjectIdTextFillRequests(objectIdFills));
  batch.push(...buildReplaceAllTextRequests(normalText, [slideObjectId]));
  batch.push(...buildReplaceAllShapesWithImageRequests(images, [slideObjectId]));
  return (
    objectIdFills.length + Object.keys(normalText).length + Object.keys(images).length
  );
}

/** Resolve a slide's speaker-notes shape id from a `getPresentation` result. */
function speakerNotesObjectId(
  presentation: slides_v1.Schema$Presentation,
  slideObjectId: string,
): string | undefined {
  const slide = presentation.slides?.find((s) => s.objectId === slideObjectId);
  return (
    slide?.slideProperties?.notesPage?.notesProperties?.speakerNotesObjectId ??
    undefined
  );
}

/**
 * Render a finished deck from a template + content payload. Fail-fast on an
 * invalid payload (nothing is copied). Returns the deck id + a render report.
 */
export async function renderDeck(
  client: SlidesClient,
  template: { presentationId: string; tagMap: TagMap },
  payload: ContentPayload,
  options: RenderOptions = {},
): Promise<RenderResult> {
  // 1. Validate — fail-fast before any API write.
  const report = validatePayload(payload, template.tagMap);
  if (!report.ok) {
    throw new Error(
      `renderDeck: invalid content payload — ${JSON.stringify(report.errors)}`,
    );
  }

  // 2. Resolve the Drive folder, then copy the template into it — the rendered
  //    deck is the copy; the template is never mutated.
  let folderId: string | undefined;
  for (const segment of options.driveFolderPath ?? []) {
    folderId = (await client.findOrCreateFolder(segment, folderId)).folderId;
  }
  const { fileId: presentationId } = await client.copyFile(
    template.presentationId,
    options.deckName ?? `Rendered deck ${new Date().toISOString()}`,
    folderId,
  );

  const fontSubstitutions = options.fontSubstitutions ?? [];
  const headingSub = fontSubstitutions.find((s) => s.role === 'heading');
  const bakeDisplay = !!headingSub && !!options.customFontFile;

  // 3. Batch 1 — duplicate each type-slide, page-scoped fills, delete prototypes.
  const batch1: slides_v1.Schema$Request[] = [];
  const rendered: { slideId: string; notes?: string }[] = [];
  let tagsFilled = 0;

  for (let i = 0; i < payload.length; i++) {
    const slide = payload[i];
    const entry = template.tagMap[slide.type];
    const srcId = entry.typeSlideObjectId;
    // `slide_` prefix keeps the id safely above the 5-char API floor for
    // every SlideType (the shortest, `CTA`, would otherwise be exactly 5).
    const newSlideId = `slide_${slide.type}_${i}`;
    rendered.push({ slideId: newSlideId, notes: slide.speakerNotes });

    // Build the duplicateObject id remap: the slide id + every field-tagged
    // element's objectId. Without a child remap, the API auto-generates random
    // ids — fine for chrome but useless for the objectId-targeted fill below.
    // info.objectId on the type-slide has the form `<srcId>_<elemSuffix>`
    // (set by slide-builder); the duplicate's child lands at
    // `<newSlideId>_<elemSuffix>` so the fill code can address it.
    const idRemap: Record<string, string> = { [srcId]: newSlideId };
    const targetIdByTag: Record<string, string> = {};
    for (const [tag, info] of Object.entries(entry.tags)) {
      if (!info.objectId) continue;
      const elemSuffix = info.objectId.slice(srcId.length + 1);
      const target = `${newSlideId}_${elemSuffix}`;
      if (target.length > 50) {
        throw new Error(
          `renderDeck: duplicated objectId "${target}" exceeds the 50-char ` +
            `Slides API limit — shorten the SlideType id or layout element id`,
        );
      }
      idRemap[info.objectId] = target;
      targetIdByTag[tag] = target;
    }

    batch1.push({ duplicateObject: { objectId: srcId, objectIds: idRemap } });

    // Field-tagged image slots aren't fillable via objectId in v1 — the
    // placeholder displays the field's sample label, so `replaceAllShapesWithImage`
    // (which keys by literal text) can't match. The objectId path for images
    // (delete-then-createImage at the saved geometry) is a documented follow-up
    // tracked in slides_render task notes. Fail fast.
    for (const tag of Object.keys(slide.images ?? {})) {
      const info = entry.tags[tag];
      if (info?.objectId) {
        throw new Error(
          `renderDeck: field-tagged image slot "${tag}" is not yet supported — ` +
            `use a legacy {tag}-style image placeholder, or fill this slot ` +
            `via the v2 image-objectId path (planned follow-up).`,
        );
      }
    }

    // Split text fills three ways:
    //   - display-baked (custom heading font + info.display) → image fill via
    //     the legacy token path;
    //   - objectId-targeted (info.objectId set, the field-tagged path) →
    //     deleteText + insertText addressed by the duplicate's child id;
    //   - legacy token (info.objectId absent) → replaceAllText.
    const normalText: Record<string, string> = {};
    const objectIdFills: { objectId: string; text: string }[] = [];
    const images: Record<string, string> = { ...(slide.images ?? {}) };
    for (const [tag, value] of Object.entries(slide.text ?? {})) {
      const info = entry.tags[tag];
      if (bakeDisplay && info?.display && options.customFontFile) {
        const png = bakeDisplayText({
          text: value,
          fontFamily: headingSub?.from ?? 'sans-serif',
          fontSizePx: DISPLAY_BAKE_FONT_PX,
          color: '#000000',
          fontFile: options.customFontFile,
        });
        const safeTag = tag.replace(/[^a-zA-Z0-9]/g, '');
        const { url } = await client.uploadImage(
          `${newSlideId}_${safeTag}.png`,
          png,
          'image/png',
          folderId,
        );
        images[tag] = url;
      } else if (info?.objectId) {
        objectIdFills.push({ objectId: targetIdByTag[tag], text: value });
      } else {
        normalText[tag] = value;
      }
    }

    tagsFilled += appendSlideFillRequests(
      batch1,
      newSlideId,
      objectIdFills,
      normalText,
      images,
    );
  }

  // Delete the prototype type-slides — the deck shows only outline slides.
  for (const type of Object.keys(template.tagMap)) {
    batch1.push({
      deleteObject: { objectId: template.tagMap[type].typeSlideObjectId },
    });
  }
  if (batch1.length > 0) {
    await client.batchUpdate(presentationId, batch1);
  }

  // 4. Resolve speaker-notes shape ids — unpredictable, needs a read.
  const presentation = await client.getPresentation(presentationId);

  // 5. Batch 2 — fill speaker notes.
  const batch2: slides_v1.Schema$Request[] = [];
  for (const { slideId, notes } of rendered) {
    if (!notes) continue;
    const notesId = speakerNotesObjectId(presentation, slideId);
    if (notesId) {
      batch2.push(...buildSetSpeakerNotesRequests(notesId, notes));
    }
  }
  if (batch2.length > 0) {
    await client.batchUpdate(presentationId, batch2);
  }

  return {
    presentationId,
    slidesRendered: payload.length,
    tagsFilled,
    fontSubstitutions,
  };
}

/* ----- Resync ----------------------------------------------------------- */

/** What `resyncDeck` returns. */
export interface ResyncResult {
  /** Always equal to `manifest.deckPresentationId` — the user-visible URL is preserved. */
  presentationId: string;
  slidesRendered: number;
  /** The per-index diff that drove this resync — empty on the no-op fast path. */
  changeReport: OutlineDiff;
  /** The updated manifest. The caller persists it via `writeManifest`. */
  manifest: RenderManifest;
}

/** Derive a {@link TagMap} from a {@link LayoutSpec}. Pure, for payload validation. */
export function tagMapFromLayoutSpec(spec: LayoutSpec): TagMap {
  const out: TagMap = {};
  for (const layout of spec.slides) {
    out[layout.type] = {
      typeSlideObjectId: `slide_${layout.type}`,
      tags: tagsFromLayout(layout),
    };
  }
  return out;
}

function tagsFromLayout(layout: SlideTypeLayout): Record<string, TagInfo> {
  const tags: Record<string, TagInfo> = {};
  for (const e of layout.elements) {
    if (!e.content) continue;
    const kind: TagInfo['kind'] = e.kind === 'image' ? 'image' : 'text';
    if ('tag' in e.content) {
      tags[e.content.tag] = { kind };
    } else if ('field' in e.content) {
      // objectId is intentionally undefined here — validation only cares about
      // `kind`; resync assigns real per-slide objectIds at build time.
      tags[e.content.field] = { kind };
    }
  }
  return tags;
}

/**
 * Resync a deck in place — preserving `deckPresentationId` (the user-visible
 * file/URL stays the same).
 *
 * Strategy (v1):
 *   1. validatePayload (fail-fast, same as renderDeck) against a tagMap
 *      derived from `manifest.layoutSpec`.
 *   2. diffOutline(manifest, newPayload). Empty diff → no API calls;
 *      only `renderedAt` is bumped in the returned manifest.
 *   3. Non-empty diff → in-place rebuild:
 *      - get current slide ids via getPresentation;
 *      - build each new payload slide via buildSlideRequests (createSlide +
 *        shapes + insertText of samples) with a resync-unique slide objectId;
 *      - for field-tagged text slots, append deleteText(ALL) + insertText
 *        with the payload value, addressed by the new slide's child id;
 *      - for legacy {tag}-text slots, page-scoped replaceAllText into the
 *        new slide; same for image slots;
 *      - deleteObject every prior slide id;
 *      - send as one atomic batchUpdate (Batch 1).
 *   4. Speaker notes: getPresentation again (notes ids for the new slides)
 *      → Batch 2 with buildSetSpeakerNotesRequests.
 *   5. Return updated manifest. Caller writes it via `writeManifest`.
 *
 * Field-tagged IMAGE slots are not yet supported (same v1 limitation as
 * renderDeck — the placeholder displays the sample label so
 * `replaceAllShapesWithImage` can't match).
 */
export async function resyncDeck(
  client: SlidesClient,
  manifest: RenderManifest,
  newPayload: ContentPayload,
): Promise<ResyncResult> {
  // 0. Refuse an empty payload — `validatePayload` accepts `[]` (forEach no-op),
  //    `diffOutline` would then produce an all-deletes batch that the Slides
  //    API rejects with an opaque INVALID_ARGUMENT ("must keep ≥1 slide").
  //    Fail-fast with a clear, actionable message instead.
  if (newPayload.length === 0) {
    throw new EmptyPayloadError(
      'resyncDeck: refusing to empty the deck (newPayload has 0 slides). ' +
        'If you intend to discard this deck, delete the manifest and presentation manually.',
    );
  }

  const tagMap = tagMapFromLayoutSpec(manifest.layoutSpec);

  // 1. Validate — fail-fast before any API write.
  const report = validatePayload(newPayload, tagMap);
  if (!report.ok) {
    throw new Error(
      `resyncDeck: invalid content payload — ${JSON.stringify(report.errors)}`,
    );
  }

  // 2. Diff.
  const changeReport = diffOutline(manifest, newPayload);
  const renderedAt = new Date().toISOString();

  if (isEmptyDiff(changeReport)) {
    return {
      presentationId: manifest.deckPresentationId,
      slidesRendered: newPayload.length,
      changeReport,
      manifest: {
        ...manifest,
        renderedAt,
        slides: newPayload.map(slideFromPayload),
      },
    };
  }

  // 3. Enumerate prior slide ids so we can delete them after the rebuild.
  const before = await client.getPresentation(manifest.deckPresentationId);
  const priorSlideIds: string[] = (before.slides ?? [])
    .map((s) => s.objectId)
    .filter((id): id is string => typeof id === 'string' && id !== '');

  // Index by layout type for quick lookup.
  const layoutByType = new Map<string, SlideTypeLayout>();
  for (const layout of manifest.layoutSpec.slides) {
    layoutByType.set(layout.type, layout);
  }

  // 4. Build Batch 1 — one createSlide-and-shape batch per payload slide,
  //    then objectId or page-scoped fills, then deletes of the prior slides.
  const batch1: slides_v1.Schema$Request[] = [];
  const builtSlideIds: { slideId: string; notes?: string }[] = [];
  // Nonce keeps every resync's slide ids unique vs. anything in the deck —
  // base36 of Date.now() is ~8 chars and well under the 50-char API limit.
  const nonce = `r${Date.now().toString(36)}`;
  let tagsFilled = 0;

  for (let i = 0; i < newPayload.length; i++) {
    const slide = newPayload[i];
    const layout = layoutByType.get(slide.type);
    if (!layout) {
      // Defensive — validatePayload should have caught this; keeps tsc strict happy.
      throw new Error(`resyncDeck: no layout for type "${slide.type}"`);
    }
    const slideObjectId = `${nonce}_${i}`;
    if (slideObjectId.length > 50) {
      throw new Error(
        `resyncDeck: slide id "${slideObjectId}" exceeds the 50-char API limit`,
      );
    }
    const built = buildSlideRequests(
      layout,
      manifest.tokens,
      manifest.fixedImageUrls,
      slideObjectId,
    );
    batch1.push(...built.requests);
    builtSlideIds.push({ slideId: slideObjectId, notes: slide.speakerNotes });

    // Fail fast on field-tagged image slots (v1 limitation; same as renderDeck).
    for (const tag of Object.keys(slide.images ?? {})) {
      const layoutTag = tagsFromLayout(layout)[tag];
      const isFieldTagged = layout.elements.some(
        (e) => e.content && 'field' in e.content && e.content.field === tag,
      );
      if (layoutTag && isFieldTagged) {
        throw new Error(
          `resyncDeck: field-tagged image slot "${tag}" is not yet supported — ` +
            `use a legacy {tag}-style image placeholder, or wait for the v2 ` +
            `image-objectId path (planned follow-up).`,
        );
      }
    }

    // Field-tagged text → deleteText + insertText addressed by the just-built
    // element's objectId (`<slideObjectId>_<elemId>`). Legacy {tag} text and
    // image slots → page-scoped replace, same shape as renderDeck.
    const objectIdFills: { objectId: string; text: string }[] = [];
    const legacyText: Record<string, string> = {};
    const images: Record<string, string> = { ...(slide.images ?? {}) };
    for (const [tag, value] of Object.entries(slide.text ?? {})) {
      const elem = layout.elements.find(
        (e) =>
          e.content &&
          (('field' in e.content && e.content.field === tag) ||
            ('tag' in e.content && e.content.tag === tag)),
      );
      if (elem && elem.content && 'field' in elem.content) {
        objectIdFills.push({
          objectId: `${slideObjectId}_${elem.id}`,
          text: value,
        });
      } else {
        legacyText[tag] = value;
      }
    }
    tagsFilled += appendSlideFillRequests(
      batch1,
      slideObjectId,
      objectIdFills,
      legacyText,
      images,
    );
  }

  // Delete prior slides last — Slides API requires at least one slide in the
  // presentation at all times, so the new slides must be created before the
  // old ones are removed (the single atomic batch makes both steps land
  // together or not at all).
  for (const id of priorSlideIds) {
    batch1.push({ deleteObject: { objectId: id } });
  }

  if (batch1.length > 0) {
    await client.batchUpdate(manifest.deckPresentationId, batch1);
  }

  // 5. Speaker notes — Batch 2.
  const presentation = await client.getPresentation(manifest.deckPresentationId);
  const batch2: slides_v1.Schema$Request[] = [];
  for (const { slideId, notes } of builtSlideIds) {
    if (!notes) continue;
    const notesId = speakerNotesObjectId(presentation, slideId);
    if (notesId) {
      batch2.push(...buildSetSpeakerNotesRequests(notesId, notes));
    }
  }
  if (batch2.length > 0) {
    await client.batchUpdate(manifest.deckPresentationId, batch2);
  }

  // `tagsFilled` is reported via the diff `changeReport` (refilled count etc.);
  // the bare count is folded into change report telemetry, not the return shape.
  void tagsFilled;

  return {
    presentationId: manifest.deckPresentationId,
    slidesRendered: newPayload.length,
    changeReport,
    manifest: {
      schema: MANIFEST_SCHEMA,
      templatePresentationId: manifest.templatePresentationId,
      deckPresentationId: manifest.deckPresentationId,
      renderedAt,
      layoutSpec: manifest.layoutSpec,
      tokens: manifest.tokens,
      fixedImageUrls: manifest.fixedImageUrls,
      fontSubstitutions: manifest.fontSubstitutions,
      slides: newPayload.map(slideFromPayload),
    },
  };
}
