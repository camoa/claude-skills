#!/usr/bin/env python3
"""
Template Generator Contract — the reusable layer.

This module is the canonical, version-controlled implementation of the
brand-content-design Template Generator Contract. It exists so that a
presentation template is *deterministic*: the template does not re-derive the
drawing machinery, it imports it from here.

A template is a thin module that:
  - imports `DeckCanvas`, `FieldSpec`, `SlideType`, `FontSpec`, `build` from here;
  - declares its own palette, fonts, slide functions and `SLIDES` registry;
  - is rendered by a backend (`pdf_backend.PdfCanvas`, `pptx_backend.PptxCanvas`)
    that subclasses `DeckCanvas`.

The five contract components implemented here:
  C1  DeckCanvas       — the abstract surface; backends implement only _-methods.
  C2  text-as-block    — `text()` takes an unwrapped string + a width; the
                         backend wraps. Anchored by the box TOP-LEFT, never a
                         baseline — no target-specific concept leaks into this
                         layer (it imports neither reportlab nor python-pptx).
  C3  SlideType        — one entry of a template's ordered SLIDES catalog.
  C4  FieldSpec        — every fillable draw carries field=; the call-site
                         string is that field's default (the sample value).
  C5  build()          — content=None → the sample deck; content → a presentation.

Contract document:
  brand-content-design/skills/brand-content-design/references/
  template-generator-contract.md

Coordinate space: 1920 x 1080 px, origin BOTTOM-LEFT, y increases UPWARD.
Shapes are placed by their bottom-left corner; text by the top-left of its box.
"""
from __future__ import annotations

import atexit
import os
import shutil
import tempfile
from dataclasses import dataclass
from typing import Callable

import cairosvg

# Standard 16:9 deck surface. A template imports these; a backend sizes its
# page/slide to them.
WIDTH, HEIGHT = 1920, 1080

# Lucide icon source — overridable via the LUCIDE_ICONS_DIR env var, or by
# reassigning this module global before the first icon() call.
ICON_DIR = os.environ.get(
    'LUCIDE_ICONS_DIR', '/home/camoa/node_modules/lucide-static/icons')

_ICON_TMP = tempfile.mkdtemp(prefix='deck_icons_')
atexit.register(shutil.rmtree, _ICON_TMP, ignore_errors=True)
_icon_cache = {}


def icon_png(name, hexcolor, px):
    """Recolor a Lucide SVG to hexcolor and rasterize it to a cached PNG.
    Backend-agnostic — produces a PNG file any backend places via _image."""
    key = (name, hexcolor, px)
    if key in _icon_cache:
        return _icon_cache[key]
    with open(os.path.join(ICON_DIR, name + '.svg'), encoding='utf-8') as f:
        svg = f.read()
    svg = svg.replace('currentColor', hexcolor)
    svg = svg.replace('stroke-width="2"', 'stroke-width="2.25"')
    out = os.path.join(_ICON_TMP, f'{name}_{hexcolor.lstrip("#")}_{px}.png')
    cairosvg.svg2png(bytestring=svg.encode('utf-8'), write_to=out,
                     output_width=px, output_height=px)
    _icon_cache[key] = out
    return out


# ==========================================================================
# C4 — field declaration. C3 — the slide-type registry entry.
# ==========================================================================
@dataclass
class FieldSpec:
    """One fillable field of a slide type (contract C4)."""
    id: str                           # vocabulary token: 'title','headline'...
    kind: str = 'text'                # 'text' | 'image'
    constraints: dict | None = None   # optional, e.g. {'max_words': 12}


@dataclass
class SlideType:
    """One entry of a template's ordered SLIDES catalog (contract C3)."""
    type: str                         # stable id, e.g. 'concept'
    draw: Callable[['DeckCanvas'], None]
    fields: list[FieldSpec]


@dataclass
class FontSpec:
    """A template's logical font. `file` is the ttf filename, `pptx` the
    installed PPTX family name, `bold` the PPTX bold flag, and `ascent` the
    box-top → first-line-baseline inset as a fraction of the font size — used
    only by a baseline-drawing backend (the PDF backend); the spec layer and
    the PPTX/Slides backends never touch it."""
    file: str
    pptx: str
    bold: bool
    ascent: float


# ==========================================================================
# C1 / C2 — the abstract drawing surface. Backends subclass this and implement
# only the _-prefixed primitives; the public methods are backend-agnostic and
# carry no layout logic, no content, no target-specific concept.
# ==========================================================================
class DeckCanvas:
    out = None         # backend sets the output path
    content = None     # field_id -> value, or None => render every default

    # ---- primitives: a backend MUST implement these ----
    def start_slide(self):
        raise NotImplementedError

    def save(self):
        raise NotImplementedError

    def _solid(self, color):
        raise NotImplementedError

    def _gradient(self, stops):
        raise NotImplementedError

    def _rect(self, x, y, w, h, color):
        raise NotImplementedError

    def _round_rect(self, x, y, w, h, r, fill, stroke, stroke_w):
        raise NotImplementedError

    def _circle(self, cx, cy, r, fill, stroke, stroke_w):
        raise NotImplementedError

    def _line(self, x1, y1, x2, y2, color, w):
        raise NotImplementedError

    def _image(self, path, x, y, w, h):
        raise NotImplementedError

    def _text_block(self, s, x, y, w, h, font, size, color, align, valign):
        """Draw text as a block: (x, y) is the box TOP-LEFT; the backend wraps
        `s` to width `w` itself. One logical text element => one wrapped block
        (one PPTX text box, one Slides text element). No pre-wrapping."""
        raise NotImplementedError

    # ---- public drawing API (slide functions call these) ----
    def solid(self, color):
        self._solid(color)

    def gradient(self, stops):
        """`stops` is an ordered list of (position 0..1, hex) — the gradient is
        brand content the template declares, never hard-coded in a backend."""
        self._gradient(stops)

    def rect(self, x, y, w, h, color):
        self._rect(x, y, w, h, color)

    def round_rect(self, x, y, w, h, r, fill=None, stroke=None, stroke_w=0):
        self._round_rect(x, y, w, h, r, fill, stroke, stroke_w)

    def circle(self, cx, cy, r, fill=None, stroke=None, stroke_w=0):
        self._circle(cx, cy, r, fill, stroke, stroke_w)

    def line(self, x1, y1, x2, y2, color, w):
        self._line(x1, y1, x2, y2, color, w)

    def image(self, path, x, y, w, h):
        self._image(path, x, y, w, h)

    def icon(self, name, hexcolor, cx, cy, d):
        """Draw a Lucide icon centred at (cx, cy) at display size d."""
        self._image(icon_png(name, hexcolor, int(d * 3)),
                    cx - d / 2, cy - d / 2, d, d)

    # ---- C2: text as a block ----
    def text(self, s, x, y, w, font, size, color, align='left', valign='top',
             field=None):
        """Draw a text block. (x, y) is the anchor point — for align='left' the
        box top-left, 'center' the top-centre, 'right' the top-right. `w` is the
        wrap width. If `field` is set and the canvas carries a content map with
        that field, its value is drawn; otherwise `s` is drawn — so `s` is the
        field's default. The backend wraps; this layer never pre-wraps."""
        value = s
        if field is not None and self.content and field in self.content:
            value = self.content[field]
        if align == 'center':
            bx = x - w / 2
        elif align == 'right':
            bx = x - w
        else:
            bx = x
        self._text_block(value, bx, y, w, size * 1.4, font, size, color,
                         align, valign)

    def headline(self, s, x, y, w, font, size, color, field=None):
        """A slide's headline. Thin wrapper over text() — never loops lines."""
        self.text(s, x, y, w, font, size, color, field=field)

    def para(self, s, x, y, w, font, size, color, field=None):
        """Body copy. Thin wrapper over text() — never loops lines."""
        self.text(s, x, y, w, font, size, color, field=field)


# ==========================================================================
# C5 — build. content=None => the sample deck (every field's default);
# content => a presentation (the outline's per-slide field values).
# ==========================================================================
def build(canvas, slides, content=None):
    """Render a template's SLIDES registry onto a backend canvas.

    slides   — the template's ordered list of SlideType.
    content  — None => one slide of every SlideType, all defaults (the sample);
               a list of {'type': <type_id>, 'values': {field_id: value}}
               => one slide per entry, fields filled from `values`.
    """
    by_type = {st.type: st for st in slides}
    if content is None:
        plan = [(st, None) for st in slides]
        mode = 'sample'
    else:
        plan = []
        for entry in content:
            st = by_type.get(entry['type'])
            if st is None:
                raise SystemExit(f"Unknown slide type: {entry['type']!r}")
            plan.append((st, entry.get('values')))
        mode = 'presentation'
    print(f'build: {len(plan)} slides ({mode})')
    for i, (st, values) in enumerate(plan):
        canvas.start_slide()
        canvas.content = values
        st.draw(canvas)
        print(f'  [{i + 1:2d}/{len(plan)}] {st.type}')
    canvas.save()
    print(f'Saved: {canvas.out}')
