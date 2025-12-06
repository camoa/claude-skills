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
/plugin marketplace add https://github.com/camoa/claude-skills
/plugin install skill-creation-tools@camoa-skills
```

## Plugins

### skill-creation-tools

Guide for creating effective Claude Code skills - covers workflow, progressive disclosure, and validation.

**Skill:** `skill-creation`

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
