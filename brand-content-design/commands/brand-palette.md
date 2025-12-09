---
description: Generate alternative color palettes from brand colors
allowed-tools: Read, Write, Glob, Bash, AskUserQuestion
---

# Brand Palette Command

Generate alternative color palettes derived from brand primary colors.

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
   - Find primary color (first color listed, or labeled "primary")
   - Find any secondary/accent colors already defined
   - If no colors found: Tell user to run `/brand-extract` first and stop

3. **Show current colors**
   Display current brand colors with color boxes:
   ```bash
   echo -e "\033[48;2;R;G;Bm     \033[0m #HEX - Color Name"
   ```

4. **Ask palette selection (two questions due to option limit)**

   **Question 1: Harmony-based palettes**
   Use AskUserQuestion with multiSelect: true
   - Header: "Harmony"
   - Question: "Which harmony-based palettes? (color wheel relationships)"
   - Options:
     - **Monochromatic** - Same hue, varying lightness (safe, cohesive)
     - **Analogous** - Adjacent colors (harmonious, comfortable)
     - **Complementary** - Opposite colors (high contrast, attention)
     - **Triadic** - Three balanced colors (vibrant, energetic)

   **Question 2: Tonal and other palettes**
   Use AskUserQuestion with multiSelect: true
   - Header: "Tonal"
   - Question: "Which tonal variations or other palettes?"
   - Options:
     - **Tints** - Lighter variations (soft backgrounds)
     - **Shades** - Darker variations (bold emphasis)
     - **Tones** - Muted variations (sophisticated, subtle)
     - **Custom** - Describe what you need

   Note: Split-Complementary and Tetradic are advanced options - generate if user selects "Other" or asks specifically.

   Reference: `references/color-palettes.md` for decision guidance

5. **If Custom selected, ask for description**
   Ask: "Describe the mood or purpose for your custom palette:"
   Examples: "summer campaign", "professional but warm", "bold and innovative"

6. **Generate palettes**
   For each selected type, calculate colors from primary:

   **Harmony calculations (from color wheel):**
   - Monochromatic: Same hue, lightness at 30%, 50%, 70%, 90%
   - Analogous: Primary ± 30° on wheel
   - Complementary: Primary + 180°
   - Split-Complementary: Primary + 150°, Primary + 210°
   - Triadic: Primary + 120°, Primary + 240°
   - Tetradic: Primary + 90°, Primary + 180°, Primary + 270°

   **Tonal calculations:**
   - Tints: Mix with white at 25%, 50%, 75%
   - Shades: Mix with black at 25%, 50%, 75%
   - Tones: Mix with gray at 25%, 50%, 75%

   **Custom:**
   - Interpret user description
   - Generate 3-4 colors matching the mood
   - Stay adjacent to brand colors when possible

7. **Display generated palettes**
   Show each palette with color boxes:
   ```
   Generated from primary #2563EB:

   ██ ██ ██  Monochromatic   #1E40AF #2563EB #60A5FA #BFDBFE
   ██ ██ ██  Complementary   #2563EB #EB8225 #F59E0B
   ██ ██ ██  Triadic         #2563EB #EB2563 #63EB25
   ```

   Use Bash with ANSI codes:
   ```bash
   echo -e "\033[48;2;37;99;235m  \033[0m \033[48;2;235;130;37m  \033[0m \033[48;2;245;158;11m  \033[0m  Complementary   #2563EB #EB8225 #F59E0B"
   ```

8. **Ask to save (multi-select)**
   Use AskUserQuestion with multiSelect: true
   - Header: "Save"
   - Question: "Which palettes would you like to save?"
   - Options: List each generated palette by name

9. **Ask for custom names (if saving Custom)**
   If Custom palette is being saved:
   Ask: "What should we call this palette?" (e.g., "Summer Campaign", "Q4 Launch")

10. **Save selected palettes**
    Append to brand-philosophy.md under `## Alternative Palettes`:

    ```markdown
    ## Alternative Palettes

    ### Complementary
    - Primary: #2563EB
    - Complement: #EB8225
    - Accent: #F59E0B

    ### Summer Campaign (Custom)
    - Base: #F59E0B
    - Secondary: #10B981
    - Accent: #EC4899
    ```

11. **Confirm and suggest usage**
    Show:
    - "Saved X palettes to brand-philosophy.md"
    - "Use these when creating content:"
    - "  - `/presentation` or `/carousel` will ask which palette to use"
    - "  - Or specify in your content brief"

## Output

- Updated: `brand-philosophy.md` with Alternative Palettes section
- Terminal display of generated palettes with color boxes

## Notes

- Multiple palettes can be selected and saved
- Custom palettes need a name for saving
- Palettes are derived from the primary brand color
- Content commands can reference saved palettes
