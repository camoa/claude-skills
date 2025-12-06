---
name: session-resume
description: Use when resuming work on existing project - reads project_state.md, summarizes current state, identifies where to continue
version: 1.0.0
---

# Session Resume

Restore context when continuing work on an existing project in a new session.

## Triggers

- Starting new Claude session on existing project
- User says "Resume project X" or "Continue where I left off"
- Opening project after break

## Process

1. **Locate project** - Find in ~/workspace/claude_memory/
2. **Read state** - Load project_state.md
3. **Detect phase** - Use phase-detector skill
4. **Load context** - Get relevant architecture/task files
5. **Summarize** - Present current state to user
6. **Recommend** - Suggest next action

## Information to Gather

### From project_state.md
- Current phase
- Recent decisions
- Current focus
- Blockers (if any)

### From architecture/
- Overall design status
- Component designs
- Open questions

### From implementation_process/
- Tasks in progress
- Recently completed tasks
- Remaining tasks

## Output Format

```markdown
## Session Resume: {Project Name}

### Quick Summary
{One sentence on project purpose}

### Current State
- **Phase:** {1/2/3} - {Name}
- **Last Updated:** {date from project_state.md}
- **Status:** {current status}

### Recent Progress
{What was accomplished in last session}

### Current Focus
{What was being worked on}

### In Progress
| Task | Status | File |
|------|--------|------|
| {task name} | {progress} | `in_progress/{file}` |

### Key Decisions Made
- {Recent decision 1}
- {Recent decision 2}

### Open Questions
- {Question needing resolution}

### Recommended Next Action
**{Action}** - {reason}

Use: `{command or skill to invoke}`

### Alternative Actions
1. {Alternative 1}
2. {Alternative 2}
```

## Context Restoration

Offer to load:
- Last worked-on task file
- Related architecture files
- Relevant guides

Ask: "Would you like me to load the context for {current task}?"

## Session Start Hook

This skill can be auto-invoked via SessionStart hook when:
- Project folder is detected
- User mentions project name
- Working directory contains project files

## Human Control Points

- User confirms project to resume
- User chooses next action
- User can request different context
