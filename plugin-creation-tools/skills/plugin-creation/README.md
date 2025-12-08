# skill-creation

Guide for creating effective Claude Code skills.

## Triggers

- "I want to create a skill"
- "How do I package a skill?"
- "My skill isn't being discovered"

## Quick Start

```bash
# Initialize
python scripts/init_skill.py my-skill --path ./skills

# Validate
python scripts/validate_skill.py ./skills/my-skill

# Package
python scripts/package_skill.py ./skills/my-skill
```

## Structure

```
skill-creation/
├── SKILL.md           # Core workflow (read first)
├── scripts/           # init, validate, package
└── references/        # Detailed guides (11 files)
```

## Official Anthropic Docs

- [Agent Skills Best Practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)
- [Agent Skills Overview](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview)
- [Anthropic Skills Repository](https://github.com/anthropics/skills)

## Related Tools

- [Anthropic skill-creator](https://github.com/anthropics/skills) - Official creator
- [Superpowers writing-skills](https://github.com/obra/superpowers-marketplace) - TDD approach
- [Skill Seeker MCP](https://github.com/camoa/skill-seeker) - Automated scraping
