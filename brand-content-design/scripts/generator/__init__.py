"""
Template generator library — the reusable layer of the brand-content-design
Template Generator Contract.

A presentation template imports this package; it does not re-derive the drawing
machinery. The contract document is at
`brand-content-design/skills/brand-content-design/references/template-generator-contract.md`.

Public API:
  DeckCanvas, FieldSpec, SlideType, FontSpec, build, icon_png, WIDTH, HEIGHT
                                  — the contract (deck_canvas)
  PdfCanvas                       — reportlab backend (pdf_backend)
  PptxCanvas                      — python-pptx backend (pptx_backend)
  check_template                  — conformance check (conformance_check)
"""
from .deck_canvas import (
    DeckCanvas, FieldSpec, SlideType, FontSpec, build, icon_png, WIDTH, HEIGHT,
)
from .pdf_backend import PdfCanvas
from .pptx_backend import PptxCanvas
from .conformance_check import check_template

__all__ = [
    'DeckCanvas', 'FieldSpec', 'SlideType', 'FontSpec', 'build', 'icon_png',
    'WIDTH', 'HEIGHT', 'PdfCanvas', 'PptxCanvas', 'check_template',
]
