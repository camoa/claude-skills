# drupal-ai-contrib — Plugin Conventions

Maintainer/contributor conventions for this plugin. Not loaded as end-user context.

## Core principle

**Evidence over assertion.** Every gate passes only on a produced artifact — a
command's output, a file diff, a live API response, a real pipeline result. Never on
the model stating "done", "passes", or "should work". This invariant governs every
component; the plugin eats its own dog food.

## Commands
- Thin entry points. Each command validates its arguments, then invokes its backing
  worker skill via the Skill tool and presents the result. No procedure logic in the
  command body.
- Frontmatter must include: `description` (with literal trigger phrases), `allowed-tools`.
- Use `argument-hint` when the command accepts arguments.
- Restrict `allowed-tools` to the minimum the backing worker skill needs.

## Skills
- Frontmatter must include: `name`, `description`, `version`.
- The umbrella skill (`drupal-ai-contrib`) and the six worker skills are
  `user-invocable: false` — invoked by their command or routed to by the umbrella.
- `contribution-guardrails` is user-invocable — a contributor may pull it up directly.
- Body uses imperative voice — instructions for Claude, not documentation.
- Under 500 lines per SKILL.md; push detail into `references/`.

## Agents
- Frontmatter must include: `name`, `description`, `version`, `model`.
- The agent tool allowlist field is `tools` (NOT `allowed-tools` — silently ignored on
  agents). Read-only agents also carry `disallowedTools: Edit, Write`.
- All three agents are read-only — they return findings, never modify files.

## Hooks
- Command hooks use exec form (`"args": []`).

## The knowledge layer — dev-guides
The plugin's technical how-to comes from the `camoa/dev-guides` contribution guides,
accessed via the `dev-guides-navigator` skill (caching + disambiguation). Worker skills
cite guides by slug; they do NOT embed or duplicate guide content, and never fetch
`llms.txt` or dev-guides URLs directly. See `skills/drupal-ai-contrib/references/dev-guides-index.md`.

## The governance layer — ai_best_practices
AI-policy + compliance + evals anchor on `ai_best_practices` (the canonical Drupal AI
source of truth) and the adopted *Policy on the use of AI when contributing to Drupal*.
Both are fetched live, never hard-coded — they move fast.

## General
- Current truth only — no historical narratives in skill/command bodies.
- Delegate, don't reinvent: `drupal-dev-framework` (phase lifecycle), `code-quality-tools`
  (philosophy/standards review), `code-paper-test` (paper testing), `drupalorg-cli`
  (issue/MR/CI). The plugin owns orchestration + evidence-gating + the contribution arc.
