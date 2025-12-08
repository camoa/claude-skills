# Writing Agents

Agents are specialized AI assistants with their own context window and custom system prompts. They can be automatically delegated to or manually invoked.

## File Location

Place agent files in:
```
plugin-name/
└── agents/
    ├── code-reviewer.md
    ├── security-checker.md
    └── performance-analyst.md
```

## Basic Structure

```markdown
---
name: agent-name
description: Brief, action-oriented description of when to use this agent
capabilities: ["capability1", "capability2", "capability3"]
tools: Read, Grep, Glob, Bash
model: sonnet
permissionMode: default
skills: skill1, skill2
---

# Agent Name

## Role
Detailed description of the agent's role, expertise, and responsibilities.

## Capabilities
- Specific task the agent excels at
- Another specialized capability
- When to use this agent vs others

## Context and Examples
Provide realistic examples of when this agent should be used and what problems it solves.

## Decision Criteria
How this agent decides what to focus on. Any constraints or special considerations.
```

## Frontmatter Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| name | string | **Yes** | Unique identifier (lowercase, hyphens) |
| description | string | **Yes** | When to invoke; used for auto-delegation |
| capabilities | array | No | List of specific tasks handled |
| tools | string | No | Comma-separated allowed tools |
| model | string | No | Model alias (sonnet, opus, haiku, inherit) |
| permissionMode | string | No | Permission handling mode |
| skills | string | No | Skills to auto-load |

## The Description Field

The description is **critical** for auto-delegation. Claude uses it to decide when to delegate tasks.

**Good descriptions**:
```yaml
# Encourages auto-delegation
description: Security specialist. Use proactively when reviewing code for vulnerabilities.

# Specific trigger conditions
description: Performance analyzer. Use when optimizing slow code or reducing memory usage.
```

**Bad descriptions**:
```yaml
# Too vague
description: Helps with code

# No trigger information
description: Reviews things
```

## Permission Modes

| Mode | Behavior |
|------|----------|
| default | Normal permission handling |
| acceptEdits | Auto-accept edit suggestions |
| bypassPermissions | Skip permission prompts |
| plan | Read-only mode |
| ignore | Ignore permission system |

## Body Content

The body becomes the agent's system prompt. Structure it clearly:

### Role Section

```markdown
## Role
Expert security analyst specializing in vulnerability detection, OWASP compliance,
and secure coding practices. Focus on identifying injection, XSS, and authentication issues.
```

### Capabilities Section

```markdown
## Capabilities
- Identify SQL injection, XSS, and command injection vulnerabilities
- Review authentication and authorization patterns
- Check for insecure dependencies
- Validate input sanitization
- Audit access control implementations
```

### Decision Criteria

```markdown
## Decision Criteria
Focus on:
1. Security-critical code paths (auth, input handling, database)
2. Changes to existing security controls
3. New external integrations

Prioritize by risk:
- Critical: Auth bypass, injection, data exposure
- High: Weak crypto, session issues
- Medium: Missing input validation
- Low: Informational findings
```

## Example Agents

### Code Reviewer Agent

```markdown
---
name: code-reviewer
description: Reviews code changes for quality, bugs, and best practices. Use proactively after code modifications.
capabilities: ["code quality", "bug detection", "best practices"]
tools: Read, Grep, Glob
model: sonnet
---

# Code Reviewer

## Role
Senior code reviewer focused on maintainability, correctness, and adherence to project conventions.

## Capabilities
- Identify logic errors and edge cases
- Check for code style consistency
- Spot performance anti-patterns
- Verify error handling completeness

## Review Process
1. Understand the change context
2. Check for correctness
3. Evaluate maintainability
4. Verify test coverage
5. Provide actionable feedback
```

### Documentation Writer Agent

```markdown
---
name: doc-writer
description: Creates and updates technical documentation. Use when generating README, API docs, or guides.
capabilities: ["technical writing", "API documentation", "user guides"]
tools: Read, Write, Glob
model: sonnet
---

# Documentation Writer

## Role
Technical writer creating clear, comprehensive documentation for developers.

## Capabilities
- Generate README files
- Create API reference documentation
- Write setup and installation guides
- Document configuration options

## Style Guidelines
- Use clear, concise language
- Include code examples
- Structure with headers and lists
- Target the intended audience
```

## Testing Agent Delegation

After creating an agent:

1. Run `/agents` to verify it appears in the list
2. Ask questions matching the description
3. Verify auto-delegation triggers appropriately
4. Adjust description if not triggering

## See Also

- `agent-patterns.md` - best practices and patterns
- `agent-tools.md` - tool configuration
- `../01-overview/what-are-agents.md` - when to use agents
