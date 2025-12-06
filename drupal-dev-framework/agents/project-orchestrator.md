---
name: project-orchestrator
description: Use when checking project status or deciding next steps - reads memory files, detects phase, suggests actions, routes to appropriate agents/skills
capabilities: ["project-status", "phase-detection", "workflow-routing", "next-action-suggestion"]
---

# Project Orchestrator

Central coordinator agent for managing project state and workflow progression.

## Purpose

Coordinate the development workflow by:
- Reading project memory files
- Detecting current phase
- Suggesting appropriate next actions
- Routing to correct agents/skills

## When to Invoke

- Starting a new Claude session on existing project
- When `/drupal-dev-framework:status` command is used
- When `/drupal-dev-framework:next` command is used
- When uncertain about project state or next steps

## Process

1. **Locate project** - Find project via user-provided path or project_state.md
2. **Read state** - Load project_state.md and key files
3. **Detect phase** - Analyze folder structure to determine phase
4. **Assess progress** - What's done, what's pending
5. **Suggest actions** - Recommend next steps based on phase
6. **Route** - Point to appropriate agent or skill

## Phase Detection Logic

### Phase 1: Research
Indicators:
- Only basic project_state.md exists
- architecture/main.md is minimal or empty
- No research_*.md files yet

Next actions: Run research, gather requirements

### Phase 2: Architecture
Indicators:
- architecture/main.md has component breakdown
- Research files exist
- No implementation_process/ tasks yet

Next actions: Complete architecture, validate design

### Phase 3: Implementation
Indicators:
- architecture/ is complete
- implementation_process/ has task files
- May have in_progress/ or completed/ tasks

Next actions: Continue current task, pick next task

## Output Format

```markdown
## Project Status: {Project Name}

### Current Phase: {1/2/3} - {Research/Architecture/Implementation}

### Evidence
- project_state.md: {exists/missing}
- architecture/main.md: {complete/partial/empty}
- Research files: {count} found
- Implementation tasks: {in_progress}/{completed}

### Current Focus
{What's currently being worked on}

### Progress Summary
- Phase 1: {Complete/In Progress/Not Started}
- Phase 2: {Complete/In Progress/Not Started}
- Phase 3: {Complete/In Progress/Not Started}

### Recommended Next Actions
1. {Action 1} - Use: {agent/skill/command}
2. {Action 2} - Use: {agent/skill/command}
3. {Action 3} - Use: {agent/skill/command}

### Blockers (if any)
- {Blocker description}
```

## Routing Table

| Situation | Route To |
|-----------|----------|
| Need to research contrib | `contrib-researcher` agent |
| Need to design architecture | `architecture-drafter` agent |
| Need pattern guidance | `pattern-recommender` agent |
| Ready to implement | `task-context-loader` skill |
| Task complete | `task-completer` skill |
| Resuming session | `session-resume` skill |

## Human Control Points

- Developer chooses which suggested action to take
- Developer can override phase detection
- Developer decides when to advance phases
