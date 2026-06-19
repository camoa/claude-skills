# Dev Guides Navigator

Smart guide discovery and routing for the [dev-guides](https://camoa.github.io/dev-guides/) site. Routes AI to the correct guide using hash-based caching and KG metadata for disambiguation.

**Two modes:** the navigator routes over two separate published catalogs —
**guide search** (`llms.txt`, atomic mechanics-level guides) and **recipe search**
(`agentic-recipes.txt`, goal-oriented capability deliveries that sequence guides/plays
end-to-end and carry a verifier). Both modes are exposed with **no hardcoded order** — the
caller decides, typically recipe-search first, then guide-search. See
[Recipe Search](#recipe-search-v070) below.

> **Not using Claude Code?** See the marketplace [PORTABILITY.md](../PORTABILITY.md) — this plugin is pure-skill and the highest-portability one in the marketplace.

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

The `disallowed-tools: WebFetch` frontmatter makes this a harness-level hard
block, not just a convention.

## Recipe Search

Alongside guide search, the navigator exposes **recipe search** over the separate
**agentic-recipes** catalog. A recipe is a prescriptive, goal-oriented delivery of **one
capability** end-to-end: it **names** the guides and plays it needs (never duplicating
them) and carries a **verifier** (the drift check). The recipes index is published
separately from `llms.txt` so the guides index never grows by a recipe.

```bash
# Recipe index hash (gates the index cache)
curl -s https://camoa.github.io/dev-guides/agentic-recipes.hash

# Recipe index
curl -s https://camoa.github.io/dev-guides/agentic-recipes.txt

# Recipe body (raw GitHub — derived from the index line's site-url)
curl -s https://raw.githubusercontent.com/camoa/dev-guides/main/docs/agentic-recipes/drupal/responsive-image-wiring.md
```

Flow: cache the index by `agentic-recipes.hash` → match a line on `capability` +
when-to-use (no match → fall back to guide search, never fabricate) → download the body
**once**, keyed by the line's per-recipe `(sha:XXXXXXXX)` → hand each guide/play the recipe
names to the existing guide-search flow, and surface the recipe's verifier to the caller.
Guide search, `llms.txt`, and the guides cache are untouched — recipe search is strictly
additive. Recipe bodies cache to a separate sibling file,
`dev-guides-recipes-cache.json` (see `references/cache-format.md`).

## Create-on-Miss (maintainer mode)

If you **maintain** the dev-guides source repo, the navigator can help close gaps. When
guide search finds **no** guide for a topic **and** the local dev-guides source repo is
detected, the navigator **offers** to author the missing guide and **hands off** to that
repo's own `/create-guide` command. It only **detects + offers + hands off** — it never
authors, partitions, commits, or deploys.

- **Detection** — `DEV_GUIDES_SRC` env/config → `$PWD` → `~/workspace/dev-guides`,
  accepting a candidate only with the full 4-part signature (`mkdocs.yml` +
  `scripts/generate_llms.py` + `docs/agentic-recipes/` + a `.claude/agents/guide-*`).
- **Offer, never auto** — on a genuine miss it asks before doing anything.
- **`/create-guide`** researches a source guide, **pauses for your review**, partitions
  it, and opens a **PR** — it never merges or deploys (a human merging the PR is the
  deploy).
- **Consumer mode is byte-for-byte unchanged** — no repo detected → no offer, no behavior
  change.

See `references/create-on-miss.md` for the detection probe and full handoff protocol.

## Configuration

No configuration required. The skill automatically caches `llms.txt` per project at:

```
~/.claude/projects/<dasherized-cwd>/memory/dev-guides-cache.json
```

`<dasherized-cwd>` is the absolute working directory with every non-alphanumeric
character replaced by `-`. See `references/cache-format.md` for the exact
derivation and the `{hash, fetched_at, content}` schema.

### Cache pre-warming (optional)

A `Setup` hook (`hooks/setup-cache.sh`) pre-warms the `llms.txt` cache so the
first navigator call in a project is instant instead of paying a round-trip to
`camoa.github.io`. It fires **only** on `claude --init-only`, `claude -p --init`,
or `claude -p --maintenance` — never on normal interactive startup. In CI,
`claude --init-only` becomes the prep step. It is a pure optimization: if `jq`
or `curl` is missing, or the network is down, the skill still fills the cache
lazily on first use.

### Skill visibility (`skillOverrides`)

This skill triggers proactively on broad development terms. On a non-Drupal or
non-development project where that is noise, use the `skillOverrides` setting in
`.claude/settings.json` (Claude Code v2.1.129+) to dial it back without editing
the plugin:

- `"dev-guides-navigator": "user-invocable-only"` — keep `/dev-guides-navigator`
  as an explicit command, suppress proactive auto-invocation.
- `"dev-guides-navigator": "name-only"` — keep it discoverable for cross-skill
  delegation but drop the aggressive proactive triggers.
- `"dev-guides-navigator": "off"` — hide it entirely.

### Skill listing budget

Claude Code shows a per-turn skill listing capped by `skillListingBudgetFraction`
(default 1% of the context window) and `maxSkillDescriptionChars` (default 1536).
On a machine with many skills installed, the least-used skills' descriptions are
collapsed to bare names when the listing exceeds the budget — which can drop the
"why" of a proactive trigger. This navigator's description is well under the
1536-char cap, but if its proactive triggers seem to stop firing, run `/doctor`
to see the truncation count and raise `skillListingBudgetFraction` if needed.

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
| AI uses WebFetch instead of curl | The `disallowed-tools: WebFetch` frontmatter hard-blocks it — if it still happens, check that the plugin is installed and the skill is active |
| curl fails (network error) | Falls back to built-in `references/guide-index.md` keyword table |
| No topic matches | Broaden keywords or check category sections in llms.txt |
| Guide too large for context | Request only the specific section from the routing table |

## Dependencies

- `llms.hash` and `llms.txt` published at `https://camoa.github.io/dev-guides/`
- `guide-meta:` frontmatter in each topic's `index.md`

## Version

See [`CHANGELOG.md`](CHANGELOG.md) for the full version history. Current version: **0.11.2**.

## License

MIT
