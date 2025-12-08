---
description: Research and add a new content type to the brand project
allowed-tools: Read, Write, WebSearch, WebFetch, AskUserQuestion
---

# Content Type New Command

Add a new content type (beyond presentations and carousels) to the project.

## Prerequisites

- Must be in a brand project folder (contains brand-philosophy.md)

## Workflow

1. **Verify project**
   - Check for brand-philosophy.md

2. **Ask content type**
   Use AskUserQuestion:
   - "What content type would you like to add?"
   - Examples: Infographic, Social Post, Email Header, Banner Ad

3. **Research best practices**
   Use WebSearch:
   - Search for "{content-type} design best practices 2025"
   - Search for "{content-type} dimensions specifications"

   Use WebFetch on top results to gather:
   - Recommended dimensions
   - Design principles
   - Structure patterns
   - Common mistakes to avoid

4. **Ask for user references**
   - "Do you have any reference documents or URLs for this content type?"
   - If provided, analyze and incorporate

5. **Create content type guide**
   Use plugin `references/presentations-guide.md` as structural reference.
   Create new guide with:
   - Zen principles adapted for format
   - Element types (equivalent to slide types)
   - Structure patterns
   - Visual design guidelines
   - Anti-patterns
   - Output specifications

6. **Save guide**
   Write to project: `{content-type}-guide.md` (in project root, alongside brand-philosophy.md)

   Note: Custom content type guides live in the project since they're project-specific.

7. **Create template folders**
   Create: `templates/{content-type}/`

8. **Update project**
   Confirm:
   - New guide created
   - Template folder ready
   - Suggest: "Create your first template with /template-{content-type}"

## Notes

After running this command, you can create templates for the new content type using a custom workflow or by adapting /template-presentation or /template-carousel.

## Output

- Created: `{content-type}-guide.md` (project root)
- Created: `templates/{content-type}/` folder
