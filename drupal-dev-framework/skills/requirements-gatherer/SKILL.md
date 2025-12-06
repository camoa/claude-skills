---
name: requirements-gatherer
description: Use when gathering project requirements - asks structured questions about scope, integrations, and constraints to populate project_state.md
version: 1.1.0
---

# Requirements Gatherer

Ask structured questions to define project requirements.

## Activation

Activate when:
- Invoked by `project-initializer` after project setup
- User says "Gather requirements" or "Define requirements"
- Starting Phase 1 on a new project

## Workflow

### 1. Load Project Context

Use `Read` to get `{project_path}/project_state.md`. Extract:
- Project name
- Current scope (if any)
- Existing requirements (if resuming)

### 2. Ask Questions by Category

Ask one category at a time. Wait for response before proceeding.

**Category 1: Scope**
```
What does this project include?
- [ ] A single Drupal module
- [ ] Multiple related modules
- [ ] A theme or sub-theme
- [ ] Configuration/site building
- [ ] Mix of the above

Please describe:
```

**Category 2: Core Functionality**
```
What is the main purpose?
1. What problem does it solve?
2. What are the must-have features?
3. What are nice-to-have features?
```

**Category 3: User Roles**
```
Who will use this?
1. Which user roles need access?
2. What permissions are needed?
3. Any role-specific features?
```

**Category 4: Data Requirements**
```
What data is involved?
1. New content types or entities needed?
2. New fields on existing types?
3. Configuration data to store?
4. Relationships to existing content?
```

**Category 5: Integrations**
```
What existing systems does this connect to?
1. Existing Drupal modules to integrate with?
2. External APIs or services?
3. ECA workflows needed?
4. Third-party libraries?
```

**Category 6: UI Requirements**
```
What interfaces are needed?
1. Admin forms or pages?
2. Frontend display requirements?
3. Specific UX patterns to follow?
4. Mobile considerations?
```

**Category 7: Constraints**
```
What limitations should we know about?
1. Drupal version (10.x, 11.x)?
2. Performance requirements?
3. Accessibility requirements (WCAG level)?
4. Browser support needs?
```

### 3. Handle Responses

For each category:
- Accept the answer
- Allow "skip" or "not sure yet" - mark as open question
- Summarize understanding back to user
- Proceed to next category

### 4. Update project_state.md

After all categories, use `Edit` tool to update the Requirements section:

```markdown
## Requirements

### Scope
- {what project includes}

### Core Functionality
- {requirement 1}
- {requirement 2}

### User Roles
| Role | Permissions | Features |
|------|-------------|----------|
| {role} | {perms} | {features} |

### Data Requirements
- {data type}: {storage approach}

### Integrations
- {module/service}: {integration type}

### UI Requirements
- {element}: {requirement}

### Constraints
- {constraint}: {details}

### Open Questions
- {questions marked as "not sure yet"}
```

### 5. Confirm

Show summary to user:
```
Requirements gathered for {project_name}:

Core: {1-2 sentence summary}
Roles: {list roles}
Integrations: {list integrations}
Open questions: {count}

Does this look complete? (yes/no/add more)
```

If "add more", ask what category to expand.

## Stop Points

STOP and wait for user after:
- Each category question
- Showing summary for confirmation
- User says "add more"
