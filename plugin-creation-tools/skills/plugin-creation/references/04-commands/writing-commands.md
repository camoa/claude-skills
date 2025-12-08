# Writing Commands

Commands are markdown files that define slash commands for Claude Code. They provide user-invoked prompts that integrate with the command system.

## File Location

Place command files in:
```
plugin-name/
└── commands/
    ├── review.md
    ├── deploy.md
    └── frontend/        # Creates namespace: /frontend:component
        └── component.md
```

## Basic Structure

```markdown
---
description: Brief description of what the command does
allowed-tools: Bash(git:*), Read, Edit
argument-hint: [argument1] [argument2]
model: claude-3-5-haiku-20241022
---

# Command Name

Detailed instructions for Claude on how to execute this command.
Include specific guidance on parameters, expected outcomes, and special considerations.

## Usage
Instructions on how to use this command with examples.
```

## Frontmatter Fields

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| description | string | **Yes** | - | Brief description (shown in `/help`) |
| allowed-tools | string | No | All | Comma-separated tool list |
| argument-hint | string | No | None | Hint for autocomplete |
| model | string | No | Inherit | Model to use |
| disable-model-invocation | bool | No | false | Prevent auto-invocation |

### disable-model-invocation Explained

When `true`, prevents Claude from invoking this command via the `SlashCommand` tool. The command remains available for direct user invocation (`/command-name`) but Claude cannot trigger it programmatically.

**Use when:**
- Command has side effects (deployments, deletions)
- Command requires explicit human decision
- Command is expensive or rate-limited

```yaml
---
description: Deploy to production (requires manual confirmation)
disable-model-invocation: true
---
```

## Description Best Practices

The description appears in `/help` and autocomplete. Write it well:

**Good**:
```yaml
description: Review current PR for code quality issues and suggest improvements
```

**Bad**:
```yaml
description: PR review
```

Include:
- What the command does
- When to use it
- Key context

## Allowed Tools

Restrict tool access when needed:

```yaml
# Read-only command
allowed-tools: Read, Grep, Glob

# Git operations only
allowed-tools: Bash(git:*)

# Full access
allowed-tools: Read, Edit, Bash, Write
```

If omitted, command inherits all available tools.

## Body Content

The body contains instructions for Claude. Write in imperative voice:

```markdown
# PR Review

Review the current pull request for:
1. Code quality issues
2. Potential bugs
3. Performance concerns
4. Security vulnerabilities

Use `git diff` to see changes. Check each file systematically.
Provide actionable feedback with specific line references.
```

## Example Commands

### Simple Review Command

```markdown
---
description: Quick code review of recent changes
allowed-tools: Bash(git:*), Read, Grep
---

# Quick Review

1. Run `git diff HEAD~1` to see recent changes
2. Identify any obvious issues
3. Provide brief summary of findings
```

### Deployment Command

```markdown
---
description: Deploy to staging environment after running tests
allowed-tools: Bash
argument-hint: [environment]
---

# Deploy

Deploy to the specified environment ($1, defaults to "staging").

1. Run test suite: `npm test`
2. If tests pass, run: `npm run deploy:$1`
3. Verify deployment with health check
4. Report success or failure
```

### Documentation Command

```markdown
---
description: Generate or update README documentation
allowed-tools: Read, Write, Glob
---

# Update README

1. Read existing README.md if present
2. Scan project structure
3. Update or create documentation covering:
   - Project overview
   - Installation
   - Usage
   - Configuration
```

## Naming Conventions

- Use lowercase with hyphens: `review-pr.md`, `deploy-staging.md`
- Be action-oriented: `optimize`, `analyze`, `generate`
- Avoid generic names: `help`, `run`, `do`

## Testing Commands

1. Install the plugin
2. Run `/command-name` with test arguments
3. Verify behavior matches expectations
4. Check `/help` shows correct description

## See Also

- `command-patterns.md` - advanced patterns (bash, files, namespacing)
- `command-arguments.md` - argument handling
- `../01-overview/what-are-commands.md` - when to use commands
