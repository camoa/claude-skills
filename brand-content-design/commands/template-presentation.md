---
description: Create or edit a presentation template through guided wizard
allowed-tools: Read, Write, Glob, AskUserQuestion, Skill
---

# Template Presentation Command

Create a new presentation template or edit an existing one.

## Prerequisites

- Must be in a brand project folder (contains brand-philosophy.md)

## Workflow

1. **Verify project**
   - Check for brand-philosophy.md
   - Load brand philosophy
   - Note the logo path from brand-philosophy.md (under Brand Assets section)

2. **Check for existing templates**
   - Glob `templates/presentations/*/template.md`
   - List any existing templates found

3. **Ask: Create new or edit existing?**
   Use AskUserQuestion:
   - Header: "Action"
   - Question: "What would you like to do?"
   - Options:
     - "Create new template" - Start fresh with a new template
     - If existing templates found, add each as an option: "Edit: {template-name}" - Modify this existing template

4. **Route based on selection**

   **If "Create new template" selected → CREATE MODE:**
   - Ask: "What should we call this template?" (will become folder name)
   - Continue with step 5

   **If "Edit: {template-name}" selected → EDIT MODE:**
   - Load existing template.md and canvas-philosophy.md from `templates/presentations/{template-name}/`
   - Show current structure summary
   - Ask: "What would you like to modify?"
     - Add/remove slides
     - Change slide order
     - Update visual style
     - Regenerate samples only
     - Start over from scratch
   - Jump to appropriate step based on selection

5. **Ask template purpose** (CREATE MODE only)
   Use AskUserQuestion:
   - "What is this presentation template for?"
   - Options: Technical/Product, Sales/Pitch, Educational/Training, Other (describe)

5. **Load presentations guide**
   - Read plugin `references/presentations-guide.md` for slide type options

6. **Ask slide types needed** (or modify existing in EDIT MODE)
   Use AskUserQuestion:
   - "Which slide types do you need?"
   - Multi-select from: Title, Content, Image, Data/Chart, Quote, CTA, Transition
   - Allow custom additions
   - In EDIT MODE: Show current slides, allow add/remove

7. **Define slide sequence**
   Based on purpose and selected types, propose a sequence:
   - Show proposed structure
   - Ask user to confirm or modify

8. **Create/update canvas philosophy** (or skip if "Regenerate samples only")
   Use AskUserQuestion for style:
   - "What visual style?" Options: Bold/Dramatic, Clean/Minimal, Warm/Friendly, Technical/Precise
   - "What mood?" Options: Professional, Creative, Authoritative, Approachable

   Generate canvas-philosophy.md using:
   - canvas-philosophy-template.md from references
   - Brand colors and fonts from brand-philosophy.md
   - Style preferences from questions

9. **Create/update template.md**
   Using template-structure.md from references:
   - Fill in purpose, content type, slide structure
   - Add visual standards and Zen principles
   - Include output configuration

10. **Generate sample PDF**
    Use the **canvas-design** skill:
    - Provide the canvas-philosophy.md content as the design philosophy input
    - Read the logo file from the path in brand-philosophy.md and incorporate it
    - **Generate ALL slides defined in template.md** (not just a subset)
    - Use placeholder/example content for each slide type
    - Request output as PDF at 1920x1080 (16:9)
    - Save as sample.pdf

11. **Generate sample PPTX**
    Use the **pptx** skill:
    - Create an editable PowerPoint version matching the full template structure
    - Include the logo from assets/
    - Set up slide masters with brand colors and fonts
    - **Create ALL slides defined in template.md** with placeholder content
    - Save as sample.pptx

12. **Save template**
    Save to `templates/presentations/{template-name}/`:
    - template.md
    - canvas-philosophy.md
    - sample.pdf
    - sample.pptx

13. **Confirm completion**
    Show template location and sample preview
    Explain how to use: `/presentation` and select this template

## Output

- Created: `templates/presentations/{name}/template.md`
- Created: `templates/presentations/{name}/canvas-philosophy.md`
- Created: `templates/presentations/{name}/sample.pdf`
- Created: `templates/presentations/{name}/sample.pptx`
