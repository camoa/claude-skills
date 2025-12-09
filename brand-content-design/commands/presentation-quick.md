---
description: Create a presentation quickly with minimal questions
allowed-tools: Read, Write, Glob, AskUserQuestion, Skill
---

# Presentation Quick Command

Create a presentation with minimal questions - just template and content.

## Prerequisites

- Must be in a brand project folder (contains brand-philosophy.md)
- Must have at least one presentation template (run `/template-presentation` first)

## Workflow

1. **Find project and templates**
   - Check `./brand-philosophy.md`, then `../brand-philosophy.md`, then `find . -maxdepth 2 -name "brand-philosophy.md"`
   - **Set PROJECT_PATH** = directory containing brand-philosophy.md
   - Run `find {PROJECT_PATH}/templates/presentations -name "template.md" 2>/dev/null`
   - If no project found: Tell user to run `/brand-init` first and stop
   - If no templates found: Tell user to run `/template-presentation` first and stop

2. **Single question for template**
   Use AskUserQuestion:
   - Header: "Template"
   - Question: "Which template?"
   - Options: List each template by name

3. **Ask for content**
   Ask: "Paste your outline or content for this presentation:"

   **Tip:** Mention `/outline <template>` if they need help preparing content.

4. **Load template files**
   - Read `{PROJECT_PATH}/templates/presentations/{template-name}/template.md`
   - Read `{PROJECT_PATH}/templates/presentations/{template-name}/canvas-philosophy.md`
   - Read plugin `references/presentations-guide.md`
   - Read plugin `references/style-constraints.md`
   - **Identify the template's style** from canvas-philosophy.md (look for "Style:" at bottom)

5. **Map content to slides**
   - Parse the pasted content
   - Map to template's slide structure
   - Fill any gaps with sensible defaults based on topic

6. **Generate presentation PDF**
   Use the **canvas-design** skill:
   - **IMPORTANT:** Use the template's existing canvas-philosophy.md as the design philosophy - do NOT create a new philosophy
   - Pass the canvas-philosophy.md content directly to canvas-design as the design direction
   - Provide presentations-guide.md for Zen principles
   - Provide brand-philosophy.md for colors, fonts, logo

   **ENFORCE STYLE CONSTRAINTS based on template's style:**
   - Look up the style's Enforcement Block in `style-constraints.md`
   - Pass it to canvas-design as hard constraints
   - All 13 styles (Minimal, Dramatic, Organic, Wabi-Sabi, Shibui, Iki, Ma, Hygge, Lagom, Swiss, Memphis, Yeo-baek, Feng Shui) have enforcement blocks

   - Generate each slide following template structure
   - Reference sample.pdf for visual style (but generate fresh content)
   - Output as multi-page PDF at 1920x1080 (16:9)

7. **Convert PDF to PPTX**
   Use the **pptx** skill:
   - Use html2pptx workflow to match PDF design
   - Create editable text boxes
   - Incorporate logo

8. **Save outputs**
   Create folder: `{PROJECT_PATH}/presentations/{YYYY-MM-DD}-{topic-slug}/`
   Save:
   - `{topic-slug}.pdf`
   - `{topic-slug}.pptx`

9. **Show result**
   Display:
   - Output location
   - "Use `/presentation` for more control over each slide"

## Output

- Created: `presentations/{date}-{name}/{name}.pdf`
- Created: `presentations/{date}-{name}/{name}.pptx`

## Notes

- This is the fast path - paste content, get presentation
- For step-by-step control, use `/presentation` instead
- For help preparing content, use `/outline <template>` first
- canvas-design ensures brand and Zen principles are followed
