# Component Comparison - When to Use What

## Quick Reference Table

| Component | Location | Invocation | Best For |
|-----------|----------|------------|----------|
| Skills | `skills/name/SKILL.md` | Model-invoked (auto) | Complex workflows with resources |
| Commands | `commands/name.md` | User (`/command`) | Quick, frequently used prompts |
| Agents | `agents/name.md` | Auto + Manual | Task-specific expertise |
| Hooks | `hooks/hooks.json` | Event-triggered | Automation and validation |
| MCP | `.mcp.json` | Auto startup | External tool integration |

## Decision Tree

### Start Here: What triggers this capability?

```
1. Should the USER explicitly trigger it?
   └── YES → COMMAND

2. Should Claude trigger it automatically based on context?
   └── YES → SKILL or AGENT
       ├── Needs own context window? → AGENT
       └── Shares conversation context? → SKILL

3. Should it run automatically on events?
   └── YES → HOOK

4. Does it need external tools/APIs?
   └── YES → MCP SERVER
```

### Detailed Decision Questions

**Use a SKILL when:**
- Complex workflow with multiple steps
- Needs supporting files (scripts, references, templates)
- Claude should decide when to use it
- Benefits from progressive disclosure of resources
- Shares context with main conversation

**Use a COMMAND when:**
- User should control when it runs
- Simple, quick operation
- Frequently used prompt
- No supporting resources needed
- Explicit trigger is important

**Use an AGENT when:**
- Task requires specialized expertise
- Benefits from fresh context window
- Needs different tool permissions than main
- Should be delegated to automatically
- Complex multi-step operations

**Use a HOOK when:**
- Should run on specific events
- Automation without user intervention
- Validation before/after operations
- Logging and audit trails
- Session setup/cleanup

**Use MCP SERVER when:**
- External API integration needed
- Database access required
- Custom tools beyond Claude's built-ins
- Third-party service integration

## Comparison by Characteristic

### Context Management

| Component | Context |
|-----------|---------|
| Skill | Shares main conversation context |
| Command | Adds to main conversation |
| Agent | Own separate context window |
| Hook | Runs independently, no conversation |
| MCP | Tool calls, results in context |

### Complexity

| Low | Medium | High |
|-----|--------|------|
| Commands | Skills, Hooks | Agents, MCP |

### Discovery

| Component | How User Finds It |
|-----------|-------------------|
| Command | `/help`, autocomplete |
| Skill | Automatic (model decides) |
| Agent | `/agents`, automatic delegation |
| Hook | Invisible (event-based) |
| MCP | Shows as available tools |

## Common Combinations

### Code Quality Plugin
```
├── skills/code-audit/       # Complex audit workflow
├── commands/quick-lint.md   # Quick user-triggered lint
├── hooks/hooks.json         # Auto-format on save
└── agents/security-review.md # Security expertise
```

### Deployment Plugin
```
├── commands/deploy.md       # User-triggered deploy
├── commands/status.md       # Check status
├── hooks/hooks.json         # Pre-deploy validation
└── .mcp.json               # Cloud provider API
```

### Documentation Plugin
```
├── skills/doc-writer/       # Complex doc generation
├── agents/doc-reviewer.md   # Review expertise
└── commands/readme.md       # Quick README update
```

## The 5-10 Rule

**Create a skill or command when:**
- Done 5+ times
- Will do 10+ more times

**Don't create when:**
- One-off task
- Simple enough to type directly
- Project-specific (use CLAUDE.md instead)

## Anti-Patterns

| Anti-Pattern | Problem | Solution |
|--------------|---------|----------|
| Everything as commands | User fatigue | Use skills for auto-trigger |
| Multi-purpose agents | Confused delegation | One agent = one task |
| Global hook matchers | Performance impact | Specific matchers |
| MCP for simple things | Over-engineering | Use commands/skills |

## See Also

- Individual component guides in respective directories
- `../02-philosophy/decision-frameworks.md` - detailed decision trees
