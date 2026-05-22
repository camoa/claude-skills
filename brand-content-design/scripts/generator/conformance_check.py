#!/usr/bin/env python3
"""
Conformance check for a template generator — generic.

Verifies that a template module conforms to the Template Generator Contract.
It is the regression guard for any template built on the generator library.

  1. Field declaration  — every SlideType declares a non-empty `fields` list
                          with ids unique within the type (contract C3/C4).
  2. Tag agreement      — the field= tags the draw functions emit match each
                          type's declared field set exactly.
  3. Text is a block    — every text element carries a positive numeric width
                          (contract C2).
  4. Sample stability   — the freshly generated sample PDF is render-identical
                          to the committed one, rasterised and compared page by
                          page (PDF metadata ignored).

Usage:
  python3 conformance_check.py <template-dir>

`<template-dir>` must contain a `deck_layout.py` template module exposing
`SLIDES`, `FONTS`, `FONT_DIR` and `SAMPLE_PDF` (path to the committed sample).

Exit 0 = conformant. Exit 1 = a violation. Exit 2 = bad invocation.
"""
import importlib
import os
import shutil
import subprocess
import sys
import tempfile

from deck_canvas import DeckCanvas, build


# --------------------------------------------------------------------------
# Capture: run build() (the sample deck) with a recording canvas that logs,
# per slide, every text element's field tag and width.
# --------------------------------------------------------------------------
def _capture_text_elements(slides):
    captured = []

    class RecordingCanvas(DeckCanvas):
        out = 'conformance'

        def start_slide(self):
            captured.append([])

        def save(self):
            pass

        def _solid(self, *a):
            pass

        def _gradient(self, *a):
            pass

        def _rect(self, *a):
            pass

        def _round_rect(self, *a):
            pass

        def _circle(self, *a):
            pass

        def _line(self, *a):
            pass

        def _image(self, *a):
            pass

        def _text_block(self, *a):
            pass

        # every text route (text/headline/para and template kicker helpers)
        # funnels through text()
        def text(self, s, x, y, w, font, size, color, align='left',
                 valign='top', field=None):
            captured[-1].append({'field': field, 'width': w})

    build(RecordingCanvas(), slides)
    return captured


# --------------------------------------------------------------------------
# Checks 1-3: field declaration, tag agreement, width presence.
# --------------------------------------------------------------------------
def _check_fields_and_widths(slides):
    errors = []
    captured = _capture_text_elements(slides)

    if len(captured) != len(slides):
        errors.append(f'build() drew {len(captured)} slides; '
                      f'SLIDES declares {len(slides)}')
        return errors

    for st, elements in zip(slides, captured):
        declared = [f.id for f in st.fields]

        if not declared:
            errors.append(f'[{st.type}] declares no fields')
        dupes = {i for i in declared if declared.count(i) > 1}
        if dupes:
            errors.append(f'[{st.type}] duplicate field ids: {sorted(dupes)}')

        emitted = {e['field'] for e in elements if e['field'] is not None}
        declared_set = set(declared)
        missing = declared_set - emitted
        stale = emitted - declared_set
        if missing:
            errors.append(f'[{st.type}] declared but never drawn: '
                          f'{sorted(missing)}')
        if stale:
            errors.append(f'[{st.type}] drawn with field= but not declared: '
                          f'{sorted(stale)}')

        for e in elements:
            w = e['width']
            if not isinstance(w, (int, float)) or w <= 0:
                tag = e['field'] or '(static)'
                errors.append(f'[{st.type}] text element {tag!r} has a '
                              f'non-positive width: {w!r}')

    return errors


# --------------------------------------------------------------------------
# Check 4: render-identity of the sample PDF.
# --------------------------------------------------------------------------
def _rasterize(pdf_path, out_prefix):
    """Rasterize a PDF to one PPM per page; return the list of page byte blobs."""
    subprocess.run(['pdftoppm', '-r', '96', pdf_path, out_prefix],
                   check=True, capture_output=True)
    pages = []
    d = os.path.dirname(out_prefix) or '.'
    base = os.path.basename(out_prefix)
    for name in sorted(os.listdir(d)):
        if name.startswith(base) and name.endswith('.ppm'):
            with open(os.path.join(d, name), 'rb') as f:
                pages.append(f.read())
    return pages


def _check_render_identity(template):
    """Regenerate the sample PDF and compare it, page by page, with the
    committed one. Returns (errors, skipped_reason)."""
    from pdf_backend import PdfCanvas

    committed = getattr(template, 'SAMPLE_PDF', None)
    if not committed or not os.path.exists(committed):
        return [], f'no committed sample PDF (template.SAMPLE_PDF={committed!r})'
    if shutil.which('pdftoppm') is None:
        return [], 'pdftoppm not on PATH — cannot rasterize'

    tmp = tempfile.mkdtemp(prefix='conformance_')
    try:
        fresh = os.path.join(tmp, 'fresh.pdf')
        build(PdfCanvas(fresh, template.FONTS, template.FONT_DIR),
              template.SLIDES)
        ref = _rasterize(committed, os.path.join(tmp, 'ref'))
        new = _rasterize(fresh, os.path.join(tmp, 'new'))
        errors = []
        if len(ref) != len(new):
            errors.append(f'page count differs: committed={len(ref)} '
                           f'fresh={len(new)}')
            return errors, None
        for i, (a, b) in enumerate(zip(ref, new), 1):
            if a != b:
                errors.append(f'page {i} is not render-identical to the '
                              f'committed sample PDF')
        return errors, None
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# --------------------------------------------------------------------------
def check_template(template):
    """Run all conformance checks against an imported template module.
    Returns a list of violation strings (empty => conformant)."""
    errors = []

    fw = _check_fields_and_widths(template.SLIDES)
    errors += fw
    n_fields = sum(len(st.fields) for st in template.SLIDES)
    if fw:
        print('  FAIL  field declaration / tag agreement / block width')
    else:
        print(f'  PASS  {len(template.SLIDES)} slide types, {n_fields} '
              f'declared fields — all tagged and widthed')

    ri, skipped = _check_render_identity(template)
    errors += ri
    if skipped:
        print(f'  SKIP  render-identity ({skipped})')
    elif ri:
        print('  FAIL  sample PDF render-identity')
    else:
        print('  PASS  sample PDF is render-identical to the committed one')

    return errors


def main(argv):
    if len(argv) != 2:
        print('usage: conformance_check.py <template-dir>', file=sys.stderr)
        return 2
    template_dir = os.path.abspath(argv[1])
    if not os.path.isfile(os.path.join(template_dir, 'deck_layout.py')):
        print(f'no deck_layout.py in {template_dir}', file=sys.stderr)
        return 2

    sys.path.insert(0, template_dir)
    template = importlib.import_module('deck_layout')
    print(f'conformance check — {template_dir}\n')
    errors = check_template(template)

    print()
    if errors:
        print(f'{len(errors)} conformance violation(s):')
        for e in errors:
            print(f'  - {e}')
        return 1
    print('CONFORMANT — the template meets the Template Generator Contract.')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
