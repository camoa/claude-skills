#!/usr/bin/env python3
"""
Template tracer — capture a template's exact layout via the committed
generator-library contract.

After the Template Generator Contract shipped (sibling `scripts/generator/`), a
template is a thin module importing `DeckCanvas`, `FieldSpec`, `SlideType`,
`FontSpec`, `build` from that library. The tracer is now just another backend
alongside `PdfCanvas` and `PptxCanvas`: a `TracingCanvas(DeckCanvas)` that
records every public draw call to JSON instead of rendering. Because it sits at
the spec layer, it captures the `field=` tag on each fillable text element
(C4) — which is exactly what `src/trace-to-layout.ts` needs to emit
`{ field, sample }` LayoutElement content.

Usage:
    python3 trace-template.py <template-dir> <out.json>

`<template-dir>` must expose a `deck_layout` module with `SLIDES`, `FONTS`,
`FONT_DIR` (the conformance-check contract). Static asset bytes (icon PNGs,
logos, photos) drawn by `image()` are copied to `<out.json>-assets/` so the
trace stays valid after the generator's tempdirs are cleaned up.

Output JSON shape (one entry per page):
    {
      "pageSize": [W, H],
      "pages": [
        {
          "type": "<slide-type-id>",
          "ops": [
            {"op": "solid", "color": "#RRGGBB"},
            {"op": "gradient", "stops": [[pos, "#RRGGBB"], ...]},
            {"op": "text", "x", "y", "w", "text", "field": <str|null>,
             "font", "size", "color", "align", "valign"},
            {"op": "rect" | "roundRect" | "circle" | "line" | "image", ...},
            ...
          ]
        },
        ...
      ]
    }

The per-page `type` is the template's declared `SlideType.type` (the registry id
that downstream code — `TagMap`, outline parser, payload — keys on).

`field` is `null` for static chrome (logos, decoration); non-null for every
fillable draw. The text op carries the call-site default in `text` AND the
field tag — `slides/src/trace-to-layout.ts` uses both: `sample = text`,
`field = field`.
"""
import importlib
import json
import os
import shutil
import sys

# Locate the committed generator library: ../../generator/ relative to this file.
_GEN_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', 'generator'))
sys.path.insert(0, _GEN_DIR)

from deck_canvas import DeckCanvas, build, WIDTH, HEIGHT  # noqa: E402


class TracingCanvas(DeckCanvas):
    """A DeckCanvas backend whose 'render' is recording the calls."""

    def __init__(self, assets_dir=None):
        self.out = '<trace>'
        self.pages = []          # one {type, ops} entry per slide, in order
        self._current_ops = None # alias of pages[-1]['ops'] for fast append
        self._assets_dir = assets_dir
        self._img_counter = 0

    # ---- page lifecycle (C1) ----
    def start_slide(self):
        # build() (from generator.deck_canvas) sets canvas.content per slide
        # AFTER start_slide() returns; we don't know the type id from start_slide
        # alone. Open the page with an empty type placeholder; trace_template()
        # back-fills `type` from the SLIDES iteration order it controls.
        entry = {'type': None, 'ops': []}
        self.pages.append(entry)
        self._current_ops = entry['ops']

    def save(self):
        # Nothing to flush; pages were collected as they were drawn.
        pass

    # ---- public text() override (C2 + C4) — capture `field` at the spec layer ----
    def text(self, s, x, y, w, font, size, color, align='left', valign='top',
             field=None):
        # Mirror the base's content+align resolution exactly, then record.
        value = s
        if field is not None and self.content and field in self.content:
            value = self.content[field]
        if align == 'center':
            bx = x - w / 2
        elif align == 'right':
            bx = x - w
        else:
            bx = x
        self._current_ops.append({
            'op': 'text',
            'x': bx, 'y': y, 'w': w,
            'text': value,
            'field': field,
            'font': font, 'size': size, 'color': color,
            'align': align, 'valign': valign,
        })

    # ---- _-primitive recorders (C1) ----
    def _text_block(self, *a):
        # text() captures everything we need; the abstract _text_block route
        # is the PDF/PPTX backend's internal seam — irrelevant to the trace.
        pass

    def _solid(self, color):
        self._current_ops.append({'op': 'solid', 'color': color})

    def _gradient(self, stops):
        # Stops normalize to a JSON-serializable list of [position, hex].
        self._current_ops.append({
            'op': 'gradient',
            'stops': [[float(p), c] for p, c in stops],
        })

    def _rect(self, x, y, w, h, color):
        self._current_ops.append({
            'op': 'rect', 'x': x, 'y': y, 'w': w, 'h': h, 'color': color,
        })

    def _round_rect(self, x, y, w, h, r, fill, stroke, stroke_w):
        self._current_ops.append({
            'op': 'roundRect',
            'x': x, 'y': y, 'w': w, 'h': h, 'r': r,
            'fill': fill, 'stroke': stroke, 'strokeW': stroke_w,
        })

    def _circle(self, cx, cy, r, fill, stroke, stroke_w):
        self._current_ops.append({
            'op': 'circle',
            'cx': cx, 'cy': cy, 'r': r,
            'fill': fill, 'stroke': stroke, 'strokeW': stroke_w,
        })

    def _line(self, x1, y1, x2, y2, color, w):
        self._current_ops.append({
            'op': 'line', 'x1': x1, 'y1': y1, 'x2': x2, 'y2': y2,
            'color': color, 'w': w,
        })

    def _image(self, path, x, y, w, h):
        # Generators draw recoloured icons from tempdirs that get cleaned up
        # at process exit (see icon_png in generator/deck_canvas.py). Copy the
        # bytes into our persistent assets dir so the trace stays usable.
        copied = path
        if self._assets_dir and os.path.isfile(path):
            self._img_counter += 1
            base = os.path.basename(path) or 'img'
            dst = os.path.join(self._assets_dir,
                               f'{self._img_counter}_{base}')
            try:
                shutil.copy(path, dst)
                copied = dst
            except OSError:
                copied = path
        self._current_ops.append({
            'op': 'image', 'path': copied, 'x': x, 'y': y, 'w': w, 'h': h,
        })


def trace_template(template_dir, out_path):
    """Build the template with a TracingCanvas; write the JSON trace.
    Returns the in-memory canvas for callers that want to assert on it."""
    template_dir = os.path.abspath(template_dir)
    out_path = os.path.abspath(out_path)
    assets_dir = out_path + '-assets'
    os.makedirs(assets_dir, exist_ok=True)

    sys.path.insert(0, template_dir)
    # Force re-import so the same process can trace multiple templates safely
    # (matters for the self-test more than for CLI use, but cheap to do here).
    if 'deck_layout' in sys.modules:
        del sys.modules['deck_layout']
    template = importlib.import_module('deck_layout')

    canvas = TracingCanvas(assets_dir=assets_dir)
    build(canvas, template.SLIDES)

    # Back-fill page-level type ids in the SLIDES order build() drew them
    # (the sample deck draws one slide per SlideType).
    if len(canvas.pages) != len(template.SLIDES):
        sys.stderr.write(
            f'WARNING: traced {len(canvas.pages)} page(s) but SLIDES declares '
            f'{len(template.SLIDES)}; type ids will be partial.\n')
    for page, st in zip(canvas.pages, template.SLIDES):
        page['type'] = st.type

    with open(out_path, 'w') as f:
        json.dump({'pageSize': [WIDTH, HEIGHT], 'pages': canvas.pages}, f)
    sys.stderr.write(f'traced {len(canvas.pages)} page(s) → {out_path}\n')
    return canvas


def main(argv):
    if len(argv) != 3:
        sys.stderr.write('usage: trace-template.py <template-dir> <out.json>\n')
        return 2
    trace_template(argv[1], argv[2])
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
