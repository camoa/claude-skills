---
description: Create a carousel using an existing template (detailed, guided mode)
allowed-tools: Read, Write, Glob, AskUserQuestion, Skill
---

# Carousel Command (Detailed Mode)

Create a carousel from an existing template with user-provided content.

## Prerequisites

- Must be in a brand project folder (contains brand-philosophy.md)
- Must have at least one carousel template (run `/template-carousel` first)

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
   - Run `find {PROJECT_PATH}/templates/carousels -name "template.md" 2>/dev/null`
   - Parse results to get template names (parent folder name)
   - If none found: Tell user to run `/template-carousel` first and stop

3. **Ask template selection**
   Use AskUserQuestion:
   - Header: "Template"
   - Question: "Which template would you like to use?"
   - Options: List each template by name (include platform info)

4. **Load template files**
   - Read `{PROJECT_PATH}/templates/carousels/{template-name}/template.md`
   - Read `{PROJECT_PATH}/templates/carousels/{template-name}/canvas-philosophy.md`
   - Read plugin `references/carousels-guide.md` for best practices
   - Note the card structure (types, purposes, content elements)
   - Note the platform/dimensions

5. **Ask for content**
   Use AskUserQuestion:
   - Header: "Content"
   - Question: "How would you like to provide content?"
   - Options:
     - "Paste outline" - I have a prepared outline (from `/outline` or elsewhere)
     - "Enter card-by-card" - Guide me through each card
     - "Paste all content" - I'll paste raw content for you to organize

6. **Collect content based on selection**

   **If "Paste outline":**
   - Ask user to paste their outline
   - Parse and validate against template structure
   - Show mapping: "Card 1 (Hook) → {their content}"
   - Ask to confirm or adjust

   **If "Enter card-by-card":**
   - For each card in template structure:
     - Show: "Card {n}: {type} - {purpose}"
     - Show: "Content needed: {elements from template}"
     - Ask user for content
     - Remind: "Keep it short - this needs to work on mobile!"
     - Confirm before next card

   **If "Paste all content":**
   - Ask user to paste their raw content
   - Analyze and map to template cards
   - Show proposed mapping
   - Ask to confirm or adjust

7. **Ask carousel details**
   - "What is the hook/title for this carousel?"

8. **Generate carousel PDF**
   Use the **canvas-design** skill:
   - **IMPORTANT:** Use the template's existing canvas-philosophy.md as the design philosophy - do NOT create a new philosophy
   - Pass the canvas-philosophy.md content directly to canvas-design as the design direction
   - Provide the carousels-guide.md best practices (mobile-first, scroll-stopping, etc.)
   - Provide brand-philosophy.md for colors, fonts, logo
   - For each card in the template structure:
     - Describe the card type and purpose
     - Provide the user's content for that card
     - Reference the sample.pdf for visual style (but generate fresh content)
   - Request output as multi-page PDF with correct dimensions:
     - LinkedIn: 1080x1350 (4:5 portrait)
     - Instagram Square: 1080x1080 (1:1)
     - Instagram Portrait: 1080x1350 (4:5)
   - Save to workspace

9. **Save outputs**
   Create folder: `{PROJECT_PATH}/carousels/{YYYY-MM-DD}-{topic-slug}/`
   Save:
   - `{topic-slug}.pdf`

10. **Present results**
    Show:
    - Output location
    - File path
    - Preview of first/last cards
    - "Ready to upload to {platform}!"

## Output

- Created: `carousels/{date}-{name}/{name}.pdf`

## Notes

- This command requires an existing template - use `/template-carousel` to create one first
- For best results, use `/outline <template>` to prepare content that matches the template structure
- Keep text concise - carousels are viewed on mobile devices
- canvas-design ensures brand consistency and carousel best practices are followed
- The PDF can be uploaded directly to LinkedIn or split into images for Instagram
