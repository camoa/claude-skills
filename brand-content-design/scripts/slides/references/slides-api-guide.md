# Google Slides API — practitioner's guide

A plugin-local reference for the `brand-content-design` Slides renderer. Curated
from the `google_slides_renderer` epic research. **Kept inside the plugin** — it
is intentionally NOT published to the public `dev-guides` system.

This guide explains the model the renderer is built on. For the module-by-module
API, read the `src/` files directly; for setup, read `../README.md`.

## What the renderer is

A batch function, not a server. `brand-content-design`'s `/presentation`
command shells out to `dist/cli.js` with a JSON command document on stdin and
reads a JSON result envelope on stdout — the same pattern `visual-content` uses
for reportlab. No MCP server, no long-running process. The `gws` CLI is used
only for the throwaway end-to-end spike, never at runtime.

## Authentication

The Slides + Drive REST APIs are called through the official `googleapis` SDK.
Credentials are resolved from environment variables by `auth.ts` — never
committed, never passed on the command line. Two modes:

- **Service account** — best for automation/CI. Set `GOOGLE_APPLICATION_CREDENTIALS`
  to a key-file path, or supply the key inline.
- **OAuth** — best for an individual user with no Workspace domain.

See `../README.md` → Credentials for the exact variable names and the Google
Cloud setup steps. The shell-out inherits the parent process environment, so
`/presentation` only needs those variables present in its session.

Required scopes: `presentations` (Slides) and `drive` (copy + export + upload).

## The batchUpdate model

Every mutation to a presentation goes through `presentations.batchUpdate` — an
ordered list of typed request objects applied **atomically**: if one request is
rejected, none are applied. The renderer leans on this hard — a rejected batch
leaves the working copy discardable, so a deck is never half-rendered.

Object ids can be **caller-assigned** in the same batch that creates an object,
which is what makes single-batch rendering possible: duplicate N slides with
ids you choose, then reference those ids in fill requests later in the same
batch. Caller-assigned ids must be ≥ 5 characters.

## The type-library + merge model

The template is a **library of typed slides** — one tagged example slide per
type (Title, Content, Image, Data, Quote, CTA, Transition). Types repeat: a real
deck has many Content slides, so the renderer **duplicates** the matching
type-slide once per outline entry rather than authoring each from scratch.

Rendering, per outline entry:

1. `duplicateObject` the matching type-slide, assigning the new slide a known id.
2. **Page-scoped** `replaceAllText` / `replaceAllShapesWithImage` on that new id
   — fills text and images for that instance only.
3. Fill the slide's speaker notes (see below).

`scaffoldTemplate` builds the template and records a **tag map** — every merge
tag per type, with its kind (`text` / `image`). `renderDeck` consumes the tag
map + a content payload and runs the merge.

## Page-scoping — why repeated types fill independently

A presentation-wide `replaceAllText` would fill *every* `{{body}}` on *every*
slide with the same value. The tag-map helpers therefore take an optional
`pageObjectIds` scope: a fill request restricted to one duplicated slide's id.
Slide 2's `{{body}}` and slide 3's `{{body}}` fill from different outline
entries because each fill is page-scoped to its own slide.

## Speaker notes

Speaker notes are a capability the PPTX path never had — the Slides renderer
adds them. They cannot be filled by `replaceAllText` (its `pageObjectIds` scope
rejects notes-page ids). Instead:

- Every slide has an intrinsic notes page; its text shape id lives at
  `slide.slideProperties.notesPage.notesProperties.speakerNotesObjectId`.
- The merge engine resolves that id from a `getPresentation` read, then writes
  the notes with `insertText` straight into the shape (a fresh copy's notes
  shapes are empty, so `insertText` at index 0 suffices — no delete-first).
- This is why a render is **two atomic batches** around one `getPresentation`:
  batch 1 duplicates + fills content, batch 2 fills notes.

The outline carries notes via an optional `Speaker notes:` field per slide —
see `commands/outline.md` and `commands/template-presentation.md`.

## Known API limits (designed around, not fought)

- **No gradient fill** — gradients are baked to images at scaffold time and
  placed as image elements.
- **No custom font embedding** — fonts are classified at preflight:
  Google-Fonts-available fonts are used natively; custom/proprietary fonts have
  their display text baked as an image, and body text is substituted with the
  nearest Google Font (the substitution is surfaced in the render report).
- **No master/layout/theme authoring** — neither the REST API nor Apps Script
  can author theme masters. Per-slide art direction does not need them (it is
  free-form element placement, which the API fully supports).
- **No native chart authoring** — charts arrive as embedded Sheets charts or as
  rendered images.

## CLI command documents

`dist/cli.js` reads `{ "command": <name>, "args": { ... } }` on stdin and writes
`{ "ok": true, "result": ... }` or `{ "ok": false, "error": { code, message } }`.

Low-level (one Slides/Drive call each): `createPresentation`, `getPresentation`,
`batchUpdate`, `copyFile`, `exportFile`, `getPageThumbnail`, `replaceAllText`,
`replaceAllShapesWithImage`.

Orchestration (compose the modules):

- `scaffoldTemplate` — `{ tokens, layoutSpec?, imagePaths?, gradients?,
  driveFolderPath? }` → `ScaffoldResult { presentationId, tagMap,
  fontSubstitutions, folderId? }`. Omit `layoutSpec` to use the built-in
  7-type default layout (`src/default-layout.ts`).
- `renderDeck` — `{ templatePresentationId, tagMap, payload,
  fontSubstitutions?, customFontFile? }` → `RenderResult { presentationId,
  slidesRendered, tagsFilled, fontSubstitutions }`.

The `payload` is produced from a filled outline by `src/outline-parser.ts`
(`parseOutline` → `toContentPayload`).

## Fidelity & the layout IR

`src/default-layout.ts` is the Slides-side layout IR — resolution-independent
per-element geometry (points, 16:9) for all seven types. The reportlab PDF path
(`visual-content`) composes layout dynamically and does not share this object at
runtime; PDF↔Slides parity is instead enforced by the epic's **visual-diff
gate** — the Slides deck is exported to PDF/PNG via Drive and compared to the
reportlab reference within a threshold. A future `visual-content` spec-emitter
that consumes the same IR is noted as follow-up, not shipped here.

## Idempotence

`renderDeck` always starts from a fresh `files.copy` of the template; the
template is never mutated. Re-running a render produces an independent deck —
safe to retry.
