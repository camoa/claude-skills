# Agent Tools

Configure which tools an agent can access and how permissions are handled.

## The tools Field

Specify allowed tools as comma-separated list:

```yaml
tools: Read, Grep, Glob, Bash
```

If omitted, agent inherits all available tools.

## The disallowedTools Field

Explicitly deny specific tools. Removed from inherited or specified tool list:

```yaml
# Allow all tools except Bash and Write
disallowedTools: Bash, Write

# Combined: allow a set, but deny specific ones
tools: Read, Write, Edit, Bash, Glob, Grep
disallowedTools: Bash
```

Use `disallowedTools` when it is easier to exclude a few tools than to list all allowed ones.

> **Note:** `disallowedTools` applies when Claude auto-delegates to the agent based on its description. It does not apply when an agent is spawned explicitly via the Task tool from the main conversation.

## Available Tools

### File Operations

| Tool | Purpose | Risk Level |
|------|---------|------------|
| Read | Read file contents | Low |
| Write | Create new files | Medium |
| Edit | Modify existing files | Medium |
| Glob | Find files by pattern | Low |
| Grep | Search file contents | Low |
| NotebookEdit | Edit Jupyter notebook cells | Medium |

### System Operations

| Tool | Purpose | Risk Level |
|------|---------|------------|
| Bash | Execute shell commands | High |
| WebFetch | Fetch URLs | Medium |
| WebSearch | Search the web | Low |

### Agent and Task Operations

| Tool | Purpose | Risk Level |
|------|---------|------------|
| Task | Spawn subagents (legacy) | Medium |
| TaskCreate | Create a new subagent task | Medium |
| TaskUpdate | Update an existing task | Medium |
| TaskList | List active tasks | Low |
| TaskGet | Get task details and output | Low |
| Skill | Invoke a preloaded skill | Low |
| AskUserQuestion | Prompt the user for input | Low |

### Planning and Discovery

| Tool | Purpose | Risk Level |
|------|---------|------------|
| EnterPlanMode | Switch agent to read-only planning | Low |
| ExitPlanMode | Leave planning mode | Low |
| ToolSearch | Discover and load deferred tools | Low |
| ListMcpResourcesTool | List available MCP resources | Low |
| ReadMcpResourceTool | Read a specific MCP resource | Low |

## MCP Tool Access

Reference MCP tools using the `mcp__server__tool` format:

```yaml
# Allow specific MCP tools
tools: Read, Grep, mcp__slack__send_message, mcp__github__create_issue

# Deny MCP tools
disallowedTools: mcp__slack__send_message
```

Pattern: `mcp__<server-name>__<tool-name>`

The server name matches the key in your MCP configuration. Use `ToolSearch` or `ListMcpResourcesTool` at runtime to discover available MCP tools.

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

Skills are preloaded when the agent activates, injecting specialized knowledge and instructions into the agent's context window. This gives the agent domain expertise without requiring it in the system prompt body.

```yaml
# Agent with skill-provided expertise
name: drupal-reviewer
tools: Read, Grep, Glob
skills: drupal-best-practices, security-review
```

The agent receives all skill content at activation, so keep skill references focused and relevant to avoid context bloat.

## Example Configurations

### Security Auditor

```yaml
name: security-auditor
tools: Read, Grep, Glob
disallowedTools: Bash, Write
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
disallowedTools: Bash
permissionMode: default
```

Can read code and write documentation files. Bash explicitly denied.

### DevOps Agent

```yaml
name: devops
tools: Read, Bash, Glob, mcp__github__create_issue
permissionMode: default
```

Bash access plus specific MCP tool for GitHub integration.

## Best Practices

1. **Principle of Least Privilege**: Only grant needed tools
2. **Prefer disallowedTools for broad access**: When an agent needs most tools but not a few, use `disallowedTools` instead of listing every allowed tool
3. **Consider Risk**: Bash and Write are higher risk
4. **Use MCP patterns for integrations**: Reference MCP tools explicitly rather than granting blanket access
5. **Test Thoroughly**: Verify agent works with limited tools
6. **Review Permissions**: bypassPermissions should be rare

## Tool Access Troubleshooting

### Agent Can't Perform Action

If agent fails on an operation:
1. Check if tool is in `tools` list
2. Check if tool is in `disallowedTools` list (takes precedence)
3. Verify permission mode allows it
4. Check project-level permissions

### Unexpected Permission Prompts

If too many prompts appear:
1. Consider `acceptEdits` for trusted agents
2. Add specific tools rather than all
3. Check if operation needs approval

## See Also

- `writing-agents.md` - full agent structure
- `agent-patterns.md` - design patterns
