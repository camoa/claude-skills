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
import type { TagMap } from './layout-spec.js';
import { validatePayload, type ContentPayload } from './payload-validator.js';
import {
  buildReplaceAllTextRequests,
  buildReplaceAllShapesWithImageRequests,
  buildSetSpeakerNotesRequests,
} from './requests.js';
import { bakeDisplayText } from './image-baker.js';

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
}

const DISPLAY_BAKE_FONT_PX = 96;

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

  // 2. Copy the template — the rendered deck is the copy; template untouched.
  const { fileId: presentationId } = await client.copyFile(
    template.presentationId,
    options.deckName ?? `Rendered deck ${new Date().toISOString()}`,
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
    const srcId = template.tagMap[slide.type].typeSlideObjectId;
    // `slide_` prefix keeps the id safely above the 5-char API floor for
    // every SlideType (the shortest, `CTA`, would otherwise be exactly 5).
    const newSlideId = `slide_${slide.type}_${i}`;
    rendered.push({ slideId: newSlideId, notes: slide.speakerNotes });

    batch1.push({
      duplicateObject: { objectId: srcId, objectIds: { [srcId]: newSlideId } },
    });

    // Split text tags into normal fills and (when the brand font is custom)
    // display tags baked as images.
    const normalText: Record<string, string> = {};
    const images: Record<string, string> = { ...(slide.images ?? {}) };
    for (const [tag, value] of Object.entries(slide.text ?? {})) {
      const info = template.tagMap[slide.type].tags[tag];
      if (bakeDisplay && info?.display && options.customFontFile) {
        const png = bakeDisplayText({
          text: value,
          fontFamily: headingSub?.from ?? 'sans-serif',
          fontSizePx: DISPLAY_BAKE_FONT_PX,
          color: '#000000',
          fontFile: options.customFontFile,
        });
        const safeTag = tag.replace(/[^a-zA-Z0-9]/g, '');
        const { url } = await client.uploadImage(`${newSlideId}_${safeTag}.png`, png);
        images[tag] = url;
      } else {
        normalText[tag] = value;
      }
    }
    batch1.push(...buildReplaceAllTextRequests(normalText, [newSlideId]));
    batch1.push(...buildReplaceAllShapesWithImageRequests(images, [newSlideId]));
    tagsFilled += Object.keys(normalText).length + Object.keys(images).length;
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
