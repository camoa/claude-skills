---
name: guide-integrator
description: Use when designing features - loads plugin references and optionally user's custom guides based on keywords
version: 2.0.0
---

# Guide Integrator

Load development references and integrate into architecture documents.

## Built-in References (Always Available)

This plugin includes references that are ALWAYS available:

| Topic | Reference File |
|-------|----------------|
| Test-Driven Development | `references/tdd-workflow.md` |
| SOLID Principles | `references/solid-drupal.md` |
| DRY Patterns | `references/dry-patterns.md` |
| Library-First/CLI-First | `references/library-first.md` |
| Quality Gates | `references/quality-gates.md` |
| Security Practices | `references/security-checklist.md` |
| Frontend Standards | `references/frontend-standards.md` |

## Activation

Activate when:
- Designing features that match reference topics
- User mentions specific patterns (TDD, SOLID, DRY)
- Architecture drafting for any feature
- Auto-triggered by `architecture-drafter` agent

## Auto-Load Rules

### Plugin References (Always Load)

These are loaded from plugin's `references/` folder - no configuration needed:

| Keywords Detected | Reference to Load |
|-------------------|-------------------|
| "test", "TDD", "unit test", "kernel test" | `references/tdd-workflow.md` |
| "service", "dependency", "inject", "SOLID" | `references/solid-drupal.md` |
| "duplicate", "reuse", "DRY", "extract" | `references/dry-patterns.md` |
| "form", "drush", "command", "service first" | `references/library-first.md` |
| "complete", "done", "quality", "gate" | `references/quality-gates.md` |
| "security", "input", "output", "XSS", "SQL" | `references/security-checklist.md` |
| "CSS", "SCSS", "JavaScript", "frontend", "BEM" | `references/frontend-standards.md` |

### User's Custom Guides (Optional)

If user has configured a `guides_path` in `project_state.md`, also check for custom guides:

| Keywords Detected | Look for Guide |
|-------------------|----------------|
| Feature-specific keywords | User's custom guide files |

**Note:** Custom guide filenames are NOT hardcoded. The skill will search the configured path for relevant files based on keywords in filenames.

## Workflow

### 1. Load Built-in References

**Always load relevant plugin references first.** Use `Read` on the plugin's `references/` folder:

Based on detected keywords in the task:
1. Identify which references apply (see Auto-Load Rules above)
2. Read each applicable reference file
3. Extract patterns relevant to current task

### 2. Check for Custom Guides (Optional)

Use `Read` on `{project_path}/project_state.md` and look for:
```markdown
**Guides Path:** {path}
```

If guides path is configured:
1. Use `Glob` to list files in the guides path: `{guides_path}/*.md`
2. Match filenames to task keywords (fuzzy matching)
3. Load any matching custom guides

If no guides path configured:
- Continue with built-in references only
- Note: "Using plugin references (no custom guides configured)"

### 3. Extract Applicable Patterns

From loaded references and guides, identify:
- Patterns that apply to current feature
- Checklists to follow
- Warnings or anti-patterns
- Recommended approaches

### 4. Add to Architecture

Use `Edit` tool to add references section to architecture file:

```markdown
## Development References

### Plugin References Applied
| Reference | Key Patterns |
|-----------|--------------|
| solid-drupal.md | Single responsibility, DI |
| library-first.md | Service → Form → Route |
| tdd-workflow.md | Red-Green-Refactor |

### Custom Guides Applied (if any)
| Guide | Relevant Sections |
|-------|-------------------|
| {user_guide}.md | {sections} |

### Enforcement Points
| Phase | Principle | Reference |
|-------|-----------|-----------|
| Design | Library-First | references/library-first.md |
| Design | SOLID | references/solid-drupal.md |
| Implement | TDD | references/tdd-workflow.md |
| Implement | DRY | references/dry-patterns.md |
| Complete | Quality Gates | references/quality-gates.md |
| Complete | Security | references/security-checklist.md |
```

### 5. Summarize

Tell user:
```
References integrated:

Plugin references:
- {reference 1}: {key points}
- {reference 2}: {key points}

Custom guides (if any):
- {guide}: {key points}

Enforcement: These will be checked at each phase.
```

## Reference Locations

| Type | Location |
|------|----------|
| Plugin references | `{plugin_path}/references/*.md` |
| Custom guides | User-configured `guides_path` |

## Stop Points

STOP and ask user:
- If multiple custom guides could apply (ask which to prioritize)
- If custom guide path is configured but no files found
- Before adding patterns that conflict with existing architecture
