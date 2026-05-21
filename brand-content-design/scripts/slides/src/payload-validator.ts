/**
 * Payload validator — checks a content payload against the scaffolder's tag
 * map before the merge engine writes anything. Pure, fail-fast: an invalid
 * payload is a real defect and is surfaced, never partially rendered.
 */
import type { TagMap } from './layout-spec.js';

/** One slide of content — names a slide type, provides values for its tags. */
export interface ContentSlide {
  /** A `SlideType` — validated against the tag map. */
  type: string;
  /** Tag token → replacement text. */
  text?: Record<string, string>;
  /** Tag token → public image URL. */
  images?: Record<string, string>;
  /** Speaker notes for this slide. */
  speakerNotes?: string;
}

/** The filled outline — an ordered list of content slides. */
export type ContentPayload = ContentSlide[];

/** A per-slide validation error. */
export interface SlideValidationError {
  slideIndex: number;
  type: string;
  /** The slide type is not in the tag map. */
  unknownType?: boolean;
  /** Template tags with no value in this slide entry. */
  missingTags: string[];
  /** Payload keys not present in the template for this type. */
  unknownTags: string[];
  /** Tags supplied with the wrong value kind (text vs image). */
  kindMismatches: string[];
}

/** The validation outcome. `ok` only when every slide validates. */
export interface ValidationReport {
  ok: boolean;
  errors: SlideValidationError[];
}

/**
 * Validate a content payload against the template tag map. Returns a report;
 * the caller (the merge engine) fails fast — renders nothing — on `ok: false`.
 */
export function validatePayload(
  payload: ContentPayload,
  tagMap: TagMap,
): ValidationReport {
  const errors: SlideValidationError[] = [];

  payload.forEach((slide, slideIndex) => {
    const entry = tagMap[slide.type];
    if (!entry) {
      errors.push({
        slideIndex,
        type: slide.type,
        unknownType: true,
        missingTags: [],
        unknownTags: [],
        kindMismatches: [],
      });
      return;
    }

    const tags = entry.tags;
    const text = slide.text ?? {};
    const images = slide.images ?? {};
    const providedKeys = new Set([...Object.keys(text), ...Object.keys(images)]);

    const missingTags: string[] = [];
    const kindMismatches: string[] = [];
    for (const [tag, info] of Object.entries(tags)) {
      if (!providedKeys.has(tag)) {
        missingTags.push(tag);
        continue;
      }
      if (info.kind === 'text' && !(tag in text)) kindMismatches.push(tag);
      if (info.kind === 'image' && !(tag in images)) kindMismatches.push(tag);
    }

    const unknownTags: string[] = [];
    for (const key of providedKeys) {
      if (!(key in tags)) unknownTags.push(key);
    }

    if (missingTags.length || unknownTags.length || kindMismatches.length) {
      errors.push({ slideIndex, type: slide.type, missingTags, unknownTags, kindMismatches });
    }
  });

  return { ok: errors.length === 0, errors };
}
