---
name: task-context-loader
description: Use when starting implementation of a task - loads architecture files, referenced patterns, relevant guides, and task file into context
version: 1.1.0
---

# Task Context Loader

Load all context needed before implementing a task.

## Activation

Activate when you detect:
- `/drupal-dev-framework:implement <task>` command
- "Work on X task" or "Implement X"
- "Start coding X"
- Beginning a coding session for a component

## Workflow

### 1. Identify Project and Task

Get project path from `project_state.md`. Find the task:
- Check `implementation_process/in_progress/` for matching task file
- If no task file exists, offer to create one via `implementation-task-creator`

### 2. Load Architecture

Use `Read` tool to load:
```
{project_path}/architecture/main.md
{project_path}/architecture/{component}.md (if exists)
```

Extract from architecture:
- Component purpose
- Dependencies
- Pattern references

### 3. Load Task File

Use `Read` on `{project_path}/implementation_process/in_progress/{task}.md`

Extract:
- Objective
- Acceptance criteria
- TDD steps
- Files to create/modify
- Current status/progress

### 4. Load Pattern References

From architecture files, find pattern references like:
```
Based on: core/modules/.../src/...
```

Use `Read` to load the referenced core files. Extract:
- Key method signatures
- Dependency injection patterns
- Implementation approach

### 5. Check for Guides

If `project_state.md` has a guides path, invoke `guide-loader` skill for relevant guides.

### 6. Present Context Summary

Format output as:
```
## Ready to Implement: {Task Name}

### Objective
{from task file}

### Architecture Summary
{key points from architecture}

### Pattern Reference
{primary core file}:
- Key methods to follow: {list}
- Dependencies to inject: {list}

### TDD Approach
1. Test file: {path}
2. First test: {what to test}

### Files to Create/Modify
- {file 1}: {what to do}
- {file 2}: {what to do}

### Acceptance Criteria
- [ ] {criterion 1}
- [ ] {criterion 2}

### Dependencies
Complete these first:
- {prerequisite task, if any}

---
Ready to write the first test?
```

### 7. Activate TDD Companion

After presenting context, remind:
```
TDD reminder: Write test first, then implement.
Use superpowers:test-driven-development for detailed TDD guidance.
```

## Stop Points

STOP and wait for user:
- If task file not found (offer to create)
- After presenting context summary
- If prerequisites are incomplete (ask how to proceed)
