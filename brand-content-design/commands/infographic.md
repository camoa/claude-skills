---
description: Create an infographic using an existing template (detailed, guided mode)
allowed-tools: Bash, Read, Write, Glob, AskUserQuestion
---

# Infographic Command

Create a branded infographic using an existing template with guided step-by-step workflow.

## Prerequisites

- Must be in a brand project folder (contains brand-philosophy.md)
- Must have at least one infographic template (run `/template-infographic` first)

## Workflow

### Phase 0: Dependency Check

0. **Ensure Node.js dependencies are installed**
   - Set `SKILL_PATH` = path to `skills/infographic-generator/` in the plugin
   - Check if `{SKILL_PATH}/node_modules` exists
   - If not, run:
     ```bash
     cd {SKILL_PATH} && npm install
     ```
   - Wait for installation to complete before proceeding

### Phase 1: Project Setup

1. **Find project and templates**
   - Check `./brand-philosophy.md`, then `../brand-philosophy.md`, then `find . -maxdepth 2 -name "brand-philosophy.md"`
   - **Set PROJECT_PATH** = directory containing brand-philosophy.md
   - Run `find {PROJECT_PATH}/templates/infographics -name "config.json" 2>/dev/null`
   - If no project found: Tell user to run `/brand-init` first and stop
   - If no templates found: Tell user to run `/template-infographic` first and stop
   - List available templates with their types

2. **Select template**
   Use AskUserQuestion:
   - Header: "Template"
   - Question: "Which infographic template?"
   - Options: List each template by name (show type: sequence, list, compare, etc.)

3. **Load template configuration**
   - Read `{PROJECT_PATH}/templates/infographics/{template-name}/config.json`
   - Read `{PROJECT_PATH}/templates/infographics/{template-name}/outline-template.md`
   - Read `{PROJECT_PATH}/brand-philosophy.md` for brand context
   - Note the template type and required data structure
   - **Check if illustrated template** (template name ends in `-illus`)

### Phase 2: Content Input (with Illustration Handling)

4. **Content source**
   Use AskUserQuestion:
   - Header: "Content"
   - Question: "How do you want to provide content?"
   - Options:
     - "Paste content" - I'll paste raw text/notes
     - "Use outline" - I have a prepared outline
     - "Generate sample" - Create with placeholder content

5. **If "Paste content":**
   - Show the outline-template.md structure
   - Ask: "Paste your content (I'll map it to the template):"
   - Parse and structure the content to match template format

6. **If "Use outline":**
   - Ask: "Paste your JSON outline or path to outline file:"
   - Validate JSON structure matches template requirements

7. **If "Generate sample":**
   - Use sample data from template or generate contextual placeholders

### Phase 2b: Illustration Handling (for `-illus` templates only)

**If template name ends in `-illus`:**

7b. **Determine output folder for illustrations**
    The infographic output folder will be: `{PROJECT_PATH}/infographics/{YYYY-MM-DD}-{infographic-name}/`
    Illustrations should be placed in: `{OUTPUT_FOLDER}/illustrations/`

    Note: We don't know the exact folder name yet (depends on step 8), so we'll ask the user to provide images from any location and copy them later.

7c. **Ask about illustrations**
    Use AskUserQuestion:
    - Header: "Illustrations"
    - Question: "This template needs visual assets. What do you have?"
    - Options:
      - **I have images** - I'll provide my own files (SVG, PNG, JPG)
      - **Find icons for me** - Suggest icons from Lucide/Heroicons
      - **Use placeholders** - Generate colored shapes as placeholders

7d. **If "I have images":**
    User already has their images ready. Just ask for the location:

    Ask: "Where are your image files? (folder path)"

    **DO NOT show the table of needed images** - user knows what they have.

    After user provides path:
    - List files found in that folder
    - Show which `illus` names from data.json will be matched
    - Validate files exist (SVG, PNG, or JPG)
    - Store paths for copying to output folder later (step 15)

    **Supported formats:** SVG (vector), PNG (with transparency), JPG

    **Naming:** Files must match the `illus` field values from the content
    - `"illus": "alarm"` → looks for alarm.svg, alarm.png, or alarm.jpg

7e. **If "Find icons for me":**
    Show table of needed illustrations with suggested searches:
    ```
    Based on your content, you need these {N} visuals:

    | # | Name | Concept | Suggested Search |
    |---|------|---------|------------------|
    | 1 | {illus1} | {label1} | "{search-term-1}", "{alt-term}" |
    | 2 | {illus2} | {label2} | "{search-term-2}", "{alt-term}" |
    ...

    Quick options to get images:

    **Icons (SVG, free):**
    - Lucide: https://lucide.dev/icons/ (minimal line icons)
    - Heroicons: https://heroicons.com/ (slightly bolder)
    - Tabler: https://tabler.io/icons (4500+ icons)

    **Illustrations/Photos:**
    - Unsplash: https://unsplash.com/ (free photos)
    - unDraw: https://undraw.co/ (free illustrations)
    - Storyset: https://storyset.com/ (free customizable illustrations)

    **AI-Generated:**
    - Use an AI image tool, save as PNG
    - Describe: "simple icon of {concept}, minimal style, single color"
    ```

    Ask: "Download your images and tell me the folder path, or continue with placeholders?"

7f. **If "Use placeholders":**
    - Generate simple placeholder shapes with brand colors
    - Each placeholder shows the illus name as text
    - Warn: "⚠️ Placeholders will be used. Replace with real images later."

### Phase 3: Naming & Customization

8. **Infographic name**
   Ask: "What name for this infographic? (e.g., company-milestones, feature-overview)"
   - Derive from content title if user says "auto" or similar
   - Sanitize: lowercase, hyphens, no special chars
   - This becomes the folder and file name

9. **Background style**
   Use AskUserQuestion:
   - Header: "Background"
   - Question: "Which background style?"
   - Options (show top 4, mention more available):
     - "spotlight-dots" - Radial spotlight + subtle dots (recommended)
     - "spotlight-grid" - Radial spotlight + grid lines
     - "tech-matrix" - Tech gradient + dense grid
     - "solid" - Plain solid color

   **All available presets:**
   - Layered: `spotlight-dots`, `spotlight-grid`, `diagonal-crosshatch`, `tech-matrix`
   - Simple: `spotlight`, `diagonal-fade`, `top-down`, `subtle-dots`, `tech-grid`, `crosshatch`, `solid`

   If user wants different preset, they can type the name directly.

10. **Output format**
    Use AskUserQuestion:
    - Header: "Format"
    - Question: "Output format?"
    - Options:
      - "PNG" - High-quality image (recommended)
      - "SVG" - Vector format (scalable)
      - "Both" - PNG and SVG

### Phase 4: Generation

12. **Prepare data JSON**
    Structure the content into the required JSON format:
    ```json
    {
      "title": "...",
      "desc": "...",
      "items": [...]
    }
    ```

13. **Generate infographic**
    Run the Node.js generator:
    ```bash
    cd {PLUGIN_PATH}/skills/infographic-generator
    node generate.js \
      --config "{PROJECT_PATH}/templates/infographics/{template-name}/config.json" \
      --data '{data-json}' \
      --background "{background-preset}" \
      --output "{OUTPUT_PATH}/{infographic-name}.png"
    ```

14. **Generate SVG if requested**
    ```bash
    node generate.js \
      --config "{PROJECT_PATH}/templates/infographics/{template-name}/config.json" \
      --data '{data-json}' \
      --format svg \
      --output "{OUTPUT_PATH}/{infographic-name}.svg"
    ```

### Phase 5: Output

15. **Save outputs**
    Create folder: `{PROJECT_PATH}/infographics/{YYYY-MM-DD}-{infographic-name}/`

    **For illustrated templates:** Copy user's images to output folder
    - Create `{OUTPUT_FOLDER}/illustrations/` subfolder
    - Copy images from user's source location (from step 7d)
    - Keep original filenames (must match `illus` field values)

    Save:
    - `{infographic-name}.png` (and/or .svg)
    - `data.json` - The content data used
    - `illustrations/` - Image files (for `-illus` templates)

16. **Show result**
    Display:
    - Output location
    - File size
    - Dimensions
    - "View: open {filename}.png"
    - "Edit content: modify data.json and regenerate"
    - "Quick regenerate: `/infographic-quick`"

## Output

- Created: `infographics/{date}-{name}/{name}.png`
- Created: `infographics/{date}-{name}/data.json`
- Created: `infographics/{date}-{name}/illustrations/` (for `-illus` templates)

## Notes

- For quick generation with minimal questions, use `/infographic-quick`
- For creating new templates, use `/template-infographic`
- For help preparing content, use `/outline infographic-{template}`

## Template Asset Types

| Type | Identifier | Data Format | Extra Assets |
|------|------------|-------------|--------------|
| **Text-only** | (default) | `{ "label": "Step 1", "desc": "Description" }` | None |
| **Icon-based** | `icon` in name | `{ "label": "icon:rocket", "desc": "Description" }` | None (uses Lucide icons) |
| **Illustrated** | `-illus` suffix | `{ "label": "Step 1", "desc": "Desc", "illus": "step-1" }` | Requires SVG files |

See `references/illustrations.md` for detailed illustration workflow.
