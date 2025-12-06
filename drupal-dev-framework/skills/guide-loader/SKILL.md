---
name: guide-loader
description: Use when needing specialized guide content - loads guides from ~/workspace/claude_memory/guides/ based on current task
version: 1.0.0
---

# Guide Loader

Load relevant development guides based on current task context.

## Triggers

- When designing or implementing specific feature types
- User requests specific guide
- Guide reference found in architecture files
- Auto-triggered during task context loading

## Available Guides

Located in `~/workspace/claude_memory/guides/`:

### Core Development
| Guide | Purpose |
|-------|---------|
| `drupal_development_guide.md` | Main 3-phase development workflow |
| `project_reference_guide.md` | Tool ecosystem and integrations |

### Feature-Specific
| Guide | Use When |
|-------|----------|
| `eca_development_guide.md` | Workflow automation, events |
| `drupal_fields_entities_guide.md` | Custom fields, entities |
| `drupal_configuration_forms_guide.md` | Admin settings forms |

### Frontend
| Guide | Use When |
|-------|----------|
| `bootstrap_*.md` | Bootstrap integration |
| `radix_*.md` | Radix theme work |
| `sdc_*.md` | Single Directory Components |

### Plugin Development
| Guide | Use When |
|-------|----------|
| `claude-code-plugin-development.md` | Creating Claude Code plugins |

## Loading Strategy

### Full Load
For primary reference during task:
- Read entire guide
- Extract relevant sections
- Summarize key points

### Section Load
For quick reference:
- Search for specific topic
- Load only relevant section
- Provide targeted guidance

### Reference Only
When just need pointer:
- Note guide exists
- Provide path for user reference
- Don't load content

## Process

1. **Identify need** - What topic needs guidance?
2. **Match guide** - Which guide covers this?
3. **Determine scope** - Full, section, or reference?
4. **Load content** - Read appropriate amount
5. **Present** - Summarize or quote relevant parts

## Output Format

```markdown
## Guide Reference: {Topic}

### Source
`~/workspace/claude_memory/guides/{guide_name}.md`

### Relevant Sections
- Section A (lines X-Y): {summary}
- Section B (lines X-Y): {summary}

### Key Points for Current Task
1. {Point 1}
2. {Point 2}
3. {Point 3}

### Apply To Current Work
{How this applies to what we're doing}
```

## Guide Not Found

If no guide exists for topic:
1. Note the gap
2. Suggest creating one (via guide-framework-maintainer)
3. Provide general best practices
4. Search web for current standards

## Human Control Points

- User can request specific guide
- User can request more/less detail
- User decides how to apply guidance
