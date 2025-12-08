# Agent Patterns

Best practices and patterns for creating effective agents.

## Core Principles

### One Agent = One Responsibility

Each agent should have a single, clear focus:

**Good**:
- `code-reviewer` - Reviews code quality
- `security-checker` - Security vulnerabilities
- `performance-analyst` - Performance optimization

**Bad**:
- `code-helper` - Does everything code-related
- `general-assistant` - No clear focus

### Action-Oriented Descriptions

Write descriptions that trigger delegation:

**Include "Use proactively"**:
```yaml
description: Security specialist. Use proactively when reviewing code for vulnerabilities.
```

**Specify trigger conditions**:
```yaml
description: Performance analyzer. Use when code is slow, memory usage is high, or optimization needed.
```

**Include keywords**:
```yaml
description: Database expert. Use for SQL optimization, query performance, indexing, and schema design.
```

## Description Patterns

### The Proactive Pattern

```yaml
description: [Expertise]. Use proactively when [trigger conditions].
```

Examples:
```yaml
description: Security reviewer. Use proactively after code changes for vulnerability analysis.
description: Test generator. Use proactively when new functions need test coverage.
description: Documentation writer. Use proactively when code lacks documentation.
```

### The Specialist Pattern

```yaml
description: [Domain] specialist for [specific tasks]. Use when [user needs].
```

Examples:
```yaml
description: React specialist for component design and hooks. Use when building React UIs.
description: API specialist for REST design and OpenAPI. Use when designing or documenting APIs.
```

### The Trigger List Pattern

```yaml
description: [Role]. Use when: [trigger1], [trigger2], [trigger3].
```

Example:
```yaml
description: DevOps engineer. Use when: deploying, configuring CI/CD, managing infrastructure.
```

## Capability Organization

### Focused Capabilities

List 3-5 specific, measurable capabilities:

```yaml
capabilities:
  - "Identify SQL injection vulnerabilities"
  - "Review authentication patterns"
  - "Check dependency security"
  - "Validate input sanitization"
```

### Avoid Vague Capabilities

```yaml
# Bad - too vague
capabilities:
  - "Help with code"
  - "Fix issues"
  - "Improve things"

# Good - specific and actionable
capabilities:
  - "Refactor functions over 50 lines"
  - "Extract duplicate code into utilities"
  - "Apply SOLID principles"
```

## Team Patterns

### Complementary Agents

Create agents that work together:

```
agents/
├── code-reviewer.md      # Quality review
├── security-checker.md   # Security review
└── performance-analyst.md # Performance review
```

Each handles one aspect, main Claude coordinates.

### Review Pipeline

```yaml
# First agent checks security
name: security-first-pass
description: Quick security scan. Use proactively on new code before detailed review.

# Second agent does deep review
name: security-deep-dive
description: Detailed security analysis. Use when security-first-pass finds concerns.
```

## Context Management

### Fresh Context Advantage

Agents get their own context window. Use this for:

- **Complex analysis** - No conversation pollution
- **Different perspectives** - Fresh look at code
- **Specialized focus** - Only relevant context

### When NOT to Use Agents

- Simple, quick tasks (use commands)
- Continuous conversation needed (main Claude)
- Shared context important (skills)

## Testing Delegation

### Verify Triggering

After creating agent, test with phrases matching description:

```
# Agent: security-checker
# Description: Security specialist for vulnerability analysis

# Should trigger:
"Check this code for security issues"
"Is there any SQL injection here?"
"Review auth implementation"

# Might not trigger:
"Fix this bug" (not security-focused)
"Write documentation" (different domain)
```

### Adjust If Not Triggering

If agent doesn't trigger when expected:
1. Add more keywords to description
2. Make trigger conditions clearer
3. Include "Use proactively" phrase
4. Test with explicit domain terms

## Anti-Patterns

| Anti-Pattern | Problem | Solution |
|--------------|---------|----------|
| Multi-purpose agent | Confused delegation | Split into focused agents |
| Vague description | Never triggers | Add specific triggers |
| Too many tools | Security risk | Limit to needed tools |
| No capabilities | Unclear scope | List specific tasks |
| Generic name | Hard to find | Use descriptive names |

## See Also

- `writing-agents.md` - agent file structure
- `agent-tools.md` - tool configuration
