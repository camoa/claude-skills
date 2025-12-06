---
name: requirements-gatherer
description: Use when gathering project requirements - asks structured questions about scope, integrations, and constraints to populate project_state.md
version: 1.0.0
---

# Requirements Gatherer

Collect structured project requirements through targeted questions.

## Triggers

- Called by `project-initializer` during project setup
- User says "Gather requirements" or "Define requirements"
- Starting Phase 1 on a new project

## Question Categories

### 1. Core Functionality
- What is the main purpose of this module/feature?
- What problem does it solve for users?
- What are the must-have features?

### 2. User Roles
- Who will use this functionality?
- What permissions are needed?
- Any role-specific features?

### 3. Data Requirements
- What data needs to be stored?
- Relationship to existing content types?
- Configuration vs content data?

### 4. Integrations
- Which existing modules will this integrate with?
- External APIs or services?
- ECA workflows needed?

### 5. UI Requirements
- Admin interface needs?
- Frontend display requirements?
- Specific UX patterns to follow?

### 6. Constraints
- Drupal version requirements?
- Performance considerations?
- Accessibility requirements?
- Timeline or resource constraints?

## Process

1. Ask questions one category at a time
2. Allow user to skip or defer questions
3. Summarize understanding after each category
4. Update project_state.md with answers
5. Confirm complete requirements with user

## Output Format

Update project_state.md Requirements section:

```markdown
## Requirements

### Core Functionality
- {requirement 1}
- {requirement 2}

### User Roles
- {role}: {permissions/features}

### Data Requirements
- {data type}: {storage approach}

### Integrations
- {module/service}: {integration type}

### UI Requirements
- {UI element}: {requirement}

### Constraints
- {constraint type}: {details}

### Open Questions
- {question needing later resolution}
```

## Human Control Points

- User answers all questions
- User can skip or defer any question
- User confirms final requirements summary
