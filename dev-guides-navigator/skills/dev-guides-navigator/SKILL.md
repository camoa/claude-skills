---
name: dev-guides-navigator
description: Use when ANY development task might benefit from a guide. Use when user says "how do I", "best practice", "pattern for", "guide for", "Drupal form", "entity type", "plugin type", "routing", "caching", "config management", "SDC component", "design system", "Bootstrap mapping", "Radix theme", "JSX to Twig", "Tailwind tokens", "SOLID", "DRY", "TDD", "security", "CSS", "Next.js". Use PROACTIVELY before any design, architecture, or implementation work. MUST be invoked before writing code that touches Drupal APIs, theming, design systems, or security. NEVER skip guide check — patterns prevent bugs.
version: 0.7.0
allowed-tools: Read, Bash, Glob, Grep, Write
disallowed-tools: WebFetch
user-invocable: true
---

# Dev-Guides Navigator

Route to the correct online guide and enforce guide application.

## Two modes

The navigator exposes **two independent routing modes** over two separate published catalogs:

- **Guide search** (`llms.txt`) — atomic, mechanics-level decision guides. The original flow. See **Core Workflow** below.
- **Recipe search** (`agentic-recipes.txt`) — goal-oriented, prescriptive capability deliveries that sequence existing guides/plays end-to-end and carry a verifier. See **Recipe Search** below.

The navigator does **not** hardcode an order. The **caller** owns ordering — typically recipe-search first (is there a prescriptive end-to-end recipe for this capability?), then guide-search (fall back to raw mechanics). Recipe search never fabricates a recipe: a miss cleanly defers to guide search.

## When to Use

- Any Drupal, Next.js, design system, or dev-practice task where a guide might help
- When another skill or agent needs domain knowledge beyond its bundled references
- When the user mentions a specific guide topic
- When a task is a whole **capability** (one end-to-end goal) rather than a single mechanic — try **recipe search** first
- NOT for: plugin methodology references (those are in drupal-dev-framework/references/)

## Core Workflow

### 1. Get llms.txt (with caching)

Cache file: `~/.claude/projects/<dasherized-cwd>/memory/dev-guides-cache.json`.
See `references/cache-format.md` for the **exact path derivation** and schema —
other plugins (e.g. `drupal-dev-framework`) consume this cache directly, so the
format and location are a contract, not an implementation detail.

**NEVER use WebFetch in this workflow.** All fetches use `curl -s` via Bash:
- WebFetch summarizes content through AI, destroying structured formats needed for matching
- MkDocs GitHub Pages URLs return 400KB+ HTML navigation shells, not guide content
- Guides are atomic and small enough for `curl` — no summarization needed

The cache schema is **exactly** three keys:

```json
{ "hash": "<contents of llms.hash>", "fetched_at": "<ISO-8601 timestamp>", "content": "<full llms.txt markdown>" }
```

Always write the **complete `llms.txt` markdown** to the `content` key. Never
write a compact placeholder (e.g. the legacy `"llms_txt": "see full content…"`
variant) — downstream consumers parse `content` directly and a placeholder
breaks them.

**No cache, OR cache file is missing the `content` key (treat as stale):**
1. Bash: `curl -s https://camoa.github.io/dev-guides/llms.hash` — save the hash
2. Bash: `curl -s https://camoa.github.io/dev-guides/llms.txt` — save the content
3. Write `{ hash, fetched_at, content }` to the cache file. This self-heals the
   old minimal (`{hash,fetched_at}`) and compact (`{hash,llms_txt}`) caches by
   backfilling `content`.

**Cache exists and has a `content` key:**
1. Bash: `curl -s https://camoa.github.io/dev-guides/llms.hash` (tiny, fast)
2. Compare with cached `hash`
   - **Same** → use cached `content`, skip re-fetch
   - **Different** → Bash: `curl -s https://camoa.github.io/dev-guides/llms.txt`,
     rewrite the cache as `{ hash, fetched_at, content }`

### 2. Match Task to Topic

Scan `llms.txt` for the topic that matches the current task. Each line has a topic title, URL, guide count, and description.

The URL in `llms.txt` is a GitHub Pages URL like `https://camoa.github.io/dev-guides/drupal/forms/`. Extract the **topic path** (e.g., `drupal/forms`) from this URL for use in raw GitHub fetches below.

### 3. Fetch Topic Index

**IMPORTANT:** Do NOT use WebFetch on GitHub Pages URLs — MkDocs renders them into 400KB+ HTML pages with navigation shells, hiding the actual content. Use `curl` with raw GitHub URLs instead.

```bash
curl -s https://raw.githubusercontent.com/camoa/dev-guides/main/docs/{topic-path}/index.md
```

Example: `curl -s https://raw.githubusercontent.com/camoa/dev-guides/main/docs/drupal/forms/index.md`

This returns the raw markdown containing:

- **"I need to..." routing table** — maps user intent to specific guide
- **`guide-meta:` frontmatter** — KG metadata for disambiguation and relationships

### 4. Use KG Metadata (from index.md)

The `guide-meta:` in the topic's frontmatter provides:

- **`concepts`** — confirms this is the right topic
- **`not`** — if the task matches a `not` term, this is the WRONG topic, go back to step 2
- **`requires`** — load prerequisite topics first
- **`complements`** — note related topics for the user

| Example Task | Correct Topic | Wrong Topic | Why |
|--------------|---------------|-------------|-----|
| story.yml props | drupal/ui-patterns | drupal/storybook | "story.yml" in ui-patterns concepts, "storybook" in not |
| stories.yml preview | drupal/storybook | drupal/ui-patterns | reverse |
| inline blocks | drupal/layout-builder | drupal/blocks | "inline blocks" in blocks' not |

### 5. Pre-filter by Summary (NEW)

The routing table in `index.md` now has 3 columns: **I need to... | Guide | Summary**.

When the user's request maps to multiple candidate rows:
- Read the Summary column for each candidate (already in the fetched `index.md` — no new fetch)
- Pick the guide whose Summary best matches the user's specific need
- Then fetch that one guide (step 6)

When only one row matches: skip to step 6.

**Do NOT fetch individual guides just to read their `tldr:`** — that's the same cost as fetching the full guide. The Summary column exists so you don't have to.

### 6. Fetch Specific Guide

From the "I need to..." routing table, select the guide that matches the task. The routing table lists guide filenames. Fetch the raw markdown:

```bash
curl -s https://raw.githubusercontent.com/camoa/dev-guides/main/docs/{topic-path}/{guide-filename}.md
```

Example: `curl -s https://raw.githubusercontent.com/camoa/dev-guides/main/docs/drupal/forms/form-validation.md`

**Do NOT use WebFetch on GitHub Pages URLs** — you'll get rendered HTML, not the guide content.

### 7. Apply the Guide (Critical)

**Do NOT just read and summarize.** Extract and apply:

1. Identify the relevant section(s) for the current task
2. Extract decision criteria, patterns, and code examples
3. Apply them directly to the implementation
4. Reference the guide in architecture docs if in design phase

## Recipe Search

Recipe search is **symmetric to guide search** but consumes a **separate** catalog —
the **agentic recipes** index. A recipe is a prescriptive, goal-oriented delivery of
**one capability** end-to-end: it **names** the guides and plays it needs (it never
duplicates them) and carries a **verifier** (the drift check). Recipes publish to their
**own** index, deliberately separate from `llms.txt` so the guides index never grows by
a recipe.

This flow is **strictly additive** — it does not touch guide search, `llms.txt`, or the
guides cache.

### Catalog contract (build to exactly this)

- **Index** (`curl`, never WebFetch):
  `https://camoa.github.io/dev-guides/agentic-recipes.txt` + `agentic-recipes.hash`
- One line per recipe, grouped under a `## Domain` heading:
  `- <name> [<capability>] (sha:XXXXXXXX): <one-line when-to-use> — <site-url>`
- **Recipe body** (full RECIPE.md) fetched as **raw markdown**, never the GH Pages HTML —
  derive from the `<site-url>` in the index line:
  `https://raw.githubusercontent.com/camoa/dev-guides/main/docs/agentic-recipes/<domain>/<name-dasherized>.md`
  (e.g. site-url `.../agentic-recipes/drupal/responsive-image-wiring/` →
  raw `.../docs/agentic-recipes/drupal/responsive-image-wiring.md`). Born-atomic: one file, one fetch.
- **Two hashes, two jobs:** `agentic-recipes.hash` gates the **index** cache; the per-line
  `(sha:XXXXXXXX)` gates each **recipe body** cache — checkable without fetching the body.

### 1. Get `agentic-recipes.txt` (with caching)

Cache file: `~/.claude/projects/<dasherized-cwd>/memory/dev-guides-recipes-cache.json` —
a **separate sibling** to the guides cache, same path derivation. See
`references/cache-format.md` for the schema and the cross-plugin contract.

**NEVER use WebFetch.** All fetches use `curl -s` via Bash (same discipline, same reasons
as guide search). The frontmatter `disallowed-tools: WebFetch` makes this a hard block.

- Bash: `curl -s https://camoa.github.io/dev-guides/agentic-recipes.hash`
- Compare with the cached `index.hash`:
  - **Same** → use cached `index.content`, skip re-fetch
  - **Different or no cache** → Bash: `curl -s https://camoa.github.io/dev-guides/agentic-recipes.txt`,
    rewrite `index` as `{ hash, fetched_at, content }`

### 2. Match capability

Scan the index lines and match on **`capability`** (the machine key in `[...]`) plus the
**when-to-use description**. Keep this lean — **do not fetch any recipe body during matching.**

- **Match** → proceed to step 3 with that line's `<name>`, `<sha>`, and `<site-url>`.
- **No match** → report "no recipe for this capability; fall back to guide search" and **STOP**.
  Never fabricate a recipe.

### 3. Fetch the body (download-once)

Read the matched line's `(sha:XXXXXXXX)`:

- Cached body for `<name>` exists with the **same sha** → **reuse it, no fetch.**
- Otherwise → `curl -s` the raw `.md` **once** (raw URL derived from the site-url, per the
  contract above) and store `recipes.<name> = { sha, fetched_at, content }`.

A body is downloaded **exactly once per content version** and reused for the session.

### 4. Apply (hand off + surface the verifier)

The recipe is **sequence + opinion + verifier**; the guides it cites are the **mechanics**.

1. For each guide or play the recipe **names**, hand off to the **existing guide-search flow**
   above (Core Workflow steps 2–7). The recipe does not replace guide search — it drives it.
2. **Surface the recipe's verifier to the caller** — it is the drift check that confirms the
   capability was delivered correctly.

## See Also

- `references/quick-reference.md` — condensed workflow table + common mistakes
- `references/examples.md` — worked routing examples (user request → correct guide)
- `references/troubleshooting.md` — what to do when a workflow step fails
- `references/cache-format.md` — guides cache + recipes cache formats (cross-plugin contract)
- `references/manifest-schema.md` — build output (llms.txt + llms.hash)
- `references/guide-index.md` — fallback keyword table (offline/network failure)
