# Cache Format

> **TRANSITIONAL — COMPAT SHIM ONLY.** The canonical store and lockfile contract is
> now `store-contract.md`. Both per-project cache files below are compat shims; they
> will be retired after `ai-dev-assistant` cuts over to reading the shared store
> (`~/.claude/dev-guides-store/`) and the per-project lockfile
> (`dev-guides.lock.json`) directly. Do not build new consumers against these paths.

This file documents the legacy per-project cache paths. `ai-dev-assistant` still
reads `dev-guides-cache.json` directly at the dashed-cwd path, so the navigator
continues to write it as a shim (see the Compat Shim section in `store-contract.md`).
The recipes cache (`dev-guides-recipes-cache.json`) is also written as a shim, rebuilt
from the shared store by the kernel's `legacy-recipes-shim` so the `recipe-loader`
consumer keeps working.

There are **two sibling cache files**, same directory, same path derivation:

| File | Catalog | Status | Schema |
|------|---------|--------|--------|
| `dev-guides-cache.json` | guides (`llms.txt`) | **COMPAT SHIM** — navigator still writes it after revalidating the `llms` index; shape preserved for `ai-dev-assistant` | `{ hash, fetched_at, content }` |
| `dev-guides-recipes-cache.json` | agentic recipes (`agentic-recipes.txt`) | **COMPAT SHIM** — rebuilt by the kernel's `legacy-recipes-shim` from the shared store (index + lockfile + blobs) after each recipe-search revalidate and body fetch; shape preserved for the `recipe-loader` consumer in `ai-dev-assistant` | `{ index, recipes }` (below) |

The two files are independent. Recipe search added the recipes cache; it does **not**
change the guides-cache schema. The recipe bodies live in the shared blob store
(`~/.claude/dev-guides-store/blobs/`); this cache file is a rebuilt projection of the
store into the legacy shape, kept until `recipe-loader` cuts over to reading the
store/lockfile directly.

## Location

```
~/.claude/projects/<dasherized-cwd>/memory/dev-guides-cache.json
```

`<dasherized-cwd>` is the **absolute current working directory** with every
character that is not a letter or digit replaced by a single hyphen `-`
(including the leading `/`). It is not an md5 hash.

```bash
# Exact derivation:
DASHED=$(printf '%s' "$PWD" | sed 's/[^a-zA-Z0-9]/-/g')
CACHE_FILE="$HOME/.claude/projects/${DASHED}/memory/dev-guides-cache.json"
```

Example: a project at `/home/user/workspace/brand/cotea` caches to
`~/.claude/projects/-home-user-workspace-brand-cotea/memory/dev-guides-cache.json`.

**Glob fallback.** When a consumer cannot reconstruct the cwd-derived path
(e.g. running from a different directory), fall back to a glob — the same
approach the pre-compact hook uses:

```bash
for dir in ~/.claude/projects/*/memory/; do
  [ -f "${dir}dev-guides-cache.json" ] && CACHE_FILE="${dir}dev-guides-cache.json" && break
done
```

## Structure

The cache schema is **exactly** three keys:

```json
{
  "hash": "<contents of llms.hash>",
  "fetched_at": "<ISO-8601 timestamp>",
  "content": "<full llms.txt markdown>"
}
```

- `hash` — the 64-char sha256 from `llms.hash`, used for staleness checks.
- `fetched_at` — ISO-8601 timestamp of the last successful fetch.
- `content` — the **complete, verbatim `llms.txt` markdown**. Consumers run
  `jq -r .content` and parse the topic table from it.

### Stale-cache rule

A cache file that **lacks a `content` key** is stale regardless of its `hash`.
This covers the legacy on-disk shapes that predate this contract:

- `{ "hash", "fetched" }` / `{ "hash", "fetched_at" }` — minimal, no content
- `{ "hash", "llms_txt" }` — wrong key name, sometimes a `"see full content…"`
  placeholder rather than the real markdown

When the navigator encounters any of these, it refetches `llms.txt` and
rewrites the file with the three-key schema, backfilling `content`. Never write
the compact `llms_txt` placeholder variant.

## Flow

**First time (no cache) OR cache missing `content` (stale):**
1. `curl -s` both `llms.hash` and `llms.txt`
2. Write `{ hash, fetched_at, content }` to the cache file

**Subsequent times (cache exists with `content`):**
1. `curl -s` `llms.hash` (tiny file)
2. Compare with cached `hash`
   - Same → use cached `content`
   - Different → re-fetch `llms.txt`, rewrite `{ hash, fetched_at, content }`

**Finding a guide:**
1. Match task keywords against the cached `content` topics
2. `curl -s` the topic's raw GitHub `index.md` (routing table)
3. Pick the specific guide from "I need to..." table
4. `curl -s` the raw GitHub URL for that guide `.md`
5. Apply the guide content to the task

**NEVER use WebFetch** — it summarizes content through AI, destroying the
structured formats needed for matching and routing.

---

## Recipes Cache (v0.7.0)

A **second, independent** cache file for the agentic-recipes catalog. Recipe
search consumes a separate published index (`agentic-recipes.txt` +
`agentic-recipes.hash`), deliberately distinct from `llms.txt`, so it gets its
own cache file. The guides cache above is untouched.

### Location

```
~/.claude/projects/<dasherized-cwd>/memory/dev-guides-recipes-cache.json
```

Same `<dasherized-cwd>` derivation and the same glob fallback as the guides
cache (see [Location](#location) above). Only the filename differs.

### Structure

```json
{
  "index": {
    "hash":       "<contents of agentic-recipes.hash>",
    "fetched_at": "<ISO-8601 timestamp>",
    "content":    "<full agentic-recipes.txt markdown>"
  },
  "recipes": {
    "<name>": {
      "sha":        "<8-char per-recipe content hash from the index line>",
      "fetched_at": "<ISO-8601 timestamp>",
      "content":    "<full RECIPE.md markdown>"
    }
  }
}
```

- `index` — caches the recipe **index** (`agentic-recipes.txt`), gated by the
  global `agentic-recipes.hash`. Same `{ hash, fetched_at, content }` shape as
  the guides cache, nested under `index`.
- `recipes` — a map keyed by recipe **name** (the `<name>` token from the index
  line, e.g. `responsive_image_wiring`). Each entry caches one recipe body
  (`RECIPE.md`), gated by that recipe's per-line `(sha:XXXXXXXX)`.

### Two hashes, two jobs

- **Index invalidation** — `agentic-recipes.hash` gates the `index` cache, exactly
  as `llms.hash` gates the guides cache.
- **Per-body invalidation** — each recipe body is gated by its own per-line
  `(sha:XXXXXXXX)`, **checkable without fetching the body**. A body is downloaded
  **exactly once per content version** and reused while its sha is unchanged.

### Flow

**Index (every recipe search):**
1. `curl -s https://camoa.github.io/dev-guides/agentic-recipes.hash`
2. Compare with cached `index.hash`
   - Same → use cached `index.content`
   - Different / no cache → `curl -s …/agentic-recipes.txt`, rewrite
     `index = { hash, fetched_at, content }`

**Body (download-once, per matched recipe):**
1. Read the matched index line's `(sha:XXXXXXXX)`
2. `recipes.<name>.sha` equals it → reuse `recipes.<name>.content`, **no fetch**
3. Else → `curl -s` the raw `.md` **once** (raw URL derived from the index line's
   site-url — never the GH Pages HTML), store
   `recipes.<name> = { sha, fetched_at, content }`

**NEVER use WebFetch**, never the GH Pages HTML URL for a body (raw only).
