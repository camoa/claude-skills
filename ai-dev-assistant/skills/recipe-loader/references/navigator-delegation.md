# Navigator Delegation

How `recipe-loader` reaches the `dev-guides-navigator` plugin (v0.8.0+) — and the exact line/cache
grammar it parses. **Fetching is the navigator's. Matching is recipe-loader's.**

## What recipe-loader delegates vs. does itself
| Concern | Owner | How |
|---|---|---|
| Refresh recipe index (two-hash) | **navigator** | invoke the navigator skill (recipe-search) |
| Download a recipe body (download-once) | **navigator** | invoke the navigator skill (recipe-search) |
| Residual guide-search (match + fetch a guide) | **navigator** | invoke the navigator skill (guide-search) |
| Read the index for 0..N matching | recipe-loader | `jq -r '.content'` on the **shared store** `indexes/agentic-recipes.json` |
| Read a fetched recipe body's routing block + `requires_*` | recipe-loader | `cat` the **shared blob** `blobs/<sha8>` (content-addressed by the index-line sha8) |
| Decompose aspects, match, rank, assemble map | recipe-loader | judgment |

**Never** `curl`, **never** `WebFetch`, **never** re-implement the cache freshness logic, **never**
call or extend `guides-matcher`.

## The shared store (a cross-plugin contract)
recipe-loader reads the **project-independent shared content store** the navigator maintains —
NOT a per-project cwd-derived cache. Root: `$DEV_GUIDES_STORE_DIR` (default
`~/.claude/dev-guides-store`). Documented in the navigator's `references/store-contract.md`. There is
**one global catalog** — no `$PWD`/codePath keying — so recipe-loader can never resolve the *caller's*
project context by accident (the GAP-B bug). The old per-project `dev-guides-recipes-cache.json` shim
is no longer read by recipe-loader (the navigator still rebuilds it for other consumers, e.g.
`work-order-compiler`).

```
~/.claude/dev-guides-store/
  indexes/agentic-recipes.json   # { hash, fetched_at, content:"<full agentic-recipes.txt>" }
  blobs/<sha8>                    # one recipe body (full RECIPE.md), keyed by the index-line sha8
```
- `indexes/agentic-recipes.json` `.content` — the recipe **index** recipe-loader scans for 0..N
  matches. Refreshed by the navigator's step-2 revalidate, gated by `agentic-recipes.hash`.
- `blobs/<sha8>` — one recipe body, **content-addressed** by the index line's `(sha:XXXXXXXX)`. A
  present blob is the body for that exact upstream version (no index↔body drift); a miss means the
  navigator hasn't fetched it yet. recipe-loader validates `<sha8>` is exactly 8 lowercase-hex before
  using it as a filename (traversal defense).

## Index-line grammar
Lines are grouped under `## <Domain>` headings:
```
- <name> [<capability>] (sha:XXXXXXXX): <one-line when-to-use> — <site-url>
```
- **Match on `[<capability>]` + when-to-use** (the semantic key) — not on `<name>`.
- `<name>` is the `recipes.<name>` cache key (used to read the body).
- `## <Domain>` is generic (concrete domain headers appear at runtime; the grammar is open) — **never hardcode a domain.**

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
  residual guide-search. (A recipe with no `requires_*` frontmatter falls here.)

## Invocation pattern (concrete forms)
recipe-loader uses the **Skill** tool to invoke `dev-guides-navigator`, then **Bash**/`jq` to read
the cache the navigator maintains. It does not assume the navigator returns structured data — it
reads the cache (the contract above). Concrete invocations (free-form intent prompts the navigator acts on):
- **Refresh the recipe index** (SKILL.md step 2): invoke `dev-guides-navigator` → *"Recipe-search:
  ensure the agentic-recipes index cache is fresh (compare `agentic-recipes.hash`, refetch only on
  change). Do NOT fetch any recipe body."*
- **Fetch a matched body** (step 5): invoke `dev-guides-navigator` → *"Recipe-search: fetch the body
  for recipe `<name>` (download-once, sha-gated). Do not fetch others."* — that populates the shared
  blob store; then read it with `cat "$STORE_DIR/blobs/<sha8>"` (the validated 8-hex index-line sha).
- **Residual guide-search** (step 6): invoke `dev-guides-navigator` → *"Guide-search for: <aspect>.
  Return the atomic guide(s) for this concern."*
If the navigator skill is unavailable, see `degrade-paths.md`.
