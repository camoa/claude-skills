# Guides Matcher Schema v1.1

**Introduced:** ai-dev-assistant v4.3.0 (v1.0); v4.10.0 adds `prose` mode (v1.1, additive).
**Owner:** `agents/guides-matcher.md`
**Consumers:** `commands/validate-guides.md` (validation mode), `commands/implement.md` (plan mode + prose mode), `commands/research.md` + `commands/design.md` (prose mode)

The `guides-matcher` agent reads the cached `dev-guides-navigator` catalog and either a list of files (changed or planned) or phase-artifact prose, and returns the catalog slugs Claude judges relevant to the work. The agent is read-only — Read + Glob only. The catalog itself is the taxonomy; this agent does NOT carry a parallel hardcoded map.

## The catalog cache

`catalog_path` points at the dev-guides catalog index. The caller resolves it to the shared store's `indexes/llms.json` (canonical — see the navigator's `references/store-contract.md`), honouring `DEV_GUIDES_STORE_DIR`, with the legacy `dev-guides-cache.json` compat shim as a transitional fallback. Either way it is a **JSON object** with the schema `{ "hash", "fetched_at", "content" }` — the same shape. The `.content` field holds the **full `llms.txt` markdown** — a topic table whose lines look like:

```
- [Modern CSS](https://camoa.github.io/dev-guides/css/modern/): 15 guides — CSS — grid, flexbox, custom properties…
```

The agent parses topic entries out of that markdown: `slug` is the URL path after `dev-guides/` with the trailing slash stripped (e.g. `css/modern`), plus the bracketed title and the trailing description. **There is no slug array** — earlier drafts of this schema implied "parse JSON, extract slugs," which never matched the real on-disk shape. A cache file with no `.content` key is treated as missing.

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
  "mode": "plan" | "validation" | "prose",
  "catalog_path": "/abs/path/to/dev-guides-cache.json",
  "files": [
    "/abs/path/to/codePath/src/Form/SettingsForm.php",
    "/abs/path/to/codePath/src/Service/DataService.php"
  ],
  "context_excerpts": [
    {"source": "architecture.md#components", "text": "..."},
    {"source": "implementation.md#files-created-modified", "text": "..."}
  ],
  "artifact_excerpts": [
    {"source": "alignment.md", "text": "Goal: we need a listing page for content…"}
  ],
  "candidate_slugs": ["<framework>/views"],
  "routing_hints": [
    {"pattern": "src/handlers/**", "role": "routing"},
    {"pattern": "*.tmpl", "role": "theming"}
  ],
  "already_cited": ["<framework>/forms/config-forms"]
}
```

- `mode` — `plan` is run BEFORE writing code (input: planned components from architecture.md). `validation` is run AFTER (input: actually-changed files). `prose` (v1.1+) is run at a phase-command preflight (input: phase-artifact prose + a Stage-1 candidate seed).
- `catalog_path` — absolute path to the dev-guides-navigator cache (a `{hash, fetched_at, content}` JSON object — see "The catalog cache" above). The agent reads this with `Read`, parses the topic table out of `.content`, treats it as the only source of truth for valid slugs.
- `files[]` — absolute paths. Used by `plan` / `validation`. Empty array is valid (returns empty `matched_guides[]` with `unmatched_files: []`).
- `context_excerpts[]` — optional supporting prose for `plan` / `validation`. Helps the agent disambiguate when a file path alone is ambiguous (e.g., `Foo.php` could be many things; the architecture.md excerpt clarifies).
- `artifact_excerpts[]` — **`prose` mode only.** Objects `{source, text}` carrying phase-artifact prose (`task.md` Goal, `alignment.md`, `research.md`, `architecture.md`). This is the text the agent semantically matches against the catalog.
- `candidate_slugs[]` — **`prose` mode only.** The catalog slugs `dev-guides-detect.sh` (Stage 1) already matched lexically. The agent treats these as a **floor** — every entry is echoed in `matched_guides[]` (re-ranked/re-justified, never dropped). The agent's job is to ADD semantic/synonym matches Stage 1's lexical scan missed.
- `routing_hints[]` — optional; `plan` / `validation` modes. Objects `{pattern, role}` the caller reconstructs from the resolved process recipe (the recipe's `## Routing hints` declaration). They carry the framework-specific file patterns (a framework's bootstrap-file suffix, its theme-file suffix, its template suffixes) the agent no longer hardcodes — the recipe is the source of truth for its own file layout. Absent ⇒ the agent's neutral role buckets fire alone (generic conventions still match; framework-specific config/template suffixes simply fall to `unmatched_files[]`). Because the gate is a soft-nudge advisory, an absent hint set degrades a suggestion, never a verdict.
- `already_cited[]` — slugs the gate already found in artifacts (`validation` mode). **Informational only**; the agent does NOT filter against this and MUST return its full honest match list. The caller (validate-guides) computes `domain_coverage_gaps` by comparing the agent's matches against `already_cited[]`.

## Output

```json
{
  "schema_version": "1.1",
  "mode": "validation",
  "catalog_size": 135,
  "files_evaluated": 12,
  "matched_guides": [
    {
      "slug": "<framework>/forms/config-forms",
      "reason": "src/Form/SettingsForm.php is a config-form subclass",
      "confidence": "high",
      "triggered_by": ["src/Form/SettingsForm.php"]
    },
    {
      "slug": "<framework>/services/dependency-injection",
      "reason": "new service definition in src/Service/DataService.php requires DI patterns",
      "confidence": "high",
      "triggered_by": ["src/Service/DataService.php"]
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
| `schema_version` | string | `"1.1"` at v4.10.0; consumers match on major |
| `mode` | enum | `"plan"` \| `"validation"` \| `"prose"` — echoes input |
| `catalog_size` | integer | Number of topic entries parsed from `.content` (sanity check; consumers can flag if 0) |
| `files_evaluated` | integer | Length of input `files[]`; `0` in `prose` mode |
| `matched_guides[]` | array | Possibly empty; never absent |
| `matched_guides[].slug` | string | MUST exist in the input catalog. Agent does NOT invent slugs (exception: a `prose`-mode `candidate_slugs[]` seed is echoed even if absent — see Invariants). Slug format follows the catalog's own taxonomy (e.g. `<framework>/<category>/<topic>`). |
| `matched_guides[].reason` | string | One-line rationale referencing file path or excerpt |
| `matched_guides[].confidence` | enum | `"high"` \| `"medium"` \| `"low"`. Consumers may filter on this |
| `matched_guides[].triggered_by[]` | array of string | `plan`/`validation`: subset of input `files[]` that drove the match. `prose`: excerpt `source` label(s) or the inferring term |
| `unmatched_files[]` | array | Files the agent could not place against any catalog entry. Often noise (test fixtures, deps); occasionally signal (genuinely uncatalogued domain). Always `[]` in `prose` mode |
| `warnings[]` | array of string | Defensive non-fatal observations: catalog stale, ambiguous file, malformed input, `seed_slug_not_in_catalog` |

### Invariants

1. `schema_version` is present and is `"1.1"` (consumers match on major — `"1.0"` consumers are unaffected).
2. Every `slug` in `matched_guides[]` MUST appear in the input catalog. No invention. **Exception:** in `prose` mode every `candidate_slugs[]` seed is echoed even when absent from the catalog, with a `seed_slug_not_in_catalog: <slug>` warning (Stage 1 and the catalog may be briefly out of sync).
3. `matched_guides[]` is sorted by `confidence` descending, then by `slug` ascending.
4. `plan`/`validation`: `unmatched_files[]` and `matched_guides[]` together cover every entry in input `files[]` (a file can appear in multiple `triggered_by[]` entries). `prose`: `unmatched_files[]` is `[]`.
5. `prose` mode: every `candidate_slugs[]` entry appears in `matched_guides[]` (the Stage-1 floor is never narrowed).
6. Output is the agent's final message — pure JSON, no commentary, no code fences in the JSON itself.

## Caller contracts

### `validate-guides` (validation mode)

Inputs `files[]` from the deduped union of:
- Files Claude edited or wrote in the current session against `codePath`
- `implementation.md` "Files Created/Modified" parsed paths
- `git status --porcelain` + `git diff --name-only HEAD` (when codePath is git)

Inputs `already_cited[]` from artifact citation extraction (Step 4 of validate-guides).

Maps the agent's `matched_guides[].slug` to a coverage check via prefix-or-equality match against `guides_cited[]`. Slugs in the agent output but missing from citations → `domain_coverage_gaps[]`. Non-empty gap demotes `pass` → `warning` (or `fail` under `--hard-block` / `--strict`).

### `/implement` Step 3 preflight (plan mode)

Inputs `files[]` parsed from architecture.md sections (`## Components`, `## Files Created/Modified`, `## Files to Create`). `dev-guides-detect.sh` (Stage 1) runs first for the methodology floor + lexical catalog candidates; the agent runs after to add component-specific guides the file-path heuristics surface.

Hands the agent's `matched_guides[].slug` list to the dev-guides-navigator preload pass. User confirms via the existing `[c]/[a]/[n]` preflight prompt — agent output is additive to the auto-load list, not a replacement.

### `/research`, `/design`, `/implement` preflight (prose mode, v1.1+)

Stage 1 (`dev-guides-detect.sh --phase <p>`) runs first and emits `methodology_floor[]` + `catalog_candidates[]`. The phase command then invokes the agent in `prose` mode with `artifact_excerpts[]` (phase-artifact prose — see `commands/*.md` for the per-phase excerpt set) and `candidate_slugs[]` = the Stage-1 `catalog_candidates[].slug` list.

The agent echoes the seed (floor) and adds semantic/synonym matches. The command unions the agent's `matched_guides[].slug` into the preflight's "Domain guides matched" group; the `methodology_floor[]` is shown separately as "Methodology (always)". `[c]/[a]/[n]` semantics unchanged. The agent can only add to or re-rank the seed — never zero it out, preserving the anti-bypass floor.

## Failure modes

| Symptom | Behavior |
|---|---|
| Catalog cache missing OR no `.content` key | Agent emits `warnings: ["catalog_cache_missing"]`, returns empty `matched_guides[]` (in `prose` mode the `candidate_slugs[]` floor is still echoed). Caller falls back to Stage-1 output alone |
| `.content` present but 0 parseable topic entries | Same as above with `warnings: ["catalog_size_zero"]` |
| Catalog cache stale (caller-side detection) | Caller (validate-guides Step 5b, /implement Step 3 Pass B) `stat`s the cache mtime and appends `warnings: ["catalog_cache_stale"]` to the envelope when older than 30 days. The agent itself does not detect staleness (Read + Glob only). Informational — does not block matching. Suggested user action: `/dev-guides-navigator --refresh` |
| Input `files[]` empty (`plan`/`validation`) | Returns `matched_guides: [], unmatched_files: []`. No warning |
| `prose` mode seed slug not in catalog | Seed slug echoed in `matched_guides[]`; `warnings: ["seed_slug_not_in_catalog: <slug>"]` |
| Malformed input JSON | Agent returns `warnings: ["malformed_input"]`, empty matches |

## Versioning

- Additive fields → no major bump
- New `mode` values → additive (v1.1 adds `prose` this way)
- New `confidence` values → major bump
- Removing fields or changing semantics → major bump
