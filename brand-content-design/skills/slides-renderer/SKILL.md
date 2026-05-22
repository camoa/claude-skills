---
name: slides-renderer
description: Use when creating a branded presentation as a native Google Slides deck. Traces the template's reportlab generator to reproduce its sample.pdf faithfully in Google Slides — the PDF is the design source of truth, not an independent re-composition.
version: 0.2.0
allowed-tools: Read, Write, Glob, Bash
user-invocable: false
---

# Slides Renderer Skill

Render a `brand-content-design` presentation template **faithfully** as a native
Google Slides deck. The template's `sample.pdf` is the design source of truth;
this skill **reproduces** it — it does not re-compose the design from the
philosophy docs (independent re-composition drifts).

## How it works — trace, don't re-compose

A presentation template ships `generate_sample.py` — a reportlab script that
draws `sample.pdf`. This skill:

1. runs that script through an **instrumented canvas** (`tracer/trace-template.py`)
   that records every draw call — text runs, rects, rounded rects, circles,
   lines, gradients, images — as JSON;
2. converts the capture to a `LayoutSpec` (`src/trace-to-layout.ts`);
3. scaffolds it into Google Slides via `scripts/slides/`.

The result matches `sample.pdf` **by construction** — same geometry, content,
colours, even syntax-highlighted code — because it *is* the PDF's draw list.
Generic: works on any template's `generate_sample.py`, no per-template code. This
is the shared-source fix the brand-content-design parity audit (B1) calls for.

## Preconditions — check FIRST, fail loudly

- **`generate_sample.py` + `sample.pdf` exist** in the template folder. Without
  the generator there is nothing to trace — stop and tell the user (a template
  predating the generator must be regenerated first).
- **The brand logo is PNG or JPG.** Read `brand-philosophy.md` → Brand Assets.
  The Slides API `createImage` cannot place an SVG — if the logo is `.svg`, stop
  and ask the user to run `/brand-extract` (it converts SVG→PNG).
- `python3` with `reportlab` available; the slides package built (run
  `npm run build` in `scripts/slides/` if `dist/` is absent).
- Credentials in the environment — `BCD_SLIDES_OAUTH_*` or
  `BCD_SLIDES_SA_KEY_FILE` (see `scripts/slides/README.md`).

## Steps

1. **Trace** the generator (its own PDF write is redirected — `sample.pdf` is
   never touched):
   ```sh
   python3 scripts/slides/tracer/trace-template.py \
     <template>/generate_sample.py /tmp/trace.json
   ```
2. **Brand tokens** — read `brand-philosophy.md` for the **heading / body / mono
   font names** and the colour palette; write a `BrandTokens` JSON. Do NOT
   hardcode fonts (parity audit B2). Shape:
   `{ colors: { primary, background, textLight, textDark, secondary?, accent? },
   typography: { headingFont, bodyFont, monoFont? } }`.
3. **Convert + scaffold** — `examples/render-from-trace.mjs` reads the trace +
   the tokens JSON and emits the `scaffoldTemplate` command. Pass:
   - `presentationName` → `"<template name> Template"`
   - `driveFolderPath` → a folder, e.g. `["<brand>", "Slides Templates"]`
   ```sh
   node examples/render-from-trace.mjs /tmp/trace.json /tmp/tokens.json \
     "<template name> Template" "<brand>,Slides Templates" \
     | node dist/cli.js
   ```
   The result envelope's `result.presentationId` is the rendered deck.
4. **Verify (MANDATORY)** — export it to PDF and compare **every slide** to the
   template's `sample.pdf`:
   ```sh
   echo '{"command":"exportFile","args":{"fileId":"<id>","mimeType":"application/pdf"}}' \
     | node dist/cli.js
   ```
   They should match closely (same source). Confirm no element overlaps, the
   logo is present, colours/fonts are right. The converter reports a `skipped`
   list (diagonal lines, stroke-only outlines — see limits); confirm nothing
   essential was dropped.

## Known limits (informed by the brand-content-design parity audit)

- **Faithful to the generator** — the Slides deck reproduces whatever
  `generate_sample.py` draws; a generator bug (e.g. a wrong hardcoded font) is
  inherited. The converter maps fonts to brand *roles* (heading/body/mono) and
  resolves them through `brand-philosophy.md` tokens, so a wrong heading font
  still renders as the brand heading font — partial B2 resilience.
- **Diagonal lines** and **stroke-only outlines** are not yet reproduced (the
  converter lists them in `skipped`). Horizontal/vertical lines (accent rules,
  dividers) and all filled shapes, text, circles, images, gradients ARE.
- **No `generate_sample.py`** → no faithful trace (parity audit G1).
- **Custom (non-Google) fonts** are substituted with the nearest Google font and
  the substitution reported; **gradients** are baked to images.

## Workflow integration

Called by `/presentation` (Google Slides output target). Naming + folder
convention: a scaffolded template → `"<name> Template"` in a Drive folder; a
rendered *presentation* (a deck filled from an outline via `renderDeck`) →
`"<presentation title> - <template name>"`.
