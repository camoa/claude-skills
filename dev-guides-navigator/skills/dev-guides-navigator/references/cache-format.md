# Cache Format

This file is a **contract**. Other plugins (notably `drupal-dev-framework`)
locate and parse this cache directly. Do not change the location derivation or
the schema without updating those consumers.

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

Example: a project at `/home/camoa/workspace/brand/cotea` caches to
`~/.claude/projects/-home-camoa-workspace-brand-cotea/memory/dev-guides-cache.json`.

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
