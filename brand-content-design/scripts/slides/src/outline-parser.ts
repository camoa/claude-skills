/**
 * Outline parser — bridges a filled `/outline` markdown to the merge engine's
 * `ContentPayload`.
 *
 * `parseOutline` reads the markdown into a neutral `ParsedOutlineSlide[]` keyed
 * by human element labels. `toContentPayload` maps those labels to tag tokens
 * via the scaffolder's `TagMap` (normalized-label match) and routes each value
 * to `text` or `images` by `TagInfo.kind`. Both are pure and fail-fast — a
 * malformed outline is a real defect, surfaced, never half-rendered. The merge
 * engine's `validatePayload` still runs downstream and catches unfilled tags.
 */
import type { TagMap } from './layout-spec.js';
import type { ContentPayload, ContentSlide } from './payload-validator.js';

/** One slide of a parsed outline — labels are human element names, not tags. */
export interface ParsedOutlineSlide {
  /** The raw type label from the `## Slide N: <Type>` header. */
  type: string;
  /** Element label → filled value. Unfilled bullets are omitted. */
  fields: Record<string, string>;
  /** Speaker notes, when the outline filled them. */
  speakerNotes?: string;
}

/** `## Slide 3: Content` / `## Card 2: Hook` → captures the type label. */
const HEADER = /^#{1,6}\s*(?:Slide|Card)\s+\d+\s*:\s*(.+?)\s*$/i;
/** `- Title: My deck` / `* **Card text**: Hello` → captures label + value. */
const BULLET = /^[-*]\s+(.+?)\s*:\s*(.*)$/;

/** Normalize a label/tag-name for matching — lowercase, alphanumeric only. */
function normalize(s: string): string {
  return s.toLowerCase().replace(/[^a-z0-9]/g, '');
}

/**
 * Strip surrounding `**bold**` markdown and any trailing parenthetical hint
 * (e.g. ` (≤10 words)`, ` (icon: shield)`) from a bullet label. The hint is
 * editorial guidance for the outline author; matching is done against the
 * bare label so labels normalize-equal `FieldSpec.id`.
 */
function cleanLabel(label: string): string {
  return label
    .replace(/\*\*/g, '')
    .replace(/\s*\([^()]*\)\s*$/, '')
    .trim();
}

/** A value is "unfilled" when blank or an underscore placeholder (`___`). */
function isUnfilled(value: string): boolean {
  const v = value.trim();
  return v === '' || /^_+$/.test(v);
}

/**
 * Parse a filled outline markdown into `ParsedOutlineSlide[]`.
 *
 * @throws {Error} when no slides are found.
 */
export function parseOutline(markdown: string): ParsedOutlineSlide[] {
  const slides: ParsedOutlineSlide[] = [];
  let current: ParsedOutlineSlide | undefined;

  for (const line of markdown.split(/\r?\n/)) {
    const header = HEADER.exec(line);
    if (header) {
      current = { type: header[1].trim(), fields: {} };
      slides.push(current);
      continue;
    }
    if (!current) continue;

    const bullet = BULLET.exec(line.trim());
    if (!bullet) continue;
    const label = cleanLabel(bullet[1]);
    const value = bullet[2].trim();
    if (isUnfilled(value)) continue;

    if (normalize(label) === 'speakernotes') {
      current.speakerNotes = value;
    } else {
      current.fields[label] = value;
    }
  }

  if (slides.length === 0) {
    throw new Error('parseOutline: no slides found — expected `## Slide N: <Type>` headers.');
  }
  return slides;
}

/** The inner name of a tag token — `{{title}}` → `title`. */
function tagName(token: string): string {
  return token.replace(/[{}]/g, '');
}

/**
 * Map a parsed outline to a `ContentPayload` using the scaffolder's tag map.
 * Field labels match tag tokens by normalized name; `TagInfo.kind` routes the
 * value to `text` vs `images`.
 *
 * @throws {Error} on an unknown slide type or a field label that matches no
 *   tag — aggregated into one message so the whole outline is reported at once.
 */
export function toContentPayload(
  parsed: ParsedOutlineSlide[],
  tagMap: TagMap,
): ContentPayload {
  const errors: string[] = [];
  const payload: ContentPayload = [];

  // Build a normalized-name lookup over tagMap keys so outline headers can use
  // natural-language type labels ("Title", "Section Divider") that resolve to
  // the template's stable type ids ("title", "divider"). Exact-key lookup is
  // tried first to preserve backward compatibility with legacy outlines that
  // already use the literal id.
  const tagMapByNorm = new Map<string, string>();
  for (const key of Object.keys(tagMap)) {
    tagMapByNorm.set(normalize(key), key);
  }

  parsed.forEach((slide, i) => {
    const resolvedType =
      slide.type in tagMap ? slide.type : tagMapByNorm.get(normalize(slide.type));
    const entry = resolvedType !== undefined ? tagMap[resolvedType] : undefined;
    if (!entry || resolvedType === undefined) {
      errors.push(`slide ${i + 1}: unknown slide type "${slide.type}"`);
      return;
    }

    // Index the type's tags by normalized inner name for label lookup.
    const byName = new Map<string, string>();
    for (const token of Object.keys(entry.tags)) {
      byName.set(normalize(tagName(token)), token);
    }

    const text: Record<string, string> = {};
    const images: Record<string, string> = {};
    for (const [label, value] of Object.entries(slide.fields)) {
      const token = byName.get(normalize(label));
      if (!token) {
        errors.push(`slide ${i + 1} (${slide.type}): no tag matches field "${label}"`);
        continue;
      }
      if (entry.tags[token].kind === 'image') images[token] = value;
      else text[token] = value;
    }

    const content: ContentSlide = { type: resolvedType, text, images };
    if (slide.speakerNotes !== undefined) content.speakerNotes = slide.speakerNotes;
    payload.push(content);
  });

  if (errors.length > 0) {
    throw new Error(`toContentPayload: outline does not match the template — ${errors.join('; ')}`);
  }
  return payload;
}
