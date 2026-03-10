---
name: dev-guides-navigator
description: Smart guide discovery and routing for dev-guides site. Use when any development task might benefit from a guide — Drupal, Next.js, design systems, CSS, testing, security, SOLID, DRY, TDD. Caches llms.txt with hash-based freshness check. Reads topic index.md for KG metadata (concepts, disambiguation, relationships) to prevent wrong-guide selection. Keywords: guide, dev-guides, llms.txt, reference, pattern, best practice.
model: haiku
---

# Dev-Guides Navigator

Route to the correct online guide and enforce guide application.

## When to Use

- Any Drupal, Next.js, design system, or dev-practice task where a guide might help
- When another skill or agent needs domain knowledge beyond its bundled references
- When the user mentions a specific guide topic
- NOT for: plugin methodology references (those are in drupal-dev-framework/references/)

## Core Workflow

### 1. Get llms.txt (with caching)

Check for cache at `~/.claude/projects/{project-hash}/memory/dev-guides-cache.json`.

**IMPORTANT:** Use `curl` (via Bash) for `llms.hash` and `llms.txt` — these are plain text files that must be stored raw. WebFetch summarizes content through an AI model, which destroys the structured line-by-line format needed for topic matching.

**No cache (first time):**
1. Bash: `curl -s https://camoa.github.io/dev-guides/llms.hash` — save the hash
2. Bash: `curl -s https://camoa.github.io/dev-guides/llms.txt` — save the content
3. Write both to cache file

**Cache exists:**
1. Bash: `curl -s https://camoa.github.io/dev-guides/llms.hash` (tiny, fast)
2. Compare with cached hash
   - **Same** → use cached `llms.txt`, skip re-fetch
   - **Different** → Bash: `curl -s https://camoa.github.io/dev-guides/llms.txt`, update cache

**Note:** WebFetch is fine for topic `index.md` pages and individual guides (steps 3+5) — AI summarization helps extract routing tables and metadata from those pages.

### 2. Match Task to Topic

Scan `llms.txt` for the topic that matches the current task. Each line has a topic title, URL, guide count, and description.

### 3. Fetch Topic Index

WebFetch the matched topic's URL (e.g., `https://camoa.github.io/dev-guides/drupal/forms/`). This returns the topic's `index.md` containing:

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

### 5. Pick Specific Guide

From the "I need to..." routing table, select the guide that matches the task. WebFetch that individual guide `.md`.

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
| Get routing table | WebFetch topic `index.md` |
| Disambiguate | Check `guide-meta:` concepts/not fields |
| Get guide | WebFetch specific guide from routing table |
| Apply | Extract patterns and implement, don't summarize |

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Reading guide and only summarizing | Extract patterns and apply to current task |
| Grabbing first keyword match | Check guide-meta `not` fields for disambiguation |
| Fetching llms.txt every time | Check llms.hash first, use cache |
| Ignoring `requires` | Load prerequisites first |

## Examples

| User says | Action |
|-----------|--------|
| "I need to create a Drupal form" | Match "form" → `drupal/forms/` → fetch index.md → pick guide for form creation |
| "Add a story.yml for my component" | Match "story.yml" → check guide-meta → `drupal/ui-patterns/` (NOT storybook) |
| "Set up responsive images" | Match "responsive image" → `drupal/image-styles/` (NOT drupal/media) |
| "How do I use Config Split?" | Match "Config Split" → `drupal/config-management/` |
| "I need SOLID architecture for my module" | Drupal context → `drupal/solid/` (NOT generic dev-solid-principles) |

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `curl` fails (network error) | Fall back to `references/guide-index.md` for keyword-to-URL lookup |
| No topic matches the task | Broaden keywords, check category sections in llms.txt, or task may not need a guide |
| Cache file path unknown | Use Bash: `echo ~/.claude/projects/*/memory/` to find the project memory directory |
| WebFetch returns truncated index.md | Ask for specific sections: "Return the guide-meta frontmatter and routing table" |
| Guide content too large for context | Request only the specific section from the routing table, not the entire guide |

## See Also

- `references/cache-format.md` — cache file format
- `references/manifest-schema.md` — build output (llms.txt + llms.hash)
- `references/guide-index.md` — fallback keyword table (offline/network failure)
