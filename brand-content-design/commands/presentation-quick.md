---
description: Create a presentation quickly with minimal questions
allowed-tools: Read, Write, Glob, AskUserQuestion, Skill
---

# Presentation Quick Command

Create a presentation with minimal questions - just topic, template, and content.

## Prerequisites

- Must be in a brand project folder (contains brand-philosophy.md)
- Must have at least one presentation template (run `/template-presentation` first)

## Workflow

1. **Verify project and templates**
   - Check for brand-philosophy.md
   - Glob: `templates/presentations/*/template.md`
   - If none found: Tell user to run `/template-presentation` first and stop

2. **Single question for template**
   Use AskUserQuestion:
   - Header: "Template"
   - Question: "Which template?"
   - Options: List each template by name

3. **Ask for content**
   Ask: "Paste your outline or content for this presentation:"

   **Tip:** Mention `/outline <template>` if they need help preparing content.

4. **Load template**
   - Read `templates/presentations/{template-name}/template.md`
   - Read `templates/presentations/{template-name}/canvas-philosophy.md`

5. **Map content to slides**
   - Parse the pasted content
   - Map to template's slide structure
   - Fill any gaps with sensible defaults based on topic

6. **Generate presentation**
   Use the **pptx** skill with the "Creating using a template" workflow:
   - Use `templates/presentations/{template-name}/sample.pptx` as template
   - Apply user content via replace.py workflow
   - Incorporate logo from brand-philosophy.md

7. **Save outputs**
   Create folder: `presentations/{YYYY-MM-DD}-{topic-slug}/`
   Save:
   - `{topic-slug}.pptx`
   - `{topic-slug}.pdf`

8. **Show result**
   Display:
   - Output location
   - "Use `/presentation` for more control over each slide"

## Output

- Created: `presentations/{date}-{name}/{name}.pptx`
- Created: `presentations/{date}-{name}/{name}.pdf`

## Notes

- This is the fast path - paste content, get presentation
- For step-by-step control, use `/presentation` instead
- For help preparing content, use `/outline <template>` first
