/**
 * Layout-spec + tag-map types for the template scaffolder.
 *
 * `LayoutSpec` is the scaffolder's input contract — the resolution-independent
 * geometry the epic calls the "shared layout IR". The scaffolder *consumes* it;
 * exposing `visual-content`'s internal layout as a `LayoutSpec` is the
 * `slides_brand_content_integration` child. `TagMap` is the scaffolder's
 * output, consumed by the merge engine and the payload validator.
 */

/**
 * A slide type label. Each template names its own type catalogue — the generic
 * `default-layout.ts` uses Title / Content / Image / Data / Quote / CTA /
 * Transition; a designed template (e.g. `community-talk`, 13 types) defines its
 * own set. Hence a free `string` rather than a fixed union.
 */
export type SlideType = string;

/** The kind of a layout element. */
export type ElementKind = 'shape' | 'image' | 'text' | 'ellipse' | 'line';

/** Which brand font a text element uses. */
export type FontRole = 'heading' | 'body' | 'mono';

/**
 * A single positioned element on a type-slide. Geometry is in **points**
 * (resolution-independent; 1 pt = 12700 EMU), top-left origin.
 */
export interface LayoutElement {
  /** Stable id within the slide; the caller-assigned API objectId derives from it. */
  id: string;
  kind: ElementKind;
  x: number;
  y: number;
  w: number;
  h: number;
  /** Paint order — lower is further back. */
  zOrder: number;
  /** Brand-token role for styling, if any (e.g. `primary`, `textDark`). */
  styleRole?: string;
  /**
   * Explicit hex colour. Overrides `styleRole` — a shape/ellipse fill or a text
   * element's foreground colour. Use when the design needs a precise colour
   * rather than a brand-token role.
   */
  color?: string;
  /**
   * A `shape` element with `rounded` is built as a `ROUND_RECTANGLE`. The
   * Slides API's rounded rectangle has an intrinsic corner style — there is no
   * settable radius — so this is a boolean, not a magnitude.
   */
  rounded?: boolean;
  /** Text only — point size. Omitted falls back to the renderer default. */
  fontSize?: number;
  /** Text only — weight 100–900 (emits `weightedFontFamily`). */
  fontWeight?: number;
  /** Text only — which brand font. Defaults to `heading`. */
  fontFamily?: FontRole;
  /** Text only — paragraph alignment. */
  align?: 'start' | 'center' | 'end';
  /**
   * Shape / ellipse outline. With `outline` and no fill `color`, the element is
   * an outline only (window frames, rings). `weight` is in points.
   */
  outline?: { color: string; weight?: number };
  /**
   * `line` only — draw the line from the bottom-left to the top-right of the
   * `x/y/w/h` box instead of the default top-left → bottom-right diagonal.
   */
  lineFromBottomLeft?: boolean;
  /**
   * Element content. Three variants:
   *  - `{ tag }`     — legacy merge placeholder (the type-slide carries the
   *                    literal `{{token}}` text; the merge engine fills via
   *                    `replaceAllText`). Used by `default-layout.ts`.
   *  - `{ fixed }`   — fixed content (chrome, decoration, sample image label).
   *  - `{ field, sample }` — field-tagged fillable slot from the generator
   *                    contract (C4): the type-slide carries `sample` (the
   *                    template's faithful default), and the renderer records
   *                    the placed element's `objectId` in the `TagMap` so the
   *                    merge engine can target it by id (`deleteText` +
   *                    `insertText`) instead of by `{{token}}` text match.
   *  - omitted       — pure styled shape (e.g. an accent bar).
   */
  content?: { tag: string } | { fixed: string } | { field: string; sample: string };
}

/** The layout of one slide type — its ordered element list. */
export interface SlideTypeLayout {
  type: SlideType;
  elements: LayoutElement[];
}

/** The full layout spec — one entry per slide type. */
export interface LayoutSpec {
  /** Slide dimensions in points. Default 16:9 = 720 × 405 (10in × 5.625in). */
  pageWidth: number;
  pageHeight: number;
  slides: SlideTypeLayout[];
}

/** Per-tag info recorded in the tag map. */
export interface TagInfo {
  kind: 'text' | 'image';
  /**
   * True for display text (e.g. headings). When the brand display font is
   * custom, the merge engine bakes a display tag's real text as an image
   * rather than filling it with `replaceAllText`.
   */
  display?: boolean;
  /**
   * The placed element's Slides API object id on the type-slide. Set for
   * `{ field, sample }` slots — the merge engine duplicates the type-slide,
   * remaps element ids, and fills slots by id (`deleteText` + `insertText`)
   * rather than by `{{token}}` text replacement. Undefined for legacy
   * `{ tag }` content.
   */
  objectId?: string;
}

/** Per-slide-type entry in the tag map. */
export interface TypeTagEntry {
  /** Object id of the type-slide the merge engine duplicates. */
  typeSlideObjectId: string;
  /** Every merge tag on the type-slide, keyed by tag token. */
  tags: Record<string, TagInfo>;
}

/** The scaffolder's output map — keyed by `SlideType`. */
export type TagMap = Record<string, TypeTagEntry>;

/** What `scaffoldTemplate` returns. */
export interface ScaffoldResult {
  presentationId: string;
  tagMap: TagMap;
  /** Font substitutions applied (custom brand font → nearest Google font). */
  fontSubstitutions: { role: string; from: string; to: string }[];
  /** The Drive folder the output was organised into, if a path was given. */
  folderId?: string;
}
