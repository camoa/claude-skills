/**
 * Layout-spec + tag-map types for the template scaffolder.
 *
 * `LayoutSpec` is the scaffolder's input contract — the resolution-independent
 * geometry the epic calls the "shared layout IR". The scaffolder *consumes* it;
 * exposing `visual-content`'s internal layout as a `LayoutSpec` is the
 * `slides_brand_content_integration` child. `TagMap` is the scaffolder's
 * output, consumed by the merge engine and the payload validator.
 */

/** A slide type in the template's type-library. */
export type SlideType =
  | 'Title'
  | 'Content'
  | 'Image'
  | 'Data'
  | 'Quote'
  | 'CTA'
  | 'Transition';

/** The kind of a layout element. */
export type ElementKind = 'shape' | 'image' | 'text';

/**
 * A single positioned element on a type-slide. Geometry is in **points**
 * (resolution-independent; 1 pt = 12700 EMU).
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
   * Element content. A `tag` makes it a merge placeholder; `fixed` makes it
   * fixed content; omitted means a pure styled shape (e.g. an accent bar).
   */
  content?: { tag: string } | { fixed: string };
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
}
