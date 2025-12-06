---
name: guide-loader
description: Use when needing specialized guide content - loads guides from configured path based on current task
version: 1.1.0
---

# Guide Loader

Load development guides into context when needed.

## Activation

Activate when:
- Designing or implementing features that match guide topics
- User requests a specific guide
- Invoked by other skills (guide-integrator, task-context-loader)
- "Load the ECA guide" or "What does my guide say about..."

## Workflow

### 1. Check for Guides Path

Use `Read` on `{project_path}/project_state.md`

Look for:
```markdown
**Guides Path:** {path}
```

If not found:
```
No guides path configured.

To add guides, edit project_state.md and add:
**Guides Path:** /path/to/your/guides/

For now, using Claude's built-in Drupal knowledge.
```

Then STOP - no guides to load.

### 2. Determine Which Guide

If specific guide requested, use that.

Otherwise, match topic to guide:

| Topic Keywords | Guide File |
|----------------|------------|
| ECA, event, workflow, automation | eca_development_guide.md |
| field, entity, bundle, content type | drupal_fields_entities_guide.md |
| form, settings, config, admin | drupal_configuration_forms_guide.md |
| theme, CSS, SCSS, Bootstrap | bootstrap_*.md |
| SDC, component, Twig | sdc_*.md |
| Radix, subtheme | radix_*.md |
| development, workflow, process | drupal_development_guide.md |

### 3. Load Guide

Use `Read` on `{guides_path}/{guide_file}`:

If file not found:
```
Guide not found: {guide_file}
Path checked: {guides_path}/{guide_file}

Available in guides folder? Use Glob to check.
```

If file found, extract:
- Table of contents (if present)
- Key sections relevant to current task
- Code examples
- Warnings/gotchas

### 4. Present Guide Content

Format as:
```
## Guide Loaded: {guide name}

### Overview
{Brief description of guide scope}

### Relevant Sections for Current Task
1. **{Section Name}** - {why relevant}
   {Key points}

2. **{Section Name}** - {why relevant}
   {Key points}

### Key Patterns
- {Pattern 1}
- {Pattern 2}

### Warnings
- {Important gotcha from guide}

### Full Reference
{guides_path}/{guide_file}
```

### 5. Integrate with Current Work

Based on guide content, suggest:
```
Apply to current task:
- {Specific recommendation from guide}
- {Pattern to follow}
- {Thing to avoid}

Add these to architecture/implementation? (yes/no)
```

## Without Guides

If no guides configured, provide built-in knowledge:
```
No custom guides available. Using built-in Drupal knowledge.

For {topic}:
- Standard approach: {description}
- Core reference: {path}
- Best practices: {list}

For custom guidance, configure guides path in project_state.md.
```

## Stop Points

STOP and wait for user:
- If no guides path configured (inform and continue without)
- If requested guide not found
- After presenting guide content (ask if need more)
