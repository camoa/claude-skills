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

3. **Show current colors and existing palettes**
   Display current brand colors with color boxes:
   ```bash
   echo -e "\033[48;2;R;G;Bm     \033[0m #HEX - Color Name"
   ```

   If `## Alternative Palettes` section exists in brand-philosophy.md:
   - Also display saved palettes with color boxes
   - Note: "You have X saved palettes"

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

5. **Ask source color(s)**
    Display brand colors with numbers:
    ```
    Your brand colors:
    [1] ██ #2563EB - Primary (Blue)
    [2] ██ #10B981 - Secondary (Green)
    [3] ██ #F59E0B - Accent (Amber)
    ```

    Use AskUserQuestion:
    - Header: "Source"
    - Question: "Which color(s) to derive palettes from?"
    - Options:
      - **Primary only** - Generate from your main brand color
      - **All brand colors** - Generate from each color, combine results
      - **Pick specific** - Choose which colors to use

    **If "Pick specific" selected:**
    Ask: "Enter color numbers (e.g., 1,3 for Primary and Accent):"

6. **Ask harmony type**
    Use AskUserQuestion with multiSelect: true
    - Header: "Harmony"
    - Question: "Which harmony palettes? (1/2)"
    - Options:
      - **Monochromatic** - Same hue, varying lightness (safe, cohesive)
      - **Analogous** - Adjacent colors on wheel (harmonious)
      - **Complementary** - Opposite colors (high contrast)
      - **More harmonies...** - See advanced options

7. **If "More harmonies..." selected, ask advanced**
    Use AskUserQuestion with multiSelect: true
    - Header: "Advanced"
    - Question: "Which advanced harmony palettes? (2/2)"
    - Options:
      - **Split-Complementary** - Contrast with less tension
      - **Triadic** - Three balanced colors (vibrant)
      - **Tetradic** - Four colors in rectangle (complex)

8. **Ask tonal variations**
    Use AskUserQuestion with multiSelect: true
    - Header: "Tonal"
    - Question: "Which tonal variations?"
    - Options:
      - **Tints** - Lighter variations (soft backgrounds)
      - **Shades** - Darker variations (bold emphasis)
      - **Tones** - Muted with gray (sophisticated)
      - **Interpolation** - Gradients between source colors

9. **Generate derived palettes**
    For each selected source color, apply selected harmony/tonal types:

    **Harmony calculations (from color wheel):**
    - Monochromatic: Same hue, lightness at 30%, 50%, 70%, 90%
    - Analogous: Source ± 30° on wheel
    - Complementary: Source + 180°
    - Split-Complementary: Source + 150°, Source + 210°
    - Triadic: Source + 120°, Source + 240°
    - Tetradic: Source + 90°, Source + 180°, Source + 270°

    **Tonal calculations:**
    - Tints: Mix source with white at 25%, 50%, 75%
    - Shades: Mix source with black at 25%, 50%, 75%
    - Tones: Mix source with gray at 25%, 50%, 75%
    - Interpolation: Blend between selected source colors at 25%, 50%, 75%

    **If multiple source colors selected:**
    - Generate palette for each source color
    - Label results: "Complementary (from Primary)", "Complementary (from Secondary)"
    - Remove duplicates if colors are very similar (< 5% difference)

    → Continue to step 10

---

## ALTERNATIVE BRANCH (Mood-Based)

If user selected "Alternative":

5. **Ask mood style**
    Use AskUserQuestion with multiSelect: true
    - Header: "Mood"
    - Question: "Which mood palettes? (1/2)"
    - Options:
      - **Pastel** - Soft, light, airy (gentle campaigns)
      - **Bold** - High saturation, strong contrast (impact)
      - **Earthy** - Natural, warm, grounded (sustainable)
      - **More moods...** - See additional options

6. **If "More moods..." selected, ask additional**
    Use AskUserQuestion with multiSelect: true
    - Header: "Mood"
    - Question: "Which mood palettes? (2/2)"
    - Options:
      - **Vibrant** - Bright, energetic (youth, excitement)
      - **Muted** - Desaturated, refined (luxury, sophistication)
      - **Monochrome** - Grayscale + one accent (editorial, dramatic)
      - **Custom** - Describe what you need

7. **If Custom selected, ask for description**
    Ask: "Describe the mood or purpose for your custom palette:"
    Examples: "summer festival", "winter elegance", "tech startup energy"

8. **Generate alternative palettes**
    For each selected mood, use the **full brand palette** as reference:

    1. **Analyze brand personality** from brand-philosophy.md
       - What emotions does the current palette evoke?
       - What's the brand energy level (calm, energetic, sophisticated)?
       - How many colors in the palette? (primary, secondary, accent, neutrals)
       - What are the color relationships? (warm/cool, high/low contrast)

    2. **Generate mood-matched colors for EACH brand color**
       Transform each brand color to the target mood:
       - Pastel: Lighten + desaturate each brand color
       - Bold: Increase saturation + contrast for each color
       - Earthy: Map each color to nearest natural equivalent
       - Vibrant: Shift each color toward bright, saturated version
       - Muted: Desaturate each color while maintaining hue relationships
       - Monochrome: Convert all to grayscale, keep primary as accent
       - Custom: Interpret description, transform entire palette

    3. **Preserve brand characteristics**
       - Maintain same number of colors (3-color brand = 3-color alternative)
       - Keep relative contrast between colors
       - Preserve warm/cool balance
       - Maintain hierarchy (primary still dominant, accent still pop)

    → Continue to step 10

---

## COMMON STEPS (Both Branches)

10. **Display generated palettes**
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

11. **Ask to save**
    Use AskUserQuestion:
    - Header: "Save"
    - Question: "Save these palettes to brand-philosophy.md?"
    - Options:
      - **Yes, save all** - Add all generated palettes
      - **No, don't save** - Just view them for now

    If user wants specific palettes, they can run `/brand-palette` again with more specific selections.

12. **If saving and Custom palette exists, ask for name**
    Ask: "What should we call the custom palette?" (e.g., "Summer Festival", "Q4 Launch")

13. **Save palettes (if Yes)**
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

14. **Confirm and suggest usage**
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
