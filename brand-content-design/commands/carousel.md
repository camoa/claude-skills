---
description: Create a carousel using brand and template (detailed, guided mode)
allowed-tools: Read, Write, Glob, AskUserQuestion, Skill
---

# Carousel Command (Detailed Mode)

Create a carousel with guided workflow, asking for template and content at each step.

## Prerequisites

- Must be in a brand project folder (contains brand-philosophy.md)

## Workflow

1. **Verify project**
   - Check for brand-philosophy.md
   - Load brand philosophy
   - Note the logo path from Brand Assets section

2. **Ask topic**
   Use AskUserQuestion:
   - "What is this carousel about?"
   - Get topic and brief description

3. **List available templates**
   - Glob: `templates/carousels/*/template.md`
   - Show list with platform and descriptions
   - Include option: "No template (one-off)"

4. **Ask template selection**
   Use AskUserQuestion:
   - "Which template would you like to use?"
   - Options: List of templates + "No template"

5. **If no template, ask platform**
   Use AskUserQuestion:
   - "Which platform?"
   - Options: LinkedIn (4:5), Instagram Square (1:1), Instagram Portrait (4:5)

6. **Check for outline**
   Ask: "Do you have an outline you'd like to use? (paste it or say 'no')"

7. **If outline provided:**
   - Parse the outline
   - If template: validate against template structure
   - Map outline points to cards

8. **If no outline:**
   - Load selected template's structure
   - For each card in structure:
     - Show card type and purpose
     - Ask for content for that card
     - Confirm before moving to next

9. **Load canvas philosophy**
   - If template: Read `templates/carousels/{name}/canvas-philosophy.md`
   - If no template: Generate a canvas philosophy using `references/canvas-philosophy-template.md` and brand-philosophy.md

10. **Generate carousel**
    Use the **canvas-design** skill:
    - Provide the canvas-philosophy.md content as the design philosophy input
    - Read the logo file from assets/ and incorporate where appropriate (first/last card)
    - For each card, describe what to create (hook, content point, CTA, etc.)
    - Request output as multi-page PDF with correct dimensions:
      - LinkedIn: 1080x1350 (4:5 portrait)
      - Instagram Square: 1080x1080 (1:1)
      - Instagram Portrait: 1080x1350 (4:5)
    - Generate all cards as pages in a single PDF

11. **Save outputs**
    Create folder: `carousels/{YYYY-MM-DD}-{topic-slug}/`
    Save:
    - `{topic-slug}.pdf`

12. **Present results**
    Show:
    - Output location
    - Preview of cards
    - Ready for upload instructions

## Output

- Created: `carousels/{date}-{name}/{name}.pdf`
