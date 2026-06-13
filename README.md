# Claude Skills

Custom plugins and tools for Claude Code.

## Background

I started building what I called "frameworks" over a year before Claude officially released Skills. Same concept, different name.

The idea came from frustration. I was tired of repeating the same instructions every conversation. Instead of starting fresh each time, I asked AI to analyze our successful interactions and create frameworks capturing recurring requirements and preferences. These became reusable project knowledge.

This approach produced results: 3 published Drupal contrib modules, 17+ blog articles, automated social media campaigns, and phase-based editorial workflows.

When Claude released Skills officially, I recognized what I'd been building. This repository translates those frameworks into proper Skills with tooling.

I wrote more about this methodology in [My Journey with AI Tools](https://adrupalcouple.us/my-journey-ai-tools-practical-tips-recent-discussion).

## Installation

```bash
# Add the marketplace
/plugin marketplace add https://github.com/camoa/claude-skills

# Install individual plugins
/plugin install dev-guides-navigator@camoa-skills
/plugin install ai-dev-assistant@camoa-skills
/plugin install plugin-creation-tools@camoa-skills
/plugin install brand-content-design@camoa-skills
/plugin install code-quality-tools@camoa-skills
/plugin install drupal-htmx@camoa-skills
/plugin install code-paper-test@camoa-skills
/plugin install drupal-ai-contrib@camoa-skills
```

## Using these plugins outside Claude Code

Skills in this marketplace conform to the open [agentskills.io](https://agentskills.io/specification) standard and work in Cursor, Codex CLI, VS Code Copilot, Gemini CLI, Cline, OpenCode, and more. Commands, agents, and hooks are Claude-Code-specific by format but can be emulated. See **[PORTABILITY.md](PORTABILITY.md)** for the full guide and **[CURSOR.md](CURSOR.md)** for Cursor-specific notes.

## Known Issues

### Skills not auto-discovered on startup

There's a [known bug in Claude Code](https://github.com/anthropics/claude-code/issues/10113) affecting git-based marketplaces. Skills may fail to load during initialization with "no such file or directory" errors because Claude Code looks for skill files in the wrong location.

**Workaround:** Skills still work when invoked via the `Skill` tool (slash commands). The issue only affects automatic discovery at startup.

**Status:** Awaiting fix from Anthropic.

## Plugins

### dev-guides-navigator (v0.1.0)

Smart guide discovery and routing for the [dev-guides](https://camoa.github.io/dev-guides/) site. Routes AI to the correct guide using hash-based caching and KG metadata for disambiguation.

- Caches `llms.txt` with hash-based freshness check — no redundant fetches
- KG metadata (`concepts`/`not` fields) prevents wrong-guide selection (e.g., "story.yml" routes to UI Patterns, not Storybook)
- Two-hop routing: `llms.txt` → topic `index.md` → specific guide
- 1200+ atomic decision guides across 66 topics

```bash
# Invoked automatically before design/dev tasks, or manually:
/dev-guides-navigator style guide
```

### ai-dev-assistant (v5.0.0)

**An AI assistant for developers focused on doing development the right way** — sound process and best practices, not just raw speed. Most AI dev tools optimize for output speed; `ai-dev-assistant` keeps AI-assisted work disciplined — understand the problem before coding, reuse what already exists, follow your standards, verify — and *teaches* best practice as you go. It delivers that through a guided **Research → Architecture → Implementation → Review** workflow with deterministic, anti-bypass gates (SOLID, TDD, DRY, security, code purposefulness). **Requires `dev-guides-navigator`.** Stack-agnostic engine; ships with a Drupal-flavored reference implementation for the deep components (a stack-neutral generalization is in progress).

> **Renamed from `drupal-dev-framework`.** Already using the old plugin? Install `ai-dev-assistant`, then run `/drupal-dev-framework:upgrade` once from the deprecated shell — it migrates your project store and per-project hooks to the new name, after which the old plugin is safe to uninstall. The shell deliberately exposes **only** `/drupal-dev-framework:upgrade` (all old command names route to it); run everything else under the unchanged-name `ai-dev-assistant:` namespace. See [drupal-dev-framework/README.md](drupal-dev-framework/README.md) for the disable/uninstall steps.

```bash
/plugin install dev-guides-navigator@camoa-skills   # Required dependency
/plugin install ai-dev-assistant@camoa-skills

/ai-dev-assistant:new my_project        # Create project
/ai-dev-assistant:next                  # Continue work (main entry point)
```

| Component | Contents |
|-----------|----------|
| Commands | 44 — the full lifecycle (`/new`, `/next`, `/research`, `/research-team`, `/design`, `/implement`, `/complete`, `/review`, `/validate*`, work-orders, visual/E2E review, playbooks, worktrees) |
| Agents | 10 with cost control — project-orchestrator, architecture-drafter, architecture-validator (isolated worktree), pattern-recommender, contrib-researcher, journey-discovery, guides-matcher, analysis, AI test selector, work-order critic |
| Skills | 23 (phase management, TDD companion, guide integration, work-order compiler/loop, context loading) |
| References | methodology docs (SOLID, TDD, DRY, Library-First, Quality Gates, Purposeful Code) + contracts/walkthroughs |
| Hooks | SessionStart (dependency check + project context), PreCompact (context preservation) |

Features competing agent research (`/research-team`) with Build/Use/Extend debate for features and competing hypothesis investigation for bugs.

See [ai-dev-assistant/README.md](ai-dev-assistant/README.md) for full documentation.

### plugin-creation-tools (v2.3.0)

Complete guide for creating Claude Code plugins — skills, commands, agents, hooks, MCP servers, and configuration. Covers 18 hook events, 4 hook types (command/prompt/agent/HTTP), agent isolation and cost control, marketplace distribution with 6 source types, and pushy description optimization.

```bash
# Just describe what you want:
Create a plugin called "my-tools" with a deploy command

# Or use specific commands:
/plugin-creation-tools:create my-tools --skill --agent --hook
/plugin-creation-tools:validate ./my-tools
```

| Component | Contents |
|-----------|----------|
| Skills | 1 (`plugin-creation` — 30+ reference docs, templates, examples) |
| Commands | 3 (`/create`, `/add-component`, `/validate`) |
| Agents | 2 (`skill-quality-reviewer`, `plugin-structure-auditor`) |

### brand-content-design (v2.8.0)

Create branded presentations, LinkedIn carousels, infographics, and HTML pages with consistent visual identity.

```bash
/brand-content-design:brand-init        # Start a new brand project
```

| Component | Contents |
|-----------|----------|
| Commands | 19 (brand management, templates, content creation — quick and guided modes) |
| Skills | 4 (`brand-content-design`, `visual-content`, `infographic-generator`, `html-generator`) |
| Agents | 1 (`brand-analyst` with project memory) |

Features 21 visual styles, 114 infographic templates, HTML design systems with 15 component types, and 17 color palette types.

See [brand-content-design/README.md](brand-content-design/README.md) for full documentation.

### code-quality-tools (v2.7.0)

Code quality and security auditing for **Drupal** (via DDEV) and **Next.js** projects.

```bash
/code-quality-tools:audit               # Full audit with synthesis
/code-quality-tools:review              # Rubric-scored code review
/code-quality-tools:security-debate     # 3-agent security debate
/code-quality-tools:architecture-debate # 3-agent architecture debate
```

| Component | Contents |
|-----------|----------|
| Commands | 11 (`/setup`, `/audit`, `/review`, `/coverage`, `/security`, `/security-debate`, `/architecture-debate`, `/lint`, `/solid`, `/dry`, `/tdd`) |
| Skills | 1 (`code-quality-audit`) |

Security coverage: Drupal (10 layers — PHPStan, Psalm, PHPMD, Semgrep, Trivy, Gitleaks, Roave, Drush, Composer audit, Security Review) and Next.js (7 layers). Optional DAST with OWASP ZAP + Nuclei.

Features rubric-scored code review (/50 with quality gate), cross-audit correlation with prioritized action plans, and two 3-agent debate commands with isolated worktrees.

See [code-quality-tools/README.md](code-quality-tools/README.md) for full documentation.


### drupal-htmx (v1.4.0)

HTMX development guidance and AJAX-to-HTMX migration tools for Drupal 11.3+.

| Component | Contents |
|-----------|----------|
| Commands | 5 (`/htmx`, `/htmx-analyze`, `/htmx-migrate`, `/htmx-pattern`, `/htmx-validate`) |
| Agents | 3 (`ajax-analyzer`, `htmx-recommender`, `htmx-validator`) |
| Skills | 1 (`htmx-development`) |
| References | 4 (quick-reference, htmx-implementation, migration-patterns, ajax-reference) |

See [drupal-htmx/README.md](drupal-htmx/README.md) for full documentation.

### code-paper-test (v0.4.0)

Systematically test code, skills, commands, and configs through mental execution — trace logic line-by-line with concrete values to find bugs, AI hallucinations, edge cases, and contract violations before deployment.

| Component | Contents |
|-----------|----------|
| Skills | 1 (`paper-test` — with data flow tracking, error propagation, config validation, severity scoring) |
| Commands | 1 (`/test-team` — competing agent team with isolated worktrees: Happy Path + Edge Case + Red Team) |
| References | 11 (core method, dependencies, contracts, AI auditing, hybrid testing, common flaws, advanced techniques + state machines, severity scoring, blind A/B comparison, rubric scoring, skill/config testing) |

Tests code AND non-code artifacts: skills, commands, agents, YAML configs. Auto-detects skill files and switches to instruction tracing mode.

See [code-paper-test/README.md](code-paper-test/README.md) for full documentation.

### drupal-ai-contrib (v0.1.0)

AI-assisted Drupal contribution quality — **evidence over assertion**: every gate passes only on a produced, captured artifact, never on an AI assertion. Mirrors the drupalci pipeline locally at CI strictness, gates on the adopted AI-contribution policy, reviews work in fresh-context agents, and confirms the real GitLab pipeline.

```bash
/drupal-ai-contrib:setup     # Onboard + environment-match a contribution workspace
/drupal-ai-contrib:verify    # Local drupalci-parity + AI-policy + eval gates
```

| Component | Contents |
|-----------|----------|
| Commands | 6 (`/setup`, `/issue`, `/verify`, `/review`, `/submit`, `/pipeline`) — the detect-driven contribution arc |
| Skills | 8 (`drupal-ai-contrib` umbrella/router, 6 worker skills, `contribution-guardrails` discipline) |
| Agents | 3 read-only (`fresh-context-reviewer`, `external-fact-verifier`, `ai-policy-checker`) |
| Hooks | PostToolUse (re-verification ledger), SessionStart (contribution-workspace reminder) |

The drupalci-parity gate set (`composer`/`phpcs`/`phpstan`/`phpunit`/`cspell`/`eslint`/`stylelint`) mirrors each enabled `gitlab_templates` job at its real strictness. Cites the `camoa/dev-guides` contribution guides by slug via `dev-guides-navigator`; a contribution is run as an `ai-dev-assistant` task.

See [drupal-ai-contrib/README.md](drupal-ai-contrib/README.md) for full documentation.

## Plugin Conventions

All plugins follow these conventions:

- **CLAUDE.md** at plugin root — plugin-specific rules and conventions
- **`.claude/rules/`** — path-scoped convention files
- **Frontmatter standards** — `version`, `model` routing (haiku/sonnet/opus), `disallowedTools` on read-only agents
- **Progressive disclosure** — SKILL.md under 500 lines; details in `references/`
- **Imperative voice** — skills and commands give instructions, not documentation

## Official Documentation

- [Agent Skills Best Practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)
- [Agent Skills Overview](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview)
- [Claude Code Skills](https://code.claude.com/docs/en/skills)
- [Anthropic Skills Repository](https://github.com/anthropics/skills)

## Related Tools

| Tool | Purpose | Install |
|------|---------|---------|
| [Anthropic skill-creator](https://github.com/anthropics/skills) | Official skill creator | `/plugin install example-skills@anthropic-agent-skills` |
| [Superpowers](https://github.com/obra/superpowers-marketplace) | TDD skill development | `/plugin marketplace add obra/superpowers-marketplace` |
| [Skill Seeker MCP](https://github.com/camoa/skill-seeker) | Automated doc scraping | See repo README |

## Acknowledgments

This marketplace was built collaboratively by Carlos Ospina and Claude (Anthropic). The methodology, frameworks, and domain expertise came from Carlos. Claude contributed code generation, research synthesis, documentation structure, and pattern implementation.

Patterns and insights drawn from:

- [Anthropic Agent Skills](https://github.com/anthropics/skills) — Official skill-creator and best practices (Apache 2.0)
- [Superpowers](https://github.com/obra/superpowers-marketplace) by Jesse Vincent — TDD approach, writing-skills methodology, and cross-platform hooks patterns (MIT)
- [Anthropic Platform Docs](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices) — Official guidelines
- [canvas-design skill](https://github.com/anthropics/skills) — High-quality PDF generation (used by brand-content-design)
- [pptx skill](https://github.com/anthropics/skills) — Editable PowerPoint creation (used by brand-content-design)

## License

MIT
