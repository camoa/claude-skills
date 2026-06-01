# Slides batchUpdate Authoring

> ⚠️ **Deprecated path — use PPTX-import instead.** 2026-05-26 empirical
> diagnostic confirmed two Google Slides API limitations that make direct-create
> batchUpdate authoring unable to match PDF-design fidelity:
>
> 1. `pageSize` is silently ignored on `presentations.create` (Google
>    IssueTracker #119321089). Forces 720×405pt; python-pptx PPTXs are 1440×810pt.
> 2. `updateShapeProperties.autofit.autofitType` rejects anything other than NONE.
>    PPTX-import gets autofit via Drive's OOXML importer; direct-create cannot.
>
> Canonical Slides path: render PPTX via python-pptx (existing `pp_*` recipes
> + `visual-content` html2pptx flow), upload to Drive with `mimeType:
> application/vnd.google-apps.presentation` to convert on import. See
> `commands/template-presentation.md` and `commands/presentation.md` for the
> updated workflow.
>
> This document remains for reference and as a fallback for narrow cases where
> direct-create authoring is genuinely required (placeholder substitution into
> an existing Drive template via `replaceAllText`, programmatic in-place updates,
> theme integration). Do not use it as the primary Slides rendering path.



How to write the Google Slides API `batchUpdate` `requests[]` list that
visually matches a reportlab-rendered PDF slide. The Python runner in
`scripts/slides/` executes the JSON; **this guide teaches the LLM how to
write it**.

This is the symmetric counterpart to `visual-content/references/technical-implementation.md`:
the reportlab patterns there are the visual ground truth, and every recipe
in this file shows the **same element** authored as a Slides API request.

## Contents

- Mental model
- Coordinate-translation contract (PDF px → Slides PT)
- Slide-creation pattern (ordering rules)
- Per-element recipes (background, gradient, text, logo, card, icon)
- Font fallback table
- Anti-patterns
- Coordinate-fidelity checklist
- Persistence contract (`{name}.slides.batchupdate.json`)
- Error-recovery loop
- End-to-end worked example

---

## Mental model

You receive **three inputs**:

1. The rendered **PDF** (the visual ground truth — what the user expects to see).
2. The **reportlab Python source** that produced the PDF (every element's
   pixel coordinates, fonts, colors).
3. The `canvas-philosophy.md` and slide content outline.

You emit **one output**: a list of Slides API request objects, persisted as
`{"requests": [...]}` in `{name}.slides.batchupdate.json`. The runner
executes it against a freshly-created blank deck.

You do **not** create the deck, manage Drive folders, write the JSON file,
or handle trash-and-recreate. The caller (a Claude Code command) does that.

> **Goal:** the Slides deck visually matches the PDF closely enough that the
> user does **not** need to tweak layout, fonts, or alignment after rendering.
> If they have to fix the deck a lot, you have failed. Mirror the reportlab
> source element-by-element.

---

## Coordinate-translation contract

ReportLab draws in **pixels, origin bottom-left, y-up** (1920 × 1080).
Slides draws in **points, origin top-left, y-down** (720 × 405 for default
10in × 5.625in 16:9).

The conversion factor is identical on both axes:

```
PX_TO_PT = 0.375   # = 720/1920 = 405/1080
```

Translate every element coordinate:

```
# Reportlab → Slides
# pdf_x, pdf_y = bottom-left corner of the element in reportlab px
# w_px, h_px   = element dimensions in px

slides_x_pt = pdf_x * 0.375
slides_y_pt = (1080 - pdf_y - h_px) * 0.375     # y-axis flip
slides_w_pt = w_px * 0.375
slides_h_pt = h_px * 0.375

font_size_pt = pdf_font_size_pt   # reportlab uses points already; do NOT scale
```

**Sanity check:** an element centered in reportlab at `(960, 540)` with size
`(800, 200)` → bottom-left = `(560, 440)`. In Slides:
`x = 560 * 0.375 = 210`, `y = (1080 − 440 − 200) * 0.375 = 165`,
`w = 300`, `h = 75`. The center is `(210 + 150, 165 + 37.5) = (360, 202.5)`
— exactly half of `(720, 405)`. ✓

Every magnitude unit in your output must be `"PT"`. Do not mix in EMU.

---

## Slide-creation pattern

For each slide in the deck, emit requests in this order:

1. `createSlide` with `predefinedLayout: "BLANK"` and an explicit `objectId`
   (you'll need it as `pageObjectId` for subsequent element requests on
   this slide).
2. **Background first.** `createShape` (RECTANGLE covering the whole slide)
   OR `createImage` (for pre-rendered gradient/photo backgrounds).
3. **Then `updateShapeProperties`** to set the background fill color and to
   strip the default outline.
4. **Then non-text elements** (cards, hosted images, icons).
5. **Then text elements**: `createShape` (TEXT_BOX) → `insertText` →
   `updateTextStyle` → `updateParagraphStyle`.

Order matters because every later request that targets an `objectId` must
come **after** that object's `create*` request.

**objectId discipline.** Use stable, predictable, role-named ids so the
JSON is human-diffable: `slide_1`, `slide_bg_1`, `headline_1`, `kicker_1`,
`logo_1`, `card_1`, `icon_1`. Slides requires ids of **5–50 chars**
matching `[a-zA-Z0-9_]+`. Two-letter roles like `bg` fail validation —
expand to `slide_bg`. Append `_<slide-index>` to keep them unique across
slides.

---

## Per-element recipes

Each recipe shows the **reportlab equivalent** (so you can pattern-match
against `technical-implementation.md`) and the **Slides batchUpdate request
sequence**.

### Page background — solid fill

ReportLab:
```python
c.setFillColor(HexColor(brand_colors['background']))
c.rect(0, 0, 1920, 1080, fill=True, stroke=False)
```

Slides (background covers the full 720×405 PT page):
```json
[
  {
    "createShape": {
      "objectId": "slide_bg_1",
      "shapeType": "RECTANGLE",
      "elementProperties": {
        "pageObjectId": "slide_1",
        "size": {
          "width":  { "magnitude": 720, "unit": "PT" },
          "height": { "magnitude": 405, "unit": "PT" }
        },
        "transform": { "scaleX": 1, "scaleY": 1, "translateX": 0, "translateY": 0, "unit": "PT" }
      }
    }
  },
  {
    "updateShapeProperties": {
      "objectId": "slide_bg_1",
      "shapeProperties": {
        "shapeBackgroundFill": {
          "solidFill": {
            "color": { "rgbColor": { "red": 0.95, "green": 0.95, "blue": 0.95 } }
          }
        },
        "outline": { "propertyState": "NOT_RENDERED" }
      },
      "fields": "shapeBackgroundFill.solidFill.color,outline.propertyState"
    }
  }
]
```

**Color conversion:** Slides RGB components are floats `0.0–1.0`, not 0–255.

```
red   = int(hex[1:3], 16) / 255
green = int(hex[3:5], 16) / 255
blue  = int(hex[5:7], 16) / 255
```

So `#F2F2F2` → `{ "red": 0.949, "green": 0.949, "blue": 0.949 }`.

**`fields` mask is mandatory.** Every property you set in `shapeProperties`
must be listed in `fields` (comma-separated dot paths). Omitting a path
silently no-ops that property.

### Gradient background

The Slides API **does not expose a `linearGradient` shape fill via
batchUpdate.** Documented workaround:

1. Pre-render the gradient as a PNG via reportlab's `draw_gradient_rect`
   (same helper that paints the PDF).
2. Upload it as a publicly-accessible URL (Drive share-link or brand CDN —
   subtask 4 will add a helper; for now, the caller hosts).
3. Use `createImage` to place it as the slide background:

```json
{
  "createImage": {
    "objectId": "slide_bg_1",
    "url": "https://example.com/gradient-slide-1.png",
    "elementProperties": {
      "pageObjectId": "slide_1",
      "size": {
        "width":  { "magnitude": 720, "unit": "PT" },
        "height": { "magnitude": 405, "unit": "PT" }
      },
      "transform": { "scaleX": 1, "scaleY": 1, "translateX": 0, "translateY": 0, "unit": "PT" }
    }
  }
}
```

URL requirements: HTTPS, publicly accessible (no auth), Content-Type
`image/png` `image/jpeg` or `image/gif`, ≤50 MB, ≤25 MP. **SVG is not
supported.**

### Headline / kicker / paragraph text

ReportLab:
```python
c.setFillColor(HexColor(brand_colors['text']))
c.setFont('Inter', 72)
c.drawString(120, 880, "Where ideas meet form")
```

The reportlab `drawString` baseline is at `(120, 880)`. Text *box* origin
(bottom-left of the bounding box) is roughly `(120, 880)` with the
baseline-to-bottom descender baked in; for translation purposes, treat the
draw point as the bottom-left of a box wide enough to hold the string and
roughly `font_size * 1.2` tall (matches the `get_text_bounds` helper in
`technical-implementation.md`).

Convert: `pdf_x=120`, `pdf_y=880`, `h_px=72*1.2=86.4`. Slides position:
`x = 120 * 0.375 = 45`, `y = (1080 − 880 − 86.4) * 0.375 = 42.6`.
Width: pick a generous box (e.g., `600` PT) so wrapping behaves; text
alignment is governed by `updateParagraphStyle`, not the box width alone.

Slides:
```json
[
  {
    "createShape": {
      "objectId": "headline_1",
      "shapeType": "TEXT_BOX",
      "elementProperties": {
        "pageObjectId": "slide_1",
        "size": {
          "width":  { "magnitude": 600, "unit": "PT" },
          "height": { "magnitude": 90,  "unit": "PT" }
        },
        "transform": { "scaleX": 1, "scaleY": 1, "translateX": 45, "translateY": 42.6, "unit": "PT" }
      }
    }
  },
  {
    "insertText": {
      "objectId": "headline_1",
      "insertionIndex": 0,
      "text": "Where ideas meet form"
    }
  },
  {
    "updateTextStyle": {
      "objectId": "headline_1",
      "style": {
        "fontFamily": "Inter",
        "fontSize": { "magnitude": 72, "unit": "PT" },
        "bold": true,
        "foregroundColor": { "opaqueColor": { "rgbColor": { "red": 0.1, "green": 0.1, "blue": 0.1 } } }
      },
      "textRange": { "type": "ALL" },
      "fields": "fontFamily,fontSize,bold,foregroundColor"
    }
  },
  {
    "updateParagraphStyle": {
      "objectId": "headline_1",
      "style": { "alignment": "START" },
      "textRange": { "type": "ALL" },
      "fields": "alignment"
    }
  }
]
```

**Text-style rules:**

- `bold` and `italic` are **properties**, never font-name suffixes. Use
  `"fontFamily": "Inter"` + `"bold": true`. Never `"fontFamily": "Inter-Bold"`.
- `fontSize.magnitude` is a number in **points** — same as reportlab's
  `setFont(font, size)` size. No scaling.
- `textRange: { "type": "ALL" }` is the cleanest way to style the entire
  inserted text run. Use `{ "type": "FIXED_RANGE", "startIndex": 0, "endIndex": 5 }`
  only when you need partial styling (e.g., colored first word).
- `fields` mask is mandatory. Every styled property must be listed.

### Logo / hosted image

ReportLab:
```python
c.drawImage('assets/logo.png', 1720, 60, width=150, height=60,
            preserveAspectRatio=True, mask='auto')
```

The reportlab call places the bottom-left of the logo at `(1720, 60)` in
px. Convert: `x = 1720 * 0.375 = 645`, `y = (1080 − 60 − 60) * 0.375 = 360`,
`w = 56.25`, `h = 22.5`.

Slides:
```json
{
  "createImage": {
    "objectId": "logo_1",
    "url": "https://drive.google.com/uc?id=<fileId>&export=download",
    "elementProperties": {
      "pageObjectId": "slide_1",
      "size": {
        "width":  { "magnitude": 56.25, "unit": "PT" },
        "height": { "magnitude": 22.5,  "unit": "PT" }
      },
      "transform": { "scaleX": 1, "scaleY": 1, "translateX": 645, "translateY": 360, "unit": "PT" }
    }
  }
}
```

**URL requirements** (repeat — these are the most common failure mode):

- HTTPS only.
- Publicly accessible — no login redirect, no auth header.
- Content-Type `image/png` `image/jpeg` `image/gif`. **No SVG.**
- ≤50 MB, ≤25 MP (5000×5000).

**Canonical hosting pattern for brand assets:** upload the PNG to Drive,
set its permission to `anyone with the link can view`, use the direct-link
URL `https://drive.google.com/uc?id=<fileId>&export=download`. A
`share_link` helper is a follow-up runner concern (subtask 4 territory).

### Card

ReportLab (rounded-corner card):
```python
canvas.setFillColor(HexColor('#FFFFFF'))
canvas.setStrokeColor(HexColor('#E5E5E5'))
canvas.setLineWidth(2)
canvas.roundRect(100, 200, 400, 250, radius=16, fill=True, stroke=True)
```

Slides has `RECTANGLE` but **no roundRect at the request level**. Two
options:

**Option A (preferred for most styles):** plain rectangle, no rounded
corners. Slides cards read fine without radius for most brand systems.

```json
[
  {
    "createShape": {
      "objectId": "card_1",
      "shapeType": "RECTANGLE",
      "elementProperties": {
        "pageObjectId": "slide_1",
        "size": {
          "width":  { "magnitude": 150,    "unit": "PT" },
          "height": { "magnitude": 93.75,  "unit": "PT" }
        },
        "transform": { "scaleX": 1, "scaleY": 1, "translateX": 37.5, "translateY": 236.25, "unit": "PT" }
      }
    }
  },
  {
    "updateShapeProperties": {
      "objectId": "card_1",
      "shapeProperties": {
        "shapeBackgroundFill": { "solidFill": { "color": { "rgbColor": { "red": 1, "green": 1, "blue": 1 } } } },
        "outline": {
          "outlineFill": { "solidFill": { "color": { "rgbColor": { "red": 0.898, "green": 0.898, "blue": 0.898 } } } },
          "weight":      { "magnitude": 2, "unit": "PT" },
          "dashStyle": "SOLID"
        }
      },
      "fields": "shapeBackgroundFill.solidFill.color,outline.outlineFill.solidFill.color,outline.weight,outline.dashStyle"
    }
  }
]
```

**Option B (when rounded corners are non-negotiable):** pre-render the card
as a PNG via reportlab's `roundRect` and place it with `createImage`.

### Icons

Local PNGs from the `icons.py` helper are not publicly reachable. Use the
**Iconify raster bridge** for in-deck Lucide icons:

```
https://api.iconify.design/lucide/{name}.png?color=%23{hex_no_hash}&width=48
```

Example: `https://api.iconify.design/lucide/rocket.png?color=%23333333&width=48`

```json
{
  "createImage": {
    "objectId": "icon_1",
    "url": "https://api.iconify.design/lucide/rocket.png?color=%23333333&width=48",
    "elementProperties": {
      "pageObjectId": "slide_1",
      "size": {
        "width":  { "magnitude": 18, "unit": "PT" },
        "height": { "magnitude": 18, "unit": "PT" }
      },
      "transform": { "scaleX": 1, "scaleY": 1, "translateX": 60, "translateY": 280, "unit": "PT" }
    }
  }
}
```

For brand-controlled icons, upload PNGs to Drive + share — same pattern as
the logo recipe.

---

## Font fallback table

Slides renders only the **Google Fonts catalog** server-side. Custom TTF/OTF
brand fonts loaded by reportlab are silently substituted with Arial.

Before authoring, check the brand's heading and body fonts against this
table. If the brand font is **not** in the Google Fonts catalog, pick the
nearest proxy by classification:

| Brand classification | Heading proxy | Body proxy |
|---|---|---|
| Geometric sans (Futura, Avenir, Gotham) | `Montserrat` | `Montserrat` |
| Humanist sans (Frutiger, Myriad, Open Sans) | `Open Sans` | `Open Sans` |
| Neo-grotesque (Helvetica, Inter, Aktiv Grotesk) | `Inter` | `Inter` |
| Industrial sans (DIN, Oswald, Bebas Neue) | `Oswald` | `Oswald` |
| Old-style serif (Garamond, Sabon, Caslon) | `EB Garamond` | `EB Garamond` |
| Transitional serif (Baskerville, Times) | `Playfair Display` | `Source Serif Pro` |
| Slab serif (Rockwell, Roboto Slab) | `Roboto Slab` | `Roboto Slab` |
| Display script | `Playfair Display` (or accept Arial fallback) | n/a |
| Monospace | `JetBrains Mono` or `IBM Plex Mono` | same |

Document the substitution in your batchUpdate output as a JSON comment is
not possible — Slides API JSON has no comments. Instead, surface
substitutions in the runner output to the user (subtask 4 concern); for
now, simply pick the closest proxy and proceed.

---

## Anti-patterns (do not do these)

| Anti-pattern | Why it fails | Fix |
|---|---|---|
| `translateX`/`translateY` outside `[0, 720]` × `[0, 405]` PT | Element off-slide; user sees nothing | Re-check the y-axis flip in the coordinate-translation contract |
| Forgetting the y-axis flip | Element appears upside down on the page | Apply `(1080 − pdf_y − h_px) * 0.375` |
| Mixing EMU and PT in one batchUpdate | Some elements render at the wrong size | Stay in PT throughout |
| Setting `style` without a matching `fields` mask | Silent no-op — Slides ignores the change | List every dot-path you set in `fields` |
| `fontFamily: "Inter-Bold"` | Silently falls back to Arial | Use `fontFamily: "Inter"` + `bold: true` |
| Custom TTF brand font (e.g. `"Founders Grotesk"`) | Silently falls back to Arial | Substitute via the font fallback table |
| Element overlap (text on top of icon, headline on logo) | Visual collision; same constraint as reportlab | Run the coordinate-fidelity checklist |
| `linearGradient` in `shapeBackgroundFill` | Not supported by the API | Pre-render gradient as PNG + `createImage` |
| SVG URL in `createImage` | API rejects with 400 | Use PNG/JPEG/GIF only |
| Authenticated/Drive-private URL in `createImage` | API rejects with 400 (no permission to fetch) | Use `?export=download` + `anyone with link` permission, or a public CDN |
| `createShape` for an `objectId` that already exists | API rejects the whole batch | Use unique ids (`<role>_<slide-index>`) |
| `objectId` shorter than 5 chars (e.g., `bg_1`) | API rejects with 400 ("The object ID length should not be less than 5") | Use `slide_bg_1` etc. — keep role names ≥3 chars |
| `outline.weight.magnitude: 0` to hide a shape outline | API rejects with 400 ("The outline weight 0.0 should not be less than or equal to zero") | Use `"outline": { "propertyState": "NOT_RENDERED" }` and list `outline.propertyState` in `fields` |
| `insertText` before the target shape exists | API rejects | Order: `createShape` → `insertText` |
| Pretending RECTANGLE has a `cornerRadius` | Field does not exist; silently ignored | Accept sharp corners or pre-render the rounded card as PNG |
| Authoring >500 requests in one batch | API rejects with 400 | Out of scope here; runner concern (subtask 4) |

---

## Coordinate-fidelity checklist

Before emitting the batchUpdate, walk every element in the reportlab source
and verify the Slides request matches on:

```
□ pageObjectId — does it point at the correct createSlide objectId?
□ translateX — applies PX_TO_PT 0.375 to the reportlab x?
□ translateY — applies the y-axis flip (1080 − pdf_y − h_px) * 0.375?
□ size.width / size.height — applies PX_TO_PT 0.375 to reportlab w/h?
□ unit — PT throughout (no EMU)?
□ Color — converted from hex to {red, green, blue} as 0.0–1.0 floats?
□ fontFamily — in the Google Fonts catalog (or substituted via the table)?
□ fontSize.magnitude — same number as reportlab's setFont size (no scaling)?
□ bold/italic — set as properties, not font-name suffixes?
□ alignment — explicit START/CENTER/END/JUSTIFIED on every text element?
□ fields — every styled property listed in the mask?
□ Image URLs — HTTPS, public, PNG/JPEG/GIF, ≤50 MB / ≤25 MP?
□ objectId — unique per element, 5–50 chars, matches [a-zA-Z0-9_]+?
□ Element overlap — no two element bounding boxes intersect (run the same
  bounding-box test from technical-implementation.md, translated to PT)?
□ Safe zones — every element stays inside roughly 18 PT (≈ 50 px) of each
  page edge, mirroring the reportlab safe-zone rule?
```

If any check fails, regenerate the relevant request before persisting.

---

## Persistence contract

The caller (subtask 4's command-md wiring) writes the LLM-authored
`requests[]` to `{name}.slides.batchupdate.json` next to the local PDF:

```
{output_folder}/
  {name}.pdf
  {name}.slides.batchupdate.json    # <— this file
  outline.md
```

Schema:

```json
{
  "requests": [
    /* Slides API request objects, in slide-then-element order */
  ]
}
```

This is the native Slides API shape — the runner consumes it without
transformation:

```python
import json
from slides.runner import SlidesRunner
from slides.auth import build_services

with open(f"{name}.slides.batchupdate.json") as f:
    payload = json.load(f)

slides_svc, drive_svc = build_services()
runner = SlidesRunner(slides_svc, drive_svc)
deck_id = runner.create_deck(name)
runner.apply_batch_update(deck_id, payload["requests"])
```

Persist the file **even when iterating**, so the next run's diff is
meaningful. Subtask 4 owns the file-write code and the trash-and-recreate
semantics that consume this file.

---

## Error-recovery loop

When the user reports overflow, overlap, off-slide elements, or wrong
fonts:

1. **Read** the persisted `{name}.slides.batchupdate.json` **and** the
   reportlab source that produced the matching PDF.
2. **Identify** the misaligned request by element role (`headline_3`,
   `card_2`, etc. — that's why object ids are stable and role-named).
3. **Diff** the offending request's coordinates / styles against the
   reportlab source for the same element. Apply the coordinate-translation
   contract to recompute.
4. **Regenerate** just the offending request (or, if the layout is
   structurally broken, the whole batch).
5. **Persist** the new batchUpdate over the old `{name}.slides.batchupdate.json`.
6. **Trash-and-recreate** the deck via subtask 4's command (the runner has
   the `move_to_folder` primitive; trash-and-recreate is a thin wrapper
   on top of `drive.files().update(fileId, body={"trashed": True})` that
   subtask 4 will add).

Iteration is destructive by design — the runner does not patch a deck in
place. This is the documented `slides_output_minimal` non-goal:
"Resync: updating an existing Slides deck in place from an edited outline.
Render-fresh-each-time only; trash-and-recreate is the iteration model."

---

## End-to-end worked example

A one-slide title deck: solid light background + centered headline +
kicker line. Used by `tests/test_authoring_smoke.py` as the validation
proof for this guide.

### ReportLab source (the visual ground truth)

```python
from reportlab.pdfgen import canvas
from reportlab.lib.colors import HexColor

SLIDE_W, SLIDE_H = 1920, 1080

c = canvas.Canvas("title.pdf", pagesize=(SLIDE_W, SLIDE_H))

# Background — light gray
c.setFillColor(HexColor("#F2F2F2"))
c.rect(0, 0, SLIDE_W, SLIDE_H, fill=True, stroke=False)

# Kicker — small, uppercase, dark gray, near top
c.setFillColor(HexColor("#666666"))
c.setFont("Helvetica", 24)
c.drawCentredString(SLIDE_W / 2, 720, "A SUBTITLE")

# Headline — large, bold, near-black, centered
c.setFillColor(HexColor("#1A1A1A"))
c.setFont("Helvetica-Bold", 72)
c.drawCentredString(SLIDE_W / 2, 560, "Where ideas meet form")

c.showPage()
c.save()
```

### Coordinate translations

| Element | reportlab x,y (px) | size (px) | Slides x,y (PT) | size (PT) |
|---|---|---|---|---|
| Background | 0, 0 | 1920×1080 | 0, 0 | 720×405 |
| Kicker (`drawCentredString` at `(960, 720)`, font 24) | bbox ≈ (820, 720) to (1100, 749) — width ~280, h=29 | 280×29 | 307.5, 116.6 | 105×10.9 |
| Headline (`drawCentredString` at `(960, 560)`, font 72) | bbox ≈ (480, 560) to (1440, 646) — width ~960, h=86.4 | 960×86.4 | 180, 162.6 | 360×32.4 |

For the worked example, we widen text-box widths and use Slides'
`alignment: CENTER` so we don't have to compute precise string widths.
Result:

### Slides batchUpdate JSON

```json
{
  "requests": [
    {
      "createSlide": {
        "objectId": "slide_1",
        "insertionIndex": 0,
        "slideLayoutReference": { "predefinedLayout": "BLANK" }
      }
    },
    {
      "createShape": {
        "objectId": "slide_bg_1",
        "shapeType": "RECTANGLE",
        "elementProperties": {
          "pageObjectId": "slide_1",
          "size": {
            "width":  { "magnitude": 720, "unit": "PT" },
            "height": { "magnitude": 405, "unit": "PT" }
          },
          "transform": { "scaleX": 1, "scaleY": 1, "translateX": 0, "translateY": 0, "unit": "PT" }
        }
      }
    },
    {
      "updateShapeProperties": {
        "objectId": "slide_bg_1",
        "shapeProperties": {
          "shapeBackgroundFill": { "solidFill": { "color": { "rgbColor": { "red": 0.949, "green": 0.949, "blue": 0.949 } } } },
          "outline": { "propertyState": "NOT_RENDERED" }
        },
        "fields": "shapeBackgroundFill.solidFill.color,outline.propertyState"
      }
    },
    {
      "createShape": {
        "objectId": "kicker_1",
        "shapeType": "TEXT_BOX",
        "elementProperties": {
          "pageObjectId": "slide_1",
          "size": {
            "width":  { "magnitude": 600, "unit": "PT" },
            "height": { "magnitude": 30,  "unit": "PT" }
          },
          "transform": { "scaleX": 1, "scaleY": 1, "translateX": 60, "translateY": 117, "unit": "PT" }
        }
      }
    },
    {
      "insertText": { "objectId": "kicker_1", "insertionIndex": 0, "text": "A SUBTITLE" }
    },
    {
      "updateTextStyle": {
        "objectId": "kicker_1",
        "style": {
          "fontFamily": "Inter",
          "fontSize": { "magnitude": 24, "unit": "PT" },
          "foregroundColor": { "opaqueColor": { "rgbColor": { "red": 0.4, "green": 0.4, "blue": 0.4 } } }
        },
        "textRange": { "type": "ALL" },
        "fields": "fontFamily,fontSize,foregroundColor"
      }
    },
    {
      "updateParagraphStyle": {
        "objectId": "kicker_1",
        "style": { "alignment": "CENTER" },
        "textRange": { "type": "ALL" },
        "fields": "alignment"
      }
    },
    {
      "createShape": {
        "objectId": "headline_1",
        "shapeType": "TEXT_BOX",
        "elementProperties": {
          "pageObjectId": "slide_1",
          "size": {
            "width":  { "magnitude": 600, "unit": "PT" },
            "height": { "magnitude": 90,  "unit": "PT" }
          },
          "transform": { "scaleX": 1, "scaleY": 1, "translateX": 60, "translateY": 163, "unit": "PT" }
        }
      }
    },
    {
      "insertText": { "objectId": "headline_1", "insertionIndex": 0, "text": "Where ideas meet form" }
    },
    {
      "updateTextStyle": {
        "objectId": "headline_1",
        "style": {
          "fontFamily": "Inter",
          "fontSize": { "magnitude": 72, "unit": "PT" },
          "bold": true,
          "foregroundColor": { "opaqueColor": { "rgbColor": { "red": 0.102, "green": 0.102, "blue": 0.102 } } }
        },
        "textRange": { "type": "ALL" },
        "fields": "fontFamily,fontSize,bold,foregroundColor"
      }
    },
    {
      "updateParagraphStyle": {
        "objectId": "headline_1",
        "style": { "alignment": "CENTER" },
        "textRange": { "type": "ALL" },
        "fields": "alignment"
      }
    }
  ]
}
```

Note the font substitution: `Helvetica` / `Helvetica-Bold` → `Inter` +
`bold:true`, per the fallback table. The Slides API would silently fall
back to Arial for `Helvetica`; explicit substitution is better.

The validation proof in `scripts/slides/tests/test_authoring_smoke.py`
executes this exact authored payload against the real Slides API and
asserts the deck reads back with the expected text and element count.
