---
description: Create a presentation using brand and template (detailed, guided mode)
allowed-tools: Read, Write, Glob, AskUserQuestion, Skill
---

# Presentation Command (Detailed Mode)

Create a presentation with guided workflow, asking for template and content at each step.

## Prerequisites

- Must be in a brand project folder (contains brand-philosophy.md)

## Workflow

1. **Verify project**
   - Check for brand-philosophy.md
   - Load brand philosophy
   - Note the logo path from Brand Assets section

2. **Ask topic**
   Use AskUserQuestion:
   - "What is this presentation about?"
   - Get topic/title and brief description

3. **List available templates**
   - Glob: `templates/presentations/*/template.md`
   - Show list of available templates with descriptions
   - Include option: "No template (one-off)"

4. **Ask template selection**
   Use AskUserQuestion:
   - "Which template would you like to use?"
   - Options: List of templates + "No template"

5. **Check for outline**
   Ask: "Do you have an outline you'd like to use? (paste it or say 'no')"

   **Tip:** Mention that `/outline <template>` can generate an outline template and AI prompt to help prepare content.

6. **If outline provided:**
   - Parse the outline
   - If template selected: validate against template structure
   - Map outline points to slides

7. **If no outline:**
   - Load selected template's structure
   - For each slide in structure:
     - Show slide type and purpose
     - Ask for content for that slide
     - Confirm before moving to next

8. **Load canvas philosophy**
   - If template: Read `templates/presentations/{name}/canvas-philosophy.md`
   - If no template: Generate a canvas philosophy using `references/canvas-philosophy-template.md` and brand-philosophy.md

9. **Generate presentation**
   Use the **canvas-design** skill:
   - Provide the canvas-philosophy.md content as the design philosophy input
   - Read the logo file from assets/ and incorporate where appropriate (title slide, footer)
   - For each slide, describe what to create (topic, key message, visual approach)
   - Request output as PDF at 1920x1080 (16:9)
   - Generate one slide at a time or as a multi-page PDF

10. **Convert to PPTX**
    Use pptx skill:
    - Convert PDF to PPTX

11. **Save outputs**
    Create folder: `presentations/{YYYY-MM-DD}-{topic-slug}/`
    Save:
    - `{topic-slug}.pdf`
    - `{topic-slug}.pptx`

12. **Present results**
    Show:
    - Output location
    - Preview of first few slides
    - File sizes

## Output

- Created: `presentations/{date}-{name}/{name}.pdf`
- Created: `presentations/{date}-{name}/{name}.pptx`
