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

1. **Find project (PROJECT_PATH)**
   Search in this order:
   - Check `./brand-philosophy.md` (current directory)
   - Check `../brand-philosophy.md` (parent directory)
   - Run `find . -maxdepth 2 -name "brand-philosophy.md"` to find nearby
   - If multiple found, ask user which project
   - If none found, tell user to run `/brand-init` first and stop
   - **Set PROJECT_PATH** = directory containing brand-philosophy.md
   - Load brand-philosophy.md

2. **Find available templates**
   - Run `find {PROJECT_PATH}/templates/presentations -name "template.md" 2>/dev/null`
   - Parse results to get template names (parent folder name)
   - If none found: Tell user to run `/template-presentation` first and stop

3. **Ask template selection**
   Use AskUserQuestion:
   - Header: "Template"
   - Question: "Which template would you like to use?"
   - Options: List each template by name

4. **Load template files**
   - Read `{PROJECT_PATH}/templates/presentations/{template-name}/template.md`
   - Read `{PROJECT_PATH}/templates/presentations/{template-name}/canvas-philosophy.md`
   - Read plugin `references/presentations-guide.md` for Zen principles
   - Read plugin `references/style-constraints.md` for style enforcement
   - Note the slide structure (types, purposes, content elements)
   - **Identify the template's style** from canvas-philosophy.md (look for "Style:" at bottom or enforcement block)

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

8. **Generate presentation PDF**
   Use the **visual-content** skill:
   - **IMPORTANT:** Use the template's existing canvas-philosophy.md as the design philosophy - do NOT create a new philosophy
   - Pass the canvas-philosophy.md content directly to visual-content as the design direction
   - Provide the presentations-guide.md principles (Zen, visual hierarchy, etc.)
   - Provide brand-philosophy.md for colors, fonts, logo

   **ENFORCE STYLE CONSTRAINTS based on template's style:**

   - Look up the template's style in `style-constraints.md`
   - Copy the exact **Enforcement Block** for that style
   - Pass it to visual-content as hard constraints

   The enforcement block format is:
   ```
   STYLE: [Style Name] ([Family])
   - HARD LIMIT: Max X words/slide. Truncate if exceeded.
   - HARD LIMIT: Min X% whitespace.
   - HARD LIMIT: Max X elements.
   - Layout: [Layout directive]
   - Typography: [Typography directive]
   - Color: [Color directive]
   - NEVER: [Anti-patterns]
   ```

   **All 13 styles have enforcement blocks in style-constraints.md:**
   - Japanese Zen: Minimal, Dramatic, Organic, Wabi-Sabi, Shibui, Iki, Ma
   - Scandinavian: Hygge, Lagom
   - European: Swiss, Memphis
   - East Asian: Yeo-baek, Feng Shui

   - For each slide in the template structure:
     - Describe the slide type and purpose
     - Provide the user's content for that slide
     - Reference the sample.pdf for visual style (but generate fresh content)
   - Request output as multi-page PDF at 1920x1080 (16:9)
   - Save to workspace

9. **Convert PDF to PPTX**
   Use the **pptx** skill:
   - Use the "Creating without a template" (html2pptx) workflow
   - Match the PDF design exactly
   - Create editable text boxes for each content element
   - Incorporate logo from brand-philosophy.md assets
   - Save as PPTX

10. **Save outputs**
    Create folder: `{PROJECT_PATH}/presentations/{YYYY-MM-DD}-{topic-slug}/`
    Save:
    - `{topic-slug}.pdf`
    - `{topic-slug}.pptx`

11. **Present results**
    Show:
    - Output location
    - File paths
    - Preview of first slide
    - "Open the PPTX to review and make final adjustments"

## Output

- Created: `presentations/{date}-{name}/{name}.pdf`
- Created: `presentations/{date}-{name}/{name}.pptx`

## Notes

- This command requires an existing template - use `/template-presentation` to create one first
- For best results, use `/outline <template>` to prepare content that matches the template structure
- The PDF is the source of truth - PPTX is generated from it for editability
- visual-content ensures brand consistency and Zen principles are followed
