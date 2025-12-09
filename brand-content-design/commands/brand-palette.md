---
description: Generate alternative color palettes from brand colors
allowed-tools: Read, Write, Glob, Bash, AskUserQuestion
---

# Brand Palette Command

Generate alternative color palettes - either derived from brand colors (color theory) or completely different colors with the same brand feeling (mood-based).

## Prerequisites

- Must be in a brand project folder (contains brand-philosophy.md)
- brand-philosophy.md must have colors defined

## Workflow

1. **Find project (PROJECT_PATH)**
   - Check `./brand-philosophy.md`, then `../brand-philosophy.md`
   - If not found: Tell user to run `/brand-init` first and stop
   - **Set PROJECT_PATH** = directory containing brand-philosophy.md

2. **Extract brand colors**
   - Read brand-philosophy.md
   - Find all colors: primary, secondary, accent, neutrals
   - If no colors found: Tell user to run `/brand-extract` first and stop

3. **Show current colors**
   Display current brand colors with color boxes:
   ```bash
   echo -e "\033[48;2;R;G;Bm     \033[0m #HEX - Color Name"
   ```

4. **Ask palette category (branching question)**
   Use AskUserQuestion:
   - Header: "Category"
   - Question: "What type of palette do you want?"
   - Options:
     - **Derived** - Colors mathematically related to your brand (harmonies, tints)
     - **Alternative** - Completely different colors, same brand feeling

---

## DERIVED BRANCH (Color Theory)

If user selected "Derived":

5a. **Ask harmony type**
    Use AskUserQuestion with multiSelect: true
    - Header: "Harmony"
    - Question: "Which harmony palettes? (1/2)"
    - Options:
      - **Monochromatic** - Same hue, varying lightness (safe, cohesive)
      - **Analogous** - Adjacent colors on wheel (harmonious)
      - **Complementary** - Opposite colors (high contrast)
      - **More harmonies...** - See advanced options

6a. **If "More harmonies..." selected, ask advanced**
    Use AskUserQuestion with multiSelect: true
    - Header: "Advanced"
    - Question: "Which advanced harmony palettes? (2/2)"
    - Options:
      - **Split-Complementary** - Contrast with less tension
      - **Triadic** - Three balanced colors (vibrant)
      - **Tetradic** - Four colors in rectangle (complex)
      - **Extended Harmony** - Harmonies from all brand colors merged

7a. **Ask tonal variations**
    Use AskUserQuestion with multiSelect: true
    - Header: "Tonal"
    - Question: "Which tonal variations?"
    - Options:
      - **Tints** - Lighter variations (soft backgrounds)
      - **Shades** - Darker variations (bold emphasis)
      - **Tones** - Muted with gray (sophisticated)
      - **Interpolation** - Gradients between brand colors

8a. **Generate derived palettes**
    For each selected type, calculate colors from brand palette:

    **Harmony calculations (from color wheel):**
    - Monochromatic: Same hue, lightness at 30%, 50%, 70%, 90%
    - Analogous: Primary ± 30° on wheel
    - Complementary: Primary + 180°
    - Split-Complementary: Primary + 150°, Primary + 210°
    - Triadic: Primary + 120°, Primary + 240°
    - Tetradic: Primary + 90°, Primary + 180°, Primary + 270°
    - Extended Harmony: Apply Triadic to each brand color, merge unique results

    **Tonal calculations:**
    - Tints: Mix with white at 25%, 50%, 75%
    - Shades: Mix with black at 25%, 50%, 75%
    - Tones: Mix with gray at 25%, 50%, 75%
    - Interpolation: Blend primary → secondary at 25%, 50%, 75%

    → Continue to step 9

---

## ALTERNATIVE BRANCH (Mood-Based)

If user selected "Alternative":

5b. **Ask mood style**
    Use AskUserQuestion with multiSelect: true
    - Header: "Mood"
    - Question: "Which mood palettes? (1/2)"
    - Options:
      - **Pastel** - Soft, light, airy (gentle campaigns)
      - **Bold** - High saturation, strong contrast (impact)
      - **Earthy** - Natural, warm, grounded (sustainable)
      - **More moods...** - See additional options

6b. **If "More moods..." selected, ask additional**
    Use AskUserQuestion with multiSelect: true
    - Header: "Mood"
    - Question: "Which mood palettes? (2/2)"
    - Options:
      - **Vibrant** - Bright, energetic (youth, excitement)
      - **Muted** - Desaturated, refined (luxury, sophistication)
      - **Monochrome** - Grayscale + one accent (editorial, dramatic)
      - **Custom** - Describe what you need

7b. **If Custom selected, ask for description**
    Ask: "Describe the mood or purpose for your custom palette:"
    Examples: "summer festival", "winter elegance", "tech startup energy"

8b. **Generate alternative palettes**
    For each selected mood:

    1. **Analyze brand personality** from brand-philosophy.md
       - What emotions does the current palette evoke?
       - What's the brand energy level (calm, energetic, sophisticated)?

    2. **Generate mood-matched colors**
       - Pastel: Light, desaturated versions maintaining brand feeling
       - Bold: High saturation, strong contrast, same energy
       - Earthy: Map to natural palette (browns, greens, terracotta)
       - Vibrant: Bright, saturated alternatives
       - Muted: Desaturated, sophisticated versions
       - Monochrome: Convert to grayscale, keep one brand accent
       - Custom: Interpret description, maintain brand relationships

    3. **Preserve brand characteristics**
       - If brand has high contrast, maintain in alternative
       - If brand is warm, keep warmth in new palette
       - Match number of colors (3-color brand = 3-color alternative)

    → Continue to step 9

---

## COMMON STEPS (Both Branches)

9. **Display generated palettes**
   Show each palette with color boxes:
   ```
   Generated palettes:

   ██ ██ ██ ██  Complementary (Derived)    #1E40AF #2563EB #EB8225 #F59E0B
   ██ ██ ██     Pastel (Alternative)       #E0E7FF #FCE7F3 #D1FAE5
   ```

   Use Bash with ANSI codes:
   ```bash
   echo -e "\033[48;2;37;99;235m  \033[0m \033[48;2;235;130;37m  \033[0m  Complementary   #2563EB #EB8225"
   ```

10. **Ask to save (multi-select)**
    Use AskUserQuestion with multiSelect: true
    - Header: "Save"
    - Question: "Which palettes would you like to save?"
    - Options: List each generated palette by name

11. **Ask for custom names (if saving Custom)**
    If Custom palette is being saved:
    Ask: "What should we call this palette?" (e.g., "Summer Festival", "Q4 Launch")

12. **Save selected palettes**
    Append to brand-philosophy.md under `## Alternative Palettes`:

    ```markdown
    ## Alternative Palettes

    ### Complementary (Derived)
    - Primary: #2563EB
    - Complement: #EB8225
    - Accent: #F59E0B

    ### Pastel (Alternative)
    - Base: #E0E7FF
    - Secondary: #FCE7F3
    - Accent: #D1FAE5

    ### Summer Festival (Custom)
    - Base: #F59E0B
    - Secondary: #10B981
    - Accent: #EC4899
    ```

13. **Confirm and suggest usage**
    Show:
    - "Saved X palettes to brand-philosophy.md"
    - "Use these when creating content:"
    - "  - `/presentation` or `/carousel` will ask which palette to use"
    - "  - Or specify in your content brief"

## Output

- Updated: `brand-philosophy.md` with Alternative Palettes section
- Terminal display of generated palettes with color boxes

## Reference

See `references/color-palettes.md` for:
- Full list of 18 palette types
- Decision guide for which to use
- Calculation formulas
- Storage format

## Notes

- Multiple palettes can be selected and saved
- Custom palettes need a name for saving
- Derived palettes use mathematical color theory
- Alternative palettes maintain brand feeling with different colors
- Content commands can reference saved palettes
