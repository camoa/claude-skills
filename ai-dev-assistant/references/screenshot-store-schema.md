# Screenshot Store Schema v1.0

**Introduced:** ai-dev-assistant v3.13.0
**Location reworked:** v4.13.0 (Task C) — store moved to codePath-native
**Owner:** `skills/screenshot-store-reader/SKILL.md` + `scripts/screenshot-store-read.sh` + `scripts/screenshot-store-write.sh`
**Consumers:** `commands/validate-visual-regression.md`, `commands/validate-visual-parity.md`, `commands/validate-all.md`

The screenshot store holds visual-regression baselines and parity references.
Per-image `.meta.json` sidecars carry provenance, integrity hashes, and source
info so any task can read the store and understand what each image represents.
The 9-field `.meta.json` schema is **unchanged**; v4.13.0 changed only the
store **location** and the `<viewport>` field's value form.

## 1. Location

**Primary (v4.13.0+) — codePath-native.** Visual-regression baselines are
committed Playwright snapshots under the project's code repository:

```
<codePath>/tests/visual/<surface>.spec.ts-snapshots/
```

This makes baselines PR-native (a baseline change diffs alongside the code
change), team-shared by default (committed to the repo), and portable (no
absolute paths in `playwright.config.ts`). Resolution Q1 in Task C `research.md`
(fork option **(b+)**).

**Legacy — memory-project `.screenshots/`.** The v3.13.0 store lived in the
memory project folder (`<project>/.screenshots/`). It is **retired for new
projects** and serves only as a migration source — see the legacy migration section and
`scripts/migrate-screenshots-to-codepath.sh`.

## 2. Directory layout (codePath-native)

```
<codePath>/tests/visual/
├── <surface>.spec.ts
└── <surface>.spec.ts-snapshots/
    ├── <surface>-<ordinal>-visual-chromium-<viewport>-<platform>.png
    ├── <surface>-<ordinal>-visual-chromium-<viewport>-<platform>.meta.json   ← provenance sidecar
    └── <surface>-<ordinal>-visual-chromium-<viewport>-<platform>.txt          ← a11y snapshot (visual-regression package)
```

Example:

```
<codePath>/tests/visual/
├── home-hero.spec.ts
└── home-hero.spec.ts-snapshots/
    ├── home-hero-visual-chromium-desktop-linux.png
    ├── home-hero-visual-chromium-desktop-linux.meta.json
    ├── home-hero-visual-chromium-tablet-linux.png
    └── home-hero-visual-chromium-tablet-linux.meta.json
```

The baseline filename is Playwright's snapshot naming —
`<snapshot-name>-<projectName>-<platform>`. Generated specs name the snapshot
explicitly after the surface id (`toHaveScreenshot('<surface-id>.png')`), so the
name is deterministic; the `<viewport>` is the `visual-chromium-<viewport>`
project segment. The `.meta.json` sidecar replaces the `.png` extension. (A
recipe-supplied capture helper that names its snapshot anonymously will instead
produce Playwright's `<test-name>-<ordinal>-…` form — the store reader enumerates
whatever baseline files exist, so either shape is accepted.)

### 2b. Legacy layout (migration source only)

The v3.13.0 memory-project store keyed images as
`.screenshots/<component>/<viewport>.png` with `<viewport>` in `WIDTHxHEIGHT`
form, plus optional `.previous.png` 1-deep history:

```
<project>/.screenshots/
└── <component>/
    ├── <viewport>.png              # <viewport> = WIDTHxHEIGHT, e.g. 1920x1080
    ├── <viewport>.meta.json
    ├── <viewport>.previous.png         # optional — 1-deep history
    └── <viewport>.previous.meta.json   # optional — 1-deep history
```

`migrate-screenshots-to-codepath.sh` copies this into the codePath-native
layout, rewriting `captured_by` and the `viewport` field. The legacy store is
never auto-deleted — the user removes it after verifying the migration.

## 3. Naming rules

| Element | Format | Regex |
|---|---|---|
| `<surface>` / `<component>` | kebab-case, lowercase, no spaces | `^[a-z0-9][a-z0-9-]*$` |
| `<viewport>` (codePath-native) | viewport **name** — kebab-case | `^[a-z0-9][a-z0-9-]*$` |
| `<viewport>` (legacy `.screenshots/`) | `WIDTHxHEIGHT` in pixels | `^[0-9]+x[0-9]+$` |

In the codePath-native layout the surface `id` is the spec-file stem and the
`<viewport>` is the registry viewport **name** (`desktop`, `tablet`, `phone`) —
the same value carried in the `viewport` field of `.meta.json`. The pixel size
lives in `registry.yml`'s viewport descriptor, not in the filename.

Surface names should describe what's captured (`home-hero`, `article-card`,
`footer`), not where on the page (`top-left`). The surface `id` in the registry
IS the store key — `/setup-visual-regression` keeps them in sync.

## 4. `.meta.json` schema v1.0 (9 fields)

Every `.png` in the store has a sibling `.meta.json` with exactly these 9 fields:

```json
{
  "schema_version": "1.0",
  "role": "baseline",
  "viewport": "desktop",
  "captured_at": "2026-04-24T14:30:00Z",
  "sha256": "429368832b95441f1bbd64e711867207eba2cfeb679919e72bb380f8740762ca",
  "originating_task": "dev_framework_granular_validation",
  "captured_by": "playwright",
  "prior_hash": null,
  "source": null
}
```

### Field contracts

| Field | Type | Values / constraints |
|---|---|---|
| `schema_version` | string | `"1.0"` for v3.13.0. Follows semver. Consumers match on major. MUST be a JSON string, never a number |
| `role` | enum | `"baseline"` (regression source of truth) \| `"parity_reference"` (imported design comp) \| `"previous"` (used ONLY if meta is explicitly rewritten to mark an archived state; normally `.previous.meta.json` keeps the prior `role` unchanged) |
| `viewport` | string | codePath-native: the viewport **name** (`desktop`), kebab-case. Legacy `.screenshots/`: `WIDTHxHEIGHT` (`^[0-9]+x[0-9]+$`). Matches the value in the filename's project segment |
| `captured_at` | string | ISO-8601 UTC with `Z` suffix (e.g. `2026-04-24T14:30:00Z`). Serves as approval timestamp for baselines (they're written at approval time) |
| `sha256` | string | Lowercase hex SHA-256 of the sibling PNG. 64 chars. Integrity + provenance |
| `originating_task` | string | Task folder name that approved/wrote this baseline. For auditing — answers "who put this here?" |
| `captured_by` | enum | `"playwright"` (primary — the framework-neutral native capture the plugin ships) \| `"playwright-accessible"` (a process recipe supplied an accessibility-aware capture helper) \| `"lullabot-playwright"` (legacy / a recipe using the Lullabot accessible-screenshot helper; accepted for back-compat) \| `"migrated-from-screenshots-store"` (set by `migrate-screenshots-to-codepath.sh`) \| `"playwright-mcp"` \| `"claude-in-chrome"` \| `"figma-export"` \| `"html-render"` \| `"user-upload"`. Identifies capture method — matters for understanding cross-run differences |
| `prior_hash` | string \| null | SHA-256 of the file rotated to `.previous` when this baseline was written. `null` on the first baseline (no predecessor). Enables quick integrity checks without reading `.previous.meta.json` |
| `source` | object \| null | REQUIRED when `role: "parity_reference"`, MUST be `null` otherwise. Shape: `{type: "figma" \| "html" \| "image" \| "url", uri: "<absolute url or path>"}`. Without this, a parity reference is unidentifiable after capture |

## 5. Invariants (writer enforces; reader reports violations as warnings)

1. `schema_version` is always `"1.0"` at v3.13.0
2. `role: "parity_reference"` requires non-null `source`; other roles have `source: null`
3. `sha256` MUST match the actual sibling PNG hash; reader emits `hash_mismatch` warning if not
4. First baseline for any `<component>/<viewport>` has `prior_hash: null`; subsequent ones have `prior_hash` = sha256 of what was rotated to `.previous`
5. `<surface>` / `<component>` matches `^[a-z0-9][a-z0-9-]*$`
6. The `viewport` field matches the `<viewport>` segment of the filename. In
   the codePath-native layout that segment is the viewport **name**
   (`^[a-z0-9][a-z0-9-]*$`, e.g. `desktop`); in the legacy `.screenshots/`
   layout it is `WIDTHxHEIGHT` (`^[0-9]+x[0-9]+$`).

## 6. `.previous` rotation (1-deep history)

> **codePath-native (v4.13.0+) has no `.previous` rotation.** Baselines are
> committed Playwright snapshots — **git history IS the baseline history**.
> `npx playwright test --update-snapshots` overwrites the PNG in place; the
> prior commit holds the old baseline. `write-baseline-codepath` still records
> the prior PNG's hash in the new sidecar's `prior_hash` field (read from the
> sidecar it is about to overwrite), but no `.previous.png` file is created.
> The reader reports `has_previous: false` / `previous_meta: null` for every
> codePath-native viewport. The rotation below applies ONLY to the legacy
> `.screenshots/` writer (`write-baseline` / `write-parity-reference`).

On every legacy `write-baseline` / `write-parity-reference` to an existing
`<viewport>`:

1. Compute SHA-256 of current `<viewport>.png` → becomes `prior_hash` in the new meta
2. Delete existing `<viewport>.previous.png` + `.previous.meta.json` if present (unconditional drop — only 1 deep ever)
3. Rename `<viewport>.png` → `<viewport>.previous.png`; rename meta similarly (rotated meta keeps its original `role`, unchanged)
4. Copy new source to `<viewport>.png`
5. Write new `<viewport>.meta.json` with the 9 fields
6. Verify sha256(new `<viewport>.png`) matches new meta's `sha256`; on mismatch, rollback via reverse-rename + emit warning

Atomic enough: `mv` on POSIX is atomic within the same filesystem; `cp` + `rm` is not, but any failure path triggers a rollback to the previous good state. No `.candidate` staging in v1 — approval + rotation happen together at the moment of user approval.

## 7. Reader JSON output contract

`scripts/screenshot-store-read.sh <codePath>` emits:

```json
{
  "schema_version": "1.0",
  "project_path": "/abs/path/to/codePath",
  "store_path": "/abs/path/to/codePath/tests/visual",
  "store_exists": true,
  "components": [
    {
      "name": "home-hero",
      "viewports": [
        {
          "viewport": "desktop",
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
| `store_missing` | store | `<codePath>/tests/visual/` does not exist (normal for projects that have not run `/setup-visual-regression`) |
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
# codePath-native baseline sidecar (v4.13.0+ — PRIMARY for visual regression).
# Playwright writes the PNG via --update-snapshots; this writes the .meta.json
# sidecar next to it. No rotation — git holds history.
screenshot-store-write.sh write-baseline-codepath \
  <codePath> <surface-id> <png-filename> <viewport-name> <captured_by> <originating_task>

# Legacy baseline in .screenshots/ (retained for the migration period).
screenshot-store-write.sh write-baseline \
  <project> <component> <viewport> <source.png> <captured_by> <originating_task>

# Parity reference (imported design comp — Task D).
screenshot-store-write.sh write-parity-reference \
  <project> <component> <viewport> <source.png> <captured_by> <originating_task> <source_type> <source_uri>
```

All three return JSON: `{status: "ok"|"rollback"|"error", warnings: [], summary: {...}}`. Exit codes: 0 ok; 1 rollback (warning in JSON); 2 arg validation; 3 IO error. `write-baseline-codepath` never rotates, so it never returns `rollback`.

## 11. Consumers

- **`screenshot-store-reader` skill** (v1.1.0) — thin wrapper around the reader script
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
  "viewport": "desktop",
  "captured_at": "2026-04-24T14:30:00Z",
  "sha256": "429368832b95441f1bbd64e711867207eba2cfeb679919e72bb380f8740762ca",
  "originating_task": "theme_redesign",
  "captured_by": "playwright",
  "prior_hash": null,
  "source": null
}
```

### Regression baseline (subsequent capture — prior_hash chained)

```json
{
  "schema_version": "1.0",
  "role": "baseline",
  "viewport": "desktop",
  "captured_at": "2026-05-15T09:12:44Z",
  "sha256": "d91ed079d493278a89a72d1e8f70144bb95a09f4c206c3a391ac44b027e65ce6",
  "originating_task": "hero_cta_update",
  "captured_by": "playwright",
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
- `references/visual-regression-walkthrough.md` — the v4.13.0 codePath-native workflow
- `scripts/migrate-screenshots-to-codepath.sh` — legacy `.screenshots/` → codePath migration
