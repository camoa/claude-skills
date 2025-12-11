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

6. **Ask harmony type (1/2)**
    Use AskUserQuestion with multiSelect: true
    - Header: "Harmony"
    - Question: "Which harmony palettes? (1/2)"
    - Options:
      - **Monochromatic** - Same hue, varying lightness (safe, cohesive)
      - **Analogous** - Adjacent colors on wheel (harmonious)
      - **Complementary** - Opposite colors (high contrast)
      - **Split-Complementary** - Contrast with less tension

7. **Ask harmony type (2/2)**
    Use AskUserQuestion with multiSelect: true
    - Header: "Harmony"
    - Question: "Which harmony palettes? (2/2)"
    - Options:
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

5. **Ask mood style (1/2)** - ALWAYS ASK
    Use AskUserQuestion with multiSelect: true
    - Header: "Mood"
    - Question: "Which mood palettes? (1/2)"
    - Options:
      - **Pastel** - Soft, light, airy (gentle campaigns)
      - **Bold** - High saturation, strong contrast (impact)
      - **Earthy** - Natural, warm, grounded (sustainable)
      - **Vibrant** - Bright, energetic (youth, excitement)

6. **Ask mood style (2/2)** - ALWAYS ASK (immediately after step 5)
    Use AskUserQuestion with multiSelect: true
    - Header: "Mood"
    - Question: "Which mood palettes? (2/2)"
    - Options:
      - **Muted** - Desaturated, refined (luxury, sophistication)
      - **Monochrome** - Grayscale + one accent (editorial, dramatic)
      - **Custom** - Describe what you need

7. **If Custom selected in step 5 or 6, ask for description**
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

10. **Validate contrast and generate text colors**

    For each generated palette, ensure it has usable text colors:

    **Contrast Analysis Algorithm:**
    ```
    1. Calculate luminance for each color:
       L = 0.299*R + 0.587*G + 0.114*B (where RGB are 0-255)
       Normalize: L = L / 255

    2. Find darkest color (lowest L) and lightest color (highest L)

    3. Calculate contrast ratio (CR):
       CR = (L_light + 0.05) / (L_dark + 0.05)

    4. Determine text colors:
       - Text (light bg): Need color with CR ≥ 4.5 against white (#FFFFFF, L=1.0)
         → Use darkest palette color if CR ≥ 4.5
         → Otherwise, darken it until CR ≥ 4.5 (reduce L by 10% increments)
         → Fallback: #1E293B (near black)

       - Text (dark bg): Need color with CR ≥ 4.5 against black (#000000, L=0)
         → Use lightest palette color if CR ≥ 4.5
         → Otherwise, lighten it until CR ≥ 4.5 (increase L by 10% increments)
         → Fallback: #F8FAFC (near white)
    ```

    **Add text colors to each palette:**
    - `Text (light bg)`: Color safe for text on light/white backgrounds
    - `Text (dark bg)`: Color safe for text on dark/black backgrounds

    If a palette needed adjustment (no original color had sufficient contrast):
    - Display: "⚠️ Added contrast-safe text colors for accessibility"

11. **Display generated palettes**
   Show each palette with color boxes including text colors:
   ```
   Generated palettes:

   ██ ██ ██ ██  Complementary (Derived)    #1E40AF #2563EB #EB8225 #F59E0B
                Text: #1E40AF (light bg) | #F59E0B (dark bg)

   ██ ██ ██     Pastel (Alternative)       #E0E7FF #FCE7F3 #D1FAE5
                Text: #1E293B (light bg) ⚠️ | #F8FAFC (dark bg)
   ```

   The ⚠️ indicates the text color was derived (not from original palette).

   Use Bash with ANSI codes:
   ```bash
   echo -e "\033[48;2;37;99;235m  \033[0m \033[48;2;235;130;37m  \033[0m  Complementary   #2563EB #EB8225"
   ```

12. **Ask to save**
    Use AskUserQuestion:
    - Header: "Save"
    - Question: "Save these palettes to brand-philosophy.md?"
    - Options:
      - **Yes, save all** - Add all generated palettes
      - **No, don't save** - Just view them for now

    If user wants specific palettes, they can run `/brand-palette` again with more specific selections.

13. **If saving and Custom palette exists, ask for name**
    Ask: "What should we call the custom palette?" (e.g., "Summer Festival", "Q4 Launch")

14. **Save palettes (if Yes)**
    Append to brand-philosophy.md under `## Alternative Palettes`:

    ```markdown
    ## Alternative Palettes

    ### Complementary (Derived)
    - Primary: #2563EB
    - Complement: #EB8225
    - Accent: #F59E0B
    - Text (light bg): #1E40AF
    - Text (dark bg): #F59E0B

    ### Pastel (Alternative)
    - Base: #E0E7FF
    - Secondary: #FCE7F3
    - Accent: #D1FAE5
    - Text (light bg): #1E293B ⚠️
    - Text (dark bg): #F8FAFC

    ### Summer Festival (Custom)
    - Base: #F59E0B
    - Secondary: #10B981
    - Accent: #EC4899
    - Text (light bg): #065F46
    - Text (dark bg): #F59E0B
    ```

    **Note:** ⚠️ indicates text color was derived (not from original palette colors).

15. **Confirm and suggest usage**
    Show:
    - "Saved X palettes to brand-philosophy.md"
    - "Use these when creating templates:"
    - "  - `/template-presentation` or `/template-carousel` will ask which palette to use"
    - "  - Templates lock in style + palette for consistent content creation"

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
