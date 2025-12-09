---
description: Create or edit a presentation template through guided wizard
allowed-tools: Bash, Read, Write, Glob, AskUserQuestion, Skill
---

# Template Presentation Command

Create a new presentation template or edit an existing one.

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
   - Run `find {PROJECT_PATH}/templates/presentations -name "template.md" 2>/dev/null`
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
   - Ask: "What name do you want for this template? (e.g., sales-pitch-enterprise, tech-demo-short, quarterly-update)"
   - Sanitize name: lowercase, replace spaces with hyphens, remove special characters
   - **Validate name is unique**: Run `test -d "{PROJECT_PATH}/templates/presentations/{name}" && echo "exists"`
   - If "exists" returned: "A template named '{name}' already exists. Please choose a different name." (loop back to ask again)
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

5. **Ask design aesthetic FIRST** (CREATE MODE, or if changing style in EDIT MODE)

   **Step 5a: Choose aesthetic family**
   Use AskUserQuestion:
   - Header: "Aesthetic"
   - Question: "Which design aesthetic for this template?"
   - Options:
     - **Japanese Zen** - Restraint, intentionality, essence (7 styles)
     - **Scandinavian Nordic** - Warmth, balance, functionality (2 styles)
     - **European Modernist** - Precision or playfulness (2 styles)
     - **East Asian Harmony** - Space, balance, energy (2 styles)

   **Step 5b: Choose specific style** (based on family selected)
   Use AskUserQuestion - options vary by family (max 4 options per question):

   **Japanese Zen** (split into 2 questions due to 7 styles):

   *Question 1:*
   - Header: "Style"
   - Question: "Which Japanese Zen style? (1/2)"
   - Options:
     - **Minimal** - Max whitespace, single focal, silence (executive, data)
     - **Dramatic** - Asymmetrical, bold contrast, tension (pitch decks)
     - **Organic** - Natural flow, subtle depth, warmth (storytelling)
     - **More styles...** - See additional options

   *Question 2 (if "More styles..." selected):*
   - Header: "Style"
   - Question: "Which Japanese Zen style? (2/2)"
   - Options:
     - **Wabi-Sabi** - Imperfect beauty, texture, handcraft (artisan, craft)
     - **Shibui** - Quiet elegance, ultra-refined (luxury, professional)
     - **Iki** - B&W + pop color, editorial confidence (fashion, editorial)
     - **Ma** - 70%+ whitespace, floating elements (meditation, luxury)

   **Scandinavian Nordic** (2 styles - single question):
   - Header: "Style"
   - Question: "Which Scandinavian style?"
   - Options:
     - **Hygge** - Warm, cozy, inviting (wellness, community)
     - **Lagom** - Balanced "just enough" (corporate, sustainability)

   **European Modernist** (2 styles - single question):
   - Header: "Style"
   - Question: "Which European Modernist style?"
   - Options:
     - **Swiss** - Strict grid, mathematical precision (tech, corporate)
     - **Memphis** - Bold colors, playful chaos (creative, youth)

   **East Asian Harmony** (2 styles - single question):
   - Header: "Style"
   - Question: "Which East Asian style?"
   - Options:
     - **Yeo-baek** - Extreme emptiness, Korean purity (premium, meditation)
     - **Feng Shui** - Yin-Yang balance, energy flow (wellness, harmony)

   **Load style constraints** from plugin `references/style-constraints.md` for the selected style.

6. **Ask template purpose** (CREATE MODE only)
   Use AskUserQuestion:
   - "What is this presentation template for?"
   - Options: Technical/Product, Sales/Pitch, Educational/Training, Other (describe)

7. **Load presentations guide**
   - Read plugin `references/presentations-guide.md` for slide type options

8. **Ask slide types needed** (or modify existing in EDIT MODE)
   Use AskUserQuestion:
   - "Which slide types do you need?"
   - Multi-select from: Title, Content, Image, Data/Chart, Quote, CTA, Transition
   - Allow custom additions
   - In EDIT MODE: Show current slides, allow add/remove

9. **Define slide sequence**
   Based on purpose and selected types, propose a sequence:
   - Show proposed structure
   - Ask user to confirm or modify

10. **Create/update canvas philosophy** (or skip if "Regenerate samples only")
    Generate canvas-philosophy.md using:
    - canvas-philosophy-template.md from references
    - **Selected style constraints from style-constraints.md**
    - Brand colors and fonts from brand-philosophy.md

    **Include the style's HARD LIMITS in the philosophy:**
    - Word count limits per slide
    - Whitespace minimums
    - Element count limits
    - Layout directives
    - Anti-patterns to avoid

11. **Create/update template.md**
    Using template-structure.md from references:
    - Fill in purpose, content type, slide structure
    - **Include selected style name and key constraints**
    - Add visual standards and Zen principles
    - Include output configuration

12. **Generate sample PDF**
    Use the **canvas-design** skill:
    - Provide the canvas-philosophy.md content as the design philosophy input
    - **IMPORTANT**: Include the style's Enforcement Block from `style-constraints.md`
    - Copy the exact enforcement block for the selected style (e.g., "STYLE: Minimal (Japanese Zen)...")
    - Read the logo file from the path in brand-philosophy.md and incorporate it
    - **Generate ALL slides defined in template.md** (not just a subset)
    - Use placeholder/example content for each slide type
    - Request output as PDF at 1920x1080 (16:9)
    - Save as sample.pdf

13. **Generate sample PPTX**
    Use the **pptx** skill:
    - Create an editable PowerPoint version matching the full template structure
    - Include the logo from assets/
    - Set up slide masters with brand colors and fonts
    - **Create ALL slides defined in template.md** with placeholder content
    - Save as sample.pptx

14. **Save template**
    Save to `templates/presentations/{template-name}/`:
    - template.md
    - canvas-philosophy.md
    - sample.pdf
    - sample.pptx

15. **Confirm completion**
    Show template location and sample preview
    Explain how to use: `/presentation` and select this template

## Output

- Created: `templates/presentations/{name}/template.md`
- Created: `templates/presentations/{name}/canvas-philosophy.md`
- Created: `templates/presentations/{name}/sample.pdf`
- Created: `templates/presentations/{name}/sample.pptx`
