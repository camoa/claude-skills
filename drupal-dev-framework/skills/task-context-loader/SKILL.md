---
name: task-context-loader
description: Use when starting implementation of a task - loads architecture files, referenced patterns, relevant guides, and task file into context
version: 1.0.0
---

# Task Context Loader

Load all relevant context before starting implementation of a task.

## Triggers

- `/drupal-dev-framework:implement <task>` command
- User says "Work on X task" or "Implement X"
- Starting coding session for a specific component

## Process

1. **Identify task** - Which component/task is being worked on?
2. **Load architecture** - Read component's architecture file
3. **Load patterns** - Fetch referenced core/contrib examples
4. **Load guides** - Get relevant guide sections
5. **Load task file** - If exists in in_progress/
6. **Present context** - Summarize what's loaded

## Files to Load

### Architecture Files
```
~/workspace/claude_memory/{project}/architecture/
├── main.md                    # Overall architecture
└── {component_name}.md        # Specific component
```

### Task Files
```
~/workspace/claude_memory/{project}/implementation_process/
├── in_progress/{task_name}.md  # Current task
└── completed/                   # Reference for related work
```

### Referenced Patterns
From architecture files, extract and load:
- Core module examples
- Contrib module references
- Pattern implementations

### Relevant Guides
Based on task type, load from `~/workspace/claude_memory/guides/`:
- Development workflow guide
- Specific feature guides (ECA, fields, etc.)

## Context Summary Format

```markdown
## Context Loaded for: {Task Name}

### Architecture Summary
{Key points from architecture files}

### Pattern References
- Pattern 1: {brief description}
- Pattern 2: {brief description}

### Relevant Guides
- {Guide}: {applicable sections}

### Task Status
- File: {path}
- Progress: {current step}
- Acceptance criteria: {count} items

### Ready to Implement
The following is ready to code:
1. {item 1}
2. {item 2}

### Dependencies
Code this after:
- {dependency 1}

Code this before:
- {dependent 1}
```

## Integration

After loading context:
- Invoke `tdd-companion` skill for TDD discipline
- Remind about `superpowers:test-driven-development`
- Note `architecture-validator` for validation

## Human Control Points

- User specifies which task to work on
- User can request additional context
- User confirms ready to start coding
