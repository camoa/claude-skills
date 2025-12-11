---
description: Create or edit a carousel template through guided wizard
allowed-tools: Bash, Read, Write, Glob, AskUserQuestion, Skill
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
   - Sanitize name: lowercase, replace spaces with hyphens, remove special characters
   - **Validate name is unique**: Run `test -d "{PROJECT_PATH}/templates/carousels/{name}" && echo "exists"`
   - If "exists" returned: "A template named '{name}' already exists. Please choose a different name." (loop back to ask again)
   - Continue with step 5

   **If "Edit: {template-name}" selected → EDIT MODE:**
   - Load existing template.md and canvas-philosophy.md from `templates/carousels/{template-name}/`
   - Show current structure summary (platform, card sequence)

   **Step 4a: Ask what aspect to modify**
   Use AskUserQuestion:
   - Header: "Modify"
   - Question: "What would you like to modify?"
   - Options:
     - **Structure** - Add, remove, or reorder cards
     - **Visual style** - Change aesthetic, style, palette, or platform
     - **Regenerate sample** - Keep settings, regenerate sample file
     - **Start over** - Discard and create from scratch

   **Step 4b: If "Structure" selected, ask specific action**
   Use AskUserQuestion:
   - Header: "Structure"
   - Question: "What structure change?"
   - Options:
     - **Add cards** - Add new card types
     - **Remove cards** - Remove existing cards
     - **Reorder cards** - Change card sequence

   - Jump to appropriate step based on selection

5. **Ask design aesthetic FIRST** (CREATE MODE, or if changing style in EDIT MODE)

   **Step 5a: Choose aesthetic family**
   Use AskUserQuestion:
   - Header: "Aesthetic"
   - Question: "Which design aesthetic for this carousel?"
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
     - **Minimal** - Max whitespace, single focal, silence (data, technical)
     - **Dramatic** - Asymmetrical, bold contrast, tension (announcements, launches)
     - **Organic** - Natural flow, subtle depth, warmth (storytelling, education)
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

6. **Visual Components (style-dependent)** (CREATE MODE, or if changing style in EDIT MODE)

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
     - Minimal/Shibui: thin border only, no fill
     - Dramatic/Hygge/Memphis: solid fills allowed
     - Swiss: grid-aligned, precise borders
   - Corner radius: [8 | 16 | 24]px (suggest based on style)

   **For Icons (if selected):**
   - Ask: "What icon categories are relevant for this carousel?"
   - Show categories: business, growth, people, technology, communication, actions, time, documents, money, misc
   - User selects 2-4 relevant categories
   - Icon size: suggest 48px for cards, 32px for inline

   **For Gradients (if selected):**
   - Gradient direction: [diagonal | horizontal | vertical]
   - Gradient colors: primary → secondary (default) or custom pair
   - Intensity: based on style (subtle for Organic, bold for Dramatic/Memphis)

   **Store component selections** for use in canvas-philosophy.md generation.

7. **Ask color palette** (CREATE MODE, or if changing style in EDIT MODE)

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

8. **Ask carousel platform** (CREATE MODE, or if changing platform in EDIT MODE)
   Use AskUserQuestion:
   - "Which platform is this carousel for?"
   - Options: LinkedIn (4:5 portrait), Instagram (1:1 square), Instagram (4:5 portrait)

9. **Ask template purpose** (CREATE MODE only)
   Ask user directly (not AskUserQuestion):
   "What is this template for? (2-4 words)
   Examples: tips carousel, story series, data highlights, how-to guide, listicle, case study"

   User provides short description like "tips carousel" or "weekly insights"

10. **Load carousels guide**
    - Read plugin `references/carousels-guide.md` for card type options

11. **Ask card types needed** (or modify existing in EDIT MODE)
    Use AskUserQuestion:
    - "Which card types do you need?"
    - Multi-select from: Hook, Content, Data, Story, CTA
    - Allow custom additions
    - In EDIT MODE: Show current cards, allow add/remove

12. **Define card sequence**
    Based on purpose and selected types, propose a sequence:
    - Show proposed structure (5-10 cards)
    - Ask user to confirm or modify

13. **Create/update canvas philosophy** (or skip if "Regenerate sample only")
    Generate canvas-philosophy.md using:
    - canvas-philosophy-template.md from references
    - **Selected style constraints from style-constraints.md**
    - **Selected color palette** (brand colors or alternative palette from step 7)
    - **Text colors from palette** (`Text (light bg)` and `Text (dark bg)`)
    - **Visual component selections from step 6** (cards, icons, gradients)
    - Platform-specific considerations (mobile-first)

    **Include the style's HARD LIMITS in the philosophy:**
    - Word count limits per card
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

    **Include Visual Components section (if enabled in step 6):**
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

14. **Create/update template.md**
    Using template-structure.md from references:
    - Fill in purpose, content type, card structure
    - **Include selected style name and key constraints**
    - **Include selected palette name and colors**
    - **Include visual components configuration** (if enabled)
    - Add visual standards and Zen principles (carousel-adapted)
    - Include output configuration for platform

15. **Generate sample**
    Use the **visual-content** skill:
    - Provide the canvas-philosophy.md content as the design philosophy input
    - **IMPORTANT**: Include the style's Enforcement Block from `style-constraints.md`
    - Copy the exact enforcement block for the selected style (e.g., "STYLE: Minimal (Japanese Zen)...")
    - Use **selected palette colors** for all visual elements
    - **Load brand assets**:
      - Read logo file from brand-philosophy.md Brand Assets section
      - If logo is SVG, convert to PNG first (visual-content handles this)
      - Load fonts from `{PROJECT_PATH}/assets/fonts/` if present
    - **Apply visual components** (if enabled in step 6):
      - Use `scripts/icons.py` for icon rendering
      - Apply card patterns from `technical-implementation.md`
      - Use gradient functions for background treatment
    - **Generate ALL cards defined in template.md** (not just a subset)
    - Use placeholder/example content for each card type
    - Request output as multi-page PDF with platform dimensions:
      - LinkedIn: 1080x1350 (4:5 portrait)
      - Instagram Square: 1080x1080 (1:1)
      - Instagram Portrait: 1080x1350 (4:5)
    - Save as sample.pdf

16. **Save template**
    Save to `templates/carousels/{template-name}/`:
    - template.md
    - canvas-philosophy.md
    - sample.pdf

17. **Confirm completion**
    Show template location and sample preview
    Explain how to use: `/carousel` and select this template

## Output

- Created/Updated: `templates/carousels/{name}/template.md`
- Created/Updated: `templates/carousels/{name}/canvas-philosophy.md`
- Created/Updated: `templates/carousels/{name}/sample.pdf`
