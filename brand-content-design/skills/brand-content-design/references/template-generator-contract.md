# Template Generator Contract

The deterministic standard for `brand-content-design` presentation templates.

## Why this exists

A presentation template used to be 4+ artifacts — `template.md`, an optional
hand-authored generator, `outline-template.md`, `sample.pdf` / `sample.pptx` —
produced by different processes (some by the AI `visual-content` skill, some
hand-authored). With no single source they drift, and no two generations match.

This contract makes a template **deterministic**: the template's **generator** is
the one canonical artifact. Every other artifact derives from it — `sample.pdf` and
`sample.pptx` by running it, `outline-template.md` from its declared fields,
`template.md` from its slide-type catalog. A presentation (Google Slides or PPTX) is
then just *generator + filled outline*. Parity is structural, not reviewed.

`community-talk/deck_layout.py` is the reference implementation of this contract.

## The canonical artifact

A template **is one Python module** (`deck_layout.py`) — an *abstract layout spec*
plus thin per-target *backends*. The module never renders directly; it draws onto a
`DeckCanvas`, and a backend turns those calls into a PDF, a PPTX, or (via the Slides
tracer) a Google Slides deck. Because every target consumes the one spec, the targets
cannot structurally diverge.

**Forbidden:** a per-template monolithic generator; a second generator in another
language for another target; layout logic or content inside a backend. (These are the
`tech-talk` anti-pattern that motivated this contract.)

## The five components

### C1 — `DeckCanvas`: the abstract drawing surface

Backends subclass `DeckCanvas` and implement only the `_`-prefixed primitives. The
shared layer holds **no** layout logic, **no** content, and **no** target-specific
concept (no PDF baselines, no EMU). It carries an optional `content` map
(`field_id → value`); `None` means "render every field's default".

Primitives a backend MUST implement:

```
start_slide()                     _line(x1,y1,x2,y2,color,w)
save()                            _image(path,x,y,w,h)
_solid(color)                     _text_block(s,x,y,w,h,font,size,color,align,valign)
_gradient(stops)                  _rect(x,y,w,h,color)
_round_rect(x,y,w,h,r,fill,stroke,stroke_w)
_circle(cx,cy,r,fill,stroke,stroke_w)
```

`start_slide()` / `save()` are the page lifecycle. `_gradient` receives the
deck's gradient as an ordered list of `(position 0..1, hex)` stops — the gradient
is brand *content* declared in the spec, never hard-coded inside a backend. Any
target-specific concept a backend needs to render a text block (a PDF baseline
inset, EMU, a line-spacing factor) is the backend's own business and stays
inside it — it never appears in this primitive list or in a slide function.

### C2 — Text is a block

The single most important rule. Text is declared as a **block** — an *unwrapped*
string plus a **width** — and anchored by the box **top-left**, never by a baseline.
The shared layer **never pre-wraps**; each backend wraps natively inside `_text_block`:

- **PDF backend** — wrap the string to the width (greedy word-wrap) and draw the lines.
- **PPTX backend** — emit **one** text box of that width with `word_wrap = True` and a
  single run. (One text element ⇒ one box. Pre-wrapping into per-line text boxes is
  the multi-line-text bug this rule eliminates.)
- **Slides** (via the tracer) — one text element of that width.

Public text API on `DeckCanvas`:

```
text(s, x, y, width, font, size, color, align='left', field=None)
headline(s, x, y, width, ..., field=None)   # thin wrapper over text()
para(s, x, y, width, ..., field=None)        # thin wrapper over text()
```

`headline()` / `para()` are single `text()` calls — they MUST NOT loop over wrapped
lines. Wrapping belongs to the backend.

### C3 — The slide-type registry

A template declares an ordered catalog of slide types:

```python
@dataclass
class SlideType:
    type: str                       # stable id, e.g. 'concept'
    draw: Callable[[DeckCanvas], None]
    fields: list[FieldSpec]

SLIDES: list[SlideType]             # the template's ordered catalog
```

`SLIDES` is the single catalog `template.md` and `/outline` read.

### C4 — Field declaration

Every **fillable** piece of content is a declared field:

```python
@dataclass
class FieldSpec:
    id: str                         # vocabulary token: 'title','headline','bullet1'…
    kind: str = 'text'              # 'text' | 'image'
    constraints: dict | None = None # optional, e.g. {'max_words': 12}
```

A fillable draw call is tagged with its field id, and **the call-site string argument
is that field's default**:

```python
d.text('Meet field_pulse', 130, 540, 1400, 'Black', 120, WHITE, field='title')
#       ^^^^^^^^^^^^^^^^^^ the default (sample) value          ^^^^^^^^^^^^ the field id
```

Static chrome (logo, accent bars, decoration) carries no `field=`. The registry's
`SlideType.fields` list and the call-site `field=` tags MUST agree — the conformance
check enforces this.

The field id is the **single vocabulary token** that spans the generator, the
outline, and the renderers — it cannot drift because it is declared once.

### C5 — `build(canvas, content=None)`

```python
def build(canvas: DeckCanvas, content: list[dict] | None = None) -> None:
    # content entry: {'type': <type_id>, 'values': {field_id: value}}
```

- `build(canvas)` — no content → every `field` resolves to its call-site default →
  the **sample deck**.
- `build(canvas, content)` — `content` is the outline payload → each `field` resolves
  to the supplied value, falling back to the default when a value is absent → a
  **presentation**.

`text(..., field=)` does the resolution: `canvas.content[field]` if present, else the
call-site default string.

## How the other artifacts derive

```
deck_layout.py ─build(canvas)──────────────▶ sample.pdf / sample.pptx
deck_layout.py ─build(canvas, outline)─────▶ a presentation (PDF / PPTX)
deck_layout.py ─traced─────────────────────▶ Google Slides template + field map
deck_layout.py SLIDES registry ────────────▶ template.md catalog
deck_layout.py SLIDES[].fields ────────────▶ outline-template.md per-type fields
```

`/template-presentation` authors the generator and runs it for the samples.
`/outline` reads `SLIDES[].fields` to emit `outline-template.md`. No artifact is
hand-authored independently; none can drift.

## Conformance requirements

A conforming template generator:

1. Draws only through `DeckCanvas` — no direct backend calls in slide functions.
2. Models every text element as a block (string + width); never pre-wraps.
3. Declares every slide type in `SLIDES` with a non-empty, unique-per-type `fields`
   list; every fillable draw carries a matching `field=`.
4. Puts each field's sample value at its call site as the default.
5. Provides `build(canvas, content=None)`.
6. Keeps backends thin — primitives only, no layout, no content.

**Sample stability.** After a refactor to conform, the generated `sample.pdf` must be
**render-identical** to the prior one — verified by rasterizing both and pixel-diffing
each page (literal byte identity is not required: reportlab embeds `/CreationDate` and
a document `/ID`). A conformance check script ships with the template and asserts
render-identity plus rules 3–4.
