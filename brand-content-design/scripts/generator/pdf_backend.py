#!/usr/bin/env python3
"""
PDF backend for the template generator — reportlab.

`PdfCanvas` subclasses `DeckCanvas` and renders to a PDF. It is
template-agnostic: the template's font table (a `{logical_name: FontSpec}` map)
and font directory are passed to the constructor.

Text-as-block (contract C2): the spec passes an unwrapped string + a box width;
this backend wraps the string itself (`_wrap`) and draws the lines from the box
top. reportlab draws from the baseline, so the box-top → baseline inset is
applied here from each `FontSpec.ascent` — a PDF-backend concern that never
appears in the shared layer.
"""
import os

from reportlab.pdfgen import canvas
from reportlab.lib.colors import HexColor
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont

from deck_canvas import DeckCanvas, WIDTH, HEIGHT


def _wrap(s, font, size, maxw):
    """Greedy word-wrap `s` to width `maxw`. Wrapping is a render concern
    (contract C2), never the shared layer's. A string that already fits is
    returned verbatim, so its internal/leading whitespace is preserved; only a
    string that genuinely overflows the width is re-spaced."""
    if pdfmetrics.stringWidth(s, font, size) <= maxw:
        return [s]
    words, lines, cur = s.split(), [], ''
    for word in words:
        trial = word if not cur else cur + ' ' + word
        if pdfmetrics.stringWidth(trial, font, size) <= maxw:
            cur = trial
        else:
            if cur:
                lines.append(cur)
            cur = word
    if cur:
        lines.append(cur)
    return lines or ['']


class PdfCanvas(DeckCanvas):
    """Renders the abstract DeckCanvas primitives to a PDF via reportlab."""

    def __init__(self, out, fonts, font_dir):
        """fonts: {logical_name: FontSpec}; font_dir: directory of the ttf files.
        Each font is registered with reportlab; a missing file fails loudly."""
        self.out = out
        self.fonts = fonts
        for name, fs in fonts.items():
            path = os.path.join(font_dir, fs.file)
            if not os.path.exists(path):
                raise SystemExit(f'Font missing: {path} — cannot render PDF.')
            try:
                pdfmetrics.registerFont(TTFont(name, path))
            except Exception:
                pass
        self.c = canvas.Canvas(out, pagesize=(WIDTH, HEIGHT))
        self._n = 0

    def start_slide(self):
        if self._n:
            self.c.showPage()
        self._n += 1

    def save(self):
        self.c.showPage()
        self.c.save()

    def _solid(self, color):
        self.c.setFillColor(HexColor(color))
        self.c.rect(0, 0, WIDTH, HEIGHT, fill=1, stroke=0)

    def _gradient(self, stops):
        self.c.linearGradient(
            0, HEIGHT, WIDTH, 0,
            [HexColor(c) for _, c in stops],
            positions=[p for p, _ in stops], extend=True)

    def _rect(self, x, y, w, h, color):
        self.c.setFillColor(HexColor(color))
        self.c.rect(x, y, w, h, fill=1, stroke=0)

    def _round_rect(self, x, y, w, h, r, fill, stroke, stroke_w):
        if fill:
            self.c.setFillColor(HexColor(fill))
        if stroke:
            self.c.setStrokeColor(HexColor(stroke))
            self.c.setLineWidth(stroke_w)
        self.c.roundRect(x, y, w, h, r,
                         fill=1 if fill else 0, stroke=1 if stroke else 0)

    def _circle(self, cx, cy, r, fill, stroke, stroke_w):
        if fill:
            self.c.setFillColor(HexColor(fill))
        if stroke:
            self.c.setStrokeColor(HexColor(stroke))
            self.c.setLineWidth(stroke_w)
        self.c.circle(cx, cy, r,
                      fill=1 if fill else 0, stroke=1 if stroke else 0)

    def _line(self, x1, y1, x2, y2, color, w):
        self.c.setStrokeColor(HexColor(color))
        self.c.setLineWidth(w)
        self.c.line(x1, y1, x2, y2)

    def _text_block(self, s, x, y, w, h, font, size, color, align, valign):
        """(x, y) is the text box top-left, y measured up from the page bottom.
        Wrap `s` to width `w`, then draw each line. The first line's baseline
        sits one ascent below the block top — the inset comes from the font's
        FontSpec.ascent, so authoring (the box top) and rendering (the baseline)
        use the identical ratio."""
        if not s:
            return
        lines = _wrap(s, font, size, w)
        leading = size * 1.25
        ascent = size * self.fonts[font].ascent
        block_h = leading * len(lines)
        if valign == 'middle':
            block_top = y - (h - block_h) / 2
        elif valign == 'bottom':
            block_top = y - (h - block_h)
        else:                                    # 'top'
            block_top = y
        self.c.setFillColor(HexColor(color))
        self.c.setFont(font, size)
        baseline = block_top - ascent
        for line in lines:
            if align == 'center':
                self.c.drawCentredString(x + w / 2, baseline, line)
            elif align == 'right':
                self.c.drawRightString(x + w, baseline, line)
            else:
                self.c.drawString(x, baseline, line)
            baseline -= leading

    def _image(self, path, x, y, w, h):
        try:
            self.c.drawImage(path, x, y, width=w, height=h, mask='auto')
        except Exception:
            pass
