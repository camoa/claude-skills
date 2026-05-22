/**
 * Scaffolder — the orchestrator. Builds a branded Google Slides *template
 * presentation* (one tagged example slide per slide type) from brand tokens
 * and a layout spec, driving `SlidesClient` + `slides_token_mapper` +
 * `slide-builder` + `font-classifier` + `image-baker`.
 *
 * Run once per brand/template. Returns the template presentation id, the tag
 * map (consumed by the merge engine + payload validator), and any font
 * substitutions applied.
 */
import type { SlidesClient } from './client.js';
import type { BrandTokens } from './token-mapper.js';
import type { LayoutSpec, TagMap, ScaffoldResult } from './layout-spec.js';
import { classifyFonts } from './font-classifier.js';
import { bakeGradient, type GradientSpec } from './image-baker.js';
import { buildSlideRequests } from './slide-builder.js';

/** Brand assets the scaffolder hosts on Drive and references by URL. */
export interface ScaffoldAssets {
  /** Fixed-image element id → image bytes (logos, pre-rendered images). */
  images?: Record<string, Buffer>;
  /** Element id → gradient spec; baked at scaffold time, then uploaded. */
  gradients?: Record<string, GradientSpec>;
}

/** Font a custom brand face is substituted with so the template renders. */
const FALLBACK_FONT = 'Inter';

/**
 * Scaffold a branded template presentation.
 *
 * Custom (non-Google) brand fonts are substituted with `Inter` so the template
 * renders, and the substitution is reported. Baking a heading in the *true*
 * custom font is a merge-time concern (the real heading text is only known
 * then) — owned by `slides_merge_engine`, not this scaffolder.
 */
/** Optional scaffold behaviour. */
export interface ScaffoldOptions {
  /**
   * Drive folder path (segment names, outermost first) to organise the
   * template presentation + baked images into. Each segment is found-or-created
   * under the previous; the leaf folder holds the output. Omit to leave files
   * in My Drive root. The integration child may pass segments mirroring the
   * local brand-project structure.
   */
  driveFolderPath?: string[];
  /**
   * Name for the created template presentation in Drive. Convention:
   * `"<template name> Template"` (e.g. `"community-talk Template"`).
   * Defaults to `"Untitled Template"` when omitted.
   */
  presentationName?: string;
}

export async function scaffoldTemplate(
  client: SlidesClient,
  tokens: BrandTokens,
  layoutSpec: LayoutSpec,
  assets: ScaffoldAssets = {},
  options: ScaffoldOptions = {},
): Promise<ScaffoldResult> {
  // 1. Classify fonts; substitute custom faces so the template renders natively.
  const fontClass = classifyFonts(tokens);
  const fontSubstitutions: ScaffoldResult['fontSubstitutions'] = [];
  if (fontClass.heading === 'custom') {
    fontSubstitutions.push({
      role: 'heading',
      from: tokens.typography.headingFont,
      to: FALLBACK_FONT,
    });
  }
  if (fontClass.body === 'custom') {
    fontSubstitutions.push({
      role: 'body',
      from: tokens.typography.bodyFont,
      to: FALLBACK_FONT,
    });
  }
  const effectiveTokens: BrandTokens = {
    ...tokens,
    typography: {
      ...tokens.typography,
      headingFont:
        fontClass.heading === 'custom' ? FALLBACK_FONT : tokens.typography.headingFont,
      bodyFont: fontClass.body === 'custom' ? FALLBACK_FONT : tokens.typography.bodyFont,
    },
  };

  // 2. Ensure the Drive folder path (find-or-create — re-scaffolding reuses it).
  let folderId: string | undefined;
  for (const segment of options.driveFolderPath ?? []) {
    folderId = (await client.findOrCreateFolder(segment, folderId)).folderId;
  }

  // 3. Create the presentation; move it into the folder (Slides creates in root).
  const { presentationId } = await client.createPresentation(
    options.presentationName ?? 'Untitled Template',
  );
  if (folderId) {
    await client.moveFileToFolder(presentationId, folderId);
  }
  // `presentations.create` seeds one blank default slide. Capture its id now —
  // it is removed once the typed slides exist (a presentation must always keep
  // at least one slide, so the delete happens last).
  const seeded = await client.getPresentation(presentationId);
  const defaultSlideId = seeded.slides?.[0]?.objectId ?? undefined;

  // 3. Bake gradients, then upload every image → fixed-image URL map.
  const imageBuffers: Record<string, Buffer> = { ...(assets.images ?? {}) };
  for (const [id, spec] of Object.entries(assets.gradients ?? {})) {
    imageBuffers[id] = bakeGradient(spec);
  }
  const fixedImageUrls: Record<string, string> = {};
  for (const [id, bytes] of Object.entries(imageBuffers)) {
    const { url } = await client.uploadImage(`${id}.png`, bytes, 'image/png', folderId);
    fixedImageUrls[id] = url;
  }

  // 4. Build + apply each type-slide; collect the tag map.
  const tagMap: TagMap = {};
  for (const layout of layoutSpec.slides) {
    const built = buildSlideRequests(layout, effectiveTokens, fixedImageUrls);
    await client.batchUpdate(presentationId, built.requests);
    tagMap[layout.type] = {
      typeSlideObjectId: built.slideObjectId,
      tags: built.tags,
    };
  }

  // Drop the API's seeded blank slide — the template is only the typed slides.
  if (defaultSlideId) {
    await client.batchUpdate(presentationId, [
      { deleteObject: { objectId: defaultSlideId } },
    ]);
  }

  return { presentationId, tagMap, fontSubstitutions, folderId };
}
