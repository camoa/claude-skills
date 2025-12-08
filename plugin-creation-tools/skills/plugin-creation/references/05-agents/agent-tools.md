# Agent Tools

Configure which tools an agent can access and how permissions are handled.

## The tools Field

Specify allowed tools as comma-separated list:

```yaml
tools: Read, Grep, Glob, Bash
```

If omitted, agent inherits all available tools.

## Available Tools

### File Operations

| Tool | Purpose | Risk Level |
|------|---------|------------|
| Read | Read file contents | Low |
| Write | Create new files | Medium |
| Edit | Modify existing files | Medium |
| Glob | Find files by pattern | Low |
| Grep | Search file contents | Low |

### System Operations

| Tool | Purpose | Risk Level |
|------|---------|------------|
| Bash | Execute shell commands | High |
| WebFetch | Fetch URLs | Medium |
| WebSearch | Search the web | Low |

### Meta Operations

| Tool | Purpose | Risk Level |
|------|---------|------------|
| Task | Spawn subagents | Medium |
| TodoWrite | Manage task lists | Low |

## Tool Restriction Patterns

### Read-Only Agent

For analysis without modifications:

```yaml
tools: Read, Grep, Glob
```

Use for: Code reviewers, analyzers, auditors

### File Modifier Agent

For agents that need to edit:

```yaml
tools: Read, Write, Edit, Glob, Grep
```

Use for: Refactoring agents, formatters

### Limited Bash Access

Restrict bash to specific commands:

```yaml
tools: Read, Bash(git:*), Bash(npm test:*)
```

Use for: Git helpers, test runners

### Full Access

For agents needing all capabilities:

```yaml
tools: Read, Write, Edit, Bash, Glob, Grep, WebFetch
```

Use sparingly - security implications

## Permission Modes

Control how permissions are requested:

```yaml
permissionMode: default
```

| Mode | Behavior | Use Case |
|------|----------|----------|
| default | Normal prompting | Most agents |
| acceptEdits | Auto-accept edits | Trusted formatters |
| bypassPermissions | Skip all prompts | Automation scripts |
| plan | Read-only mode | Planning agents |
| ignore | Ignore permission system | Testing |

### Default Mode

```yaml
permissionMode: default
```

Agent follows normal permission rules. User prompted for sensitive operations.

### Accept Edits Mode

```yaml
permissionMode: acceptEdits
```

Automatically accepts edit operations. Use for trusted refactoring agents.

### Bypass Permissions

```yaml
permissionMode: bypassPermissions
```

Skip all permission prompts. **Use with extreme caution** - only for fully trusted automation.

### Plan Mode

```yaml
permissionMode: plan
```

Read-only - no modifications allowed. For exploration and analysis agents.

## Skills Integration

Load specific skills into agent context:

```yaml
skills: code-review, testing-patterns
```

Skills are loaded when agent activates, providing specialized knowledge.

## Example Configurations

### Security Auditor

```yaml
name: security-auditor
tools: Read, Grep, Glob
permissionMode: default
```

Read-only access for safe security analysis.

### Code Refactorer

```yaml
name: refactorer
tools: Read, Edit, Grep, Glob
permissionMode: acceptEdits
skills: refactoring-patterns
```

Edit access with auto-accept for efficient refactoring.

### Test Generator

```yaml
name: test-generator
tools: Read, Write, Edit, Bash(npm test:*)
permissionMode: default
skills: testing
```

Can write tests and run npm test commands.

### Documentation Writer

```yaml
name: doc-writer
tools: Read, Write, Glob
permissionMode: default
```

Can read code and write documentation files.

### DevOps Agent

```yaml
name: devops
tools: Read, Bash, Glob
permissionMode: default
```

Bash access for infrastructure commands.

## Best Practices

1. **Principle of Least Privilege**: Only grant needed tools
2. **Consider Risk**: Bash and Write are higher risk
3. **Document Choices**: Explain why tools are included
4. **Test Thoroughly**: Verify agent works with limited tools
5. **Review Permissions**: bypassPermissions should be rare

## Tool Access Troubleshooting

### Agent Can't Perform Action

If agent fails on an operation:
1. Check if tool is in `tools` list
2. Verify permission mode allows it
3. Check project-level permissions

### Unexpected Permission Prompts

If too many prompts appear:
1. Consider `acceptEdits` for trusted agents
2. Add specific tools rather than all
3. Check if operation needs approval

## See Also

- `writing-agents.md` - full agent structure
- `agent-patterns.md` - design patterns
