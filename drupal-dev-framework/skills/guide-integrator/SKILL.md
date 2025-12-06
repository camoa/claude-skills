---
name: guide-integrator
description: Use when designing features covered by existing guides - loads relevant guides and adds references to architecture (if guides are configured)
version: 1.1.0
---

# Guide Integrator

Load and integrate development guides into architecture documents.

## Activation

Activate when:
- Designing features that match guide topics (ECA, fields, forms, frontend)
- User mentions a specific guide
- Architecture drafting for specialized features
- Auto-triggered by `architecture-drafter` agent

## Workflow

### 1. Check for Guides Path

Use `Read` on `{project_path}/project_state.md` and look for:
```markdown
**Guides Path:** {path}
```

If no guides path configured:
- Skip guide loading
- Use Claude's built-in Drupal knowledge
- Note in output: "No guides configured - using built-in knowledge"

### 2. Detect Feature Type

Analyze the feature being designed. Match to guide categories:

| Feature Keywords | Guide to Load |
|------------------|---------------|
| ECA, workflow, automation, event, trigger | eca_development_guide.md |
| field, entity, bundle, storage | drupal_fields_entities_guide.md |
| form, settings, configuration, admin | drupal_configuration_forms_guide.md |
| theme, CSS, SCSS, component, Bootstrap | bootstrap guides, radix guides |
| SDC, component, Twig | sdc guides |

### 3. Load Relevant Guide

If guides path exists, use `Read` to load matching guide:
```
{guides_path}/{matched_guide}.md
```

If file not found, note: "Guide {name} not found at configured path"

### 4. Extract Applicable Patterns

From the loaded guide, identify:
- Patterns that apply to current feature
- Code examples to reference
- Warnings or gotchas
- Recommended approaches

### 5. Add to Architecture

Use `Edit` tool to add a "Related Guides" section to the architecture file:

```markdown
## Related Guides

### {Guide Name}

**Applicable sections:**
- {Section name}: {why relevant}
- {Section name}: {why relevant}

**Patterns to apply:**
- {pattern 1}
- {pattern 2}

**Reference:** `{guides_path}/{guide_name}.md`

**Notes:**
{Any project-specific adaptations needed}
```

### 6. Summarize

Tell user:
```
Integrated guide: {guide_name}

Added to architecture:
- {count} applicable patterns
- {count} reference sections

Key guidance:
- {most important point}
```

## Without Guides

If no guides are configured, provide:
- Built-in Drupal knowledge for the feature area
- Core pattern references (use `core-pattern-finder`)
- Standard Drupal best practices

Format as:
```markdown
## Development Patterns

### {Feature Area}

**Standard approach:**
- {pattern 1}
- {pattern 2}

**Core reference:** `{core path}`

**Best practices:**
- {practice 1}
- {practice 2}
```

## Stop Points

STOP and ask user:
- If multiple guides could apply (ask which to prioritize)
- If guide file not found (ask for correct path)
- Before adding patterns that conflict with existing architecture
