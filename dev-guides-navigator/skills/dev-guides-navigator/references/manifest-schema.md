# Build Output

## Files Generated

The build step (`generate_llms.py`) produces two files in `site/`:

| File | Purpose | Size |
|------|---------|------|
| `llms.txt` | Topic index — maps topics to their URL | ~4KB |
| `llms.hash` | SHA-256 of `llms.txt` content | 64 bytes |

## llms.txt Format

```
# Dev Guides

> AI-friendly atomic decision guides...

## Drupal

- [Drupal Form API](https://camoa.github.io/dev-guides/drupal/forms/): 26 guides — ...
- [Drupal Blocks](https://camoa.github.io/dev-guides/drupal/blocks/): 23 guides — ...

## Design Systems

- [Bootstrap Mapping](https://camoa.github.io/dev-guides/design-systems/bootstrap/): 16 guides — ...
```

Each entry points to a topic's `index.md` page, which contains the "I need to..." routing table.

## llms.hash Format

Plain text file containing the SHA-256 hash of `llms.txt`:

```
a1b2c3d4e5f6...
```

## KG Metadata

Lives in each topic's `index.md` frontmatter as `guide-meta:`. Not in the build output — read when the AI fetches the topic index.

```yaml
---
description: Topic description
guide-meta:
  concepts: [terms this guide owns]
  not: [terms that should NOT route here]
  requires: [prerequisite topic keys]
  complements: [related topic keys]
  specializes: ""
  category: drupal
---
```

The AI reads this when it fetches the `index.md` to understand relationships and disambiguation.
