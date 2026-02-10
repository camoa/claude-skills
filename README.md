# Claude Skills

Custom plugins and tools for Claude Code.

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
/plugin install drupal-htmx@camoa-skills
/plugin install code-paper-test@camoa-skills
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

### plugin-creation-tools (v2.1.0)

Complete guide for creating Claude Code plugins. Covers skills, commands, agents, hooks, MCP servers, settings, and output configuration.

| Component | Contents |
|-----------|----------|
| Skills | 1 skill (`plugin-creation`) |
| Commands | 3 commands (`/create`, `/add-component`, `/validate`) |

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

### drupal-dev-framework (v3.2.0)

Systematic Drupal development workflow. Enforces SOLID, TDD, DRY, security, and code purposefulness principles through 5 quality gates.

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

| Component | Contents |
|-----------|----------|
| Skills | 15 skills (phase-detector, requirements-gatherer, tdd-companion, etc.) |
| Commands | 9 commands (`/new`, `/next`, `/research`, `/design`, `/implement`, `/complete`, `/status`, `/validate`, `/pattern`) |
| Agents | 5 agents (project-orchestrator, architecture-drafter, contrib-researcher, pattern-recommender, architecture-validator) |
| References | 8 reference docs (SOLID, TDD, DRY, Library-First, Quality Gates, Security, Frontend, Code Purposefulness) |

See [WORKFLOW.md](drupal-dev-framework/WORKFLOW.md) for complete documentation.

### brand-content-design (v2.1.0)

Create branded presentations, LinkedIn carousels, infographics, and HTML pages with consistent visual identity. Uses a three-layer system: Brand Philosophy → Templates / Design Systems → Content.

**Quick Start:**
```
/brand-content-design:brand-init
```

**Content Types:**

| Type | Flow | Output |
|------|------|--------|
| Presentations | Template → Content | PDF + PPTX |
| Carousels | Template → Content | Multi-page PDF |
| Infographics | Template → Content | PNG / SVG |
| HTML Pages | Design System → Components → Page | Standalone `.html` |

| Component | Contents |
|-----------|----------|
| Skills | 4 skills (`brand-content-design`, `visual-content`, `infographic-generator`, `html-generator`) |
| Commands | 19 commands (`/brand-init`, `/brand`, `/brand-extract`, `/brand-assets`, `/brand-palette`, `/template-presentation`, `/template-carousel`, `/template-infographic`, `/outline`, `/presentation`, `/presentation-quick`, `/carousel`, `/carousel-quick`, `/infographic`, `/infographic-quick`, `/design-html`, `/html-page`, `/html-page-quick`, `/content-type-new`) |
| Agents | 1 agent (`brand-analyst` with project memory) |

**Features:**
- 21 visual styles across 5 aesthetic families (Japanese Zen, Scandinavian, European, East Asian, Digital Native)
- 114 infographic templates (sequence, list, hierarchy, compare, quadrant, relation, chart)
- HTML design systems with 15 component types and 10 page category presets
- 17 color palette types (10 derived + 7 alternative)
- Visual components (cards, icons, gradients) — style-dependent
- Wizard-guided and quick modes for all content types
- PDF output via `canvas-design` skill, editable PPTX via `pptx` skill

See [brand-content-design/README.md](brand-content-design/README.md) for complete documentation.

### code-quality-tools (v2.3.0)

Code quality and security auditing for **Drupal** (via DDEV) and **Next.js** projects. Supports TDD, SOLID, DRY, and OWASP security checks with Semgrep, Trivy, Gitleaks, and more.

| Component | Contents |
|-----------|----------|
| Skills | 1 skill (`code-quality-audit`) |
| Commands | 8 commands (`/setup`, `/audit`, `/coverage`, `/security`, `/lint`, `/solid`, `/dry`, `/tdd`) |
| Scripts | Drupal + Next.js shell scripts, templates, decision guides |

**Security Coverage:**
- Drupal: 10 layers (PHPStan, Psalm taint, PHPMD, Semgrep, Trivy, Gitleaks, Roave, Drush, Composer audit, Security Review)
- Next.js: 7 layers (npm audit, ESLint security, Semgrep, Trivy, Gitleaks, Socket CLI, custom patterns)
- Optional DAST: OWASP ZAP + Nuclei for pre-production

See [code-quality-tools/README.md](code-quality-tools/README.md) for complete documentation.

### drupal-htmx (v1.1.0)

HTMX development guidance and AJAX-to-HTMX migration tools for Drupal 11.3+.

| Component | Contents |
|-----------|----------|
| Skills | 1 skill (`htmx-development`) |
| Commands | 5 commands (`/htmx`, `/htmx-analyze`, `/htmx-migrate`, `/htmx-pattern`, `/htmx-validate`) |
| Agents | 3 agents (`ajax-analyzer`, `htmx-recommender`, `htmx-validator`) |
| References | 4 reference docs (quick-reference, htmx-implementation, migration-patterns, ajax-reference) |

See [drupal-htmx/README.md](drupal-htmx/README.md) for complete documentation.

### code-paper-test (v0.2.0)

Systematically test code through mental execution — trace code line-by-line with concrete values to find bugs, logic errors, missing code, edge cases, and contract violations before deployment.

| Component | Contents |
|-----------|----------|
| Skills | 1 skill (`paper-test`) |
| References | 7 reference docs (core-method, dependency-verification, contract-patterns, ai-code-auditing, hybrid-testing, common-flaws, advanced-techniques) |

See [code-paper-test/README.md](code-paper-test/README.md) for complete documentation.

## Plugin Conventions

All plugins in this marketplace follow these conventions:

- **CLAUDE.md** at plugin root — defines plugin-specific rules and conventions
- **`.claude/rules/`** — path-scoped convention files (skill-conventions.md, command-conventions.md, agent-conventions.md)
- **Frontmatter standards** — `version`, `model` routing (haiku/sonnet/opus), `disallowedTools` on read-only agents
- **Progressive disclosure** — SKILL.md stays under 500 lines; detailed content goes in `references/`
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
