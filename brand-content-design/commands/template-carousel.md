---
description: Create or edit a carousel template through guided wizard
allowed-tools: Read, Write, Glob, AskUserQuestion, Skill
---

# Template Carousel Command

Create a new carousel template or edit an existing one.

## Prerequisites

- Must be in a brand project folder (contains brand-philosophy.md)

## Workflow

1. **Verify project**
   - Check for brand-philosophy.md
   - Load brand philosophy
   - Note the logo path from brand-philosophy.md (under Brand Assets section)

2. **Check for existing templates**
   - Glob `templates/carousels/*/template.md`
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
   - Load existing template.md and canvas-philosophy.md from `templates/carousels/{template-name}/`
   - Show current structure summary (platform, card sequence)
   - Ask: "What would you like to modify?"
     - Add/remove cards
     - Change card order
     - Update visual style
     - Change platform
     - Regenerate sample only
     - Start over from scratch
   - Jump to appropriate step based on selection

5. **Ask carousel platform** (CREATE MODE, or if changing platform in EDIT MODE)
   Use AskUserQuestion:
   - "Which platform is this carousel for?"
   - Options: LinkedIn (4:5 portrait), Instagram (1:1 square), Instagram (4:5 portrait)

5. **Ask template purpose** (CREATE MODE only)
   Use AskUserQuestion:
   - "What is this carousel template for?"
   - Options: Educational/Tips, Storytelling, Data/Statistics, Listicle, Other (describe)

6. **Load carousels guide**
   - Read plugin `references/carousels-guide.md` for card type options

7. **Ask card types needed** (or modify existing in EDIT MODE)
   Use AskUserQuestion:
   - "Which card types do you need?"
   - Multi-select from: Hook, Content, Data, Story, CTA
   - Allow custom additions
   - In EDIT MODE: Show current cards, allow add/remove

8. **Define card sequence**
   Based on purpose and selected types, propose a sequence:
   - Show proposed structure (5-10 cards)
   - Ask user to confirm or modify

9. **Create/update canvas philosophy** (or skip if "Regenerate sample only")
   Use AskUserQuestion for style:
   - "What visual style?" Options: Bold/Eye-catching, Clean/Minimal, Warm/Engaging, Professional/Corporate
   - "What mood?" Options: Inspiring, Educational, Authoritative, Friendly

   Generate canvas-philosophy.md using:
   - canvas-philosophy-template.md from references
   - Brand colors and fonts from brand-philosophy.md
   - Style preferences from questions
   - Platform-specific considerations (mobile-first)

10. **Create/update template.md**
    Using template-structure.md from references:
    - Fill in purpose, content type, card structure
    - Add visual standards and Zen principles (carousel-adapted)
    - Include output configuration for platform

11. **Generate sample**
    Use the **canvas-design** skill:
    - Provide the canvas-philosophy.md content as the design philosophy input
    - Read the logo file from the path in brand-philosophy.md and incorporate it
    - **Generate ALL cards defined in template.md** (not just a subset)
    - Use placeholder/example content for each card type
    - Request output as multi-page PDF with platform dimensions:
      - LinkedIn: 1080x1350 (4:5 portrait)
      - Instagram Square: 1080x1080 (1:1)
      - Instagram Portrait: 1080x1350 (4:5)
    - Save as sample.pdf

12. **Save template**
    Save to `templates/carousels/{template-name}/`:
    - template.md
    - canvas-philosophy.md
    - sample.pdf

13. **Confirm completion**
    Show template location and sample preview
    Explain how to use: `/carousel` and select this template

## Output

- Created/Updated: `templates/carousels/{name}/template.md`
- Created/Updated: `templates/carousels/{name}/canvas-philosophy.md`
- Created/Updated: `templates/carousels/{name}/sample.pdf`
