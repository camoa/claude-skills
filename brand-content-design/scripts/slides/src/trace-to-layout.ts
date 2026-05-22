/**
 * Trace → LayoutSpec converter (v2 — post-Template Generator Contract).
 *
 * Consumes the spec-layer trace JSON written by `tracer/trace-template.py` (a
 * `TracingCanvas(DeckCanvas)` subclass) and produces the `LayoutSpec` the
 * Slides renderer scaffolds. Because the trace is the template's own
 * `DeckCanvas` call list, the Google Slides output reproduces the
 * template-rendered PDF *by construction* — same geometry, same content,
 * same colours. Generic: no per-template code.
 *
 * The trace lives in the generator-contract space (1920×1080 px, origin
 * bottom-left; shapes by bottom-left corner; text by box top-left); this
 * converts to the renderer's 720×405 top-left point space.
 *
 * The trace's per-page `type` becomes the `LayoutSpec` slide-type id — the
 * key downstream `TagMap` / outline-parser / content-payload pipelines key on.
 *
 * Field tags from the generator's `field=` kwarg (contract C4) propagate as
 * `{ field, sample }` `LayoutElement.content` entries; the slide-builder
 * inserts the `sample` text on the type-slide and records `field → objectId`
 * in the `TagMap` (B3). Ops without `field` stay `{ fixed }`.
 */
import type { LayoutSpec, LayoutElement, SlideTypeLayout, FontRole } from './layout-spec.js';
import type { GradientSpec } from './image-baker.js';

/* ---- the trace shape (mirrors tracer/trace-template.py output) ---- */
type Hex = string;
interface SolidOp { op: 'solid'; color: Hex }
interface GradientOp { op: 'gradient'; stops: [number, Hex][] }
interface RectOp { op: 'rect'; x: number; y: number; w: number; h: number; color: Hex }
interface RoundRectOp { op: 'roundRect'; x: number; y: number; w: number; h: number; r: number; fill: Hex | null; stroke: Hex | null; strokeW: number }
interface CircleOp { op: 'circle'; cx: number; cy: number; r: number; fill: Hex | null; stroke: Hex | null; strokeW: number }
interface LineOp { op: 'line'; x1: number; y1: number; x2: number; y2: number; color: Hex; w: number }
interface ImageOp { op: 'image'; path: string; x: number; y: number; w: number; h: number }
interface TextOp {
  op: 'text';
  x: number; y: number; w: number;
  text: string;
  field: string | null;
  font: string; size: number; color: Hex;
  align: 'left' | 'center' | 'right';
  valign: 'top' | 'middle' | 'bottom';
}
type Op = SolidOp | GradientOp | RectOp | RoundRectOp | CircleOp | LineOp | ImageOp | TextOp;
export interface TracePage { type: string; ops: Op[] }
export interface TemplateTrace { pageSize: [number, number]; pages: TracePage[] }

/** Everything `scaffoldTemplate` needs to render the traced template. */
export interface TraceRenderInputs {
  layoutSpec: LayoutSpec;
  gradients: Record<string, GradientSpec>;
  imagePaths: Record<string, string>;
  /** Draw ops the renderer cannot express (recorded for transparency). */
  skipped: { page: number; op: string }[];
}

const PAGE_W = 720;
const PAGE_H = 405;

/** Generator's `align` → LayoutElement's `align` vocabulary. */
const ALIGN: Record<TextOp['align'], 'start' | 'center' | 'end'> = {
  left: 'start',
  center: 'center',
  right: 'end',
};

/** A reportlab/PIL-style font name → the renderer's font role + numeric weight. */
function fontOf(name: string): { family: FontRole; weight: number } {
  const n = name.toLowerCase();
  const family: FontRole = /mono|jetbrains/.test(n) ? 'mono' : /inter/.test(n) ? 'body' : 'heading';
  const weight = /black/.test(n)
    ? 900
    : /extrabold|xbold/.test(n)
      ? 800
      : /semibold|sbold/.test(n)
        ? 600
        : /bold/.test(n)
          ? 700
          : /medium/.test(n)
            ? 500
            : /light|thin/.test(n)
              ? 300
              : 400;
  return { family, weight };
}

/**
 * Convert a template trace into render inputs — generator-contract page
 * (1920×1080, bottom-left origin) → 720×405 top-left page.
 */
export function traceToLayoutSpec(trace: TemplateTrace): TraceRenderInputs {
  const [srcW, srcH] = trace.pageSize;
  const S = PAGE_W / srcW; // uniform scale (both axes — the source is 16:9)
  const gradients: Record<string, GradientSpec> = {};
  const imagePaths: Record<string, string> = {};
  const skipped: { page: number; op: string }[] = [];

  /** Spec bottom-left y of a shape's bottom edge → top-left y, scaled. */
  const shapeTop = (yBottom: number, h: number): number => (srcH - yBottom - h) * S;
  /** Spec y of a text box's TOP edge → top-left y, scaled (text y is already top). */
  const textTop = (yTopSrc: number): number => (srcH - yTopSrc) * S;

  const slides: SlideTypeLayout[] = trace.pages.map((page, pageIdx) => {
    const elements: LayoutElement[] = [];
    page.ops.forEach((op, z) => {
      const id = `e${z}`;
      switch (op.op) {
        case 'solid': {
          // A full-page solid fill. Represent as a shape covering the page.
          elements.push({
            id, kind: 'shape', x: 0, y: 0, w: PAGE_W, h: PAGE_H, zOrder: z,
            color: op.color,
          });
          break;
        }
        case 'gradient': {
          // A full-page gradient. The generator's gradient is brand content
          // (per C1) declared as ordered (pos, hex) stops — the direction is
          // template-defined and we treat it as diagonal here (image-baker
          // bakes the actual pixels at render time).
          const gid = `grad${pageIdx}`;
          gradients[gid] = {
            width: srcW,
            height: srcH,
            colors: op.stops.map(([, hex]) => hex),
            direction: 'diagonal',
            positions: op.stops.map(([pos]) => pos),
          };
          elements.push({
            id: gid, kind: 'image', x: 0, y: 0, w: PAGE_W, h: PAGE_H, zOrder: z,
            content: { fixed: 'gradient' },
          });
          break;
        }
        case 'rect': {
          elements.push({
            id, kind: 'shape',
            x: op.x * S, y: shapeTop(op.y, op.h),
            w: op.w * S, h: op.h * S, zOrder: z,
            color: op.color,
          });
          break;
        }
        case 'roundRect': {
          if (!op.fill && !op.stroke) {
            skipped.push({ page: pageIdx + 1, op: 'roundRect (no fill/stroke)' });
            break;
          }
          const el: LayoutElement = {
            id, kind: 'shape', rounded: true,
            x: op.x * S, y: shapeTop(op.y, op.h),
            w: op.w * S, h: op.h * S, zOrder: z,
          };
          if (op.fill) el.color = op.fill;
          if (op.stroke) el.outline = { color: op.stroke, weight: Math.max((op.strokeW || 1) * S, 0.5) };
          elements.push(el);
          break;
        }
        case 'circle': {
          if (!op.fill && !op.stroke) {
            skipped.push({ page: pageIdx + 1, op: 'circle (no fill/stroke)' });
            break;
          }
          const el: LayoutElement = {
            id, kind: 'ellipse',
            x: (op.cx - op.r) * S, y: shapeTop(op.cy - op.r, op.r * 2),
            w: op.r * 2 * S, h: op.r * 2 * S, zOrder: z,
          };
          if (op.fill) el.color = op.fill;
          if (op.stroke) el.outline = { color: op.stroke, weight: Math.max((op.strokeW || 1) * S, 0.5) };
          elements.push(el);
          break;
        }
        case 'line': {
          const x0 = Math.min(op.x1, op.x2);
          const yBot = Math.min(op.y1, op.y2);
          const w = Math.abs(op.x2 - op.x1);
          const h = Math.abs(op.y2 - op.y1);
          // Spec y is up: the line "rises" (bottom-left → top-right) when the
          // higher-x endpoint also has the higher y.
          const leftIsP1 = op.x1 <= op.x2;
          const rising = (leftIsP1 ? op.y2 : op.y1) > (leftIsP1 ? op.y1 : op.y2);
          elements.push({
            id, kind: 'line',
            x: x0 * S, y: shapeTop(yBot, h),
            w: Math.max(w, 1) * S, h: Math.max(h, 1) * S,
            zOrder: z,
            color: op.color,
            outline: { color: op.color, weight: Math.max((op.w || 2) * S, 0.5) },
            lineFromBottomLeft: rising,
          });
          break;
        }
        case 'image': {
          // Image element ids must be unique ACROSS pages — `imagePaths` is
          // keyed by the bare element id.
          const imgId = `img${pageIdx}_${z}`;
          imagePaths[imgId] = op.path;
          elements.push({
            id: imgId, kind: 'image',
            x: op.x * S, y: shapeTop(op.y, op.h),
            w: op.w * S, h: op.h * S, zOrder: z,
            content: { fixed: 'image' },
          });
          break;
        }
        case 'text': {
          const { family, weight } = fontOf(op.font);
          const content: { field: string; sample: string } | { fixed: string } =
            op.field !== null
              ? { field: op.field, sample: op.text }
              : { fixed: op.text };
          elements.push({
            id, kind: 'text',
            x: op.x * S, y: textTop(op.y),
            w: op.w * S, h: op.size * 1.4 * S,
            zOrder: z,
            color: op.color,
            fontSize: op.size * S,
            fontWeight: weight,
            fontFamily: family,
            align: ALIGN[op.align],
            content,
          });
          break;
        }
      }
    });
    return { type: page.type, elements };
  });

  return { layoutSpec: { pageWidth: PAGE_W, pageHeight: PAGE_H, slides }, gradients, imagePaths, skipped };
}
