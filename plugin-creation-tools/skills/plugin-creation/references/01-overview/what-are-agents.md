# What Are Agents (Subagents)?

Agents are specialized AI assistants with their own context window, custom system prompt, and configurable tool permissions. They can be automatically delegated to based on context or manually invoked.

## Key Characteristics

- **Own separate context window** (prevents main conversation pollution)
- Custom system prompts for specialized expertise
- Configurable tool permissions
- Automatic delegation based on context
- Can be manually invoked
- Appear in `/agents` interface

## When to Use Agents

**Good Use Cases**:
- Task-specific expertise areas (code review, security analysis)
- Different tool permission levels
- Team workflows requiring specialized knowledge
- Complex, multi-step operations
- Tasks that benefit from a fresh context

**Examples**:
- Security reviewer that checks for vulnerabilities
- Performance analyst for optimization
- Documentation writer
- Test generator

## Agents vs Other Components

| Aspect | Agents | Commands | Skills |
|--------|--------|----------|--------|
| Invocation | Auto + Manual | User (`/command`) | Model-invoked |
| Context | Own window | Included in command | Shared with main |
| Files | Single .md | Single .md | Directory + SKILL.md |
| Best For | Task expertise | Quick prompts | Complex workflows |

## Built-in Agent Types

Claude Code includes built-in agents:

| Agent | Purpose |
|-------|---------|
| general-purpose | Complex multi-step tasks with read+write access |
| Plan | Read-only codebase exploration in plan mode |
| Explore | Fast, lightweight, read-only with Haiku |

## File Location

```
plugin-name/
└── agents/
    ├── code-reviewer.md
    ├── security-checker.md
    └── performance-analyst.md
```

## Basic Format

```markdown
---
name: security-reviewer
description: Reviews code for security vulnerabilities. Use proactively after code changes.
capabilities: ["vulnerability detection", "OWASP compliance", "dependency audit"]
tools: Read, Grep, Glob
model: sonnet
permissionMode: default
---

# Security Reviewer

## Role
Expert security analyst specializing in vulnerability detection and code hardening.

## Capabilities
- Identify injection vulnerabilities (SQL, XSS, command)
- Check for insecure dependencies
- Verify authentication patterns

## When to Use
- After code changes
- Before merges to main
- During security audits
```

## Auto-Delegation

Include "Use proactively" in the description for automatic delegation:

```
description: Security specialist. Use proactively when reviewing code for vulnerabilities.
```

## See Also

- `../05-agents/writing-agents.md` - how to write agents
- `../05-agents/agent-patterns.md` - best practices
- `../05-agents/agent-tools.md` - tool configuration
