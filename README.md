# Claude Skills

Custom skills and tools for Claude Code.

## Background

I started building what I called "frameworks" over a year before Claude officially released Skills. Same concept, different name.

The idea came from frustration. I was tired of repeating the same instructions every conversation. Instead of starting fresh each time, I asked AI to analyze our successful interactions and create frameworks capturing recurring requirements and preferences. These became reusable project knowledge.

A practical example. After tailoring several resumes and repeatedly saying "don't embellish my experience" or "don't invent technologies I haven't used," I formalized those patterns. No more repeating corrections. The framework already contained my preferences.

This approach produced results.

- 3 published Drupal contrib modules
- 17+ blog articles
- Automated social media campaigns generating 5-10 posts per published piece
- Phase-based editorial workflows with database tracking

When Claude released Skills officially, I recognized what I'd been building. This repository translates those frameworks into proper Skills with tooling.

My original frameworks were instructions and workflow patterns without embedded code. Skills add executable scripts, bundled resources, and automatic invocation. This repo bridges that gap.

I wrote more about this methodology in [My Journey with AI Tools](https://adrupalcouple.us/my-journey-ai-tools-practical-tips-recent-discussion).

## Installation

```bash
# Add the marketplace
/plugin marketplace add https://github.com/camoa/claude-skills

# Install individual plugins
/plugin install plugin-creation-tools@camoa-skills
/plugin install drupal-dev-framework@camoa-skills
/plugin install brand-content-design@camoa-skills
/plugin install code-quality-tools@camoa-skills
```

## Known Issues

### Skills not auto-discovered on startup

There's a [known bug in Claude Code](https://github.com/anthropics/claude-code/issues/10113) affecting git-based marketplaces. Skills may fail to load during initialization with "no such file or directory" errors because Claude Code looks for skill files in the wrong location (marketplace cache instead of the git repository).

**Effects:**
- Skills won't appear in auto-discovery during plugin initialization
- Commands and agents may have similar issues

**Workaround:**
Skills still work when invoked via the `Skill` tool (e.g., typing the skill name or using slash commands) because the SKILL.md header contains the correct path. The issue only affects automatic discovery at startup.

**Status:** Awaiting fix from Anthropic.

## Plugins

### skill-creation-tools [DEPRECATED]

> **Deprecated**: Use `plugin-creation-tools` instead for comprehensive plugin development.

Skills-only guide for creating Claude Code skills. Does not cover commands, agents, hooks, or MCP servers.

| Component | Name |
|-----------|------|
| Skill | `skill-creation` |

### plugin-creation-tools [BETA]

Complete guide for creating Claude Code plugins. Covers skills, commands, agents, hooks, MCP servers, settings, and output configuration.

| Component | Name |
|-----------|------|
| Skill | `plugin-creation` |

**Status:** Beta - comprehensive but still being tested.

**Usage:**

Just tell Claude what you want to create:

```
Create a plugin called "my-tools" with a deploy command
```

```
Add a code formatting hook to my plugin
```

```
Create an agent that reviews code for security issues
```

The skill triggers automatically when you mention creating plugins, skills, commands, agents, or hooks.

**Migration from skill-creation-tools:**

If you have `skill-creation-tools` installed and want to try the beta:

```bash
# Option 1: Keep both (recommended during beta)
/plugin install plugin-creation-tools@camoa-skills

# Option 2: Replace deprecated with beta
/plugin uninstall skill-creation-tools@camoa-skills
/plugin install plugin-creation-tools@camoa-skills
```

### drupal-dev-framework

Systematic Drupal development workflow based on the [Claude Code Drupal Development Framework v3.0](https://adrupalcouple.us). Enforces SOLID, TDD, DRY, security, and code purposefulness principles through 5 quality gates.

**Quick Start:**
```
# Start a new project
/drupal-dev-framework:new my_project

# Continue existing work
/drupal-dev-framework:next
```

**Workflow:**
```
Step 0: Project Selection (lists from registry)
     ↓
Step 1: Requirements (gathered once per project)
     ↓
Step 2: Task Selection (lists existing tasks OR create new)
     ↓
Step 3: Task Phases (each task cycles through):
        Phase 1: Research → Phase 2: Architecture → Phase 3: Implementation
     ↓
Task Complete (5 Quality Gates) → Back to Step 2
```

**Key Concepts:**
- Projects have requirements (gathered once)
- Projects contain multiple tasks
- Each task goes through 3 phases independently
- No code until Phase 3 (research and design first)
- SOLID, TDD, DRY, security, and code purposefulness enforced
- 5 quality gates at task completion

**Built-in References:**
- SOLID principles (Drupal-specific)
- TDD workflow (Red-Green-Refactor)
- DRY patterns (Service, Trait, Component)
- Library-First & CLI-First development
- Security checklist (OWASP)
- Frontend standards (BEM, mobile-first)
- Code Purposefulness (Gate 5)

| Component | Contents |
|-----------|----------|
| Skills | 15 skills (phase-detector, requirements-gatherer, tdd-companion, etc.) |
| Commands | 9 commands (/new, /next, /research, /design, /implement, /complete, /status, /validate, /pattern) |
| Agents | 5 agents (project-orchestrator, architecture-drafter, contrib-researcher, pattern-recommender, architecture-validator) |
| References | 8 reference docs (SOLID, TDD, DRY, Library-First, Quality Gates, Security, Frontend, Code Purposefulness) |

See [WORKFLOW.md](drupal-dev-framework/WORKFLOW.md) for complete documentation.

### brand-content-design

Create branded presentations and carousels with consistent visual identity. Uses a three-layer system: Brand Philosophy → Templates → Content.

**Quick Start:**
```
/brand-content-design:brand-init
```

**The Flow:**
```
Brand Guidelines → Templates → Content
```

1. **Brand Guidelines** - Extract visual & verbal identity once (`/brand-init`)
2. **Templates** - Create reusable slide/card structures (`/template-presentation`, `/template-carousel`)
3. **Content** - Generate presentations/carousels using templates (`/presentation`, `/carousel`)

| Component | Contents |
|-----------|----------|
| Skills | 1 skill (`brand-content-design`) |
| Commands | 11 commands (`/brand-init`, `/brand`, `/brand-palette`, `/template-presentation`, `/template-carousel`, `/presentation`, `/presentation-quick`, `/carousel`, `/carousel-quick`, `/outline`, etc.) |
| Agents | 1 agent (`brand-analyst`) |

**Features:**
- 13 visual styles across 4 aesthetic families (Japanese Zen, Scandinavian, European, East Asian)
- 10 color palette types (harmony-based + tonal variations + custom)
- Wizard-guided template creation
- Quick mode for fast content generation
- Outline templates for content preparation in Claude Projects
- PDF output via `canvas-design` skill
- Editable PPTX via `pptx` skill
- LinkedIn and Instagram carousel support

See [brand-content-design/README.md](brand-content-design/README.md) for complete documentation.

### code-quality-tools

Code quality auditing tools for TDD, SOLID, and DRY principles via DDEV.

| Component | Name |
|-----------|------|
| Skill | `code-quality-audit` |

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

This marketplace was built collaboratively by Carlos Ospina and Claude (Anthropic). The methodology, frameworks, and domain expertise came from Carlos. Claude contributed code generation, research synthesis, documentation structure, and pattern implementation. Neither could have produced this alone.

Patterns and insights drawn from:

- [Anthropic Agent Skills](https://github.com/anthropics/skills) - Official skill-creator and best practices (Apache 2.0)
- [Superpowers](https://github.com/obra/superpowers-marketplace) by Jesse Vincent - TDD approach, writing-skills methodology, and cross-platform hooks patterns (MIT)
- [superpowers-developing-for-claude-code](https://github.com/obra/superpowers-marketplace) by Jesse Vincent - Polyglot hook wrapper technique, troubleshooting patterns, and example plugin structures
- [Anthropic Platform Docs](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices) - Official guidelines
- [Claude Code Settings Docs](https://code.claude.com/docs/en/settings) - Settings hierarchy and configuration patterns
- [canvas-design skill](https://github.com/anthropics/skills) - High-quality PDF generation for presentations and carousels (used by brand-content-design)
- [pptx skill](https://github.com/anthropics/skills) - Editable PowerPoint creation (used by brand-content-design)

## License

MIT
