# Surface Registry Schema v1.2

**Introduced:** ai-dev-assistant v4.11.0 (Task A — `visual_and_e2e_review_gates`)
**v1.1:** v4.14.0 (Task D) — extends the `parity_reference` object additively
**v1.2:** v5.1.0 — adds the framework-agnostic `auth_context` surface field and the optional top-level `e2e.preflight_command`, both additive. These are the two generic seams that let the e2e/visual gates run stack-neutral while a process recipe supplies the framework-specific values.
**Owner:** `commands/review.md` step 6 (change-impact dispatcher)
**Consumers:** `/setup-e2e` + `/validate:e2e` (Task B), the reworked
`validate-visual-regression` (Task C), `/setup-visual-parity` + the reworked
`validate-visual-parity` (Task D)

The **surface registry** is the project's single source of truth for *which rendered
surfaces have review coverage* — which URLs, at which viewports, with which masks, for
which gates. It is the "visual coverage manifest" v3.13.0 flagged as a v2 candidate
(`validate-all.md` lines 28, 134).

Task A ships **only this schema** — no registry file is created in any project. A
project gains a registry when a `/setup-*` command (Task B/C/D) writes one. `/review`
on a project with no registry runs zero new gates and prints the opt-in notice.

## 1. Two layers

| Layer | File | Written by | Lifetime |
|---|---|---|---|
| **Project registry** | `<project>/.visual-review/registry.yml` | `/setup-*` commands | Outlives any task |
| **Task fragment** | `<task_folder>/visual-review-surfaces.yml` | A task that adds/changes surfaces | Merged into the project registry at `/complete`, then archived with the task |

`<project>` is the **memory project folder** (the one holding `project_state.md`,
`implementation_process/`, `.screenshots/`). The registry co-locates with the existing
`.screenshots/` store — both are project-scoped review metadata, not code.

> **Relocatable (research D7).** Task C may move the `.screenshots/` store to
> `codePath` when it resolves the screenshot-store fork. If it does, the registry may
> follow. Consumers MUST resolve the registry path from the `project_state.md`
> `**Visual Review:**` pointer (below), never hardcode `.visual-review/registry.yml`.

## 2. Pointer in `project_state.md`

A project opts into visual review by carrying one scalar field in `project_state.md`,
following the `**Code path:**` / `**Playbook Sets:**` pointer convention:

```markdown
**Visual Review:** enabled .visual-review/registry.yml
```

Grammar — `**Visual Review:** <state> <relative-path>`:

- `<state>` — `enabled` or `disabled`. First whitespace-delimited token.
- `<relative-path>` — registry file path relative to the project folder. Remainder of
  the line. Must resolve **within** the project folder (path-escape rejected — see
  `scripts/project-state-read.sh`).
- **Absent line** ⇒ the project has not set up visual review at all.
- `disabled` ⇒ set up once but currently off; `/review` skips the new gates.

`scripts/project-state-read.sh` parses this field into
`visualReview: {enabled, registryPath}` (or `null` when absent). See its header.

## 3. Project registry schema (`registry.yml`) v1.2

```yaml
schema_version: "1.2"
e2e:                             # optional top-level block
  preflight_command: "<stack-setup-command>"   # framework-agnostic; value is project-specific
viewports:                       # project default viewport matrix
  - {name: desktop, width: 1920, height: 1080}
  - {name: tablet,  device: "Galaxy Tab S4"}
  - {name: phone,   device: "Pixel 5"}
surfaces:
  - id: home-hero                # kebab-case; doubles as the screenshot-store key
    url: "/"
    gates: [visual_regression, e2e]      # gate-applicability flags
    viewports: [desktop, tablet, phone]  # optional — overrides the default matrix
    masks: ["time", ".field--name-created"]   # CSS selectors, optional
    auth_context: null           # null | string — opaque auth context name
    parity_reference: null       # null | object
```

A surface that participates in visual parity carries a populated `parity_reference`
object and `visual_parity` in its `gates` list — `/setup-visual-parity` writes both:

```yaml
  - id: marketing-landing
    url: "/landing"
    gates: [visual_regression, visual_parity]
    parity_reference:
      type: html-template
      uri: "themes/custom/foo/design/landing.html"
      reference_hash: "a1b2c3…"            # sha256 of the reference file
      compare_selectors: [".hero-title", ".hero .cta", ".card"]
      notes: "CTA colour intentionally darker than comp"
      last_compared_at: "2026-05-21T12:00:00Z"
```

### 3.1 Top-level keys

| Key | Type | Required | Notes |
|---|---|---|---|
| `schema_version` | string | yes | `"1.0"` (v4.11.0), `"1.1"` (v4.14.0+), or `"1.2"` (v5.1.0+). Consumers gate on major; a lower-minor registry is a valid higher-minor registry (every minor addition is optional). |
| `e2e` | object | no | Optional e2e configuration block. Absent ⇒ the e2e gate runs no preflight. |
| `viewports` | list | yes | The project default viewport matrix. Each entry is a **viewport descriptor**. |
| `surfaces` | list | yes | Zero or more **surface entries**. Empty list is valid (set up, no surfaces yet). |

### 3.2 Surface entry

| Field | Type | Required | Contract |
|---|---|---|---|
| `id` | string | yes | Kebab-case, `^[a-z0-9][a-z0-9-]*$`. **Unique** within `surfaces[]`. Doubles as the screenshot-store `<component>` key. |
| `url` | string | yes | Path or absolute URL of the surface. Relative paths resolve against the Playwright `baseURL`. |
| `gates` | list | yes | Subset of `[e2e, visual_regression, visual_parity]` — which gates apply to this surface. Empty list = registered but no gate runs it. |
| `viewports` | list | no | List of viewport **names** (from `viewports[].name`). Absent ⇒ the project default matrix applies. |
| `masks` | list | no | CSS selectors masked before capture (dynamic regions — timestamps, ad slots). Absent ⇒ none. |
| `auth_context` | string \| null | no | `null`/absent ⇒ anonymous capture. A non-null **opaque context name** `"<ctx>"` routes the surface through the authenticated-VR seam (wired in v1.2, no longer reserved). See the concrete contract below. Framework-agnostic: the plugin treats `<ctx>` as an opaque key and never learns how the auth was obtained; the stack's process recipe supplies the login. |
| `parity_reference` | object \| null | no | `null`, or the **parity-reference object**. Consumed by `/setup-visual-parity` + `/validate:visual-parity` (Task D). |

**`auth_context` contract (wired in v1.2).** A non-null `auth_context: "<ctx>"`
routes the surface to the authenticated-VR seam. `/setup-visual-regression` wires
it as follows (`<vp>` = viewport name; `<id>` = surface id):

- authed visual project: `visual-chromium-<vp>-<ctx>` (one per viewport),
  declaring `dependencies: ['visual-setup-<ctx>']` and loading
  `storageState: tests/visual/.auth/<ctx>.json`.
- session producer: `tests/visual/.auth/<ctx>.setup.ts`, run by the
  `visual-setup-<ctx>` setup project to write that storageState. The plugin emits
  this file as a throwing stub; the **stack's process recipe supplies the login**
  and removes the throw. An unfilled stub fails the gate loudly (never a silent
  logged-out capture).
- authed surface spec: `tests/visual/auth/<ctx>/<id>.spec.ts` (same starter
  template as anonymous; auth is carried by the project's storageState, not the
  spec).
- authed baselines: `<id>-visual-chromium-<vp>-<ctx>-linux.png`.

`<ctx>` stays opaque to the plugin — it is a key, not a credential or a role. A
process recipe maps its framework's roles onto these names (example: a recipe maps
its auth roles → context names). The storageState JSON is
a secret-bearing runtime artifact and is gitignored; the `<ctx>.setup.ts` is
committed.

### 3.3 Viewport descriptor

Either an explicit pixel size **or** a Playwright device name — never both:

```yaml
{name: desktop, width: 1920, height: 1080}   # explicit pixels
{name: phone,   device: "Pixel 5"}           # Playwright device preset
```

| Field | Type | Required | Contract |
|---|---|---|---|
| `name` | string | yes | Kebab-case label. Referenced by surface `viewports[]`. |
| `width` / `height` | int | one form | Explicit pixel size. Both required together. |
| `device` | string | one form | A Playwright built-in device name. Mutually exclusive with `width`/`height`. |

### 3.4 Parity-reference object (v1.1)

The `parity_reference` field is `null` (the surface has no design comp) or an object
declaring the external design reference the surface is checked against. `/setup-visual-parity`
writes it; `/validate:visual-parity` reads it. **Every field but `type` and `uri` is
optional** — a v1.0-shaped `{type, uri}` object remains valid.

| Field | Type | Required | Contract |
|---|---|---|---|
| `type` | enum | yes | `figma` \| `react-template` \| `html-template` \| `image` \| `prod-url`. **Renderable** (`html-template`, `react-template`, `prod-url`) → both sides have a DOM → full CSS-actionable diff. **Static** (`figma`, `image`) → a flat PNG, no DOM → build-only diff. |
| `uri` | string | yes | A **file path** (for `figma`, `image`, `html-template`, and a pre-rendered `react-template`) or an **`http(s)` URL** (for `prod-url`, or a `react-template` served by a dev server). File paths must resolve within `codePath` or be a user-confirmed absolute path; non-`http(s)` schemes are rejected for `prod-url`. |
| `reference_hash` | string \| null | no | Lowercase hex sha256 of the reference **file**. `null` for URL-only references (`prod-url`, served `react-template`) — a live URL has no stable hash. Drives "reference changed since last compare" drift detection. |
| `compare_selectors` | list | no | CSS selectors whose computed styles are compared across build and reference. Absent ⇒ the gate's default set (headings `h1`–`h3`, `button`/`.button`/`.cta`, the main content container). |
| `notes` | string | no | Free-text — e.g. an accepted intentional deviation recorded by `[i]` classification. Never executed; display-only. |
| `last_compared_at` | string \| null | no | ISO-8601 UTC of the last `/validate:visual-parity` run touching this surface. Written by the gate. |

**v1.0 → v1.1 changes (all additive):** `type` widens from `{figma, prod, mockup}` to
`{figma, react-template, html-template, image, prod-url}`. `prod` is renamed `prod-url`
and `mockup` is renamed `image` — no migration is needed because Task A shipped the
schema only and **no v1.0 registry file exists in the wild** (the first registry any
project gets is written by a Task C/D `/setup-*` command, which emits v1.1). The new
optional fields (`reference_hash`, `compare_selectors`, `notes`, `last_compared_at`) are
ignored by any v1.0 consumer.

### 3.5 e2e block (v1.2)

The optional top-level `e2e` object configures the e2e gate without coupling it to any framework.

```yaml
e2e:
  preflight_command: "<stack-setup-command>"
```

| Field | Type | Required | Contract |
|---|---|---|---|
| `preflight_command` | string | no | A shell command the e2e gate runs in `codePath` **before** the Playwright tests. A non-zero exit fails the gate; the command's output is captured into `preflight_warnings`. The gate (`scripts/validate-e2e.sh`) is framework-agnostic — it runs whatever this resolves to and assumes nothing about the stack. `/validate:e2e` reads this field and passes it through as `--preflight-cmd`. Absent ⇒ no preflight runs. The **field** is generic; the **value** is project-specific — a project's `e2e-setup` recipe, resolved by `/setup-e2e`, seeds the appropriate command for its stack; each project registers its own (or none). |

This is the seam that removed the last hardcoded preflight command from the gate: the framework-specific command now lives in project config that a process recipe writes, not in plugin code.

## 4. Task fragment (`visual-review-surfaces.yml`)

A task that adds or changes review coverage drops a fragment in its task folder:

```yaml
schema_version: "1.0"
surfaces:
  - id: checkout-summary
    url: "/checkout"
    gates: [e2e, visual_regression]
```

- **Identical `surfaces:` shape** to the project registry.
- **No `viewports:` block** — a fragment inherits the project default matrix. A surface
  that needs a non-default matrix sets its own `viewports:` field.
- Merged into the project registry at `/complete`.

### 4.1 Merge semantics (research D2)

At `/complete`, the task fragment merges into the project registry:

- **Union** of surfaces.
- **Last-write-wins per `id`** — a fragment surface with an `id` already in the project
  registry **replaces** the project entry (the task is the most recent intent).
- **New `id`** ⇒ appended.
- The merge is **surfaced, not silent** — `/complete` prints
  `visual-review: updated surface <id>` / `added surface <id>` per merged entry.
- A hard error is **not** raised on conflict — it would block `/complete` for a benign
  case. Last-write-wins + the printed surface line is the resolution.

## 5. Forward-compatibility with the v3.13.0 screenshot store

The v3.13.0 screenshot store keys images as `.screenshots/<component>/<viewport>.png`,
where `<component>` is kebab-case and `<viewport>` is `WIDTHxHEIGHT`
(`references/screenshot-store-schema.md`).

The registry is designed so Task C can bridge old store ↔ new registry **with no key
translation**:

- A surface `id` **is** the store `<component>` key — same kebab-case regex.
- A viewport descriptor maps to the store `<viewport>` key by
  `width + "x" + height` (e.g. `{width: 1920, height: 1080}` → `1920x1080`). Device-form
  viewports resolve to pixels via the Playwright device table at capture time.

So `.screenshots/home-hero/1920x1080.png` corresponds exactly to registry surface
`home-hero` at the viewport whose pixels are `1920x1080`. Task C can read the existing
store and emit a registry, or vice versa, without renaming anything.

## 6. Why YAML (not JSON)

The registry is **human-curated** — users add, remove, and annotate surfaces by hand.
YAML's comments and terseness suit that. No Task A *script* parses the registry; it is
read by Claude (the `/review` dispatcher, per `change-impact-dispatch.md`) and by the
Task B/C/D commands — all of which parse YAML natively. The sibling
`change-impact.json` rule file is JSON precisely because a *shell script*
(`change-impact-classify.sh`) parses it and the framework has no YAML parser.

## 7. Versioning policy

- **Major bumps** (`2.0`) are breaking: removed/renamed required fields, reshaped
  surface entry, changed merge semantics.
- **Minor bumps** (`1.1`) are additive: new optional surface fields, new optional
  top-level keys, new `parity_reference.type` values. Existing consumers ignore unknown
  keys.
- v1.0 committed for v4.11.0.
- **v1.1 committed for v4.14.0** (Task D) — the `parity_reference` object grows four
  optional fields and its `type` enum widens. Additive: a v1.0 consumer reading a
  v1.1 registry ignores the new keys; a v1.1 consumer reading a v1.0-shaped
  `parity_reference` sees only `type`/`uri` and applies its defaults.
- **v1.2 committed for v5.1.0** — adds the optional `auth_context` surface field
  and the optional top-level `e2e.preflight_command`. Both additive: a pre-v1.2
  consumer ignores them; the gates degrade to anonymous capture / no preflight when
  absent. These are the generic seams that make the e2e and visual gates framework-agnostic.

## 8. Non-goals

- **No registry file is created by Task A.** Only this schema ships. `/setup-*`
  (Task B/C/D) writes the first registry.
- **No SDC component-level granularity** — surfaces are page-level URLs. Component
  isolation is a future epic (Spike #1).
- **No per-surface baseline data** — baselines live in the screenshot store (Task C
  owns its schema). The registry says *what to cover*, not *what the baseline is*.
- **No scoping of VR by component dependency graph** — out of epic scope.
