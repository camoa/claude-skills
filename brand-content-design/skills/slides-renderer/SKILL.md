---
name: slides-renderer
description: Use when creating a branded presentation as a native Google Slides deck. Composes a resolution-independent layout spec from any template's canvas philosophy and renders it via the Slides API — the Google Slides analog of the visual-content (PDF) skill.
version: 0.1.0
allowed-tools: Read, Write, Glob, Bash
user-invocable: false
---

# Slides Renderer Skill

Render a branded presentation natively in **Google Slides** — the counterpart of
`visual-content` (which renders PDF). Where `visual-content` reads a template's
design and writes reportlab code, this skill reads the **same** design and
composes a **`LayoutSpec`** — a resolution-independent layout the bundled
`scripts/slides/` renderer turns into a real Google Slides deck.

## The Critical Understanding

This is **composition, not per-template code**. There is no hardcoded layout for
any one template. You — reading a template's `canvas-philosophy.md` and
`template.md` — compose its `LayoutSpec`, exactly as `visual-content` composes a
PDF for any template from the same inputs. A new template needs no new code: its
design docs ARE the input.

The split:
- **`scripts/slides/`** (TypeScript) is the *rendering engine* — like reportlab.
  It is generic: it renders any `LayoutSpec`. Do not modify it.
- **This skill** is the *compositor* — like the artistic layout work inside
  `visual-content`. It produces the `LayoutSpec`.

## Part 1 — Inputs

The calling command (`/presentation`, `/template-presentation`) provides, or you
locate, a template folder under `templates/presentations/<name>/`:

- `canvas-philosophy.md` — the aesthetic manifesto, **Composition Rules**, the
  colour + typography application, component support, brand anchors.
- `template.md` — the **Slide Types** catalogue: each type's background, focal
  point, word ceiling, content elements.

Plus the project's `brand-philosophy.md` (colours, fonts, logo) and the renderer
at `scripts/slides/` (run `npm run build` in it once if `dist/` is absent).
Credentials: `BCD_SLIDES_OAUTH_*` or `BCD_SLIDES_SA_KEY_FILE` in the environment
(see `scripts/slides/README.md`).

## Part 2 — Read the design

1. **`canvas-philosophy.md`** — internalise the movement, the style constraints,
   and the **Composition Rules** section (focal-point placement, element
   positioning, component frequency, density). This is the same reading
   `visual-content` Part 1 does. If the file has no Composition Rules section,
   fall back to `references/slide-composition-rules.md`.
2. **`template.md`** — list every slide **type** and, per type, its background,
   focal point, content elements, and word ceiling.
3. **`brand-philosophy.md`** — extract the colour tokens and the heading / body /
   mono fonts.

## Part 3 — Compose the LayoutSpec

A `LayoutSpec` is `{ pageWidth: 720, pageHeight: 405, slides: SlideTypeLayout[] }`
— a **type library**: one `SlideTypeLayout` per slide type (the merge engine
duplicates a type per outline entry). Geometry is **points, top-left origin**, a
16:9 720×405 page.

For **each slide type** in `template.md`, compose a `SlideTypeLayout` — an
ordered `LayoutElement[]`. Apply the Composition Rules: place the background
first, then the focal element off-centre per the style, then supporting elements
as counterweight, then accents and the logo. Honour the type scale, the colour
roles (primary ~60 / secondary ~30 / accent ~10), and the component gates from
`canvas-philosophy.md`.

**Each `LayoutElement`** carries `id`, `kind` (`text`|`shape`|`image`|`ellipse`),
`x`/`y`/`w`/`h`, `zOrder`, and optionally `color`, `rounded`, `fontSize`,
`fontWeight` (100–900), `fontFamily` (`heading`|`body`|`mono`), `align`, and
`content`. `content` is `{ tag: '{{name}}' }` for a **merge placeholder** (every
variable content slot the outline fills), `{ fixed: '…' }` for fixed copy or a
fixed image, or omitted for a pure styled shape (accent bar, card fill).

The exact schema is `scripts/slides/src/layout-spec.ts`. **Read
`scripts/slides/src/community-talk-layout.ts` — it is a complete worked example**:
the `community-talk` template (13 typed slides) composed into a `LayoutSpec`,
with the coordinate helpers and the gradient/logo pattern. Compose new templates
the same way; do not copy its numbers.

Decoration the Slides API cannot fill (gradients) is baked: declare a full-bleed
`image` element and pass a `GradientSpec` (see Part 4).

## Part 4 — Build tokens, gradients, and render

1. **`BrandTokens`** — `{ colors: { primary, background, textLight, textDark,
   secondary?, accent? }, typography: { headingFont, bodyFont, monoFont? } }`
   from `brand-philosophy.md`. `textLight` = text on light backgrounds,
   `textDark` = text on dark.
2. **Gradients** — if the style uses a gradient background, build a
   `GradientSpec` (`colors`, `direction`, optional `positions`); the renderer
   bakes it to an image.
3. **Render** — write the command document and invoke the CLI:
   ```sh
   echo '{"command":"scaffoldTemplate","args":{"tokens":<BrandTokens>,
     "layoutSpec":<LayoutSpec>,"imagePaths":{"logo":"<assets/logo.png>"},
     "gradients":{"grad":<GradientSpec>}}}' | node scripts/slides/dist/cli.js
   ```
   The result envelope's `result.presentationId` is the rendered Google Slides
   template.

## Part 5 — Verify (MANDATORY)

Export the rendered deck and check it before declaring done:
```sh
echo '{"command":"exportFile","args":{"fileId":"<presentationId>","mimeType":"application/pdf"}}' \
  | node scripts/slides/dist/cli.js
```
Decode the base64 to a PDF and review every slide: focal point placed, no
overlaps, brand colours, text-on-background contrast, type scale, logo present.
If the template has a `sample.pdf`, compare against it. Fix the `LayoutSpec` and
re-render until faithful — composition is iterative, exactly as in `visual-content`.

## Part 6 — Honest API limits

Designed around, never fought (full detail in `scripts/slides/references/slides-api-guide.md`):
- **No gradient fill** — baked to an image (Part 4).
- **No master/layout/theme authoring** — per-slide free-form placement only.
- **Custom (non-Google) fonts** — the renderer substitutes the nearest Google
  font and reports it; display text in a custom face is baked to an image.
- Google Slides is not a pixel engine like reportlab — aim for brand- and
  structure-faithful, verified against `sample.pdf`, not pixel-identical.

## Part 7 — Workflow integration

Called by `/presentation` (Google Slides output target) and may be called by
`/template-presentation` to render a Slides sample. The renderer's merge engine
(`renderDeck`) then fills the typed template per a content outline — see
`scripts/slides/references/slides-api-guide.md`.

## Part 8 — Speaker notes

Each slide type may carry speaker-notes content; the outline supplies it per
slide (`/outline` + `template.md` carry a `Speaker notes:` slot). The renderer
fills the notes page — a capability the PPTX path does not have.
