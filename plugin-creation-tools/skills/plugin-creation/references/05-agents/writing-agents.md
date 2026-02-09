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
disallowedTools: WebFetch, WebSearch
model: sonnet
memory: project
permissionMode: default
skills: skill1, skill2
hooks:
  preToolCall:
    - matcher: Write
      command: echo "Write operation triggered"
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
| disallowedTools | string | No | Tools to explicitly deny (takes precedence over tools) |
| model | string | No | `haiku`, `sonnet`, `opus`, or `inherit` |
| memory | string | No | `user`, `project`, or `local` |
| permissionMode | string | No | Permission handling mode |
| skills | string | No | Skills to preload into agent context |
| hooks | object | No | Hooks scoped to this agent (same format as hooks.json) |

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

## Model Selection

Choose the model based on task complexity and cost:

| Model | Best For | Cost |
|-------|----------|------|
| haiku | Simple, focused tasks (formatting, linting, lookups) | Lowest |
| sonnet | Balanced tasks (code review, documentation, refactoring) | Medium |
| opus | Complex reasoning (architecture decisions, security analysis) | Highest |
| inherit | Use whatever model the parent session uses | Varies |

```yaml
# Cost-efficient: simple file lookups
model: haiku

# Default for most agents
model: sonnet

# Complex multi-step reasoning
model: opus
```

If omitted, the agent inherits the parent session's model.

## Memory Configuration

Memory controls cross-session learning for the agent.

| Mode | Scope | Use Case |
|------|-------|----------|
| user | All projects for current user | Personal coding preferences, universal patterns |
| project | Current project only | Project conventions, architecture decisions |
| local | Not shared | Temporary or sensitive tasks |

```yaml
# Agent remembers project conventions across sessions
memory: project

# Agent learns user preferences across all projects
memory: user

# No cross-session memory
memory: local
```

If omitted, the agent has no persistent memory.

## Permission Modes

| Mode | Behavior |
|------|----------|
| default | Normal permission handling |
| acceptEdits | Auto-accept edit suggestions |
| bypassPermissions | Skip permission prompts |
| plan | Read-only mode |
| ignore | Ignore permission system |

## Hooks

Scope hooks to a specific agent using the same format as `hooks.json`:

```yaml
hooks:
  preToolCall:
    - matcher: Bash
      command: echo "Bash command intercepted"
  postToolCall:
    - matcher: Write
      command: echo "File written: $TOOL_INPUT"
```

Hooks run only when this agent is active.

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
disallowedTools: Bash, Write
model: sonnet
memory: project
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

### Quick Lookup Agent

```markdown
---
name: quick-lookup
description: Fast file and symbol lookups. Use when finding definitions, references, or file locations.
capabilities: ["file search", "symbol lookup", "reference finding"]
tools: Read, Grep, Glob
model: haiku
memory: local
permissionMode: plan
---

# Quick Lookup

## Role
Fast, cost-efficient lookup agent for finding files, symbols, and references.

## Capabilities
- Find file locations by name or pattern
- Locate function and class definitions
- Search for symbol references
- Read specific file contents
```

### Architecture Advisor Agent

```markdown
---
name: architecture-advisor
description: Evaluates architecture decisions and system design. Use for complex design questions or reviewing structural changes.
capabilities: ["architecture review", "design patterns", "system design"]
tools: Read, Grep, Glob
model: opus
memory: project
permissionMode: plan
skills: design-patterns
---

# Architecture Advisor

## Role
Senior architect providing guidance on system design, patterns, and structural decisions.

## Capabilities
- Evaluate architectural trade-offs
- Recommend design patterns
- Review system boundaries and interfaces
- Assess scalability implications

## Decision Criteria
Consider:
1. Maintainability and complexity
2. Performance and scalability
3. Team conventions and existing patterns
4. Long-term evolution of the codebase
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
