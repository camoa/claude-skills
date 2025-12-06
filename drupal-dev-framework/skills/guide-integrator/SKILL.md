---
name: guide-integrator
description: Use when designing features covered by existing guides - loads relevant guides (ECA, Fields, Bootstrap) and adds references to architecture
version: 1.0.0
---

# Guide Integrator

Surface and integrate relevant development guides during architecture design.

## Triggers

- Designing features that match available guides
- Working with ECA, fields, forms, or frontend
- Need specialized guidance for a feature area
- Auto-triggered during architecture drafting

## Available Guides

Located in `~/workspace/claude_memory/guides/`:

| Guide | Use When |
|-------|----------|
| `drupal_development_guide.md` | Overall development workflow |
| `eca_development_guide.md` | ECA automation, events, conditions |
| `drupal_fields_entities_guide.md` | Field and entity development |
| `drupal_configuration_forms_guide.md` | Admin configuration forms |
| `bootstrap_*.md` | Frontend theming, Bootstrap components |
| `sdc_*.md` | Single Directory Components |
| `radix_*.md` | Radix theme customization |

## Process

1. **Analyze feature** - What functionality is being designed?
2. **Match to guides** - Which guides are relevant?
3. **Load guide content** - Read relevant sections
4. **Extract applicable patterns** - What applies to this feature?
5. **Add references** - Update architecture with guide references

## Guide Matching

### ECA Guide
Match when:
- Workflow automation needed
- Event-driven behavior
- Conditional actions
- Integration with external systems

### Fields/Entities Guide
Match when:
- Custom field types
- Entity type development
- Field formatters/widgets
- Data modeling

### Configuration Forms Guide
Match when:
- Module settings pages
- Admin configuration UI
- System configuration

### Frontend Guides
Match when:
- Theme customization
- Component development
- CSS/SCSS work
- Bootstrap integration

## Output Format

Add to architecture files:

```markdown
## Related Guides

### {Guide Name}
Relevant sections:
- Section X: {why it's relevant}
- Section Y: {why it's relevant}

Key patterns to apply:
- {pattern from guide}

Reference: `~/workspace/claude_memory/guides/{guide_name}.md`
```

## Integration Notes

When integrating guide content:
- Reference, don't reproduce
- Point to specific sections
- Extract only patterns applicable to this project
- Note any deviations from guide recommendations

## Human Control Points

- User can request specific guides
- User reviews guide applicability
- User decides which patterns to adopt
