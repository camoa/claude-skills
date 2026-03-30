---
name: dev-guides-navigator
description: "Use when looking up development guides, best practices, or reference documentation for Drupal, theming, design systems, Next.js, SOLID, DRY, TDD, or security tasks. Fetches guides from camoa.github.io/dev-guides with hash-based caching, matches tasks to topics using KG metadata disambiguation, and returns actionable patterns and code examples. Use when user says 'how do I', 'best practice', 'pattern for', 'guide for', 'Drupal form', 'entity type', 'routing', 'caching', 'SDC component', or 'design system'. Invoke proactively before design, architecture, or implementation work touching Drupal APIs, theming, or security."
version: 0.2.0
allowed-tools: Read, Bash, Glob, Grep, Write
user-invocable: true
---

# Dev-Guides Navigator

Route to the correct online guide, fetch it, and apply its patterns to the current task.

**CRITICAL: NEVER use WebFetch in this workflow.** All fetches use `curl -s` via Bash — WebFetch returns AI summaries or 400KB+ MkDocs HTML shells, destroying the structured content needed for matching. Guides are atomic and small enough for `curl`.

Not for: plugin methodology references (those are in drupal-dev-framework/references/).

## Core Workflow

### 1. Get llms.txt (with caching)

Check for cache at `~/.claude/projects/{project-hash}/memory/dev-guides-cache.json`.

**No cache (first time):**
1. Bash: `curl -s https://camoa.github.io/dev-guides/llms.hash` — save the hash
2. Bash: `curl -s https://camoa.github.io/dev-guides/llms.txt` — save the content
3. Write both to cache file

**Cache exists:**
1. Bash: `curl -s https://camoa.github.io/dev-guides/llms.hash` (tiny, fast)
2. Compare with cached hash
   - **Same** → use cached `llms.txt`, skip re-fetch
   - **Different** → Bash: `curl -s https://camoa.github.io/dev-guides/llms.txt`, update cache

### 2. Match Task to Topic

Scan `llms.txt` for the topic that matches the current task. Each line has a topic title, URL, guide count, and description.

The URL in `llms.txt` is a GitHub Pages URL like `https://camoa.github.io/dev-guides/drupal/forms/`. Extract the **topic path** (e.g., `drupal/forms`) from this URL for use in raw GitHub fetches below.

### 3. Fetch Topic Index

```bash
curl -s https://raw.githubusercontent.com/camoa/dev-guides/main/docs/{topic-path}/index.md
```

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

### 5. Fetch Specific Guide

From the "I need to..." routing table, select the guide that matches the task. The routing table lists guide filenames. Fetch the raw markdown:

```bash
curl -s https://raw.githubusercontent.com/camoa/dev-guides/main/docs/{topic-path}/{guide-filename}.md
```

Example: `curl -s https://raw.githubusercontent.com/camoa/dev-guides/main/docs/drupal/forms/form-validation.md`

### 6. Apply the Guide (Critical)

**Do NOT just read and summarize.** Extract and apply:

1. Identify the relevant section(s) for the current task
2. Extract decision criteria, patterns, and code examples
3. Apply them directly to the implementation
4. Reference the guide in architecture docs if in design phase

## Quick Reference

| Step | Action |
|------|--------|
| Cache check | `curl -s` llms.hash, compare with cached hash |
| Find topic | Match task keywords in cached `llms.txt` |
| Get routing table | `curl -s` raw GitHub URL for topic `index.md` |
| Disambiguate | Check `guide-meta:` concepts/not fields |
| Get guide | `curl -s` raw GitHub URL for specific guide `.md` |
| Apply | Extract patterns and implement, don't summarize |

## Examples

| User says | Action |
|-----------|--------|
| "I need to create a Drupal form" | Match "form" → `drupal/forms/` → fetch index.md → pick guide for form creation |
| "Add a story.yml for my component" | Match "story.yml" → check guide-meta → `drupal/ui-patterns/` (NOT storybook) |
| "Set up responsive images" | Match "responsive image" → `drupal/image-styles/` (NOT drupal/media) |
| "How do I use Config Split?" | Match "Config Split" → `drupal/config-management/` |

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `curl` fails (network error) | Fall back to `references/guide-index.md` for keyword-to-URL lookup |
| No topic matches the task | Broaden keywords, check category sections in llms.txt |
| Guide content too large for context | Request only the specific section from the routing table |
| First keyword match is wrong topic | Check guide-meta `not` fields for disambiguation |
| Cache file path unknown | Use Bash: `echo ~/.claude/projects/*/memory/` |

## See Also

- `references/cache-format.md` — cache file format
- `references/manifest-schema.md` — build output (llms.txt + llms.hash)
- `references/guide-index.md` — fallback keyword table (offline/network failure)
