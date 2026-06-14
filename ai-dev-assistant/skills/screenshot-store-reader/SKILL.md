---
name: screenshot-store-reader
description: Use when a framework command needs to inspect the project's visual-regression baseline store — the codePath-native tests/visual/ snapshot tree. Reads the store defensively via scripts/screenshot-store-read.sh and returns structured JSON. Never blocks on malformed input.
version: 1.2.0
user-invocable: false
model: inherit
allowed-tools: Bash
disallowed-tools: Write, Edit
---

# Screenshot Store Reader

Thin wrapper around `${CLAUDE_PLUGIN_ROOT}/scripts/screenshot-store-read.sh`.
The script inspects the **codePath-native** visual-regression store —
`<codePath>/tests/visual/*.spec.ts-snapshots/` — and emits structured JSON per
`references/screenshot-store-schema.md` v1.0. This skill gives the reader a
Skill-tool-callable name and documents the invocation contract.

The store moved to codePath in v4.13.0 (Task C). Baselines are committed
Playwright snapshots; `.meta.json` provenance sidecars travel with each PNG.

## Contract

**Input:** the absolute `codePath` (the project root). Optional
`--legacy-path <memory_project_folder>` adds a `legacy_store_present` boolean
when a v3.13.0 `.screenshots/` directory still exists there.

**Output:** single JSON object to stdout per `references/screenshot-store-schema.md`. Exit code always 0 except for unrecoverable read failures.

Fields:
- `schema_version` — JSON string, currently `"1.0"`
- `project_path` — the codePath passed in
- `store_path` — `<codePath>/tests/visual`; present whether or not it exists
- `store_exists` — boolean (`tests/visual/` present)
- `legacy_store_present` — boolean; emitted ONLY when `--legacy-path` is given
- `components[]` — per-surface array of `{name, viewports[]}` where each
  viewport has `{viewport, has_current, has_previous, meta, previous_meta, warnings}`
- `warnings[]` — store-level warnings

`name` is the spec-file stem (the surface `id`). `viewport` is the viewport
**name** (`desktop`), parsed from the baseline filename's `visual-chromium-<name>`
project segment — not `WIDTHxHEIGHT`.

## Defensive posture (never throws)

| Input state | Warning code | Level |
|---|---|---|
| codePath missing | `error` | store |
| `tests/visual/` does not exist | `store_missing` | store |
| baseline PNG exists without `.meta.json` | `component_missing_meta` | viewport |
| `.meta.json` invalid JSON or missing required v1.0 fields | `meta_schema_mismatch` | viewport |
| `.meta.json.sha256` differs from actual PNG hash | `hash_mismatch` | viewport |
| `.meta.json` exists without a PNG sibling | `orphan_meta` | store |
| Unrecoverable read failure (permission, IO) | `error` | store |

## Invocation

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/screenshot-store-read.sh" "/abs/path/to/codePath"
"${CLAUDE_PLUGIN_ROOT}/scripts/screenshot-store-read.sh" "/abs/codePath" --legacy-path "/abs/memory/project"
```

Parse with `jq`. Examples:

```bash
OUT=$("${CLAUDE_PLUGIN_ROOT}/scripts/screenshot-store-read.sh" "$CODE_PATH")
STORE_EXISTS=$(jq -r '.store_exists' <<<"$OUT")
SURFACE_COUNT=$(jq '.components | length' <<<"$OUT")
# Has a specific baseline?
HAS_HERO=$(jq -e '.components[] | select(.name == "home-hero") | .viewports[] | select(.viewport == "desktop" and .has_current)' <<<"$OUT" >/dev/null && echo true || echo false)
# Surfaces with a missing-meta or hash warning:
jq -r '.components[] | .name as $n | .viewports[] | select((.warnings|length)>0) | "\($n)/\(.viewport)"' <<<"$OUT"
```

## codePath-native layout — no `.previous` tier

In the v3.13.0 memory-project store, an intentional change rotated the prior
baseline to `.previous.png`. The codePath-native store has **no `.previous`
files** — git history IS the baseline history, and Playwright's
`--update-snapshots` overwrites in place. The reader keeps `has_previous` and
`previous_meta` in the output for contract-compatibility, but they are always
`false` / `null`. The prior baseline's hash is still carried in the current
sidecar's `prior_hash` field.

## Consumers (v4.13.0+)

- `/ai-dev-assistant:validate-visual-regression` — checks `has_current` /
  warnings before running; reports missing baselines as a loud failure
- `/ai-dev-assistant:validate-all` — enumerates surfaces for the
  visual-regression coverage check; reads `legacy_store_present` to surface
  migration status
- `/ai-dev-assistant:setup-visual-regression` — checks which surfaces
  already have baselines before the bootstrap prompt

Future consumers needing screenshot-store data should call this skill rather
than parsing the store directly.

## Do NOT

- Do not write to the store from this skill. Reading only. Baseline PNGs are
  written by Playwright (`--update-snapshots`); provenance sidecars by
  `scripts/screenshot-store-write.sh write-baseline-codepath`.
- Do not treat non-empty `warnings[]` as a blocking error — warnings are
  observations.
- Do not duplicate the parsing logic elsewhere. Call this skill or the script.
- Do not assume any surface or viewport exists. Guard on `store_exists`, then
  filter `components[]`.

## See also

- `${CLAUDE_PLUGIN_ROOT}/scripts/screenshot-store-read.sh` — the reader
- `${CLAUDE_PLUGIN_ROOT}/scripts/screenshot-store-write.sh` — the writer
  (`write-baseline-codepath` for sidecars; legacy `write-baseline` /
  `write-parity-reference` retained for migration + parity)
- `references/screenshot-store-schema.md` — canonical layout + `.meta.json` v1.0 schema, warning codes
- `references/validation-gate-result.md` — the result envelope visual gates emit
- `alignment-reader` / `project-state-reader` skills — same design pattern
