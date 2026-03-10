# Dev Guides Navigator

Smart guide discovery and routing for the [dev-guides](https://camoa.github.io/dev-guides/) site. Routes AI to the correct guide using hash-based caching and KG metadata for disambiguation.

## Installation

```bash
/plugin marketplace add camoa-skills
/plugin install dev-guides-navigator
```

## How It Works

1. **Cache check** — fetches `llms.hash` (64 bytes), compares with cached hash
2. **Topic match** — scans cached `llms.txt` for matching topic
3. **Fetch index** — reads topic's `index.md` with routing table and guide-meta
4. **Disambiguate** — uses `concepts`/`not` fields to prevent wrong-guide selection
5. **Fetch guide** — loads the specific guide from the routing table
6. **Apply** — extracts patterns and applies them to the current task

## Components

- **Skill**: `dev-guides-navigator` — triggered by any task that might benefit from a guide (Drupal, Next.js, design systems, CSS, testing, security, SOLID, DRY, TDD)

## Configuration

No configuration required. The skill automatically caches `llms.txt` per project at:

```
~/.claude/projects/{project-hash}/memory/dev-guides-cache.json
```

## Dependencies

- `llms.hash` and `llms.txt` published at `https://camoa.github.io/dev-guides/`
- `guide-meta:` frontmatter in each topic's `index.md`
