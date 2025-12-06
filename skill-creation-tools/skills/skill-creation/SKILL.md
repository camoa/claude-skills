---
name: skill-creation
description: Use when creating, updating, or validating Claude Code skills - provides six-step workflow, progressive disclosure architecture, and reference-first philosophy. Triggers on requests to build skills, package skills, optimize skill descriptions, or troubleshoot skill discovery issues.
---

# Skill Creation

Guide for creating effective Claude Code skills that are discoverable, efficient, and maintainable.

## What Are Skills?

Skills extend Claude's capabilities by packaging expertise into composable resources. They are **model-invoked** (Claude decides when to use them based on description).

See `references/what-are-skills.md` for: definitions, characteristics, comparison with other Claude features.

## Core Philosophy

1. **Claude is already very smart** - Only add context Claude doesn't have
2. **Reference, don't reproduce** - Point to source files, don't copy implementations
3. **Decision-focused** - "When to use X vs Y" not "How to install X"
4. **Context is a public good** - Every token must justify its cost

See `references/core-philosophy.md` for: iron laws, content strategy, degrees of freedom, DRY principle.

## Six-Step Workflow

### Step 1: Understand with Concrete Examples
Clarify exactly how the skill will be used:
- What would a user say that should trigger this skill?
- What are 3-5 concrete usage examples?
- What outputs does the user expect?

### Step 2: Plan Reusable Contents
For each example, identify:
- Scripts to execute repeatedly
- References to load on demand
- Assets to use in output

### Step 3: Initialize
```bash
python scripts/init_skill.py <skill-name> --path <output-dir>
```

### Step 4: Edit the Skill
1. Implement bundled resources (scripts/, references/, assets/)
2. Write SKILL.md answering: purpose, triggers, workflow

**Writing style**: Imperative form ("To accomplish X, do Y")

See `references/writing-skillmd.md` for: voice/style guide, structure, word count targets.
See `references/reference-dont-reproduce.md` for: code example strategy, when to reference vs reproduce.

### Step 5: Validate and Package
```bash
python scripts/validate_skill.py <skill-path>
python scripts/package_skill.py <skill-path>
```

### Step 6: Iterate
Test on real tasks, note struggles, update, re-test.

## Skill Anatomy

```
my-skill/
├── SKILL.md              # Required: triggers, workflow, quick reference
├── scripts/              # Executed without loading into context
├── references/           # Loaded on demand when Claude needs them
└── assets/               # Used in output, never loaded into context
```

## The Description Field

**The most critical part** - determines whether Claude loads your skill.

**Formula:**
```
Use when [specific triggers] - [what it does, third person]
```

**Checklist:**
- Starts with "Use when..."
- Third person (not "you should")
- Includes specific symptoms/triggers
- Includes relevant keywords
- Under 1024 characters (ideal: 200-500)

See: `references/description-patterns.md` for templates by skill type.

## Progressive Disclosure

| Level | Content | When Loaded |
|-------|---------|-------------|
| Metadata | name + description (~100 tokens) | Always |
| SKILL.md body | Core instructions (<5k tokens) | When triggered |
| Bundled resources | scripts, references, assets | On demand |

**Key rule**: Keep SKILL.md under 500 lines. Split into references/ if larger.

## Component Selection

| Content Type | Location |
|--------------|----------|
| Core workflow Claude must know | SKILL.md body |
| Detailed reference (>100 lines) | references/{topic}.md |
| Reusable, tested code | scripts/{name}.py |
| Template/image used in output | assets/{name}/ |
| Everything else | DON'T INCLUDE |

## Quick Validation

```bash
# Check frontmatter
head -20 SKILL.md

# Count lines (target: <500)
wc -l SKILL.md

# Find broken references
grep -o 'references/[^)]*' SKILL.md | while read f; do [ -f "$f" ] || echo "Missing: $f"; done
```

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Copying code that exists elsewhere | Reference file paths instead |
| Description too vague | Add specific triggers, keywords |
| SKILL.md over 500 lines | Split into references/ |
| Untested scripts | Run scripts before packaging |
| First person in description | Use third person: "Use when..." |

## Should You Create a Skill?

**First, check if another approach fits better:**

| Instead of Skill | Use When |
|------------------|----------|
| Slash command | User must trigger explicitly |
| MCP server | External API/service integration |
| Agent definition | Complex autonomous multi-step work |
| CLAUDE.md | Project-specific context |

**The 5-10 Rule**: Done 5+ times? Will do 10+ more? → Create a skill.

**Multiple creation approaches exist** - see `references/creation-approaches.md` for:
- Manual vs Automated (Skill Seeker MCP) vs Hybrid
- When to use each tool
- Decision framework

## References

### Foundational
- `references/what-are-skills.md` - Definitions, characteristics, skill types, comparison with other features
- `references/core-philosophy.md` - Iron laws, content strategy, degrees of freedom, DRY principle
- `references/decision-frameworks.md` - All decision trees: should I create? what type? where does content live?

### Creation Process
- `references/creation-approaches.md` - Manual vs automated vs hybrid, tool installation, comparison matrix
- `references/writing-skillmd.md` - Voice/style, structure, word count targets, progressive disclosure patterns
- `references/reference-dont-reproduce.md` - Code example strategy, format standards, when to reference

### Components & Quality
- `references/description-patterns.md` - Templates for description field by skill type
- `references/bundled-resources.md` - When to use scripts vs references vs assets
- `references/anti-patterns.md` - Common mistakes and how to avoid them
- `references/testing.md` - TDD approach for skills, validation checklists
- `references/quick-reference.md` - Templates, validation commands, size guidelines

## Scripts

- `scripts/init_skill.py` - Initialize new skill directory
- `scripts/validate_skill.py` - Validate skill before packaging
- `scripts/package_skill.py` - Package skill for distribution
