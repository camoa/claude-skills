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

1. **Find project and templates**
   - Check `./brand-philosophy.md`, then `../brand-philosophy.md`, then `find . -maxdepth 2 -name "brand-philosophy.md"`
   - **Set PROJECT_PATH** = directory containing brand-philosophy.md
   - Run `find {PROJECT_PATH}/templates/carousels -name "template.md" 2>/dev/null`
   - If no project found: Tell user to run `/brand-init` first and stop
   - If no templates found: Tell user to run `/template-carousel` first and stop

2. **Single question for template**
   Use AskUserQuestion:
   - Header: "Template"
   - Question: "Which template?"
   - Options: List each template by name (include platform)

3. **Ask for content**
   Ask: "Paste your outline or content for this carousel:"

   **Tip:** Mention `/outline <template>` if they need help preparing content.

4. **Load template files**
   - Read `{PROJECT_PATH}/templates/carousels/{template-name}/template.md`
   - Read `{PROJECT_PATH}/templates/carousels/{template-name}/canvas-philosophy.md`
   - Read plugin `references/carousels-guide.md`
   - Read plugin `references/style-constraints.md`
   - Note platform/dimensions
   - **Identify the template's style** (Minimal, Dramatic, or Organic) from canvas-philosophy.md

5. **Map content to cards**
   - Parse the pasted content
   - Map to template's card structure
   - Fill any gaps with sensible defaults
   - Keep text concise for mobile

6. **Generate carousel PDF**
   Use the **canvas-design** skill:
   - **IMPORTANT:** Use the template's existing canvas-philosophy.md as the design philosophy - do NOT create a new philosophy
   - Pass the canvas-philosophy.md content directly to canvas-design as the design direction
   - Provide carousels-guide.md for best practices
   - Provide brand-philosophy.md for colors, fonts, logo

   **ENFORCE STYLE CONSTRAINTS based on template's style:**
   - Minimal: "ENFORCE: Max 8 words/card, 60% whitespace, centered, 3 elements max"
   - Dramatic: "ENFORCE: Max 12 words/card, 35% whitespace, asymmetrical, 5 elements max"
   - Organic: "ENFORCE: Max 10 words/card, 50% whitespace, organic flow, 4 elements max"

   - Generate each card following template structure
   - Reference sample.pdf for visual style (but generate fresh content)
   - Output as multi-page PDF with correct dimensions

7. **Save outputs**
   Create folder: `{PROJECT_PATH}/carousels/{YYYY-MM-DD}-{topic-slug}/`
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
- canvas-design ensures brand and carousel best practices are followed
