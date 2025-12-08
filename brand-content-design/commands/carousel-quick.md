---
description: Create a carousel quickly with minimal questions
allowed-tools: Read, Write, Glob, AskUserQuestion, Skill
---

# Carousel Quick Command

Create a carousel with minimal questions - just template and content.

## Prerequisites

- Must be in a brand project folder (contains brand-philosophy.md)
- Must have at least one carousel template (run `/template-carousel` first)

## Workflow

1. **Verify project and templates**
   - Check for brand-philosophy.md
   - Glob: `templates/carousels/*/template.md`
   - If none found: Tell user to run `/template-carousel` first and stop

2. **Single question for template**
   Use AskUserQuestion:
   - Header: "Template"
   - Question: "Which template?"
   - Options: List each template by name (include platform)

3. **Ask for content**
   Ask: "Paste your outline or content for this carousel:"

   **Tip:** Mention `/outline <template>` if they need help preparing content.

4. **Load template**
   - Read `templates/carousels/{template-name}/template.md`
   - Read `templates/carousels/{template-name}/canvas-philosophy.md`
   - Note platform/dimensions

5. **Map content to cards**
   - Parse the pasted content
   - Map to template's card structure
   - Fill any gaps with sensible defaults
   - Keep text concise for mobile

6. **Generate carousel**
   Use the **canvas-design** skill:
   - Provide canvas-philosophy.md as design philosophy
   - Use sample.pdf as visual reference
   - Apply user content to each card
   - Output as multi-page PDF with correct dimensions
   - Incorporate logo from brand-philosophy.md

7. **Save outputs**
   Create folder: `carousels/{YYYY-MM-DD}-{topic-slug}/`
   Save:
   - `{topic-slug}.pdf`

8. **Show result**
   Display:
   - Output location
   - "Ready to upload to {platform}!"
   - "Use `/carousel` for more control over each card"

## Output

- Created: `carousels/{date}-{name}/{name}.pdf`

## Notes

- This is the fast path - paste content, get carousel
- For step-by-step control, use `/carousel` instead
- For help preparing content, use `/outline <template>` first
