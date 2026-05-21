# Surface Registry Schema v1.0

**Introduced:** drupal-dev-framework v4.11.0 (Task A — `visual_and_e2e_review_gates`)
**Owner:** `commands/review.md` step 6 (change-impact dispatcher)
**Consumers (planned):** `/setup-atk` + `/validate:e2e` (Task B), the reworked
`validate-visual-regression` (Task C), `validate-visual-parity` (Task D)

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

## 3. Project registry schema (`registry.yml`) v1.0

```yaml
schema_version: "1.0"
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
    parity_reference: null       # null | {type: figma|prod|mockup, uri: "..."}
```

### 3.1 Top-level keys

| Key | Type | Required | Notes |
|---|---|---|---|
| `schema_version` | string | yes | `"1.0"` for v4.11.0. Consumers gate on major. |
| `viewports` | list | yes | The project default viewport matrix. Each entry is a **viewport descriptor** (§3.3). |
| `surfaces` | list | yes | Zero or more **surface entries** (§3.2). Empty list is valid (set up, no surfaces yet). |

### 3.2 Surface entry

| Field | Type | Required | Contract |
|---|---|---|---|
| `id` | string | yes | Kebab-case, `^[a-z0-9][a-z0-9-]*$`. **Unique** within `surfaces[]`. Doubles as the screenshot-store `<component>` key (§5). |
| `url` | string | yes | Path or absolute URL of the surface. Relative paths resolve against the Playwright `baseURL`. |
| `gates` | list | yes | Subset of `[e2e, visual_regression, visual_parity]` — which gates apply to this surface. Empty list = registered but no gate runs it. |
| `viewports` | list | no | List of viewport **names** (from `viewports[].name`). Absent ⇒ the project default matrix applies. |
| `masks` | list | no | CSS selectors masked before capture (dynamic regions — timestamps, ad slots). Absent ⇒ none. |
| `parity_reference` | object \| null | no | `null`, or `{type, uri}` with `type ∈ {figma, prod, mockup}`. Consumed by Task D. |

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

## 4. Task fragment (`visual-review-surfaces.yml`)

A task that adds or changes review coverage drops a fragment in its task folder:

```yaml
schema_version: "1.0"
surfaces:
  - id: checkout-summary
    url: "/checkout"
    gates: [e2e, visual_regression]
```

- **Identical `surfaces:` shape** to the project registry (§3.2).
- **No `viewports:` block** — a fragment inherits the project default matrix. A surface
  that needs a non-default matrix sets its own `viewports:` field (§3.2).
- Merged into the project registry at `/complete` (§4.1).

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
(`references/screenshot-store-schema.md` §3).

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

## 8. Non-goals

- **No registry file is created by Task A.** Only this schema ships. `/setup-*`
  (Task B/C/D) writes the first registry.
- **No SDC component-level granularity** — surfaces are page-level URLs. Component
  isolation is a future epic (Spike #1).
- **No per-surface baseline data** — baselines live in the screenshot store (Task C
  owns its schema). The registry says *what to cover*, not *what the baseline is*.
- **No scoping of VR by component dependency graph** — out of epic scope.
