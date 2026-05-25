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
   - `driveFolderPath` → **`["<brand>", "Slide Templates", "<template name>"]`** —
     each template gets its own subfolder under the brand's `Slide Templates`
     folder (e.g. `Palcera/Slide Templates/community-talk`).
   ```sh
   node examples/render-from-trace.mjs /tmp/trace.json /tmp/tokens.json \
     "<template name> Template" "<brand>,Slide Templates,<template name>" \
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
- **No `generate_sample.py`** → no faithful trace (parity audit G1).
- **Custom (non-Google) fonts** are substituted with the nearest Google font and
  the substitution reported; **gradients** are baked to images.

## Create — render a deck from an outline (`renderDeck`)

The steps above produce a **template** in Drive. To produce a **presentation**,
fill that template with a `/outline`-shaped markdown via the `renderDeck`
command. The CLI is a stdin-JSON → stdout-envelope adapter; there are no
`--flag` arguments — pipe a single JSON command document into `node dist/cli.js`.

1. **Parse the outline → payload.** Send `outlineToPayload` with the outline
   markdown and the layout's `tagMap` (derive from the saved `LayoutSpec` via
   `tagMapFromLayoutSpec`, or pass the same map used at scaffold time):
   ```sh
   echo '{"command":"outlineToPayload","args":{
     "outlineMarkdown":"<...>","tagMap":{...}
   }}' | node dist/cli.js
   ```
   `result` is the `ContentPayload` array to hand to `renderDeck`.

2. **Render the deck.** Send `renderDeck`. Include `manifestPath` (plus the
   `layoutSpec`, `tokens`, and `fixedImageUrls` used at scaffold time) so the
   sidecar gets written for future resyncs:
   ```sh
   echo '{"command":"renderDeck","args":{
     "templatePresentationId":"<scaffolded-template-id>",
     "tagMap":{...},
     "payload":[...],
     "deckName":"<presentation title> - <template name>",
     "driveFolderPath":["<brand>","presentations"],
     "manifestPath":"<outline.md>.render-manifest.json",
     "layoutSpec":{...},
     "tokens":{...},
     "fixedImageUrls":{...}
   }}' | node dist/cli.js
   ```
   What it does: duplicates the template in Drive → fills tagged text + image
   slots from the payload → writes `<outline>.render-manifest.json` beside the
   outline source. The envelope's `result.presentationId` is the new deck's
   Drive id; `result.manifestPath` is the sidecar location.

   Manifest path convention: **`<outline>.render-manifest.json` next to the
   outline file** (e.g. `talk.outline.md` → `talk.outline.md.render-manifest.json`).
   Without `manifestPath` the render still works, but no resync is possible.

## Resync — re-render an edited outline in place (`resyncDeck`)

For subsequent edits to the **same** outline, use `resyncDeck`. It reads the
manifest, diffs prior payload vs new outline, and rebuilds slides **in place**
on the same `deckPresentationId` — the user-visible file id and URL are
preserved.

```sh
echo '{"command":"resyncDeck","args":{
  "manifestPath":"<outline.md>.render-manifest.json",
  "outlineMarkdown":"<new outline contents>"
}}' | node dist/cli.js
```

Behaviour notes:

- **Empty diff = no-op fast path.** When nothing changed, only `renderedAt` in
  the manifest is updated; no batchUpdate is issued.
- **Frozen `layoutSpec`.** Resync rebuilds from the `layoutSpec` captured in
  the manifest at first render — it does NOT re-trace the template. If the
  template's structure changed (new slide type, moved geometry, retagged
  fields), run `renderDeck` fresh against the new template instead; resync is
  for outline-content edits, not template-shape changes.
- **Field-tagged IMAGE slots = v1 limitation.** Same constraint as
  `renderDeck` — fixed/chrome images are rebuilt from `fixedImageUrls`;
  outline-driven image fields are not yet supported.
- **Missing manifest → error.** If the sidecar is absent, `resyncDeck` fails
  with a `BAD_COMMAND` envelope ("run renderDeck first to produce one"). A
  corrupt manifest throws `ManifestCorruptError`.

## Workflow integration

Called by `/presentation` (Google Slides output target). First run = Create
(scaffold + `renderDeck`); subsequent edits to the same outline = Resync
(`resyncDeck`, same Drive file).

**Drive naming + folder convention:**
- a scaffolded **template** → name `"<template name> Template"`, folder
  `<brand>/Slide Templates/<template name>/`.
- a rendered **presentation** (a deck filled from an outline via `renderDeck`)
  → name `"<presentation title> - <template name>"`, folder
  `<brand>/presentations/`.
- a resynced presentation keeps its original name, file id, and folder — the
  Drive URL is stable across edits.
