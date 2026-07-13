# Claude Skills

A marketplace of Claude Code plugins built on one idea: **AI is fast; these tools make the parts it likes to skip hard to skip.** The gates enforce your standards, the guides keep the AI working from current best practice instead of stale training data, and you make every decision. The reasoning behind that is in [PHILOSOPHY.md](PHILOSOPHY.md).

## What it looks like in practice

The flagship, `ai-dev-assistant`, run on a single task:

```text
$ /ai-dev-assistant:scope rss_feed      # you set the goal and success criteria (or confirm a draft)
$ /ai-dev-assistant:research rss_feed   # finds drupal/views_rss already covers ~80%: reuse, don't rebuild
$ /ai-dev-assistant:design rss_feed     # approach and acceptance criteria
$ /ai-dev-assistant:implement rss_feed  # test-first
$ /ai-dev-assistant:review rss_feed     # tdd / solid / security gates pass, PR body written
```

It never picked your architecture for you. It just refused to skip the scope, the existing-solution check, the tests, or the review, and it left everything it did on disk, so a decision that later looks wrong is a file you open. That is the idea behind all of these plugins.

None of it is perfect. The AI still slips a step past us now and then, and when it does, that gap becomes the next gate we add. See [PHILOSOPHY.md](PHILOSOPHY.md) for the fuller picture.

## Installation

```bash
# Add the marketplace
/plugin marketplace add https://github.com/camoa/claude-skills

# Install the plugins you want
/plugin install ai-dev-assistant@camoa-skills        # pulls dev-guides-navigator automatically
/plugin install dev-guides-navigator@camoa-skills
/plugin install plugin-creation-tools@camoa-skills
/plugin install code-quality-tools@camoa-skills
/plugin install code-paper-test@camoa-skills
/plugin install drupal-ai-contrib@camoa-skills
/plugin install drupal-htmx@camoa-skills
/plugin install brand-content-design@camoa-skills
```

Each plugin's README has its own requirements, worked examples, and a `docs/usage.md`. Versions and component counts live there and in each `CHANGELOG.md`, not here, so this page does not go stale.

## Using these plugins outside Claude Code

The skills conform to the open [agentskills.io](https://agentskills.io/specification) standard and work in Cursor, Codex CLI, VS Code Copilot, Gemini CLI, Cline, OpenCode, and more. Commands, agents, and hooks are Claude-Code-specific by format but can be emulated. See **[PORTABILITY.md](PORTABILITY.md)** for the full guide and **[CURSOR.md](CURSOR.md)** for the highest-fidelity option.

## The plugins, by the problem each solves

### Building software

**[ai-dev-assistant](ai-dev-assistant/README.md)**: *The AI jumps straight to code: it skips understanding the problem, misses a library that already exists, drifts from your standards, and forgets the tests.* Runs any coding task through a required scope contract, then research, design, implement, and review, with gates it cannot quietly skip. Works on any stack (process recipes carry the framework specifics) and on Claude Code plugin work too. This is the flagship; most of the others plug into its gates.

**[dev-guides-navigator](dev-guides-navigator/README.md)**: *The model writes code from whatever it remembered at training time, which is often out of date.* Routes each task to the current best-practice guide from a catalog of 1200+ atomic decision guides, hash-cached so nothing is re-fetched. Required by `ai-dev-assistant`; useful on its own.

**[plugin-creation-tools](plugin-creation-tools/README.md)**: *Building a Claude Code plugin means guessing at the structure of skills, commands, agents, hooks, and MCP servers.* An authoring and audit toolkit with a `validate` gate that catches structural problems (and leaked home-paths or secrets) before you publish.

### Checking the work

**[code-quality-tools](code-quality-tools/README.md)**: *Is this code actually safe and sound, or does it just run?* TDD, SOLID, and DRY checks plus multi-layer security scanning (Semgrep, Trivy, Gitleaks, and more) for Drupal and Next.js. Powers `ai-dev-assistant`'s quality gates.

**[code-paper-test](code-paper-test/README.md)**: *Does this code, skill, or config actually do what it claims, before you run it in anger?* Mental-execution testing that traces logic line by line with concrete values, plus an adversarial test-team, to surface bugs, edge cases, and AI hallucinations. Part of the review method for plugin work.

### Drupal

**[drupal-ai-contrib](drupal-ai-contrib/README.md)**: *AI-assisted Drupal.org contributions get bounced for unverified claims and policy misses.* Evidence-over-assertion gates that mirror the drupalci pipeline locally at CI strictness and check the AI-contribution policy, so a contribution passes only on a produced artifact, never an assertion.

**[drupal-htmx](drupal-htmx/README.md)**: *Migrating Drupal AJAX to HTMX by hand is fiddly and easy to get wrong.* HTMX patterns and an AJAX-to-HTMX migration path for Drupal 11.3+.

### Content and brand

**[brand-content-design](brand-content-design/README.md)**: *Every deck, carousel, and one-pager drifts a little further from the brand.* Branded presentations, carousels, infographics, and HTML pages generated from one shared brand and design system.

### Deprecated

**drupal-dev-framework** is the old name of `ai-dev-assistant`, kept only as a one-time migration shell. If you are still on it, [its README](drupal-dev-framework/README.md) has the `/drupal-dev-framework:upgrade` steps; otherwise you can ignore it.

## Background

I started building what I called "frameworks" over a year before Claude officially released Skills. Same concept, different name. The idea came from frustration: I was tired of repeating the same instructions every conversation, so I asked AI to analyze our successful interactions and capture the recurring requirements and preferences as reusable project knowledge. That produced real work: 3 published Drupal contrib modules, 17+ blog articles, automated social campaigns, and phase-based editorial workflows. When Claude released Skills officially, I recognized what I had been building, and this repository translates those frameworks into proper Skills with tooling. More on the methodology: [My Journey with AI Tools](https://adrupalcouple.us/my-journey-ai-tools-practical-tips-recent-discussion).

## Contributing

Conventions, plugin structure, and the review bar are in [CONTRIBUTING.md](CONTRIBUTING.md) and [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md). In short: `CONVENTIONS.md` at each plugin root (not a plugin-root `CLAUDE.md`, which Claude Code does not load), path-scoped `.claude/rules/`, version and model routing in frontmatter, and progressive disclosure (SKILL.md lean, detail in `references/`).

## Official documentation

- [Agent Skills Best Practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)
- [Agent Skills Overview](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview)
- [Claude Code Skills](https://code.claude.com/docs/en/skills)
- [Anthropic Skills Repository](https://github.com/anthropics/skills)

## Related tools

| Tool | Purpose | Install |
|------|---------|---------|
| [Anthropic skill-creator](https://github.com/anthropics/skills) | Official skill creator | `/plugin install example-skills@anthropic-agent-skills` |
| [Superpowers](https://github.com/obra/superpowers-marketplace) | TDD skill development | `/plugin marketplace add obra/superpowers-marketplace` |

## Acknowledgments

Built collaboratively by Carlos Ospina and Claude (Anthropic). The methodology, frameworks, and domain expertise came from Carlos; Claude contributed code generation, research synthesis, documentation structure, and pattern implementation. Patterns and insights drawn from:

- [Anthropic Agent Skills](https://github.com/anthropics/skills): official skill-creator and best practices (Apache 2.0)
- [Superpowers](https://github.com/obra/superpowers-marketplace) by Jesse Vincent: TDD approach, writing-skills methodology, cross-platform hooks patterns (MIT)
- [canvas-design skill](https://github.com/anthropics/skills): high-quality PDF generation (used by brand-content-design)
- [pptx skill](https://github.com/anthropics/skills): editable PowerPoint creation (used by brand-content-design)

## License

MIT
