---
description: Suggest next action based on project state
allowed-tools: Read, Glob, Task
argument-hint: [project-name]
---

# Next

Get recommendation for what to do next based on project state.

## Usage

```
/drupal-dev-framework:next                # Current project
/drupal-dev-framework:next my_module      # Specific project
```

## What This Does

1. Invokes `project-orchestrator` agent
2. Analyzes current state
3. Considers phase requirements
4. Suggests prioritized next actions

## Output Format

```markdown
## Recommended Next Action

**Action:** {What to do}
**Command:** {Command to run}
**Reason:** {Why this is the priority}

### Context
{Brief explanation of current state}

### Alternative Actions
1. {Alternative 1} - {when to choose this instead}
2. {Alternative 2} - {when to choose this instead}

### Blockers (if any)
- {Blocker description}
- {How to resolve}
```

## Decision Logic

### Phase 1 (Research)
Priority order:
1. Gather requirements (if not done)
2. Research existing solutions
3. Validate research complete → Move to Phase 2

### Phase 2 (Architecture)
Priority order:
1. Design overall architecture (if not done)
2. Design remaining components
3. Validate architecture → Move to Phase 3

### Phase 3 (Implementation)
Priority order:
1. Complete current in-progress task
2. Start next priority task
3. All tasks complete → Project done

## Examples

```
/drupal-dev-framework:next

Recommended: Research existing solutions
Command: /drupal-dev-framework:research content workflow
Reason: Requirements gathered but no research files exist yet.
```

```
/drupal-dev-framework:next

Recommended: Continue implementing settings form
Command: /drupal-dev-framework:implement settings_form
Reason: Task in progress, 2/5 acceptance criteria met.
```

## Related Commands

- `/drupal-dev-framework:status` - Full status overview
