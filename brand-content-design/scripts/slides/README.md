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

### Service account (best for automation / CI)

```sh
export BCD_SLIDES_SA_KEY_FILE=/abs/path/to/service-account-key.json
```

The service account needs access to the files it touches — share the template
(and an output folder) with the service-account email, or use a Shared Drive,
or domain-wide delegation.

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

`tagMap` / `tagImageMap` are `{ "{{tag}}": "value" }` objects — keys are the
literal tag tokens in the template, values are replacement text or image URLs.

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
| `cli.ts` | stdin-JSON → stdout-envelope adapter |
