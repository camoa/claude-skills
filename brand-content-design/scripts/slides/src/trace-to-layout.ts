/**
 * Trace → LayoutSpec converter.
 *
 * Turns a `tracer/trace-template.py` capture (every reportlab draw call of a
 * template's `generate_sample.py`) into a `LayoutSpec` the Slides renderer
 * scaffolds. Because the trace is the PDF's own draw list, the Google Slides
 * output reproduces `sample.pdf` *by construction* — same geometry, same
 * content, same colours. Generic: no per-template code.
 *
 * The trace is in reportlab space (bottom-left origin, page in points); this
 * converts to the renderer's 720×405 top-left point space.
 */
import type { LayoutSpec, LayoutElement, SlideTypeLayout, FontRole } from './layout-spec.js';
import type { GradientSpec } from './image-baker.js';

/* ---- the trace shape (mirrors tracer/trace-template.py output) ---- */
type RGB = [number, number, number];
interface TextOp { op: 'text'; x: number; y: number; text: string; align: 'start' | 'center' | 'end'; font: string; size: number; color: RGB }
interface RectOp { op: 'rect' | 'roundRect'; x: number; y: number; w: number; h: number; radius?: number; fill: boolean; stroke: boolean; color: RGB; strokeColor: RGB }
interface CircleOp { op: 'circle'; cx: number; cy: number; r: number; fill: boolean; color: RGB }
interface EllipseOp { op: 'ellipse'; x: number; y: number; w: number; h: number; fill: boolean; color: RGB }
interface GradientOp { op: 'gradient'; x0: number; y0: number; x1: number; y1: number; colors: RGB[]; positions: number[] | null }
interface ImageOp { op: 'image'; path: string; x: number; y: number; w: number | null; h: number | null }
interface LineOp { op: 'line'; x1: number; y1: number; x2: number; y2: number; width: number; color: RGB }
type Op = TextOp | RectOp | CircleOp | EllipseOp | GradientOp | ImageOp | LineOp;
export interface TemplateTrace { pageSize: [number, number]; pages: Op[][] }

/** Everything `scaffoldTemplate` needs to render the traced template. */
export interface TraceRenderInputs {
  layoutSpec: LayoutSpec;
  gradients: Record<string, GradientSpec>;
  imagePaths: Record<string, string>;
  /** Draw ops the renderer cannot yet express (stroke-only shapes, lines). */
  skipped: { page: number; op: string }[];
}

const PAGE_W = 720;
const PAGE_H = 405;

/** A reportlab 0–1 RGB triple → `#RRGGBB`. */
function hex(rgb: RGB): string {
  return (
    '#' +
    rgb
      .map((c) => Math.round(Math.min(1, Math.max(0, c)) * 255).toString(16).padStart(2, '0'))
      .join('')
  );
}

/** A reportlab font name → the renderer's font role + numeric weight. */
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
 * Convert a template trace into render inputs. `scaleW`/`scaleH` map the
 * reportlab page onto the 720×405 renderer page; `flip` converts the
 * bottom-left origin to top-left.
 */
export function traceToLayoutSpec(trace: TemplateTrace): TraceRenderInputs {
  const [srcW, srcH] = trace.pageSize;
  const S = PAGE_W / srcW; // uniform scale (16:9 in, 16:9 out)
  const gradients: Record<string, GradientSpec> = {};
  const imagePaths: Record<string, string> = {};
  const skipped: { page: number; op: string }[] = [];

  /** reportlab bottom-left y of an element's bottom edge → top-left y, scaled. */
  const top = (yBottom: number, h: number): number => (srcH - yBottom - h) * S;

  const slides: SlideTypeLayout[] = trace.pages.map((page, pageIdx) => {
    const elements: LayoutElement[] = [];
    page.forEach((op, z) => {
      const id = `e${z}`;
      if (op.op === 'gradient') {
        const gid = `grad${pageIdx}`;
        const horizontal = Math.abs(op.y0 - op.y1) < 1;
        const vertical = Math.abs(op.x0 - op.x1) < 1;
        gradients[gid] = {
          width: srcW,
          height: srcH,
          colors: op.colors.map(hex),
          direction: horizontal ? 'horizontal' : vertical ? 'vertical' : 'diagonal',
          ...(op.positions ? { positions: op.positions } : {}),
        };
        elements.push({ id: gid, kind: 'image', x: 0, y: 0, w: PAGE_W, h: PAGE_H, zOrder: z, content: { fixed: 'gradient' } });
      } else if (op.op === 'rect' || op.op === 'roundRect') {
        if (!op.fill) {
          skipped.push({ page: pageIdx + 1, op: `${op.op} (stroke-only)` });
          return;
        }
        elements.push({
          id,
          kind: 'shape',
          x: op.x * S,
          y: top(op.y, op.h),
          w: op.w * S,
          h: op.h * S,
          zOrder: z,
          color: hex(op.color),
          ...(op.op === 'roundRect' ? { rounded: true } : {}),
        });
      } else if (op.op === 'circle') {
        if (!op.fill) {
          skipped.push({ page: pageIdx + 1, op: 'circle (stroke-only)' });
          return;
        }
        elements.push({
          id,
          kind: 'ellipse',
          x: (op.cx - op.r) * S,
          y: top(op.cy - op.r, op.r * 2),
          w: op.r * 2 * S,
          h: op.r * 2 * S,
          zOrder: z,
          color: hex(op.color),
        });
      } else if (op.op === 'ellipse') {
        if (!op.fill) {
          skipped.push({ page: pageIdx + 1, op: 'ellipse (stroke-only)' });
          return;
        }
        elements.push({ id, kind: 'ellipse', x: op.x * S, y: top(op.y, op.h), w: op.w * S, h: op.h * S, zOrder: z, color: hex(op.color) });
      } else if (op.op === 'image') {
        // Image element ids must be unique ACROSS pages — `imagePaths` (and the
        // scaffolder's resolved-URL map) is keyed by the bare element id.
        const imgId = `img${pageIdx}_${z}`;
        imagePaths[imgId] = op.path;
        elements.push({
          id: imgId,
          kind: 'image',
          x: op.x * S,
          y: top(op.y, op.h ?? 0),
          w: (op.w ?? 0) * S,
          h: (op.h ?? 0) * S,
          zOrder: z,
          content: { fixed: 'image' },
        });
      } else if (op.op === 'text') {
        const { family, weight } = fontOf(op.font);
        const fontSize = op.size * S;
        // reportlab y is the text baseline; the box top sits ~one font-size above it.
        const yTop = (srcH - op.y - op.size) * S;
        const h = op.size * 1.4 * S;
        // Honour the reportlab anchor: start = left edge at x; center/end use a
        // generous box positioned so the anchor lands at x.
        let x: number;
        let w: number;
        if (op.align === 'center') {
          w = 1000 * S;
          x = op.x * S - w / 2;
        } else if (op.align === 'end') {
          w = 1000 * S;
          x = op.x * S - w;
        } else {
          x = op.x * S;
          w = (srcW - op.x) * S;
        }
        elements.push({
          id,
          kind: 'text',
          x,
          y: yTop,
          w,
          h,
          zOrder: z,
          color: hex(op.color),
          fontSize,
          fontWeight: weight,
          fontFamily: family,
          align: op.align,
          content: { fixed: op.text },
        });
      } else if (op.op === 'line') {
        // Horizontal / vertical lines (accent underlines, column dividers) become
        // thin rectangles — exact, no renderer change. Diagonals are skipped.
        const lw = op.width || 2;
        if (Math.abs(op.y1 - op.y2) < 1) {
          const x0 = Math.min(op.x1, op.x2);
          const w = Math.abs(op.x2 - op.x1);
          elements.push({ id, kind: 'shape', x: x0 * S, y: top(op.y1 - lw / 2, lw), w: w * S, h: lw * S, zOrder: z, color: hex(op.color) });
        } else if (Math.abs(op.x1 - op.x2) < 1) {
          const y0 = Math.min(op.y1, op.y2);
          const h = Math.abs(op.y2 - op.y1);
          elements.push({ id, kind: 'shape', x: (op.x1 - lw / 2) * S, y: top(y0, h), w: lw * S, h: h * S, zOrder: z, color: hex(op.color) });
        } else {
          skipped.push({ page: pageIdx + 1, op: 'line (diagonal)' });
        }
      }
    });
    return { type: `p${pageIdx + 1}`, elements };
  });

  return { layoutSpec: { pageWidth: PAGE_W, pageHeight: PAGE_H, slides }, gradients, imagePaths, skipped };
}
