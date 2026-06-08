# Navigator Delegation

How `recipe-loader` reaches the `dev-guides-navigator` plugin (v0.8.0+) — and the exact line/cache
grammar it parses. **Fetching is the navigator's. Matching is recipe-loader's.**

## What recipe-loader delegates vs. does itself
| Concern | Owner | How |
|---|---|---|
| Refresh recipe index (two-hash) | **navigator** | invoke the navigator skill (recipe-search) |
| Download a recipe body (download-once) | **navigator** | invoke the navigator skill (recipe-search) |
| Residual guide-search (match + fetch a guide) | **navigator** | invoke the navigator skill (guide-search) |
| Read the cached index for 0..N matching | recipe-loader | `jq -r '.index.content'` on the cache |
| Read a cached recipe body's routing block + `requires_*` | recipe-loader | `jq -r '.recipes[$n].content'` |
| Decompose aspects, match, rank, assemble map | recipe-loader | judgment |

**Never** `curl`, **never** `WebFetch`, **never** re-implement the cache freshness logic, **never**
call or extend `guides-matcher`.

## The recipes cache (a cross-plugin contract)
File: `~/.claude/projects/<dasherized-cwd>/memory/dev-guides-recipes-cache.json`
(`<dasherized-cwd>` = `$PWD` with every non-alphanumeric char → `-`). Documented in the navigator's
`references/cache-format.md`. **recipe-loader uses the cwd-derived path ONLY — it never globs to
another project's cache** (that would load the wrong / attacker-seeded catalog; see `degrade-paths.md`).
The glob fallback documented in `cache-format.md` is the *navigator's* internal lookup, not a
recipe-loader instruction.

```json
{
  "index":   { "hash": "...", "fetched_at": "...", "content": "<full agentic-recipes.txt>" },
  "recipes": { "<name>": { "sha": "...", "fetched_at": "...", "content": "<full RECIPE.md>" } }
}
```
- `index.content` — the recipe **index** recipe-loader scans for 0..N matches. Gated by
  `agentic-recipes.hash` (the navigator's job).
- `recipes.<name>.content` — one recipe body, gated by that recipe's per-line `(sha:XXXXXXXX)`
  (checkable without a fetch).

## Index-line grammar
Lines are grouped under `## <Domain>` headings:
```
- <name> [<capability>] (sha:XXXXXXXX): <one-line when-to-use> — <site-url>
```
- **Match on `[<capability>]` + when-to-use** (the semantic key) — not on `<name>`.
- `<name>` is the `recipes.<name>` cache key (used to read the body).
- `## <Domain>` is generic (`## Drupal` exists today; the grammar is open) — **never hardcode a domain.**

## Recipe body: routing block + optional machine deps
The body's frontmatter has two tiers, separated by a seam comment:
```yaml
---
# Routing block — an orchestrator reads to here and decides.
name: <name>
capability: <capability>
description: <when-to-use, richer than the index line>
# Metadata — read only after a match.
recipe_schema_version: ...
version: ...
# requires_guides: [...]   ← OPTIONAL; may be absent (see degrade-paths.md)
# requires_plays:  [...]   ← OPTIONAL
---
```
- Read `requires_guides` / `requires_plays` if present → the recipe's declared guides/plays.
- If **absent** → `has_machine_deps:false`; do not parse the prose `## References` table; fall to
  residual guide-search. (The shipped `responsive_image_wiring` recipe is this case.)

## Invocation pattern (concrete forms)
recipe-loader uses the **Skill** tool to invoke `dev-guides-navigator`, then **Bash**/`jq` to read
the cache the navigator maintains. It does not assume the navigator returns structured data — it
reads the cache (the contract above). Concrete invocations (free-form intent prompts the navigator acts on):
- **Refresh the recipe index** (SKILL.md step 2): invoke `dev-guides-navigator` → *"Recipe-search:
  ensure the agentic-recipes index cache is fresh (compare `agentic-recipes.hash`, refetch only on
  change). Do NOT fetch any recipe body."*
- **Fetch a matched body** (step 5): invoke `dev-guides-navigator` → *"Recipe-search: fetch the body
  for recipe `<name>` (download-once, sha-gated). Do not fetch others."* then read it from cache with
  `jq -r --arg n "$N" '.recipes[$n].content'`.
- **Residual guide-search** (step 6): invoke `dev-guides-navigator` → *"Guide-search for: <aspect>.
  Return the atomic guide(s) for this concern."*
If the navigator skill is unavailable, see `degrade-paths.md`.
