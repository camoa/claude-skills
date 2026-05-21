/**
 * Pure request-object builders for the Slides batchUpdate API.
 *
 * These functions translate a plain tag map into Slides API request objects so
 * callers (the merge engine, the CLI tag-map helpers) never hand-write request
 * JSON. Pure — no I/O, no SDK calls — and therefore trivially unit-testable.
 *
 * Tag-map keys are the literal tag tokens as they appear in the template (e.g.
 * `{{title}}`). This module makes no assumption about the delimiter convention;
 * the merge engine owns that.
 */
import type { slides_v1 } from 'googleapis';
import type { TagMap } from './types.js';

/**
 * Build one `replaceAllText` request per entry in `tagMap`.
 * `matchCase` is always true — tags are exact, case-sensitive tokens.
 *
 * When `pageObjectIds` is non-empty the replacement is scoped to those pages
 * only. This is essential for the renderer's model: a slide *type* can repeat
 * (every instance carries the same tags such as `{{body}}`), so each instance
 * must be filled by scoping to its own page id. Passing a slide's notes-page
 * id likewise targets speaker notes independently.
 */
export function buildReplaceAllTextRequests(
  tagMap: TagMap,
  pageObjectIds?: string[],
): slides_v1.Schema$Request[] {
  const scope =
    pageObjectIds && pageObjectIds.length > 0 ? { pageObjectIds } : {};
  return Object.entries(tagMap).map(([tag, value]) => ({
    replaceAllText: {
      containsText: { text: tag, matchCase: true },
      replaceText: value,
      ...scope,
    },
  }));
}

/**
 * Build one `replaceAllShapesWithImage` request per entry in `tagImageMap`.
 * Each value is a publicly reachable image URL. `CENTER_INSIDE` preserves the
 * image aspect ratio within the tagged placeholder shape.
 *
 * `pageObjectIds`, when non-empty, scopes the replacement to those pages only —
 * needed so a repeated slide type's image placeholders are filled per instance.
 */
export function buildReplaceAllShapesWithImageRequests(
  tagImageMap: TagMap,
  pageObjectIds?: string[],
): slides_v1.Schema$Request[] {
  const scope =
    pageObjectIds && pageObjectIds.length > 0 ? { pageObjectIds } : {};
  return Object.entries(tagImageMap).map(([tag, imageUrl]) => ({
    replaceAllShapesWithImage: {
      containsText: { text: tag, matchCase: true },
      imageUrl,
      imageReplaceMethod: 'CENTER_INSIDE',
      ...scope,
    },
  }));
}

/**
 * Build the request to set a slide's speaker notes.
 *
 * Speaker notes can NOT be filled by `replaceAllText`: its `pageObjectIds`
 * scope rejects notes-page ids, and an unscoped replace would write the same
 * text into every repeated slide's notes. Notes are instead written straight
 * into the slide's speaker-notes shape, addressed by the `speakerNotesObjectId`
 * found at `slide.slideProperties.notesPage.notesProperties.speakerNotesObjectId`
 * (the merge engine resolves that id from a `getPresentation` call).
 *
 * The renderer copies a fresh template per deck and template notes shapes start
 * empty, so a single `insertText` at index 0 suffices — no delete-first. Empty
 * notes text yields no request.
 */
export function buildSetSpeakerNotesRequests(
  speakerNotesObjectId: string,
  notesText: string,
): slides_v1.Schema$Request[] {
  if (notesText === '') return [];
  return [
    {
      insertText: {
        objectId: speakerNotesObjectId,
        text: notesText,
        insertionIndex: 0,
      },
    },
  ];
}
