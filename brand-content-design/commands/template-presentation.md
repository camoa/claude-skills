---
description: Create or edit a presentation template through guided wizard. Use when user says "create presentation template", "new slide template", "presentation template wizard", "edit template".
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

   **Step 4a: Ask what aspect to modify**
   Use AskUserQuestion:
   - Header: "Modify"
   - Question: "What would you like to modify?"
   - Options:
     - **Structure** - Add, remove, or reorder slides
     - **Visual style** - Change aesthetic family, style, or palette
     - **Regenerate samples** - Keep settings, regenerate sample files
     - **Start over** - Discard and create from scratch

   **Step 4b: If "Structure" selected, ask specific action**
   Use AskUserQuestion:
   - Header: "Structure"
   - Question: "What structure change?"
   - Options:
     - **Add slides** - Add new slide types
     - **Remove slides** - Remove existing slides
     - **Reorder slides** - Change slide sequence

   - Jump to appropriate step based on selection

5. **Ask template purpose** (CREATE MODE only)
   Ask user directly (not AskUserQuestion):
   "What is this template for? (2-4 words)
   Examples: sales pitch, product demo, quarterly update, team training, investor deck, tech overview"

   User provides short description like "sales pitch" or "product launch"

5b. **Ask audience** (CREATE MODE only)
   Use AskUserQuestion:
   - Header: "Audience"
   - Question: "Who is the primary audience for this presentation?"
   - Options:
     - **C-suite / Board** - Executive leadership, board members
     - **Technical** - Engineers, developers, technical staff
     - **General** - All-hands, mixed audiences
     - **More audiences...** - See additional options

   *If "More audiences..." selected:*
   - Header: "Audience"
   - Question: "Which audience?"
   - Options:
     - **Creative** - Designers, creatives, marketing
     - **Investors** - VCs, angel investors, fundraising
     - **Customers / External** - Clients, prospects, partners

6. **Style recommendation** (CREATE MODE, or if changing style in EDIT MODE)

   Load `references/style-recommendation-engine.md` and run the scoring algorithm:

   **Step 6a: Extract brand personality**
   - Read voice traits from brand-philosophy.md
   - Map to Aaker dimensions using the engine's Section 1

   **Step 6b: Score all 18 styles**
   - Brand match: from Section 2 (Aaker → Style Affinity)
   - Purpose match: from Section 3 (using purpose from step 5)
   - Audience adjustment: from Section 4 (using audience from step 5b)
   - Calculate total score per style

   **Step 6c: Present top 3 recommendations**
   Use AskUserQuestion:
   - Header: "Style"
   - Question: "Based on your brand, purpose, and audience, here are the recommended styles:"
   - Options (build dynamically from top 3 scores):
     - **{Style 1}** - {reasoning sentence from engine}
     - **{Style 2}** - {reasoning sentence from engine}
     - **{Style 3}** - {reasoning sentence from engine}
     - **Browse all 18 styles** - See the full style catalog

   **If "Browse all 18 styles" selected:**
   Fall back to the existing family → style selection flow (Step 6d below).

   **Step 6d: Manual style selection (fallback)**
   Same as the existing step 5 flow — choose aesthetic family first, then specific style.

   **Load style constraints** from plugin `references/style-constraints.md` for the selected style.

   **Step 6d-a: Choose aesthetic family**
   Use AskUserQuestion (split into 2 questions due to 5 families):

   *Question 1:*
   - Header: "Aesthetic"
   - Question: "Which design aesthetic for this template? (1/2)"
   - Options:
     - **Japanese Zen** - Restraint, intentionality, essence (7 styles)
     - **Scandinavian Nordic** - Warmth, balance, functionality (2 styles)
     - **European Modernist** - Precision or playfulness (2 styles)
     - **More families...** - See additional options

   *Question 2 (if "More families..." selected):*
   - Header: "Aesthetic"
   - Question: "Which design aesthetic? (2/2)"
   - Options:
     - **East Asian Harmony** - Space, balance, energy (2 styles)
     - **Contemporary Professional** - Clean, data-aware, business-forward (5 styles)

   **Step 6d-b: Choose specific style** (based on family selected)
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

   **Contemporary Professional** (5 styles - split into 2 questions due to 5 styles):

   *Question 1:*
   - Header: "Style"
   - Question: "Which Contemporary Professional style? (1/2)"
   - Options:
     - **Tech-Modern** - Clean, systematic, data-aware (SaaS, product demos)
     - **Data-Forward** - Numbers as visual anchors (quarterly reviews, analytics)
     - **Corporate-Confident** - Authoritative, polished, trustworthy (board, company comms)
     - **More styles...** - See additional options

   *Question 2 (if "More styles..." selected):*
   - Header: "Style"
   - Question: "Which Contemporary Professional style? (2/2)"
   - Options:
     - **Pitch-Velocity** - High-energy, momentum-driven (fundraising, sales pitches)
     - **Narrative-Clean** - Story-driven, editorial clarity (case studies, thought leadership)

   **Load style constraints** from plugin `references/style-constraints.md` for the selected style.

7. **Visual Components (style-dependent)** (CREATE MODE, or if changing style in EDIT MODE)

   After selecting a style, check `references/style-constraints.md` for which visual components the style supports:
   - **Cards**: ✓ Full, ◐ Subtle only, ✗ None
   - **Icons**: ✓ Allowed, ✗ Not allowed
   - **Gradients**: ✓ Allowed, ✗ Not allowed

   **Skip this step entirely** for styles that don't support ANY visual components (Ma, Yeo-baek).

   **If style supports at least one component type:**

   Use AskUserQuestion:
   - Header: "Components"
   - Question: "Enable visual components for this template?"
   - Options (build dynamically based on style support):
     - **Yes, with cards** - Use rounded card containers (if style supports cards)
     - **Yes, with icons** - Use Lucide icons (if style supports icons)
     - **Yes, with gradient** - Use gradient backgrounds (if style supports gradients)
     - **No components** - Keep it simple, text and images only

   Note: User can select multiple options since multiSelect: true.

   **If any visual components enabled, ask follow-up:**

   **For Cards (if selected):**
   - Card style: based on selected aesthetic
     - Minimal/Shibui/Narrative-Clean: thin border only, no fill
     - Dramatic/Hygge/Memphis/Pitch-Velocity: solid fills allowed
     - Swiss/Tech-Modern: grid-aligned, precise borders
     - Data-Forward: stat cards (large number + label)
     - Corporate-Confident: clean borders, white fills
   - Corner radius: [8 | 16 | 24]px (suggest based on style)

   **For Icons (if selected):**
   - Ask: "What icon categories are relevant for this presentation?"
   - Show categories: business, growth, people, technology, communication, actions, time, documents, money, misc
   - User selects 2-4 relevant categories
   - Icon size: suggest 64px for slides, 48px for cards

   **For Gradients (if selected):**
   - Gradient direction: [diagonal | horizontal | vertical]
   - Gradient colors: primary → secondary (default) or custom pair
   - Intensity: based on style (subtle for Organic, bold for Dramatic/Memphis)

   **Store component selections** for use in canvas-philosophy.md generation.

8. **Ask color palette** (CREATE MODE, or if changing style in EDIT MODE)

   First, check brand-philosophy.md for `## Alternative Palettes` section.
   Count total palettes available (1 brand + N alternatives).

   **For each palette, extract:**
   - Shape/accent colors (Primary, Secondary, Accent, etc.)
   - `Text (light bg)`: Color for text on light backgrounds
   - `Text (dark bg)`: Color for text on dark backgrounds

   If a palette doesn't have text colors (legacy format), calculate them using the contrast algorithm from `/brand-palette` step 10.

   **If 4 or fewer total palettes:** Use AskUserQuestion
   - Header: "Palette"
   - Question: "Which color palette for this template?"
   - Options (build dynamically, 2-4 options):
     - **Brand colors** - Use original brand palette
     - **{Alternative 1}** - Name from Alternative Palettes section
     - (add more if available, up to 4 total)

   **If more than 4 total palettes:** Use conversational list
   Display all palettes with numbers:
   ```
   Available palettes:
   1. Brand colors (original) - Text: ✓
   2. {Palette Name} ({Type}) - Text: ✓
   3. {Palette Name} ({Type}) - Text: ⚠️ derived
   ... (list all)

   Enter the number or name of the palette to use:
   ```
   Parse user response (number or name match).

   **Store selected palette** including text colors for use in canvas-philosophy.md generation.

9. **Load presentations guide**
   - Read plugin `references/presentations-guide.md` for slide type options

10. **Ask slide types needed** (or modify existing in EDIT MODE)
    Use AskUserQuestion:
    - "Which slide types do you need?"
    - Multi-select from: Title, Content, Image, Data/Chart, Quote, CTA, Transition
    - Allow custom additions
    - In EDIT MODE: Show current slides, allow add/remove

11. **Define slide sequence**
    Based on purpose and selected types, propose a sequence:
    - Show proposed structure
    - Ask user to confirm or modify

12. **Create/update canvas philosophy** (or skip if "Regenerate samples only")
    Generate canvas-philosophy.md using:
    - canvas-philosophy-template.md from references
    - **Selected style constraints from style-constraints.md**
    - **Selected color palette** (brand colors or alternative palette from step 8)
    - **Text colors from palette** (`Text (light bg)` and `Text (dark bg)`)
    - **Visual component selections from step 7** (cards, icons, gradients)

    **Include the style's HARD LIMITS in the philosophy:**
    - Word count limits per slide
    - Whitespace minimums
    - Element count limits
    - Layout directives
    - Anti-patterns to avoid

    **Include text color guidance:**
    ```
    ## Text Colors (from palette contrast analysis)
    - Light backgrounds: Use {Text (light bg)} for all text
    - Dark backgrounds: Use {Text (dark bg)} for all text
    - Description/secondary text: Use text color at 70% opacity
    ```

    **Include Visual Components section (if enabled in step 7):**
    ```
    ## Visual Components

    ### Card System
    - Card style: {selected style}
    - Corner radius: {selected radius}px
    - Fill approach: {selected approach}

    ### Icon Usage
    - Icon categories: {selected categories}
    - Icon size: {selected size}px
    - Icon color: {primary | secondary | accent}

    ### Background Treatment
    - Gradient: {direction}, {color1} → {color2}
    - Intensity: {subtle | moderate | bold}
    ```

    **Include Composition Rules section (populated from slide-composition-rules.md):**
    - Read `references/slide-composition-rules.md`
    - Look up the selected style in Section 3 (Style-Aware Layout Modifiers)
    - Apply the style's modifier to base positions from Section 2
    - Set grid system, headline zone, supporting zone based on style
    - Set component frequency limits from Section 4 (adapted for total slide count)
    - Set image treatment from Section 5
    - Write the adapted rules into the Composition Rules section of canvas-philosophy.md

13. **Create/update template.md**
    Using template-structure.md from references:
    - Fill in purpose, content type, slide structure
    - **Include selected style name and key constraints**
    - **Include selected palette name and colors**
    - **Include visual components configuration** (if enabled)
    - Add visual standards and Zen principles
    - Include output configuration

14. **Generate sample PDF**
    Use the **visual-content** skill:
    - Provide the canvas-philosophy.md content as the design philosophy input
    - **IMPORTANT**: Include the style's Enforcement Block from `style-constraints.md`
    - Copy the exact enforcement block for the selected style (e.g., "STYLE: Minimal (Japanese Zen)...")
    - **Load brand assets**:
      - Read logo file from brand-philosophy.md Brand Assets section
      - If logo is SVG, convert to PNG first (visual-content handles this)
      - Load fonts from `{PROJECT_PATH}/assets/fonts/`
      - **If no font files found**: STOP and warn — do not silently fall back to system fonts
    - **Apply Brand Anchors** (from canvas-philosophy-template.md):
      - Logo on every slide (bottom-right, subtle, max 150px)
      - Primary brand color as accent on every slide
      - Brand heading font (mandatory — no fallback)
    - **Apply visual components** (if enabled in step 7):
      - Use `scripts/icons.py` for icon rendering
      - Apply card patterns from `technical-implementation.md`
      - Use gradient functions for background treatment
    - **Generate ALL slides defined in template.md** (not just a subset)
    - Use placeholder/example content for each slide type
    - Request output as PDF at 1920x1080 (16:9)
    - Save as sample.pdf

15. **Generate sample PPTX**
    Use the **pptx** skill:
    - Create an editable PowerPoint version matching the full template structure
    - Include the logo from assets/
    - Set up slide masters with **selected palette colors**
    - **Create ALL slides defined in template.md** with placeholder content
    - Save as sample.pptx

16. **Save template**
    Save to `templates/presentations/{template-name}/`:
    - template.md
    - canvas-philosophy.md
    - sample.pdf
    - sample.pptx

17. **Confirm completion**
    Show template location and sample preview
    Explain how to use: `/presentation` and select this template

## Output

- Created: `templates/presentations/{name}/template.md`
- Created: `templates/presentations/{name}/canvas-philosophy.md`
- Created: `templates/presentations/{name}/sample.pdf`
- Created: `templates/presentations/{name}/sample.pptx`
