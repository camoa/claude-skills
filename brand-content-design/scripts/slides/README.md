# Slides/Drive API client

The Google Slides + Drive API transport layer for the `brand-content-design`
plugin's `google_slides_renderer` epic. A typed TypeScript library
(`SlidesClient`) plus a thin CLI wrapper — **not** an MCP server, not a
long-running process. Sibling renderer components (scaffolder, merge engine)
call it; a skill invokes the CLI via shell-out.

## Setup

```sh
cd brand-content-design/scripts/slides
npm install
npm run build      # tsc → dist/
```

`node_modules/` and `dist/` are git-ignored. Re-run `npm run build` after any
change under `src/`.

## Credentials

Credentials come **only** from environment variables — never commit them. The
`.gitignore` already excludes `*-key.json`, `service-account*.json`, and
`.env*`.

Two modes; the service account wins if both are set.

### Which mode should I use?

- **Personal Google account (`@gmail.com`) → use OAuth.** Decks are created
  directly in *your own* Drive, where you can open them. A service account has
  its own Drive with **no browsable UI**, so files it creates are not in your
  Drive unless it parents them into a folder you pre-shared with it — and the
  clean fix for that (a **Shared Drive**) requires Google Workspace, which
  personal accounts do not have.
- **Google Workspace account, or unattended CI → use the service account.**
  No consent screen, no refresh token; pair it with a Shared Drive.

Heads-up: some projects have the `iam.disableServiceAccountKeyCreation` org
policy on, which greys out JSON-key creation — another reason OAuth is the
smoother path for an individual.

### Creating the credentials in Google Cloud

One-time, in [console.cloud.google.com](https://console.cloud.google.com):

1. Create or pick a project; under **APIs & Services → Library** enable **both**
   the **Google Slides API** and the **Google Drive API**.
2. **Service account path** — **IAM & Admin → Service Accounts → Create**, then
   **Keys → Add key → Create new key → JSON**. The downloaded file's path is
   `BCD_SLIDES_SA_KEY_FILE`. Share the template presentation (and any output
   folder) with the service-account email, or put them in a Shared Drive it can
   access.
3. **OAuth path** — **APIs & Services → OAuth consent screen** (add yourself as
   a test user), then **Credentials → Create credentials → OAuth client ID →
   Desktop app** for the client id/secret. Mint a refresh token with the
   [OAuth Playground](https://developers.google.com/oauthplayground): ⚙ → "Use
   your own OAuth credentials" → scopes `auth/presentations` + `auth/drive.file`
   → Authorize → Exchange authorization code for tokens.

The service-account path has fewer steps (no consent screen, no refresh token),
but see "Which mode should I use?" above — on a personal account OAuth is
usually the better fit despite the extra steps.

### Service account (best for Workspace accounts / CI)

```sh
export BCD_SLIDES_SA_KEY_FILE=/abs/path/to/service-account-key.json
```

The service account needs access to the files it touches — share the template
(and an output folder) with the service-account email, or use a Shared Drive,
or domain-wide delegation. **Files the service account creates land in the
service account's own Drive** (which has no UI); to see them, have it create
everything inside a folder you own and shared with it as Editor, or use a
Shared Drive (Workspace only).

### OAuth (best for an individual user — no Workspace domain needed)

```sh
export BCD_SLIDES_OAUTH_CLIENT_ID=...
export BCD_SLIDES_OAUTH_CLIENT_SECRET=...
export BCD_SLIDES_OAUTH_REFRESH_TOKEN=...
```

### Scopes

The client requests the narrowest scopes that work:
`https://www.googleapis.com/auth/presentations` and `.../auth/drive.file`.
`drive.file` only covers files the app created or opened — sufficient when the
template is created through this client. A hand-built seed master needs the
broader `.../auth/drive` scope or an explicit share.

## CLI usage

The CLI reads one JSON command document on **stdin** and writes one JSON
envelope to **stdout**.

```sh
echo '{"command":"createPresentation","args":{"title":"My Deck"}}' \
  | node dist/cli.js
```

Envelope:

```json
{ "ok": true,  "result": { "presentationId": "1AbC..." } }
{ "ok": false, "error": { "code": "INVALID_ARGUMENT", "message": "...",
                          "failedRequest": { } } }
```

Exit code is `0` when `ok`, `1` otherwise — but always read the envelope.

### Commands

| `command` | `args` | result |
|---|---|---|
| `createPresentation` | `title` | `{ presentationId }` |
| `getPresentation` | `presentationId` | the presentation resource |
| `batchUpdate` | `presentationId`, `requests[]` | `{ replies[] }` |
| `copyFile` | `fileId`, `newName`, `parentId?` | `{ fileId }` |
| `exportFile` | `fileId`, `mimeType` (`application/pdf`\|`image/png`) | `{ base64 }` |
| `getPageThumbnail` | `presentationId`, `pageObjectId` | `{ contentUrl }` |
| `replaceAllText` | `presentationId`, `tagMap` | `{ occurrencesByTag }` |
| `replaceAllShapesWithImage` | `presentationId`, `tagImageMap` | `{ occurrencesByTag }` |
| `scaffoldTemplate` | `tokens`, `layoutSpec?`, `imagePaths?`, `gradients?`, `driveFolderPath?`, `presentationName?` | `ScaffoldResult` |
| `outlineToPayload` | `outlineMarkdown`, `tagMap` | `ContentPayload` |
| `renderDeck` | `templatePresentationId`, `tagMap`, `payload`, `fontSubstitutions?`, `customFontFile?` | `RenderResult` |

`tagMap` / `tagImageMap` (on the low-level text/image commands) are
`{ "{{tag}}": "value" }` objects — keys are the literal tag tokens in the
template, values are replacement text or image URLs.

`scaffoldTemplate`, `outlineToPayload`, and `renderDeck` are the orchestration
commands the `/presentation` Google Slides target shells out to, in that order.
`scaffoldTemplate` omitting `layoutSpec` uses the built-in 7-type default
layout. `outlineToPayload` parses a filled `/outline` markdown into the
`ContentPayload` that `renderDeck` consumes. See
`references/slides-api-guide.md` for the full rendering model.

Note: `exportFile` with `image/png` exports the **first page only** (a Drive
API limitation — `files.export` is whole-file). For per-page images use
`getPageThumbnail`.

## Library usage

```ts
import { google } from 'googleapis';
import { resolveAuthConfig, createAuthClient } from './dist/auth.js';
import { SlidesClient } from './dist/client.js';

const auth = createAuthClient(resolveAuthConfig(process.env));
const client = new SlidesClient({
  slides: google.slides({ version: 'v1', auth }),
  drive: google.drive({ version: 'v3', auth }),
});
const { presentationId } = await client.createPresentation('My Deck');
```

## Tests

```sh
npm test           # vitest — unit tests, googleapis fully mocked, no network
```

## Integration spike (manual)

`spike/run.mjs` exercises the real APIs end to end (copy → text merge → image
merge → PDF export). Env-gated, never in CI:

```sh
export BCD_SLIDES_SPIKE_TEMPLATE_ID=<a Slides file id>
# plus auth env vars above; optional BCD_SLIDES_SPIKE_IMAGE_URL
npm run spike
```

## Module map

| `src/` | role |
|---|---|
| `types.ts` | shared types — the contract sibling components compile against |
| `auth.ts` | resolve credentials from env vars; build the auth client |
| `requests.ts` | pure Slides request-object builders — tag-map text/image (optional `pageObjectIds` scope) + speaker notes |
| `retry.ts` | exponential backoff for `429` / `5xx` |
| `errors.ts` | normalize any throwable into a structured `SlidesError` |
| `client.ts` | `SlidesClient` — the typed API surface |
| `cli.ts` | stdin-JSON → stdout-envelope adapter; low-level + orchestration commands |
| `token-mapper.ts` | pure brand-token → Slides styling-request mapper |
| `layout-spec.ts` | layout-IR + tag-map types — scaffolder input/output contract |
| `default-layout.ts` | the built-in 16:9 layout IR for all 7 slide types |
| `font-classifier.ts` | classify brand fonts — Google-Fonts-native vs custom |
| `image-baker.ts` | bake gradients + custom-font display text to PNG (`@napi-rs/canvas`) |
| `slide-builder.ts` | build one type-slide's create/style requests from a layout |
| `scaffolder.ts` | `scaffoldTemplate` — compose the branded typed-slide template |
| `payload-validator.ts` | validate a content payload against the tag map (fail-fast) |
| `outline-parser.ts` | parse a filled `/outline` markdown → `ContentPayload` |
| `merge-engine.ts` | `renderDeck` — outline-driven render of a finished deck |

## Reference

`references/slides-api-guide.md` — the rendering model (auth, the batchUpdate
model, the type-library + merge model, page-scoping, speaker notes, known API
limits). Plugin-local; not part of the public `dev-guides` system.
