# Dev Guides Navigator

Smart guide discovery and routing for the [dev-guides](https://camoa.github.io/dev-guides/) site. Routes AI to the correct guide using hash-based caching and KG metadata for disambiguation.

## Installation

```bash
/plugin install dev-guides-navigator@camoa-skills
```

## How It Works

1. **Cache check** — `curl -s` fetches `llms.hash` (64 bytes), compares with cached hash
2. **Topic match** — scans cached `llms.txt` for matching topic
3. **Fetch index** — `curl -s` reads topic's raw `index.md` with routing table and guide-meta
4. **Disambiguate** — uses `concepts`/`not` fields to prevent wrong-guide selection
5. **Fetch guide** — `curl -s` loads the specific guide from raw GitHub URL
6. **Apply** — extracts patterns and applies them to the current task

## Usage

The skill triggers automatically when any development task might benefit from a guide. You can also invoke it directly:

```
/dev-guides-navigator forms
/dev-guides-navigator SOLID drupal
/dev-guides-navigator design system bootstrap
```

### What It Covers

| Category | Topics |
|----------|--------|
| Drupal | Forms, entities, plugins, services, routing, caching, config, security, SDC, views, blocks, layout builder, migration, recipes, testing, and more |
| Design Systems | Bootstrap mapping, Radix/SDC, Tailwind tokens, DaisyUI, JSX-to-Twig, component recognition |
| Dev Practices | SOLID, DRY, TDD, security, modern CSS, CSS Craft |
| Next.js | next-drupal, Tiptap editor, DeepChat |

## Fetching Rule: curl Only

**All fetches use `curl -s` via Bash — never WebFetch.**

Why:
- **WebFetch summarizes content through AI**, destroying the structured markdown formats needed for routing and pattern matching
- **MkDocs GitHub Pages URLs** return 400KB+ HTML navigation shells, not guide content
- **Guides are atomic** and small enough for `curl` — no summarization needed

```bash
# Hash check (64 bytes)
curl -s https://camoa.github.io/dev-guides/llms.hash

# Topic index (llms.txt)
curl -s https://camoa.github.io/dev-guides/llms.txt

# Topic routing table (raw GitHub, not GitHub Pages)
curl -s https://raw.githubusercontent.com/camoa/dev-guides/main/docs/drupal/forms/index.md

# Specific guide (raw GitHub)
curl -s https://raw.githubusercontent.com/camoa/dev-guides/main/docs/drupal/forms/form-validation.md
```

## Configuration

No configuration required. The skill automatically caches `llms.txt` per project at:

```
~/.claude/projects/{project-hash}/memory/dev-guides-cache.json
```

## Disambiguation

KG metadata in each topic's `index.md` prevents routing to the wrong guide:

| Term | Correct Guide | NOT This Guide |
|------|---------------|----------------|
| story.yml | drupal/ui-patterns | drupal/storybook |
| stories.yml | drupal/storybook | drupal/ui-patterns |
| inline blocks | drupal/layout-builder | drupal/blocks |
| block plugin | drupal/blocks | drupal/layout-builder |
| SOLID (Drupal) | drupal/solid | dev-practices/solid-principles |

## Troubleshooting

| Problem | Fix |
|---------|-----|
| AI uses WebFetch instead of curl | The `allowed-tools` field excludes WebFetch — if it still happens, check that the plugin is installed |
| curl fails (network error) | Falls back to built-in `references/guide-index.md` keyword table |
| No topic matches | Broaden keywords or check category sections in llms.txt |
| Guide too large for context | Request only the specific section from the routing table |

## Dependencies

- `llms.hash` and `llms.txt` published at `https://camoa.github.io/dev-guides/`
- `guide-meta:` frontmatter in each topic's `index.md`

## Version

**v0.2.0** (Current) — Fixed WebFetch contradictions, upgraded to sonnet, pushy descriptions, allowed-tools enforcement

**v0.1.0** — Initial release with hash-based caching and KG metadata disambiguation

## License

MIT
