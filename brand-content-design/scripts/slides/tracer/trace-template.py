#!/usr/bin/env python3
"""
Template tracer — capture a template's exact layout from its reportlab generator.

`brand-content-design` templates ship a `generate_sample.py` that draws the
template's `sample.pdf` with reportlab. This script runs that generator through
an **instrumented `Canvas`** that records every primitive draw call — text runs
(with position, font, size, colour, alignment), rectangles, rounded rectangles,
circles, lines, gradients, images — as structured JSON, one page at a time.

The Slides renderer converts that JSON into a `LayoutSpec` (see
`src/trace-to-layout.ts`), so the Google Slides output reproduces the PDF *by
construction* — same geometry, same content. Generic: works on any template's
`generate_sample.py`, no per-template code.

Usage:
    python3 trace-template.py <path/to/generate_sample.py> <out-trace.json>

The generator's own PDF write is redirected to a throwaway file — the template's
`sample.pdf` is never touched.
"""
import json
import sys
import tempfile

from reportlab.pdfgen import canvas as _canvas_mod


def _rgb(color):
    """A reportlab colour → an [r,g,b] list of 0–1 floats."""
    try:
        return [round(color.red, 4), round(color.green, 4), round(color.blue, 4)]
    except AttributeError:
        return [0, 0, 0]


_pages = []          # finished pages, each a list of op dicts
_current = []        # ops on the page being drawn
_pagesize = [1920, 1080]


class RecordingCanvas(_canvas_mod.Canvas):
    """A reportlab Canvas that records every draw call and still renders."""

    def __init__(self, filename, *args, **kwargs):
        # Redirect the generator's PDF to a throwaway — never touch sample.pdf.
        self._trace_throwaway = tempfile.NamedTemporaryFile(suffix='.pdf', delete=False)
        super().__init__(self._trace_throwaway.name, *args, **kwargs)
        self._font = ('Helvetica', 12)
        self._fill = [0, 0, 0]
        self._stroke = [0, 0, 0]
        self._linewidth = 1.0
        global _pagesize, _current
        _pagesize = [self._pagesize[0], self._pagesize[1]]
        _current = []

    # --- state tracking ---
    def setFont(self, name, size, *a, **kw):
        self._font = (name, size)
        return super().setFont(name, size, *a, **kw)

    def setFillColor(self, color, *a, **kw):
        self._fill = _rgb(color)
        return super().setFillColor(color, *a, **kw)

    def setFillColorRGB(self, r, g, b, *a, **kw):
        self._fill = [r, g, b]
        return super().setFillColorRGB(r, g, b, *a, **kw)

    def setStrokeColor(self, color, *a, **kw):
        self._stroke = _rgb(color)
        return super().setStrokeColor(color, *a, **kw)

    def setStrokeColorRGB(self, r, g, b, *a, **kw):
        self._stroke = [r, g, b]
        return super().setStrokeColorRGB(r, g, b, *a, **kw)

    def setLineWidth(self, width, *a, **kw):
        self._linewidth = width
        return super().setLineWidth(width, *a, **kw)

    # --- recorded draw calls ---
    def _text(self, x, y, text, align):
        _current.append({'op': 'text', 'x': x, 'y': y, 'text': text, 'align': align,
                         'font': self._font[0], 'size': self._font[1], 'color': list(self._fill)})

    def drawString(self, x, y, text, *a, **kw):
        self._text(x, y, text, 'start')
        return super().drawString(x, y, text, *a, **kw)

    def drawCentredString(self, x, y, text, *a, **kw):
        self._text(x, y, text, 'center')
        return super().drawCentredString(x, y, text, *a, **kw)

    def drawRightString(self, x, y, text, *a, **kw):
        self._text(x, y, text, 'end')
        return super().drawRightString(x, y, text, *a, **kw)

    def rect(self, x, y, w, h, stroke=1, fill=0, *a, **kw):
        _current.append({'op': 'rect', 'x': x, 'y': y, 'w': w, 'h': h,
                         'fill': bool(fill), 'stroke': bool(stroke),
                         'color': list(self._fill), 'strokeColor': list(self._stroke)})
        return super().rect(x, y, w, h, stroke=stroke, fill=fill, *a, **kw)

    def roundRect(self, x, y, w, h, radius, stroke=1, fill=0, *a, **kw):
        _current.append({'op': 'roundRect', 'x': x, 'y': y, 'w': w, 'h': h, 'radius': radius,
                         'fill': bool(fill), 'stroke': bool(stroke),
                         'color': list(self._fill), 'strokeColor': list(self._stroke)})
        return super().roundRect(x, y, w, h, radius, stroke=stroke, fill=fill, *a, **kw)

    def circle(self, cx, cy, r, stroke=1, fill=0, *a, **kw):
        _current.append({'op': 'circle', 'cx': cx, 'cy': cy, 'r': r,
                         'fill': bool(fill), 'stroke': bool(stroke),
                         'color': list(self._fill), 'strokeColor': list(self._stroke)})
        return super().circle(cx, cy, r, stroke=stroke, fill=fill, *a, **kw)

    def ellipse(self, x1, y1, x2, y2, stroke=1, fill=0, *a, **kw):
        _current.append({'op': 'ellipse', 'x': min(x1, x2), 'y': min(y1, y2),
                         'w': abs(x2 - x1), 'h': abs(y2 - y1),
                         'fill': bool(fill), 'stroke': bool(stroke),
                         'color': list(self._fill), 'strokeColor': list(self._stroke)})
        return super().ellipse(x1, y1, x2, y2, stroke=stroke, fill=fill, *a, **kw)

    def line(self, x1, y1, x2, y2, *a, **kw):
        _current.append({'op': 'line', 'x1': x1, 'y1': y1, 'x2': x2, 'y2': y2,
                         'width': self._linewidth, 'color': list(self._stroke)})
        return super().line(x1, y1, x2, y2, *a, **kw)

    def linearGradient(self, x0, y0, x1, y1, colors, positions=None, *a, **kw):
        _current.append({'op': 'gradient', 'x0': x0, 'y0': y0, 'x1': x1, 'y1': y1,
                         'colors': [_rgb(c) for c in colors],
                         'positions': list(positions) if positions else None})
        return super().linearGradient(x0, y0, x1, y1, colors, positions=positions, *a, **kw)

    def drawImage(self, image, x, y, width=None, height=None, *a, **kw):
        _current.append({'op': 'image', 'path': str(image), 'x': x, 'y': y,
                         'w': width, 'h': height})
        return super().drawImage(image, x, y, width=width, height=height, *a, **kw)

    def showPage(self, *a, **kw):
        global _current
        _pages.append(_current)
        _current = []
        return super().showPage(*a, **kw)


def main():
    if len(sys.argv) != 3:
        sys.stderr.write('usage: trace-template.py <generate_sample.py> <out.json>\n')
        sys.exit(2)
    gen_path, out_path = sys.argv[1], sys.argv[2]

    # Instrument: every `canvas.Canvas(...)` in the generator becomes a recorder.
    _canvas_mod.Canvas = RecordingCanvas

    with open(gen_path) as f:
        source = f.read()
    exec(compile(source, gen_path, 'exec'), {'__name__': '__main__'})

    # `save()` flushes a final un-showPage'd page; capture it if present.
    if _current:
        _pages.append(_current)

    with open(out_path, 'w') as f:
        json.dump({'pageSize': _pagesize, 'pages': _pages}, f)
    sys.stderr.write(f'traced {len(_pages)} page(s) → {out_path}\n')


if __name__ == '__main__':
    main()
