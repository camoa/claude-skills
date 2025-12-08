---
description: Create a presentation using an existing template (detailed, guided mode)
allowed-tools: Read, Write, Glob, AskUserQuestion, Skill
---

# Presentation Command (Detailed Mode)

Create a presentation from an existing template with user-provided content.

## Prerequisites

- Must be in a brand project folder (contains brand-philosophy.md)
- Must have at least one presentation template (run `/template-presentation` first)

## Workflow

1. **Verify project**
   - Check for brand-philosophy.md
   - Load brand philosophy

2. **List available templates**
   - Glob: `templates/presentations/*/template.md`
   - If none found: Tell user to run `/template-presentation` first and stop

3. **Ask template selection**
   Use AskUserQuestion:
   - Header: "Template"
   - Question: "Which template would you like to use?"
   - Options: List each template by name

4. **Load template**
   - Read `templates/presentations/{template-name}/template.md`
   - Read `templates/presentations/{template-name}/canvas-philosophy.md`
   - Note the slide structure (types, purposes, content elements)

5. **Ask for content**
   Use AskUserQuestion:
   - Header: "Content"
   - Question: "How would you like to provide content?"
   - Options:
     - "Paste outline" - I have a prepared outline (from `/outline` or elsewhere)
     - "Enter slide-by-slide" - Guide me through each slide
     - "Paste all content" - I'll paste raw content for you to organize

6. **Collect content based on selection**

   **If "Paste outline":**
   - Ask user to paste their outline
   - Parse and validate against template structure
   - Show mapping: "Slide 1 (Title) → {their content}"
   - Ask to confirm or adjust

   **If "Enter slide-by-slide":**
   - For each slide in template structure:
     - Show: "Slide {n}: {type} - {purpose}"
     - Show: "Content needed: {elements from template}"
     - Ask user for content
     - Confirm before next slide

   **If "Paste all content":**
   - Ask user to paste their raw content
   - Analyze and map to template slides
   - Show proposed mapping
   - Ask to confirm or adjust

7. **Ask presentation details**
   - "What is the title of this presentation?"
   - "Any subtitle or date to include?"

8. **Generate presentation**
   Use the **pptx** skill with the "Creating using a template" workflow:
   - Use `templates/presentations/{template-name}/sample.pptx` as the template
   - Follow the pptx skill's template workflow:
     1. Extract template text and create thumbnail grid
     2. Analyze template and create inventory
     3. Create presentation outline with template mapping
     4. Use rearrange.py if needed
     5. Extract text inventory
     6. Generate replacement text JSON from user content
     7. Apply replacements with replace.py
   - Incorporate logo from brand-philosophy.md assets

9. **Save outputs**
   Create folder: `presentations/{YYYY-MM-DD}-{topic-slug}/`
   Save:
   - `{topic-slug}.pptx`
   - `{topic-slug}.pdf` (convert from pptx)

10. **Present results**
    Show:
    - Output location
    - File paths
    - "Open the PPTX to review and make final adjustments"

## Output

- Created: `presentations/{date}-{name}/{name}.pptx`
- Created: `presentations/{date}-{name}/{name}.pdf`

## Notes

- This command requires an existing template - use `/template-presentation` to create one first
- For best results, use `/outline <template>` to prepare content that matches the template structure
- The generated PPTX can be edited in PowerPoint/Google Slides for final tweaks
