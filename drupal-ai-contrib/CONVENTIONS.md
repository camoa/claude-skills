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
- `model: inherit` on every SKILL.md. A skill `model:` is an inline, current-turn
  override with no context isolation — pinning a sub-1M tier (`sonnet`/`haiku`) overflows
  when the skill activates from a large conversation (validator S14). Pin a tier only on
  a Task-dispatched **agent** (fresh context), never on a skill.
- Read-only worker skills carry `disallowed-tools: Edit, Write` (kebab-case on skills —
  distinct from the agent `disallowedTools` camelCase field): `contribution-review`,
  `-verify`, `-pipeline`, and `-guardrails` dispatch agents / run gates / read status and
  never mutate contribution files. `-setup`, `-issue`, `-submit`, and the umbrella write
  or run git ops, so they keep full tool access.
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
- Delegate, don't reinvent: `ai-dev-assistant` (phase lifecycle), `code-quality-tools`
  (philosophy/standards review), `code-paper-test` (paper testing), `mglaman/drupalorg-cli`
  (issue/MR/CI — executable `drupalorg`; see `skills/drupal-ai-contrib/references/drupalorg-cli.md`).
  The plugin owns orchestration + evidence-gating + the contribution arc.

## Enforcement model & known limitations

Be honest about what this plugin can and cannot enforce — the plugin preaches evidence
over assertion, so it must apply that candor to itself.

- **Enforcement is instruction-level, plus one hook.** A Claude Code plugin is skills
  (instructions) — there is no runtime engine that *compels* the model to run `phpcs`,
  dispatch an agent, or paste a captured artifact. The gate contracts in
  `contribution-verify` and `contribution-guardrails` are followed because the
  instructions are explicit and strongly worded, not because a supervisor blocks a
  skipped step. The **`PostToolUse` re-verification hook is the one piece of genuine
  runtime enforcement.** When wording a gate, make the *artifact* the thing reported —
  "paste the `phpcs` output", not "confirm phpcs passes" — so a skipped step is visible
  in the transcript.
- **Re-verification covers `Edit`/`Write` only.** The ledger hook does not see files
  written through the `Bash` tool (shell redirects, `sed -i`) or other write-capable
  tools. This never causes a false green — `contribution-verify` re-runs the full gate
  set every run; the ledger only adds *extra* re-runs after a gate passed mid-session.
  A `Bash`-written change is simply caught by the next full `verify`.
- **Live-fetched governance is authoritative over inline text.** Any AI-policy
  threshold quoted inline in a skill (e.g. the "significant portion" examples) is
  *illustrative*. The binding state is whatever the `ai-policy-checker` agent fetches
  live for the contribution. If a source is unreachable, the AI-policy gate is UNRUN,
  never silently passed.

## Release hygiene

- Run `/plugin-creation-tools:validate --strict` before every release. `--strict`
  promotes S14 (sub-1M `model:` pins on a skill) and other warnings to errors, so the
  inline-overflow footgun cannot slip into a release as a tolerated warning. A release is
  clean only when `--strict` passes.
- Bump `.claude-plugin/plugin.json`, sync the root `.claude-plugin/marketplace.json`
  entry **and** `metadata.version`, add a `CHANGELOG.md` entry, and update `README.md` in
  the same change. One minor bump per PR; one release = one PR.
