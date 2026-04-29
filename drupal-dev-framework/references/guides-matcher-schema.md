# Guides Matcher Schema v1.0

**Introduced:** drupal-dev-framework v4.3.0
**Owner:** `agents/guides-matcher.md`
**Consumers:** `commands/validate-guides.md` (validation mode), `commands/implement.md` (plan mode)

The `guides-matcher` agent reads the cached `dev-guides-navigator` catalog and the files (changed or planned) and returns the catalog slugs Claude judges relevant to the work. The agent is read-only — Read + Glob only. The catalog itself is the taxonomy; this agent does NOT carry a parallel hardcoded map.

## Why a subagent

- Bounded inputs (catalog ~10–20KB JSON + a list of paths)
- Bounded output (JSON list of slugs)
- No persistent state, no side effects
- Two callers want the exact same matching judgment in different modes — DRY
- Haiku is sufficient: structured catalog + clear file paths + small reasoning surface

## Input

Callers spawn the agent with this prompt structure (pseudo-shape; real prompt is prose with these elements):

```json
{
  "mode": "plan" | "validation",
  "catalog_path": "/abs/path/to/dev-guides-cache.json",
  "files": [
    "/abs/path/to/codePath/src/Form/SettingsForm.php",
    "/abs/path/to/codePath/my_module.services.yml"
  ],
  "context_excerpts": [
    {"source": "architecture.md#components", "text": "..."},
    {"source": "implementation.md#files-created-modified", "text": "..."}
  ],
  "already_cited": ["drupal/forms/config-forms"]
}
```

- `mode` — `plan` is run BEFORE writing code (input: planned components from architecture.md). `validation` is run AFTER (input: actually-changed files).
- `catalog_path` — absolute path to the dev-guides-navigator cache. The agent reads this with `Read`, parses, treats as the only source of truth for valid slugs.
- `files[]` — absolute paths. Empty array is valid (returns empty `matched_guides[]` with `unmatched_files: []`).
- `context_excerpts[]` — optional supporting prose. Helps the agent disambiguate when a file path alone is ambiguous (e.g., `Foo.php` could be many things; the architecture.md excerpt clarifies).
- `already_cited[]` — slugs the gate already found in artifacts. **Informational only**; the agent does NOT filter against this and MUST return its full honest match list. The caller (validate-guides) computes `domain_coverage_gaps` by comparing the agent's matches against `already_cited[]`.

## Output

```json
{
  "schema_version": "1.0",
  "mode": "validation",
  "catalog_size": 135,
  "files_evaluated": 12,
  "matched_guides": [
    {
      "slug": "drupal/forms/config-forms",
      "reason": "src/Form/SettingsForm.php is a ConfigFormBase subclass",
      "confidence": "high",
      "triggered_by": ["src/Form/SettingsForm.php"]
    },
    {
      "slug": "drupal/services/dependency-injection",
      "reason": "new service definition in my_module.services.yml requires DI patterns",
      "confidence": "high",
      "triggered_by": ["my_module.services.yml"]
    }
  ],
  "unmatched_files": [
    "tests/fixtures/dummy.txt"
  ],
  "warnings": []
}
```

### Field contracts

| Field | Type | Notes |
|---|---|---|
| `schema_version` | string | `"1.0"` at v4.3.0; consumers match on major |
| `mode` | enum | `"plan"` \| `"validation"` — echoes input |
| `catalog_size` | integer | Number of guides parsed from the cache (sanity check; consumers can flag if 0) |
| `files_evaluated` | integer | Length of input `files[]` |
| `matched_guides[]` | array | Possibly empty; never absent |
| `matched_guides[].slug` | string | MUST exist in the input catalog. Agent does NOT invent slugs |
| `matched_guides[].reason` | string | One-line rationale referencing file path or excerpt |
| `matched_guides[].confidence` | enum | `"high"` \| `"medium"` \| `"low"`. Consumers may filter on this |
| `matched_guides[].triggered_by[]` | array of string | Subset of input `files[]` that drove the match |
| `unmatched_files[]` | array | Files the agent could not place against any catalog entry. Often noise (test fixtures, deps); occasionally signal (genuinely uncatalogued domain) |
| `warnings[]` | array of string | Defensive non-fatal observations: catalog stale, ambiguous file, malformed input |

### Invariants

1. `schema_version: "1.0"` always present.
2. Every `slug` in `matched_guides[]` MUST appear in the input catalog. No invention.
3. `matched_guides[]` is sorted by `confidence` descending, then by `slug` ascending.
4. `unmatched_files[]` and `matched_guides[]` together cover every entry in input `files[]` (a file can appear in multiple `triggered_by[]` entries).
5. Output is the agent's final message — pure JSON, no commentary, no code fences in the JSON itself.

## Caller contracts

### `validate-guides` (validation mode)

Inputs `files[]` from the deduped union of:
- Files Claude edited or wrote in the current session against `codePath`
- `implementation.md` "Files Created/Modified" parsed paths
- `git status --porcelain` + `git diff --name-only HEAD` (when codePath is git)

Inputs `already_cited[]` from artifact citation extraction (Step 4 of validate-guides).

Maps the agent's `matched_guides[].slug` to a coverage check via prefix-or-equality match against `guides_cited[]`. Slugs in the agent output but missing from citations → `domain_coverage_gaps[]`. Non-empty gap demotes `pass` → `warning` (or `fail` under `--hard-block` / `--strict`).

### `/implement` Step 3 preflight (plan mode)

Inputs `files[]` parsed from architecture.md sections (`## Components`, `## Files Created/Modified`, `## Files to Create`). The keyword-based `dev-guides-detect.sh` continues to run first for fast lexical matches; the agent runs after to add component-specific guides the keyword grep misses.

Hands the agent's `matched_guides[].slug` list to the dev-guides-navigator preload pass. User confirms via the existing `[c]/[a]/[n]` preflight prompt — agent output is additive to the auto-load list, not a replacement.

## Failure modes

| Symptom | Behavior |
|---|---|
| Catalog cache missing | Agent emits `warnings: ["catalog_cache_missing"]`, returns empty `matched_guides[]`. Caller falls back to keyword detect alone (plan mode) or skips inference (validation mode) |
| Catalog cache empty / 0 entries | Same as above with `warnings: ["catalog_size_zero"]` |
| Catalog cache stale (caller-side detection) | Caller (validate-guides Step 5b, /implement Step 3 Pass B) `stat`s the cache mtime and appends `warnings: ["catalog_cache_stale"]` to the envelope when older than 30 days. The agent itself does not detect staleness (Read + Glob only). Informational — does not block matching. Suggested user action: `/dev-guides-navigator --refresh` |
| Input `files[]` empty | Returns `matched_guides: [], unmatched_files: []`. No warning |
| Malformed input JSON | Agent returns `warnings: ["malformed_input"]`, empty matches |

## Versioning

- Additive fields → no major bump
- New `mode` values → additive
- New `confidence` values → major bump
- Removing fields or changing semantics → major bump
