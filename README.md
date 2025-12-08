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

Systematic Drupal development workflow based on the [Claude Code Drupal Development Framework v3.0](https://adrupalcouple.us).

**Quick Start:**
```
/drupal-dev-framework:next
```

This single command handles everything - project selection, task selection, and next action.

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
Task Complete → Back to Step 2
```

**Key Concepts:**
- Projects have requirements (gathered once)
- Projects contain multiple tasks
- Each task goes through 3 phases independently
- No code until Phase 3 (research and design first)
- TDD enforced in Phase 3

| Component | Contents |
|-----------|----------|
| Skills | 15 skills (phase-detector, requirements-gatherer, tdd-companion, etc.) |
| Commands | 9 commands (/next, /new, /research, /design, /implement, /complete, /status, /validate, /pattern) |
| Agents | 5 agents (project-orchestrator, architecture-drafter, contrib-researcher, pattern-recommender, architecture-validator) |

See [WORKFLOW.md](drupal-dev-framework/WORKFLOW.md) for complete documentation.

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
- [Superpowers](https://github.com/obra/superpowers-marketplace) by Jesse Vincent - TDD approach and writing-skills methodology (MIT)
- [Anthropic Platform Docs](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices) - Official guidelines

## License

MIT
