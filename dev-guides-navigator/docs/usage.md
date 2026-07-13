# Using Dev Guides Navigator

The [README](../README.md) is the shop window. This is the how: what the skill does, when it fires, what it needs, how you know it is working, and where it fits with the rest of the marketplace.

## What it does

It is a routing and caching layer over a published catalog of guides, so an AI session works from current best practice instead of a training-time guess. Three modes, over three separate catalogs, and the caller (typically an orchestrator like `ai-dev-assistant`, or you directly) decides which to try first:

- **Guide search** (`llms.txt`), the original flow: match the task to a topic, fetch that topic's routing table (`index.md`), disambiguate near-duplicate topics using `guide-meta` (`concepts`/`not`/`requires`/`complements` fields), fetch the specific guide, and apply its patterns to the task rather than summarizing them at you.
- **Recipe search** (`agentic-recipes.txt`): for a whole capability rather than one mechanic. A recipe names the guides and plays it needs (it never duplicates them) and carries a verifier, the drift check that confirms the capability was actually delivered. A capability with no matching recipe falls back to guide search; recipe search never fabricates a recipe.
- **Process-recipe lookup** (`process-recipes.txt`): resolved by `(phase, framework)`, called only by `ai-dev-assistant` at a lifecycle phase boundary, never during free task routing. It returns a store path to the body, not the body itself, so the caller reads the file rather than the body streaming into the conversation.

Every fetch goes through a deterministic cache kernel and uses `curl`, never `WebFetch` (the frontmatter hard-blocks it): WebFetch summarizes content through AI, which destroys the structured markdown the routing logic depends on. Guide bodies, task-recipe bodies, and process-recipe bodies are content-addressed in a shared blob store (keyed by sha256 or sha8, whichever the catalog publishes), so the same body is fetched once per content version and reused after that, even across projects. A per-project lockfile records what that project actually touched.

If you maintain the dev-guides source repo yourself, a genuine guide-search miss (nothing in the catalog, nothing in the offline fallback table) triggers a create-on-miss offer: detect the source repo, ask before doing anything, then hand off to that repo's own `/create-guide` command, which researches a guide, pauses for your review, partitions it, and opens a PR (never merges or deploys). Consumer installs (no source repo detected) see no behavior change.

## When to reach for it

You mostly won't reach for it. It is proactive by design: the skill's trigger phrases ("how do I," "best practice," "pattern for," "guide for," a named topic like "Drupal form" or "SDC component") fire it automatically before design, architecture, or implementation work that touches a domain with a real current best practice. It is also invocable directly, by naming the skill or the topic in the request, when you want to check a guide without waiting on a proactive match, or when you are another skill or agent that needs domain knowledge beyond your own bundled references.

Reach for recipe search specifically when the task is one whole capability, not a single mechanic, delivered end to end (a responsive-image pipeline wired up, not just "how do image styles work"). Reach for process-recipe lookup never directly; it is `ai-dev-assistant`'s mechanism for resolving the framework-specific method at a phase boundary.

Skip it for edits that don't touch a pattern: a rename, a typo fix, a one-line config value, project management, or plain conversation. If you never want it firing proactively on a given project (a non-development repo, for instance), set it to `user-invocable-only` or `off` via `skillOverrides` rather than declining the same prompt over and over.

## Prerequisites

- **`curl` and `jq`** for the cache kernel (`scripts/dev-guides-store.sh`) and the fetches themselves. Without `jq`/`curl`, the cache pre-warming hook simply skips and the skill fills the cache lazily on first use instead.
- **Network access** to `camoa.github.io` (indexes and hashes) and `raw.githubusercontent.com` (guide, recipe, and process-recipe bodies). A network failure on guide search falls back to the offline keyword table in the skill's bundled `skills/dev-guides-navigator/references/guide-index.md`; a network failure on recipe search or process-recipe lookup reports unavailable rather than fabricating a result.
- **No plugin dependencies.** This plugin installs standalone; nothing else has to be present first.
- **Claude Code v2.1.129+** only if you want the `skillOverrides` setting to dial back proactive triggering; earlier CLI versions still get the skill, just without that override.
- **A writable `~/.claude/` tree** for the shared store (`~/.claude/dev-guides-store/`, machine-level, shared across projects) and the per-project lockfile (`~/.claude/projects/<dasherized-cwd>/memory/dev-guides.lock.json`).

## It's working if

- A development question ("how do I validate a Drupal form," "what's the pattern for an SDC component") gets an answer that cites and applies a specific guide, not a generic answer from memory.
- `~/.claude/dev-guides-store/indexes/llms.json` exists after the first call and is not re-fetched (same `hash`) on the next call in the same session.
- A guide body lands in `~/.claude/dev-guides-store/blobs/<sha256>`, and the project's `dev-guides.lock.json` records the `<topic>/<file.md>` key under `guides`.
- A near-duplicate term routes to the correct topic, not the wrong one: "story.yml" resolves to `drupal/ui-patterns`, not `drupal/storybook`.
- Asking for a whole capability (recipe search) either returns a named recipe with its guides applied and its verifier surfaced, or a clean "no recipe for this, falling back to guide search," never a fabricated recipe.

If none of this happens (the AI just answers from memory, no cache files appear, or WebFetch shows up in the transcript instead of curl), confirm the plugin is installed and not muted by a `skillOverrides` setting, then see the [README's Troubleshooting table](../README.md#troubleshooting).

## Where it fits

- **[ai-dev-assistant](../../ai-dev-assistant/README.md)** declares this plugin as a required dependency: every research and architecture phase loads guides through it, and process-recipe lookup (the third mode above) is invoked only by its lifecycle orchestrator at a phase boundary. This plugin has no dependency the other direction; it runs standalone.
- It is the plugin that keeps the rest of the marketplace working from **current** information rather than a training-time snapshot. Any plugin whose skills touch Drupal, a design system, Next.js, or general dev-practice patterns benefits from checking a guide here before writing anything, the same rule `ai-dev-assistant`'s `CONVENTIONS.md` states for itself.
- For the reasoning behind guides-that-explain versus gates-that-enforce, and why current information matters as much as correct process, see the marketplace [PHILOSOPHY.md](../../PHILOSOPHY.md).
