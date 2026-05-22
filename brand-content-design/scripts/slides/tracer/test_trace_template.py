#!/usr/bin/env python3
"""
Self-test for trace-template.py — the A2 acceptance check.

Builds a synthetic 2-slide template inline (no committed-template dependency),
runs the tracer against it, and asserts:

  1. Every fillable text op carries its declared `field`.
  2. Every static-chrome text op carries `field: null`.
  3. The op shape is JSON-roundtrippable.
  4. Non-text primitives (solid, rect, line, circle, gradient) record.

Run:  python3 tracer/test_trace_template.py
Exit: 0 on PASS; 1 on assertion failure.
"""
import json
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.abspath(os.path.join(HERE, '..', '..', 'generator')))

from deck_canvas import FieldSpec, SlideType, FontSpec  # noqa: E402
import importlib  # noqa: E402


def _build_fixture(tmpdir):
    """Write a synthetic template module to tmpdir/deck_layout.py."""
    src = '''
"""Synthetic test template — exercises field= tagging + a few primitives."""
import os
import sys

# The tracer pre-loads the generator library on sys.path before importing us;
# we just import normally.
from deck_canvas import FieldSpec, SlideType, FontSpec, WIDTH, HEIGHT

FONTS = {
    'body': FontSpec(file='dummy.ttf', pptx='Arial', bold=False, ascent=0.75),
}
FONT_DIR = '/nonexistent'   # tracer never registers fonts


def slide_one(d):
    d.solid('#101010')
    d.rect(100, 980, 200, 8, '#FF00FF')               # static decoration
    d.text('Hello world', 200, 800, 1500, 'body', 60, '#FFFFFF',
           field='headline')                          # FILLABLE
    d.text('subtitle text', 200, 700, 1500, 'body', 30, '#CCCCCC',
           field='subtitle')                          # FILLABLE
    d.text('palcera', 100, 60, 200, 'body', 14, '#888888')   # static chrome
    d.line(0, 50, WIDTH, 50, '#222222', 1)


def slide_two(d):
    d.gradient([(0.0, '#FF0000'), (1.0, '#0000FF')])
    d.circle(960, 540, 200, fill='#00FF00')
    d.text('Quote text', 200, 800, 1500, 'body', 50, '#FFFFFF',
           field='quote')                             # FILLABLE
    d.text('— Author', 200, 720, 1500, 'body', 30, '#CCCCCC',
           field='attribution')                       # FILLABLE


SLIDES = [
    SlideType(type='title', draw=slide_one, fields=[
        FieldSpec(id='headline'),
        FieldSpec(id='subtitle'),
    ]),
    SlideType(type='quote', draw=slide_two, fields=[
        FieldSpec(id='quote'),
        FieldSpec(id='attribution'),
    ]),
]
'''
    with open(os.path.join(tmpdir, 'deck_layout.py'), 'w') as f:
        f.write(src)


def _run_tracer(template_dir, out_path):
    # Import lazily so we re-import the tracer cleanly each test run.
    if 'trace-template' in sys.modules:
        del sys.modules['trace-template']
    # Hyphen in module name forces SourceFileLoader.
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        'trace_template_mod', os.path.join(HERE, 'trace-template.py'))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.trace_template(template_dir, out_path)


def _assert(cond, msg):
    if not cond:
        sys.stderr.write(f'  FAIL  {msg}\n')
        sys.exit(1)
    sys.stderr.write(f'  PASS  {msg}\n')


def main():
    with tempfile.TemporaryDirectory() as tmpdir:
        _build_fixture(tmpdir)
        trace_path = os.path.join(tmpdir, 'trace.json')
        _run_tracer(tmpdir, trace_path)

        with open(trace_path) as f:
            data = json.load(f)

        # --- Shape ---
        _assert(data['pageSize'] == [1920, 1080], 'pageSize is [WIDTH, HEIGHT]')
        _assert(len(data['pages']) == 2,
                f"2 pages traced (got {len(data['pages'])})")
        _assert(data['pages'][0]['type'] == 'title',
                "page 0 carries type='title'")
        _assert(data['pages'][1]['type'] == 'quote',
                "page 1 carries type='quote'")

        # --- Slide 1 — text ops field tags ---
        p0_text = [op for op in data['pages'][0]['ops'] if op['op'] == 'text']
        by_text = {op['text']: op for op in p0_text}
        _assert(by_text['Hello world']['field'] == 'headline',
                "headline text carries field='headline'")
        _assert(by_text['subtitle text']['field'] == 'subtitle',
                "subtitle text carries field='subtitle'")
        _assert(by_text['palcera']['field'] is None,
                'static chrome text carries field=null')

        # --- Slide 1 — non-text primitives ---
        ops0 = [op['op'] for op in data['pages'][0]['ops']]
        _assert('solid' in ops0, 'slide 1 records solid()')
        _assert('rect' in ops0, 'slide 1 records rect()')
        _assert('line' in ops0, 'slide 1 records line()')

        # --- Slide 2 — gradient + circle + field tags ---
        p1 = data['pages'][1]['ops']
        ops1 = [op['op'] for op in p1]
        _assert('gradient' in ops1, 'slide 2 records gradient()')
        _assert('circle' in ops1, 'slide 2 records circle()')

        grad = next(op for op in p1 if op['op'] == 'gradient')
        _assert(grad['stops'] == [[0.0, '#FF0000'], [1.0, '#0000FF']],
                'gradient stops recorded as [[pos, hex], ...]')

        p1_text = [op for op in p1 if op['op'] == 'text']
        by_text_2 = {op['text']: op for op in p1_text}
        _assert(by_text_2['Quote text']['field'] == 'quote',
                "quote text carries field='quote'")
        _assert(by_text_2['— Author']['field'] == 'attribution',
                "attribution text carries field='attribution'")

        # --- Sanity: text geometry survives (width is present) ---
        for op in p0_text + p1_text:
            _assert(isinstance(op.get('w'), (int, float)) and op['w'] > 0,
                    f"text op '{op['text']}' carries positive numeric width")

    print()
    print('PASS — tracer captures field tags + records primitives.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
