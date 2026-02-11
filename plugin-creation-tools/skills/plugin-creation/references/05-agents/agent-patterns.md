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

## Agent Team Patterns

Agent teams spawn multiple agents working in parallel with independent context windows. A lead agent orchestrates, assigns tasks, and synthesizes results. Unlike subagents (which report back), teammates can challenge each other's conclusions.

**Requires:** `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` environment variable.

### The Three Execution Models

| | Single Session | Subagents (Task tool) | Agent Teams |
|---|---|---|---|
| **Context** | One window | Own context, results return | Fully independent sessions |
| **Communication** | N/A | Report back only | Message each other via lead |
| **Coordination** | You do everything | You orchestrate | Shared task list, self-claiming |
| **Cost** | Baseline | Moderate (~1.5-3x) | High (~4-10x) |
| **Best for** | Sequential work | Focused lookups, independent research | Competing perspectives, debate |

### The "Debate Threshold" Decision

The real question isn't "can this be parallelized?" — subagents already parallelize. The question is: **"Do the workers need to challenge each other's conclusions?"**

```
Is the task parallelizable?
├── NO → Single session
└── YES → Do workers need to challenge each other?
    ├── NO → Subagents (cheaper, faster)
    └── YES → Do findings need synthesis through debate?
        ├── NO → Subagents with structured output
        └── YES → Agent team
```

### When to Use Agent Teams

| Use Agent Teams When | Use Subagents / Single Session When |
|---------------------|--------------------------------------|
| Multiple perspectives needed that should **debate** | Focused lookup or independent research |
| Competing viewpoints improve quality | One clear approach exists |
| Decision costs more than the tokens spent debating it | Simple or low-stakes task |
| Build vs Use vs Extend decisions | Sequential workflow (TDD, implementation) |
| Attack scenario construction from security findings | Tool execution (use bash parallelism) |

### Poor Fit for Agent Teams
- Tool execution (bash parallelism is free and faster)
- Individual content creation (single voice needed)
- TDD implementation (sequential by design)
- Quality gate checks (independent, no debate needed)
- Dependency verification (report back, no debate)

### Pattern: Competing Perspectives (Debate Team)

Spawn agents with different mandates analyzing the same topic. Lead synthesizes.

**Structure:**
```
Lead (orchestrator)
├── Agent A: Perspective 1 (e.g., "Build custom")
├── Agent B: Perspective 2 (e.g., "Use existing library")
└── Agent C: Perspective 3 (e.g., "Extend contrib module")
```

**Workflow:**
1. Lead defines the question and assigns to all agents
2. Each agent researches independently with its assigned perspective
3. Agents report findings back to lead
4. Lead synthesizes a recommendation weighing all perspectives

**When to use:** Research tasks, architecture decisions, technology selection, buy vs build decisions.

**Example — Feature Research Team:**
```
Lead: Research best approach for [feature]
├── contrib-scout (haiku): Find existing solutions, analyze maturity/maintenance
├── core-finder (haiku): Find core patterns to build on, check roadmap
└── devils-advocate (sonnet): Challenge findings — "Is contrib maintained? Is core pattern outdated?"
```

Cost: ~4x a single subagent but produces a debated Build vs Use vs Extend recommendation instead of a raw list.

**Example — Security Debate Team** (after tool execution):
```
[FIRST: Run security tools in parallel via bash — cheap and fast]
THEN spawn team to analyze results:
├── defender (sonnet): Prioritize by actual exploitability — "Can this be reached from user input?"
├── red-team (sonnet): Chain findings into attack scenarios — "Combine vuln A with config B..."
└── compliance-checker (haiku): Map against OWASP Top 10, identify coverage gaps
```

A single-pass audit gives a flat findings list. A debate team gives **attack scenarios** and **coverage gaps**.

### Pattern: Competing Hypotheses (Investigation Team)

Spawn agents each pursuing a different theory about a problem. Lead validates.

**Structure:**
```
Lead (orchestrator)
├── Agent A: Hypothesis 1 (e.g., "Race condition in auth")
├── Agent B: Hypothesis 2 (e.g., "Cache invalidation bug")
└── Agent C: Hypothesis 3 (e.g., "Database connection leak")
```

**Workflow:**
1. Lead identifies possible root causes and assigns one per agent
2. Each agent investigates their hypothesis with evidence gathering
3. Agents report confidence level and evidence
4. Lead compares evidence, determines most likely cause

**When to use:** Bug investigation, performance debugging, incident response.

**Example — Competing Testers:**
```
Lead: Paper-test [function] for bugs
├── happy-path (sonnet): Trace with ideal inputs, verify intended behavior
├── edge-case-hunter (sonnet): Trace with boundary values, empty/null/huge — "Happy path says X works, but with empty input..."
└── red-team-attacker (sonnet): Adversarial inputs, injection, race conditions — "You both assume trusted input. What if..."
```

Three testers with adversarial mandates find **different categories of bugs** — logic errors, crashes, and security holes. They challenge each other's assumptions.

### Pattern: Parallel Task Execution

Spawn agents for independent implementation tasks.

**Structure:**
```
Lead (orchestrator)
├── Agent A: Task 1 (e.g., "Build API endpoint")
├── Agent B: Task 2 (e.g., "Create frontend component")
└── Agent C: Task 3 (e.g., "Write integration tests")
```

**When to use:** Implementation with clearly independent subtasks, no shared state.

### Team Composition Guidelines

| Consideration | Recommendation |
|--------------|----------------|
| Team size | 2-4 agents (more adds coordination overhead) |
| Agent independence | Each agent should work without needing results from others |
| Communication | Agents communicate through lead, not directly with each other |
| Task granularity | Each agent's task should take 5-15 minutes of work |

### Model Routing by Role

Match model to role for cost efficiency:

| Role | Model | Effort | Why |
|------|-------|--------|-----|
| Scout / Lookup | Haiku | Low | Fast data gathering, no reasoning needed |
| Analyst / Challenger | Sonnet | Medium | Good reasoning at moderate cost |
| Architect / Synthesizer | Opus | High | Complex synthesis, only for lead or final output |
| Compliance / Checklist | Haiku | Low | Structured verification, no creativity |

### Cost Estimates

| Approach | Relative Cost | Output Quality |
|----------|--------------|----------------|
| Single session | 1x | Good for simple tasks |
| 3 subagents (Haiku) | ~1.5x | Parallel data, no synthesis |
| 3 subagents (Sonnet) | ~3x | Parallel analysis, reported back |
| 3 teammates (Haiku scouts + Sonnet challenger) | ~4x | Debated findings, challenged assumptions |
| 3 teammates (all Sonnet) | ~6x | Deep debate, high-quality synthesis |

**Rule of thumb**: Agent teams are worth it when the decision being informed costs more than the tokens spent debating it. A quarterly strategy debate is worth 6x tokens. A routine file lookup is not.

### Implementing Teams in a Plugin

Teams are orchestrated via commands or skills, not agent definitions:

```markdown
# In a command (e.g., commands/research-team.md):

## Workflow
1. Create team with TeamCreate
2. Create tasks with TaskCreate for each perspective
3. Spawn teammates with Task tool (subagent_type + team_name)
4. Agents work independently, report back
5. Lead synthesizes findings
6. Shutdown teammates with SendMessage (type: shutdown_request)
7. Cleanup with TeamDelete
```

Agent definitions (in `agents/`) define what each team member knows. The command/skill defines how they coordinate.

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
