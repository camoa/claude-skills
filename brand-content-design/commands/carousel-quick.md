---
description: Create a carousel quickly with minimal questions
allowed-tools: Read, Write, Glob, AskUserQuestion, Skill
---

# Carousel Quick Command

Create a carousel with minimal questions - topic and template only.

## Prerequisites

- Must be in a brand project folder (contains brand-philosophy.md)

## Workflow

1. **Verify project**
   - Check for brand-philosophy.md
   - Load brand philosophy
   - Note the logo path from Brand Assets section

2. **Single question**
   Get available templates:
   - Glob: `templates/carousels/*/template.md`

   Use AskUserQuestion (single combined question):
   - "What's the topic and which template?"
   - Text input for topic
   - Options for template (including "default/last used")

3. **Check for outline in user message**
   - If user provided outline with the request, use it
   - If not, auto-generate minimal structure from topic

4. **Auto-generate content structure**
   Based on template or default:
   - Hook card: Attention-grabbing version of topic
   - Content cards: Auto-suggest 3-5 key points
   - CTA card: Generic engagement CTA

5. **Load canvas philosophy**
   - If template: Read `templates/carousels/{name}/canvas-philosophy.md`
   - If no template: Generate a canvas philosophy using `references/canvas-philosophy-template.md` and brand-philosophy.md

6. **Generate carousel**
   Use the **canvas-design** skill:
   - Provide the canvas-philosophy.md content as the design philosophy input
   - Read the logo file from assets/ and incorporate where appropriate
   - For each card, describe what to create based on auto-generated structure
   - Request output as multi-page PDF with correct dimensions:
     - LinkedIn: 1080x1350 (4:5 portrait)
     - Instagram Square: 1080x1080 (1:1)
     - Instagram Portrait: 1080x1350 (4:5)

7. **Save outputs**
   Create folder: `carousels/{YYYY-MM-DD}-{topic-slug}/`
   Save PDF

8. **Show preview**
   Display:
   - Output location
   - Quick preview of cards
   - "Use /carousel for more control"

## Output

- Created: `carousels/{date}-{name}/{name}.pdf`
