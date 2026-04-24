# Screenshot Store Schema v1.0

**Introduced:** drupal-dev-framework v3.13.0
**Owner:** `skills/screenshot-store-reader/SKILL.md` + `scripts/screenshot-store-read.sh` + `scripts/screenshot-store-write.sh`
**Consumers (as of v3.13.0):** `commands/validate-visual-regression.md`, `commands/validate-visual-parity.md`, `commands/validate-all.md`

The screenshot store is a project-scoped filesystem tree that holds regression baselines and parity references for visual validation. Per-image metadata files carry provenance, integrity hashes, and source info so any task can read the store and understand what each image represents.

## 1. Location

```
<claude_memory_projects_base>/<project_name>/.screenshots/
```

The store lives next to the memory project's other artifacts (`project_state.md`, `implementation_process/`, etc.). It is NOT under `codePath` — screenshots are framework metadata, not code. Users who want team-sharing can use git on the memory folder or copy individual references manually.

## 2. Directory layout

```
.screenshots/
└── <component>/
    ├── <viewport>.png
    ├── <viewport>.meta.json
    ├── <viewport>.previous.png         # optional — 1-deep history
    └── <viewport>.previous.meta.json   # optional — 1-deep history
```

Examples:

```
.screenshots/
├── home-hero/
│   ├── 1920x1080.png
│   ├── 1920x1080.meta.json
│   ├── 1920x1080.previous.png
│   ├── 1920x1080.previous.meta.json
│   └── 375x812.png
│   └── 375x812.meta.json
└── article-hero/
    ├── 1920x1080.png
    └── 1920x1080.meta.json
```

## 3. Naming rules

| Element | Format | Regex |
|---|---|---|
| `<component>` | kebab-case, lowercase, no spaces | `^[a-z0-9][a-z0-9-]*$` |
| `<viewport>` | `WIDTHxHEIGHT` in pixels | `^[0-9]+x[0-9]+$` |

No nesting beyond `<component>/<viewport>`. Flat within each component keeps retrieval predictable at Drupal-theme scale (dozens to hundreds of components). Multi-viewport per component is the common case.

Component names should describe what's captured (`home-hero`, `article-card`, `admin-toolbar`, `footer`), not where on the page (`top-left`). Callers are responsible for sanitizing user input to the kebab-case format before invoking the writer.

## 4. `.meta.json` schema v1.0 (9 fields)

Every `.png` in the store has a sibling `.meta.json` with exactly these 9 fields:

```json
{
  "schema_version": "1.0",
  "role": "baseline",
  "viewport": "1920x1080",
  "captured_at": "2026-04-24T14:30:00Z",
  "sha256": "429368832b95441f1bbd64e711867207eba2cfeb679919e72bb380f8740762ca",
  "originating_task": "dev_framework_granular_validation",
  "captured_by": "playwright-mcp",
  "prior_hash": null,
  "source": null
}
```

### Field contracts

| Field | Type | Values / constraints |
|---|---|---|
| `schema_version` | string | `"1.0"` for v3.13.0. Follows semver. Consumers match on major. MUST be a JSON string, never a number |
| `role` | enum | `"baseline"` (regression source of truth) \| `"parity_reference"` (imported design comp) \| `"previous"` (used ONLY if meta is explicitly rewritten to mark an archived state; normally `.previous.meta.json` keeps the prior `role` unchanged) |
| `viewport` | string | Matches `^[0-9]+x[0-9]+$` — same as the filename stem |
| `captured_at` | string | ISO-8601 UTC with `Z` suffix (e.g. `2026-04-24T14:30:00Z`). Serves as approval timestamp for baselines (they're written at approval time) |
| `sha256` | string | Lowercase hex SHA-256 of the sibling PNG. 64 chars. Integrity + provenance |
| `originating_task` | string | Task folder name that approved/wrote this baseline. For auditing — answers "who put this here?" |
| `captured_by` | enum | `"playwright-mcp"` \| `"claude-in-chrome"` \| `"figma-export"` \| `"html-render"` \| `"user-upload"`. Identifies capture method — matters for understanding cross-run differences |
| `prior_hash` | string \| null | SHA-256 of the file rotated to `.previous` when this baseline was written. `null` on the first baseline (no predecessor). Enables quick integrity checks without reading `.previous.meta.json` |
| `source` | object \| null | REQUIRED when `role: "parity_reference"`, MUST be `null` otherwise. Shape: `{type: "figma" \| "html" \| "image" \| "url", uri: "<absolute url or path>"}`. Without this, a parity reference is unidentifiable after capture |

## 5. Invariants (writer enforces; reader reports violations as warnings)

1. `schema_version` is always `"1.0"` at v3.13.0
2. `role: "parity_reference"` requires non-null `source`; other roles have `source: null`
3. `sha256` MUST match the actual sibling PNG hash; reader emits `hash_mismatch` warning if not
4. First baseline for any `<component>/<viewport>` has `prior_hash: null`; subsequent ones have `prior_hash` = sha256 of what was rotated to `.previous`
5. `<component>` matches `^[a-z0-9][a-z0-9-]*$`
6. `<viewport>` matches `^[0-9]+x[0-9]+$` and matches the filename stem exactly

## 6. `.previous` rotation (1-deep history)

On every write to an existing `<viewport>`:

1. Compute SHA-256 of current `<viewport>.png` → becomes `prior_hash` in the new meta
2. Delete existing `<viewport>.previous.png` + `.previous.meta.json` if present (unconditional drop — only 1 deep ever)
3. Rename `<viewport>.png` → `<viewport>.previous.png`; rename meta similarly (rotated meta keeps its original `role`, unchanged)
4. Copy new source to `<viewport>.png`
5. Write new `<viewport>.meta.json` with the 9 fields
6. Verify sha256(new `<viewport>.png`) matches new meta's `sha256`; on mismatch, rollback via reverse-rename + emit warning

Atomic enough: `mv` on POSIX is atomic within the same filesystem; `cp` + `rm` is not, but any failure path triggers a rollback to the previous good state. No `.candidate` staging in v1 — approval + rotation happen together at the moment of user approval.

## 7. Reader JSON output contract

`scripts/screenshot-store-read.sh <project_folder>` emits:

```json
{
  "schema_version": "1.0",
  "project_path": "/abs/path/to/project",
  "store_path": "/abs/path/to/project/.screenshots",
  "store_exists": true,
  "components": [
    {
      "name": "home-hero",
      "viewports": [
        {
          "viewport": "1920x1080",
          "has_current": true,
          "has_previous": true,
          "meta": { ... 9-field object ... },
          "previous_meta": { ... 9-field object OR null ... },
          "warnings": [ ... per-viewport warnings ... ]
        }
      ]
    }
  ],
  "warnings": [ ... store-level warnings ... ]
}
```

Exit code always 0 except on unrecoverable IO failures (permission denied, etc.), which also produce best-effort JSON with `code: "error"` in `warnings`.

## 8. Warning codes

| Code | Level | When |
|---|---|---|
| `store_missing` | store | `.screenshots/` does not exist (normal for projects that never ran visual tests) |
| `component_missing_meta` | viewport | `<viewport>.png` exists but no `.meta.json` sibling |
| `meta_schema_mismatch` | viewport | `.meta.json` is invalid JSON OR missing one or more required v1.0 fields |
| `hash_mismatch` | viewport | `.meta.json`'s `sha256` does not match the actual PNG (data drift; file edited outside the writer) |
| `orphan_meta` | store | `<viewport>.meta.json` exists but no PNG sibling (cleanup needed) |
| `error` | store | Unrecoverable read failure |

Warnings are additive — a single viewport can have multiple. Never blocks; consumers decide severity.

## 9. Versioning policy

- **Adding fields within v1.x** — consumers ignore unknown keys. No schema bump required
- **Changing field semantics or removing a field** — major bump (v2.0) with migration note
- **Adding new warning codes within v1.x** — consumers treat unknown codes as informational (display, don't error)
- **Changing `role` enum values or `captured_by` enum values** — minor-or-major depending on whether old values remain valid

## 10. Writer invocation reference

```bash
# Baseline (regression source-of-truth)
screenshot-store-write.sh write-baseline \
  <project> <component> <viewport> <source.png> <captured_by> <originating_task>

# Parity reference (imported design comp)
screenshot-store-write.sh write-parity-reference \
  <project> <component> <viewport> <source.png> <captured_by> <originating_task> <source_type> <source_uri>
```

Both return JSON: `{status: "ok"|"rollback"|"error", warnings: [], summary: {...}}`. Exit codes: 0 ok; 1 rollback (warning in JSON); 2 arg validation; 3 IO error pre-rotation.

## 11. Consumers

- **`screenshot-store-reader` skill** (v1.0.0) — thin wrapper around the reader script
- **`/validate:visual-regression`** — reads current baseline; on approved intentional change, invokes `write-baseline` to rotate
- **`/validate:visual-parity`** — reads/writes parity references; diffs against current capture
- **`/validate:all`** — reads store for summary; does NOT write

Future consumers needing screenshot data should call the reader skill rather than parsing the store directly.

## 12. Example meta files

### Regression baseline (first capture, no predecessor)

```json
{
  "schema_version": "1.0",
  "role": "baseline",
  "viewport": "1920x1080",
  "captured_at": "2026-04-24T14:30:00Z",
  "sha256": "429368832b95441f1bbd64e711867207eba2cfeb679919e72bb380f8740762ca",
  "originating_task": "theme_redesign",
  "captured_by": "playwright-mcp",
  "prior_hash": null,
  "source": null
}
```

### Regression baseline (after rotation)

```json
{
  "schema_version": "1.0",
  "role": "baseline",
  "viewport": "1920x1080",
  "captured_at": "2026-05-15T09:12:44Z",
  "sha256": "d91ed079d493278a89a72d1e8f70144bb95a09f4c206c3a391ac44b027e65ce6",
  "originating_task": "hero_cta_update",
  "captured_by": "playwright-mcp",
  "prior_hash": "429368832b95441f1bbd64e711867207eba2cfeb679919e72bb380f8740762ca",
  "source": null
}
```

### Parity reference imported from Figma

```json
{
  "schema_version": "1.0",
  "role": "parity_reference",
  "viewport": "375x812",
  "captured_at": "2026-04-24T16:00:00Z",
  "sha256": "ffef02c5368e578cede902d953e7a9f20ef671d37700aab313d7fb5fcb8ec86c",
  "originating_task": "mobile_redesign",
  "captured_by": "figma-export",
  "prior_hash": null,
  "source": {
    "type": "figma",
    "uri": "https://figma.com/file/abc123/mobile-redesign?node-id=12:45"
  }
}
```

## 13. See also

- `scripts/screenshot-store-read.sh` — the reader
- `scripts/screenshot-store-write.sh` — the writer
- `skills/screenshot-store-reader/SKILL.md` — skill wrapper
- `references/validation-gate-result.md` — the JSON envelope emitted by all `/validate:*` commands
- Architecture §4 in `dev_framework_granular_validation/architecture.md`
