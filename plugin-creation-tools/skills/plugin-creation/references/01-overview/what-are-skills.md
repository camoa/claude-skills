# What Are Skills?

Foundational understanding of Claude Code skills.

## Official Definition

> "Skills extend Claude's capabilities by packaging your expertise into composable resources, transforming general-purpose agents into specialized agents that fit your needs." — Anthropic

## What Skills Provide

1. **Specialized workflows** - Multi-step procedures for specific domains
2. **Tool integrations** - Instructions for working with specific file formats or APIs
3. **Domain expertise** - Company-specific knowledge, schemas, business logic
4. **Bundled resources** - Scripts, references, and assets for complex and repetitive tasks

## Key Characteristics

| Aspect | Description |
|--------|-------------|
| **Model-Invoked** | Claude automatically decides when to use based on description |
| **Progressive Disclosure** | Only loads what's needed, when needed |
| **Procedural Knowledge** | Workflows and expertise, not just reference data |
| **Composable** | Multiple focused skills work better than one large skill |

## Skills vs Other Claude Features

| Feature | Invocation | Use Case |
|---------|------------|----------|
| **Skills** | Automatic (model-invoked) | Specialized capabilities, workflows |
| **Slash Commands** | Manual (`/command`) | Quick shortcuts, explicit actions |
| **MCP Servers** | Tool calls | External service integrations |
| **Projects** | Always loaded | Project context, instructions |
| **Agents** | Task tool | Complex multi-step autonomous work |
| **CLAUDE.md** | Always loaded | Project-specific instructions |

## When to Use Skills vs Alternatives

| Use Case | Best Choice | Why |
|----------|-------------|-----|
| Specialized workflow Claude should auto-detect | **Skill** | Model-invoked, progressive disclosure |
| User must explicitly trigger | **Slash Command** | Manual invocation required |
| External API/service integration | **MCP Server** | Tool calls, real-time data |
| Project-specific context always needed | **CLAUDE.md** | Always in context |
| Complex autonomous multi-step work | **Agent** | Dedicated subprocess |

## Skill Types

### Technique Skills
Teach a method or approach.
- Focus: How-to guidance, examples
- Example: TDD workflow, debugging methodology

### Discipline Skills
Enforce process or prevent mistakes.
- Focus: Rules, rationalization counters
- Example: Verification before completion, code review requirements

### Reference Skills
Provide lookup information.
- Focus: Searchable documentation
- Example: API reference, schema documentation

### Toolkit Skills
Provide utilities and tools.
- Focus: Scripts, integrations
- Example: PDF processing, document creation

## The 5-10 Rule

```
Have you done this task 5+ times?
├─ NO → Don't create skill yet
└─ YES → Will you do it 10+ more times?
    ├─ NO → Consider slash command instead
    └─ YES → Create a skill
```
