# Dev Guides Navigator

[![Listed on ClaudePluginHub](https://www.claudepluginhub.com/badge/camoa-dev-guides-navigator-dev-guides-navigator)](https://www.claudepluginhub.com/plugins/camoa-dev-guides-navigator-dev-guides-navigator?ref=badge)

The model writes code from whatever it remembered at training time, which is often out of date. APIs change, defaults shift, and a training cutoff has no idea about this month's Drupal core release, a design system that moved to a new token format, or the security guidance that hardened since. Left alone, the AI writes from memory and calls it done.

Dev Guides Navigator routes each task to the current guide instead of a guess. It matches the task to a topic in a published catalog of 1200+ atomic decision guides (Drupal, Next.js, design systems, and dev practices), disambiguates near-duplicate guides using metadata so a similar-sounding term doesn't route to the wrong one, and applies the guide's patterns directly to the task rather than summarizing them at you. Everything is hash-cached, so a guide already loaded this session, or this project, is never re-fetched. It is a required dependency of `ai-dev-assistant` (every phase loads guides through it), and it works standalone for any task, from any plugin, that wants current information instead of stale training data.

> **Not using Claude Code?** See the marketplace [PORTABILITY.md](../PORTABILITY.md). This plugin is pure-skill (no commands, no agents; its only hooks are an optional Setup cache warmer and a lightweight PreCompact pointer that just re-surfaces the catalog path), which makes it the highest-portability plugin in the marketplace.

## See it in action

No command to remember. You ask the thing you'd normally ask, and the skill triggers on its own:

```text
You: How do I add form validation to this Drupal module?
```

```text
Cache check   → llms.hash unchanged, using the cached llms.txt
Topic match   → drupal/forms
Disambiguate  → guide-meta confirms this is the right topic (not drupal/entity-forms)
Fetch guide   → form-validation.md (served from cache, sha256 unchanged since last fetch)
Apply         → validation pattern applied to your form class, not just described
```

That is the guide-search mode, the original flow. Two more exist for different situations: recipe search, for a whole capability rather than one mechanic (see [docs/usage.md](docs/usage.md#what-it-does)), and process-recipe lookup, called by `ai-dev-assistant` at phase boundaries, not something you invoke directly.

You do not have to wait for the proactive trigger. Naming the skill directly, for example "check the navigator for Drupal SOLID principles" or "look up the guide for SDC components," runs the same routing on demand.

## When to reach for it

Reach for it, or let it trigger on its own, whenever a task touches a domain with a real current best practice: Drupal APIs, theming, a design system, Next.js integration, or anything security-sensitive. It is proactive by design (see the frontmatter's trigger phrases in the skill itself), so most of the time you won't reach for it at all, it will already be running before you finish describing the task. Skip it for edits that don't touch a pattern: renaming a variable, fixing a typo, a one-line config tweak.

It is the guide-loading engine behind `ai-dev-assistant`'s Research and Architecture phases, but it is independent and useful without that plugin: any Claude Code session that wants current best practice instead of a memorized one can install just this.

## Installation

```bash
/plugin install dev-guides-navigator@camoa-skills
```

No plugin dependencies: it talks directly to the published catalog over `curl`, nothing else to install first.

## How it works

Three independent routing modes, over three separate published catalogs. The caller decides the order, typically recipe search first (is there an end-to-end recipe for this capability?), then guide search (fall back to raw mechanics):

| Mode | Catalog | What it resolves |
|------|---------|-------------------|
| Guide search | `llms.txt` | An atomic, mechanics-level guide for one pattern or decision. |
| Recipe search | `agentic-recipes.txt` | A prescriptive, goal-oriented sequence of guides and plays for one whole capability, plus a verifier. |
| Process-recipe lookup | `process-recipes.txt` | The framework-specific method for one lifecycle phase, resolved by `(phase, framework)`. Invoked only by `ai-dev-assistant`, never during free task routing. |

A guide-search miss on a near-duplicate topic is the case the metadata exists to prevent:

| Term | Correct guide | Not this guide |
|------|---------------|-----------------|
| story.yml | `drupal/ui-patterns` | `drupal/storybook` |
| stories.yml | `drupal/storybook` | `drupal/ui-patterns` |
| inline blocks | `drupal/layout-builder` | `drupal/blocks` |
| SOLID (Drupal) | `drupal/solid` | `dev-practices/solid-principles` |

Full mechanics (the cache kernel, blob-addressed guide bodies, recipe search, process-recipe lookup, and create-on-miss for dev-guides maintainers) are in [docs/usage.md](docs/usage.md#what-it-does).

## What it covers

| Category | Topics |
|----------|--------|
| Drupal | Forms, entities, plugins, services, routing, caching, config, security, SDC, views, blocks, layout builder, migration, recipes, testing, and more |
| Design systems | Bootstrap mapping, Radix/SDC, Tailwind tokens, DaisyUI, JSX-to-Twig, component recognition |
| Dev practices | SOLID, DRY, TDD, security, modern CSS, CSS Craft |
| Next.js | next-drupal, Tiptap editor, DeepChat |

## Fetching rule: curl only

All fetches use `curl -s`, never WebFetch. WebFetch summarizes content through AI, which destroys the structured markdown the routing and disambiguation logic needs, and the MkDocs GitHub Pages URLs return 400KB+ HTML navigation shells rather than guide content. The `disallowed-tools: WebFetch` frontmatter makes this a hard block, not just a convention:

```bash
curl -s https://camoa.github.io/dev-guides/llms.hash                                              # hash check, 64 bytes
curl -s https://camoa.github.io/dev-guides/llms.txt                                                # topic index
curl -s https://raw.githubusercontent.com/camoa/dev-guides/main/docs/drupal/forms/index.md         # topic routing table
curl -s https://raw.githubusercontent.com/camoa/dev-guides/main/docs/drupal/forms/form-validation.md  # specific guide
```

## Configuration

No configuration required. The skill caches `llms.txt` and guide bodies per project (guide bodies in a shared, content-addressed blob store, so the same guide is never fetched twice on the same machine even across projects). See [docs/usage.md](docs/usage.md#prerequisites) for the exact paths.

Two things worth knowing if the defaults don't fit:

- **Cache pre-warming (optional).** A `Setup` hook fires only on `claude --init-only`, `claude -p --init`, or `claude -p --maintenance` (a CI prep step, never normal interactive startup) to fill the `llms.txt` cache ahead of the first call. If `jq` or `curl` is missing, or the network is down, the skill still fills the cache lazily on first use; the hook is a pure optimization.
- **Skill visibility (`skillOverrides`, Claude Code v2.1.129+).** This skill triggers proactively on broad development terms, which is noise on a non-development project. Set `"dev-guides-navigator"` to `"user-invocable-only"` (keep direct invocation, drop proactive triggers), `"name-only"` (keep it discoverable for cross-skill delegation, drop the aggressive triggers), or `"off"` (hide it entirely) in `.claude/settings.json`.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| AI uses WebFetch instead of curl | The `disallowed-tools: WebFetch` frontmatter hard-blocks it; if it still happens, confirm the plugin is installed and the skill is active |
| curl fails (network error) | Falls back to the skill's built-in keyword table in `skills/dev-guides-navigator/references/guide-index.md` |
| No topic matches | Broaden your keywords, or check the category sections in `llms.txt` directly |
| Guide too large for context | Ask for the specific section named in the routing table, not the whole guide |

## Dependencies

- `llms.hash` and `llms.txt`, published at `https://camoa.github.io/dev-guides/`.
- `guide-meta:` frontmatter in each topic's `index.md`, which is what makes disambiguation possible.

## Version

See [CHANGELOG.md](CHANGELOG.md) for the full version history. Current version: **0.11.4**.

## License

MIT
