# Component Comparison - When to Use What

## Quick Reference Table

| Component | Location | Invocation | Best For |
|-----------|----------|------------|----------|
| CLAUDE.md | `.claude/CLAUDE.md` | Always loaded | Project conventions, always-on rules |
| Skills | `skills/name/SKILL.md` | Model-invoked (auto) | Complex workflows with resources |
| Commands | `commands/name.md` | User (`/command`) | Quick, frequently used prompts |
| Agents | `agents/name.md` | Auto + Manual | Task-specific expertise (subagents) |
| Agent Teams | Multiple agents | Parallel sessions | Independent parallel workstreams (experimental) |
| Hooks | `hooks/hooks.json` | Event-triggered | Automation and validation |
| MCP | `.mcp.json` | Auto startup | External tool integration |

## Context Cost Considerations

Understanding when each feature loads and its context cost helps you choose the right component.

| Component | When Loaded | Context Cost | Stays in Context |
|-----------|-------------|--------------|------------------|
| CLAUDE.md | Every session, always | Low-medium (entire file) | Yes, always present |
| Skills | On-demand when model matches intent | Medium-high (SKILL.md + referenced files) | Yes, for duration of use |
| Commands | On user invocation | Low-medium (command content) | Yes, for that turn |
| Agents (Subagents) | On delegation | None in parent (own context window) | No, returns result only |
| Agent Teams | On orchestration | None in parent per agent | No, each has own context |
| Hooks | On event trigger | None (runs outside context) | No, side-effect only |
| MCP | Session startup | Low (tool definitions only) | Tool schemas always, results per-call |

**Key insight**: CLAUDE.md costs tokens every session. Skills cost tokens only when triggered. Choose accordingly.

## Decision Tree

### 6-Step Decision Process

```
1. Always-on conventions or project rules?
   └── YES → CLAUDE.md

2. Reference material, workflows, or complex guidance?
   └── YES → SKILL

3. External services, APIs, or databases?
   └── YES → MCP SERVER

4. Isolated execution with own context?
   └── YES → SUBAGENT (Agent)

5. Parallel independent workstreams?
   └── YES → AGENT TEAM (experimental)

6. Predictable automation on events?
   └── YES → HOOK
```

**Still unsure?** Ask: should the USER explicitly trigger it? Then use a COMMAND.

### Detailed Decision Questions

**Use CLAUDE.md when:**
- Rules apply to every session in this project
- Conventions should always be enforced
- Content is small enough to justify always-on cost
- Project-specific patterns Claude must always follow

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

**Use an AGENT (Subagent) when:**
- Task requires specialized expertise
- Benefits from fresh context window
- Needs different tool permissions than main
- Should be delegated to automatically
- Complex multi-step operations needing isolation

**Use an AGENT TEAM when (experimental):**
- Multiple independent tasks can run in parallel
- Each task needs its own context window
- Tasks don't depend on each other's intermediate results
- Workload benefits from parallelism

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

## Key Comparisons

### CLAUDE.md vs Skill

| Aspect | CLAUDE.md | Skill |
|--------|-----------|-------|
| Loading | Every session, always | On-demand when matched |
| Context cost | Constant, every turn | Only when triggered |
| Best for | Short rules, conventions | Complex workflows, references |
| Size guidance | Keep small (< 200 lines) | Can be large with references |
| Flexibility | One file, flat | Directory with supporting files |
| Trigger | Automatic, always | Model decides based on description |

**Rule of thumb**: If it's a short rule that always applies, use CLAUDE.md. If it's a detailed workflow or reference, use a Skill.

### Subagent vs Agent Team

| Aspect | Subagent | Agent Team |
|--------|----------|------------|
| Execution | Sequential, one at a time | Parallel, independent sessions |
| Coordination | Parent delegates, child returns | Orchestrator coordinates multiple |
| Context | Own window, returns result | Each agent has own window |
| Use case | Focused single task | Multiple independent tasks |
| Maturity | Stable | Experimental |
| Communication | Parent-child | No inter-agent communication |

### MCP vs Skill

MCP provides **connection**; Skill provides **knowledge**.

| Aspect | MCP Server | Skill |
|--------|------------|-------|
| Purpose | Connect to external tools/services | Provide context, workflows, guidance |
| What it adds | New tool capabilities | Knowledge and decision frameworks |
| Context cost | Tool schemas (low) | Content (medium-high) |
| Runtime | Persistent process | Loaded into context |
| Example | Notion API, database access | "How to write good docs" workflow |

**Pattern**: MCP gives Claude new abilities. Skills tell Claude when and how to use those abilities effectively.

## Combination Patterns

Components work best in combination. Common effective patterns:

### Skill + MCP
Skill provides the workflow knowledge; MCP provides the tool connection.
```
Example: Documentation skill that knows HOW to write docs + Notion MCP that can CREATE pages
```

### Skill + Subagent
Skill orchestrates the workflow; subagent handles isolated subtasks.
```
Example: Code review skill delegates security analysis to a security-focused agent
```

### CLAUDE.md + Skills
CLAUDE.md sets the always-on rules; skills provide on-demand detailed guidance.
```
Example: CLAUDE.md says "always use BEM methodology" + CSS skill provides full BEM workflow
```

### Hook + MCP
Hook triggers on events; MCP executes external actions.
```
Example: PostToolUse hook detects file save → MCP server pushes notification to Slack
```

## Comparison by Characteristic

### Context Management

| Component | Context |
|-----------|---------|
| CLAUDE.md | Always in system prompt |
| Skill | Shares main conversation context |
| Command | Adds to main conversation |
| Agent | Own separate context window |
| Agent Team | Each agent has own context |
| Hook | Runs independently, no conversation |
| MCP | Tool calls, results in context |

### Complexity

| Low | Medium | High |
|-----|--------|------|
| CLAUDE.md, Commands | Skills, Hooks | Agents, Agent Teams, MCP |

### Discovery

| Component | How User Finds It |
|-----------|-------------------|
| CLAUDE.md | Invisible (always active) |
| Command | `/help`, autocomplete |
| Skill | Automatic (model decides) |
| Agent | `/agents`, automatic delegation |
| Hook | Invisible (event-based) |
| MCP | Shows as available tools |

## Common Plugin Combinations

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
| CLAUDE.md as encyclopedia | Token waste every session | Move detailed content to skills |
| Skill for simple rules | Unnecessary complexity | Use CLAUDE.md for short rules |

## See Also

- Individual component guides in respective directories
- `../02-philosophy/decision-frameworks.md` - detailed decision trees
