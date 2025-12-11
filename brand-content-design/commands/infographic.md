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

7b. **Check for existing illustrations**
    - Look for SVG files in the template folder or output folder
    - List any found SVGs

7c. **Ask about illustrations**
    Use AskUserQuestion:
    - Header: "Illustrations"
    - Question: "This template needs SVG illustrations. Do you have them?"
    - Options:
      - "I have SVGs" - I'll provide the file paths
      - "Generate placeholders" - Use colored rectangles as placeholders
      - "Help me create them" - Guide me through getting illustrations

7d. **If "I have SVGs":**
    Ask: "Where are your SVG files? (folder path or list each file)"
    - Validate SVGs exist
    - Map illus names to file paths

7e. **If "Generate placeholders":**
    - Generate simple placeholder SVGs with brand colors
    - Warn: "Placeholders will be used. Replace with real illustrations later."

7f. **If "Help me create them":**
    Show:
    ```
    Based on your content, you need these illustrations:

    1. {item1.illus}: Describe what "{item1.label}" should look like
    2. {item2.illus}: Describe what "{item2.label}" should look like
    ...

    Options to get SVGs:
    1. Search Lucide icons: https://lucide.dev/icons/
    2. Use an AI image generator, then convert to SVG
    3. Create in Figma/Illustrator
    4. Find on icon sites: flaticon.com, thenounproject.com

    Once you have SVGs, place them in:
    {PROJECT_PATH}/infographics/{name}/illustrations/

    Name them: {illus-name}.svg
    ```

    Ask: "Ready to continue with placeholders, or do you want to get the SVGs first?"

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
    Save:
    - `{infographic-name}.png` (and/or .svg)
    - `data.json` - The content data used

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
