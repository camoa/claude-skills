---
description: Create or edit a carousel template through guided wizard
allowed-tools: Read, Write, Glob, AskUserQuestion, Skill
---

# Template Carousel Command

Create a new carousel template or edit an existing one.

## Prerequisites

- Must be in a brand project folder (contains brand-philosophy.md)

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
   - Note the logo path from Brand Assets section

2. **Find existing templates**
   - Run `find {PROJECT_PATH}/templates/carousels -name "template.md" 2>/dev/null`
   - Parse results to get template names (parent folder name)
   - List any existing templates found (may be empty for new projects)

3. **Ask: Create new or edit existing?**
   Use AskUserQuestion:
   - Header: "Action"
   - Question: "What would you like to do?"
   - Options:
     - "Create new template" - Start fresh with a new template
     - If existing templates found, add each as an option: "Edit: {template-name}" - Modify this existing template

   **Note:** If no templates exist yet, skip this question and go directly to CREATE MODE.

4. **Route based on selection**

   **If "Create new template" selected → CREATE MODE:**
   - Ask: "What name do you want for this template? (e.g., tips-linkedin-minimal, story-instagram, data-highlights)"
   - **Validate name is unique**: Check if `{PROJECT_PATH}/templates/carousels/{name}/` already exists
   - If name exists: "A template named '{name}' already exists. Please choose a different name."
   - Sanitize name: lowercase, replace spaces with hyphens, remove special characters
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

5. **Ask visual style FIRST** (CREATE MODE, or if changing style in EDIT MODE)
   Use AskUserQuestion:
   - Header: "Style"
   - Question: "Which visual style for this carousel?"
   - Options:
     - **Minimal** - Maximum whitespace, single focal point, profound silence (best for data, technical content)
     - **Dramatic** - Asymmetrical layouts, bold contrast, visual tension (best for announcements, launches)
     - **Organic** - Natural flow, subtle depth, warm humanity (best for storytelling, education)

   **Load style constraints** from plugin `references/style-constraints.md` based on selection.

6. **Ask carousel platform** (CREATE MODE, or if changing platform in EDIT MODE)
   Use AskUserQuestion:
   - "Which platform is this carousel for?"
   - Options: LinkedIn (4:5 portrait), Instagram (1:1 square), Instagram (4:5 portrait)

7. **Ask template purpose** (CREATE MODE only)
   Use AskUserQuestion:
   - "What is this carousel template for?"
   - Options: Educational/Tips, Storytelling, Data/Statistics, Listicle, Other (describe)

8. **Load carousels guide**
   - Read plugin `references/carousels-guide.md` for card type options

9. **Ask card types needed** (or modify existing in EDIT MODE)
   Use AskUserQuestion:
   - "Which card types do you need?"
   - Multi-select from: Hook, Content, Data, Story, CTA
   - Allow custom additions
   - In EDIT MODE: Show current cards, allow add/remove

10. **Define card sequence**
    Based on purpose and selected types, propose a sequence:
    - Show proposed structure (5-10 cards)
    - Ask user to confirm or modify

11. **Create/update canvas philosophy** (or skip if "Regenerate sample only")
    Generate canvas-philosophy.md using:
    - canvas-philosophy-template.md from references
    - **Selected style constraints from style-constraints.md**
    - Brand colors and fonts from brand-philosophy.md
    - Platform-specific considerations (mobile-first)

    **Include the style's HARD LIMITS in the philosophy:**
    - Word count limits per card
    - Whitespace minimums
    - Element count limits
    - Layout directives
    - Anti-patterns to avoid

12. **Create/update template.md**
    Using template-structure.md from references:
    - Fill in purpose, content type, card structure
    - **Include selected style name and key constraints**
    - Add visual standards and Zen principles (carousel-adapted)
    - Include output configuration for platform

13. **Generate sample**
    Use the **canvas-design** skill:
    - Provide the canvas-philosophy.md content as the design philosophy input
    - **IMPORTANT**: Include the style constraints explicitly:
      - For Minimal: "ENFORCE: Max 8 words/card, 60% whitespace, centered layout"
      - For Dramatic: "ENFORCE: Max 12 words/card, 35% whitespace, asymmetrical layout"
      - For Organic: "ENFORCE: Max 10 words/card, 50% whitespace, organic flow"
    - Read the logo file from the path in brand-philosophy.md and incorporate it
    - **Generate ALL cards defined in template.md** (not just a subset)
    - Use placeholder/example content for each card type
    - Request output as multi-page PDF with platform dimensions:
      - LinkedIn: 1080x1350 (4:5 portrait)
      - Instagram Square: 1080x1080 (1:1)
      - Instagram Portrait: 1080x1350 (4:5)
    - Save as sample.pdf

14. **Save template**
    Save to `templates/carousels/{template-name}/`:
    - template.md
    - canvas-philosophy.md
    - sample.pdf

15. **Confirm completion**
    Show template location and sample preview
    Explain how to use: `/carousel` and select this template

## Output

- Created/Updated: `templates/carousels/{name}/template.md`
- Created/Updated: `templates/carousels/{name}/canvas-philosophy.md`
- Created/Updated: `templates/carousels/{name}/sample.pdf`
