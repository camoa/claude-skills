---
description: Create a presentation quickly with minimal questions
allowed-tools: Read, Write, Glob, AskUserQuestion, Skill
---

# Presentation Quick Command

Create a presentation with minimal questions - topic and template only.

## Prerequisites

- Must be in a brand project folder (contains brand-philosophy.md)

## Workflow

1. **Verify project**
   - Check for brand-philosophy.md
   - Load brand philosophy
   - Note the logo path from Brand Assets section

2. **Single question**
   Get available templates:
   - Glob: `templates/presentations/*/template.md`

   Use AskUserQuestion (single combined question):
   - "What's the topic and which template?"
   - Text input for topic
   - Options for template (including "default/last used")

3. **Check for outline in user message**
   - If user provided outline with the request, use it
   - If not, auto-generate minimal structure from topic

4. **Auto-generate content structure**
   Based on template:
   - Title slide: Topic as title
   - Content slides: Auto-suggest 3-5 key points
   - CTA slide: Generic call to action

5. **Load canvas philosophy**
   - If template: Read `templates/presentations/{name}/canvas-philosophy.md`
   - If no template: Generate a canvas philosophy using `references/canvas-philosophy-template.md` and brand-philosophy.md

6. **Generate presentation**
   Use the **canvas-design** skill:
   - Provide the canvas-philosophy.md content as the design philosophy input
   - Read the logo file from assets/ and incorporate where appropriate
   - For each slide, describe what to create based on auto-generated structure
   - Request output as PDF at 1920x1080 (16:9)

7. **Convert to PPTX**
   Use pptx skill to convert

8. **Save outputs**
   Create folder: `presentations/{YYYY-MM-DD}-{topic-slug}/`
   Save PDF and PPTX

9. **Show preview**
   Display:
   - Output location
   - Quick preview
   - "Use /presentation for more control"

## Output

- Created: `presentations/{date}-{name}/{name}.pdf`
- Created: `presentations/{date}-{name}/{name}.pptx`
