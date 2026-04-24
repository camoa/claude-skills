---
name: screenshot-store-reader
description: Use when a framework command needs to inspect the project's screenshot store — baselines and parity references used by visual-regression and visual-parity validation. Reads the store defensively via scripts/screenshot-store-read.sh and returns structured JSON. Never blocks on malformed input.
version: 1.0.0
user-invocable: false
model: haiku
allowed-tools: Bash
---

# Screenshot Store Reader

Thin wrapper around `${CLAUDE_PLUGIN_ROOT}/scripts/screenshot-store-read.sh`. The script inspects `.screenshots/` under a memory project folder and emits structured JSON per `references/screenshot-store-schema.md` v1.0. This skill gives the reader a Skill-tool-callable name and documents the invocation contract.

## Contract

**Input:** one argument — absolute path to a memory project folder (the one that may contain `.screenshots/`).

**Output:** single JSON object to stdout per `references/screenshot-store-schema.md` §7. Exit code always 0 except for unrecoverable read failures (permission denied, IO error).

Fields:
- `schema_version` — JSON string, currently `"1.0"`
- `project_path` — absolute path passed in
- `store_path` — absolute path to the store (`<project>/.screenshots`); present whether or not it exists
- `store_exists` — boolean
- `components[]` — per-component array of `{name, viewports[]}` where each viewport has `{viewport, has_current, has_previous, meta, previous_meta, warnings}`
- `warnings[]` — store-level warnings

## Defensive posture (never throws)

| Input state | Warning code | Level |
|---|---|---|
| Project folder missing | `error` | store |
| `.screenshots/` does not exist | `store_missing` | store |
| `<viewport>.png` exists without `.meta.json` | `component_missing_meta` | viewport |
| `.meta.json` invalid JSON or missing required v1.0 fields | `meta_schema_mismatch` | viewport |
| `.meta.json.sha256` differs from actual PNG hash | `hash_mismatch` | viewport |
| `<viewport>.meta.json` exists without PNG sibling | `orphan_meta` | store |
| Unrecoverable read failure (permission, IO) | `error` | store |

## Invocation

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/screenshot-store-read.sh" "/abs/path/to/memory/project"
```

Parse with `jq`. Examples:

```bash
OUT=$("${CLAUDE_PLUGIN_ROOT}/scripts/screenshot-store-read.sh" "$PROJECT_DIR")
STORE_EXISTS=$(jq -r '.store_exists' <<<"$OUT")
COMPONENT_COUNT=$(jq '.components | length' <<<"$OUT")
# Has a specific baseline?
HAS_HERO=$(jq -e '.components[] | select(.name == "home-hero") | .viewports[] | select(.viewport == "1920x1080" and .has_current)' <<<"$OUT" >/dev/null && echo true || echo false)
# Any warnings at the store level?
jq -e '.warnings | length > 0' <<<"$OUT" >/dev/null && echo "store warnings present"
# Get a specific baseline's prior_hash (for integrity check)
PRIOR=$(jq -r '.components[] | select(.name=="home-hero") | .viewports[] | select(.viewport=="1920x1080") | .meta.prior_hash // "none"' <<<"$OUT")
```

## `.previous` siblings

Every baseline OR parity reference MAY have an optional `.previous.png` + `.previous.meta.json` sibling (1-deep history). The reader surfaces these:
- `has_previous: true|false` per viewport
- `previous_meta: { ... }` contains the rotated meta exactly as it was when current, OR `null` if no `.previous` exists

Consumers wanting to verify the rotation chain can cross-reference `meta.prior_hash` against `previous_meta.sha256`.

**Validation asymmetry (v1):** the reader performs full schema validation + hash verification on the CURRENT meta but NOT on `.previous.meta.json`. Rationale: `.previous` is opportunistic historical state (may be edited or deleted by the user without concern; not a source of truth). If a consumer needs full integrity on the previous tier, it should re-invoke the reader's validation logic OR treat `previous_meta` as best-effort. v2 candidate: symmetric validation if real use-cases surface.

## Consumers (v3.13.0+)

- `/drupal-dev-framework:validate-visual-regression` — reads current baseline; checks `has_current` before running; reads `meta.sha256` for integrity
- `/drupal-dev-framework:validate-visual-parity` — reads imported parity references; checks `source` field for provenance
- `/drupal-dev-framework:validate-all` — enumerates components for visual coverage summary
- `/drupal-dev-framework:complete` — (future v2) reads for pending-update surfacing when batch approval lands

Future consumers needing screenshot-store data should call this skill rather than parsing the store directly.

## Do NOT

- Do not write to the store from this skill. Reading only. Writes happen via `scripts/screenshot-store-write.sh` invoked directly from visual gate commands
- Do not treat non-empty `warnings[]` as a blocking error — warnings are observations
- Do not duplicate the parsing logic elsewhere. Call this skill or the script
- Do not assume any component or viewport exists. Always guard on `store_exists`, then filter `components[]`

## See also

- `${CLAUDE_PLUGIN_ROOT}/scripts/screenshot-store-read.sh` — the reader
- `${CLAUDE_PLUGIN_ROOT}/scripts/screenshot-store-write.sh` — the writer (invoked directly by visual gate commands, not wrapped as a skill in v1)
- `references/screenshot-store-schema.md` — canonical directory + `.meta.json` v1.0 schema, warning codes
- `references/validation-gate-result.md` — the result envelope visual gates emit
- `alignment-reader` skill (v1.0.0) — same design pattern
- `project-state-reader` skill (v1.0.0) — same design pattern
- `task-frontmatter-reader` skill (v2.0.0) — same design pattern
