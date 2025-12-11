---
description: Create or edit an infographic template through guided wizard
allowed-tools: Bash, Read, Write, Glob, AskUserQuestion
---

# Template Infographic Command

Create a new infographic template or edit an existing one.

## Prerequisites

- Must be in a brand project folder (contains brand-philosophy.md)

## Workflow

### Phase 1: Project Setup

1. **Find project (PROJECT_PATH)**
   Search in this order:
   - Check `./brand-philosophy.md` (current directory)
   - Check `../brand-philosophy.md` (parent directory)
   - Run `find . -maxdepth 2 -name "brand-philosophy.md"` to find nearby
   - If multiple found, ask user which project
   - If none found, tell user to run `/brand-init` first and stop
   - **Set PROJECT_PATH** = directory containing brand-philosophy.md
   - Load brand-philosophy.md
   - Extract brand colors from Visual Identity / Color Palette section

2. **Find existing templates**
   - Run `find {PROJECT_PATH}/templates/infographics -name "config.json" 2>/dev/null`
   - Parse results to get template names (parent folder name)
   - List any existing templates found (may be empty for new projects)

3. **Create or Edit?**
   - If no templates exist: skip to CREATE MODE (step 4)
   - If templates exist: Ask "Create new or edit existing?" with options

### Phase 2: Type & Design Selection (Two-Step)

4. **Step 1: Choose Category**

   Display this table:
   ```
   ## Infographic Categories

   | # | Category    | Use Cases                                    | Designs |
   |---|-------------|----------------------------------------------|---------|
   | 1 | Sequence    | Timelines, steps, processes, roadmaps, flows | 43      |
   | 2 | List        | Tips, features, grids, pyramids, sectors     | 23      |
   | 3 | Hierarchy   | Org charts, tree structures, taxonomies      | 25      |
   | 4 | Compare     | VS, before/after, pros/cons, SWOT            | 17      |
   | 5 | Quadrant    | 2x2 matrices, priority grids                 | 3       |
   | 6 | Relation    | Networks, circular connections               | 2       |
   | 7 | Chart       | Statistics, metrics, bar charts              | 1       |

   **Which category fits your infographic?** (enter 1-7 or name)
   ```

   Wait for user input and parse response.

5. **Step 2: Choose Design** (based on category)

   **Legend for Notes column:**
   - **icons** = Can use `icon:rocket` syntax for icon-based items
   - **illus** = Needs custom SVG illustrations (advanced)
   - No tag = Text-only template (most common, recommended)

   Display the appropriate table for the selected category:

   **If SEQUENCE selected:**
   ```
   ## Sequence Designs (43 templates)

   ### Timelines
   | # | Design                | Template Name                          | Notes                            |
   |---|-----------------------|----------------------------------------|----------------------------------|
   | 1 | Timeline Simple       | sequence-timeline-simple               | Clean horizontal                 |
   | 2 | Timeline Illustrated  | sequence-timeline-simple-illus         | Visual storytelling | **illus**  |
   | 3 | Timeline Done List    | sequence-timeline-done-list            | Checkmark milestones             |
   | 4 | Timeline Rounded      | sequence-timeline-rounded-rect-node    | Card-style nodes                 |
   | 5 | Timeline Plain        | sequence-timeline-plain-text           | Minimal text only                |

   ### Steps
   | # | Design                | Template Name                          | Notes                            |
   |---|-----------------------|----------------------------------------|----------------------------------|
   | 6 | Steps Simple          | sequence-steps-simple                  | Horizontal flow                  |
   | 7 | Steps Illustrated     | sequence-steps-simple-illus            | Rich visuals | **illus**         |
   | 8 | Steps Badge Card      | sequence-steps-badge-card              | Rich step cards                  |
   | 9 | Ascending Steps       | sequence-ascending-steps               | Rising progression               |

   ### Snake (Zigzag)
   | # | Design                | Template Name                          | Notes                            |
   |---|-----------------------|----------------------------------------|----------------------------------|
   | 10| Snake Simple          | sequence-snake-steps-simple            | Basic zigzag                     |
   | 11| Snake Illustrated     | sequence-snake-steps-simple-illus      | Zigzag visuals | **illus**       |
   | 12| Snake Compact Card    | sequence-snake-steps-compact-card      | Cards in zigzag                  |
   | 13| Snake Pill Badge      | sequence-snake-steps-pill-badge        | Badges in zigzag                 |
   | 14| Snake Underline       | sequence-snake-steps-underline-text    | Underlined text                  |
   | 15| Color Snake Icon      | sequence-color-snake-steps-horizontal-icon-line | Colorful | **icons**    |
   | 16| Color Snake Illus     | sequence-color-snake-steps-simple-illus | Colorful | **illus**          |

   ### Horizontal Zigzag
   | # | Design                | Template Name                          | Notes                            |
   |---|-----------------------|----------------------------------------|----------------------------------|
   | 17| H-Zigzag Simple       | sequence-horizontal-zigzag-simple      | Basic horizontal                 |
   | 18| H-Zigzag Illustrated  | sequence-horizontal-zigzag-simple-illus | Horizontal visuals | **illus** |
   | 19| H-Zigzag Plain        | sequence-horizontal-zigzag-plain-text  | Text only                        |
   | 20| H-Zigzag Underline    | sequence-horizontal-zigzag-underline-text | Underlined text               |
   | 21| H-Zigzag Arrow        | sequence-horizontal-zigzag-simple-horizontal-arrow | With arrows           |
   | 22| H-Zigzag Icon         | sequence-horizontal-zigzag-horizontal-icon-line | With icons | **icons** |

   ### Roadmap (Vertical)
   | # | Design                | Template Name                          | Notes                            |
   |---|-----------------------|----------------------------------------|----------------------------------|
   | 23| Roadmap Simple        | sequence-roadmap-vertical-simple       | Basic vertical                   |
   | 24| Roadmap Badge Card    | sequence-roadmap-vertical-badge-card   | With cards                       |
   | 25| Roadmap Pill Badge    | sequence-roadmap-vertical-pill-badge   | With badges                      |
   | 26| Roadmap Plain         | sequence-roadmap-vertical-plain-text   | Text only                        |
   | 27| Roadmap Underline     | sequence-roadmap-vertical-underline-text | Underlined text                |
   | 28| Roadmap Quarter Circ  | sequence-roadmap-vertical-quarter-circular | Circular markers              |
   | 29| Roadmap Quarter Card  | sequence-roadmap-vertical-quarter-simple-card | Card markers               |

   ### 3D Effects
   | # | Design                | Template Name                          | Notes                            |
   |---|-----------------------|----------------------------------------|----------------------------------|
   | 30| Stairs 3D Simple      | sequence-ascending-stairs-3d-simple    | 3D staircase                     |
   | 31| Stairs 3D Underline   | sequence-ascending-stairs-3d-underline-text | 3D with text                |
   | 32| Cylinders 3D          | sequence-cylinders-3d-simple           | 3D cylinders                     |
   | 33| Zigzag Pucks 3D       | sequence-zigzag-pucks-3d-simple        | 3D puck markers                  |
   | 34| Zigzag Pucks Card     | sequence-zigzag-pucks-3d-indexed-card  | 3D with cards                    |
   | 35| Zigzag Pucks Text     | sequence-zigzag-pucks-3d-underline-text | 3D with underline               |
   | 36| Zigzag Steps Text     | sequence-zigzag-steps-underline-text   | Zigzag underline                 |

   ### Circular & Other
   | # | Design                | Template Name                          | Notes                            |
   |---|-----------------------|----------------------------------------|----------------------------------|
   | 37| Circular Simple       | sequence-circular-simple               | Cyclical flow                    |
   | 38| Circular Underline    | sequence-circular-underline-text       | Cycle with text                  |
   | 39| Circle Arrows Card    | sequence-circle-arrows-indexed-card    | Arrow flow                       |
   | 40| Pyramid Simple        | sequence-pyramid-simple                | Pyramid progression              |
   | 41| Filter Mesh Simple    | sequence-filter-mesh-simple            | Funnel-like                      |
   | 42| Filter Mesh Text      | sequence-filter-mesh-underline-text    | Funnel with text                 |
   | 43| Mountain              | sequence-mountain-underline-text       | Mountain shape                   |

   **Which design?** (enter number or name)
   ```

   **If LIST selected:**
   ```
   ## List Designs (23 templates)

   ### Grid Layouts
   | # | Design              | Template Name                      | Notes                           |
   |---|---------------------|------------------------------------|--------------------------------|
   | 1 | Grid Simple         | list-grid-simple                   | Clean grid                      |
   | 2 | Grid Badge Card     | list-grid-badge-card               | Cards with badges               |
   | 3 | Grid Compact Card   | list-grid-compact-card             | Compact cards                   |
   | 4 | Grid Candy Lite     | list-grid-candy-card-lite          | Colorful cards                  |
   | 5 | Grid Progress Card  | list-grid-progress-card            | Progress indicators             |
   | 6 | Grid Ribbon Card    | list-grid-ribbon-card              | Ribbon-style cards              |
   | 7 | Grid Done List      | list-grid-done-list                | Checkmark items                 |
   | 8 | Grid Circular Prog  | list-grid-circular-progress        | Circular progress               |
   | 9 | Grid H-Icon Arrow   | list-grid-horizontal-icon-arrow    | Arrow flow | **icons**          |

   ### Row Layouts
   | # | Design              | Template Name                      | Notes                           |
   |---|---------------------|------------------------------------|--------------------------------|
   | 10| Row Simple Arrow    | list-row-simple-horizontal-arrow   | Horizontal arrows               |
   | 11| Row Circular Prog   | list-row-circular-progress         | Progress circles                |
   | 12| Row H-Icon Arrow    | list-row-horizontal-icon-arrow     | Arrow flow | **icons**          |
   | 13| Row H-Icon Line     | list-row-horizontal-icon-line      | Line connectors | **icons**     |
   | 14| Row Illustrated     | list-row-simple-illus              | Visual items | **illus**        |

   ### Column Layouts
   | # | Design              | Template Name                      | Notes                           |
   |---|---------------------|------------------------------------|--------------------------------|
   | 15| Column V-Arrow      | list-column-simple-vertical-arrow  | Vertical arrows                 |
   | 16| Column Done List    | list-column-done-list              | Checkmark items                 |
   | 17| Column V-Icon Arrow | list-column-vertical-icon-arrow    | Vertical flow | **icons**       |

   ### Pyramid Layouts
   | # | Design              | Template Name                      | Notes                           |
   |---|---------------------|------------------------------------|--------------------------------|
   | 18| Pyramid Badge Card  | list-pyramid-badge-card            | Pyramid with cards              |
   | 19| Pyramid Compact     | list-pyramid-compact-card          | Compact pyramid                 |
   | 20| Pyramid Rounded     | list-pyramid-rounded-rect-node     | Rounded nodes                   |

   ### Sector (Radial) Layouts
   | # | Design              | Template Name                      | Notes                           |
   |---|---------------------|------------------------------------|--------------------------------|
   | 21| Sector Simple       | list-sector-simple                 | Full radial                     |
   | 22| Sector Half Plain   | list-sector-half-plain-text        | Half circle text                |
   | 23| Sector Plain Text   | list-sector-plain-text             | Text labels                     |

   **Which design?** (enter number or name)
   ```

   **If COMPARE selected:**
   ```
   ## Compare Designs (17 templates)

   ### Badge Card Style (with rich cards)
   | # | Design                | Template Name                                  | Notes                 |
   |---|-----------------------|------------------------------------------------|-----------------------|
   | 1 | Badge Card VS         | compare-binary-horizontal-badge-card-vs        | Classic VS            |
   | 2 | Badge Card Arrow      | compare-binary-horizontal-badge-card-arrow     | Arrow divider         |
   | 3 | Badge Card Fold       | compare-binary-horizontal-badge-card-fold      | Folded paper style    |

   ### Compact Card Style
   | # | Design                | Template Name                                  | Notes                 |
   |---|-----------------------|------------------------------------------------|-----------------------|
   | 4 | Compact Card VS       | compare-binary-horizontal-compact-card-vs      | Compact VS            |
   | 5 | Compact Card Arrow    | compare-binary-horizontal-compact-card-arrow   | Compact with arrow    |
   | 6 | Compact Card Fold     | compare-binary-horizontal-compact-card-fold    | Compact fold          |

   ### Simple Style
   | # | Design                | Template Name                                  | Notes                 |
   |---|-----------------------|------------------------------------------------|-----------------------|
   | 7 | Simple VS             | compare-binary-horizontal-simple-vs            | Basic VS layout       |
   | 8 | Simple Arrow          | compare-binary-horizontal-simple-arrow         | Basic with arrow      |
   | 9 | Simple Fold           | compare-binary-horizontal-simple-fold          | Basic fold            |

   ### Underline Text Style
   | # | Design                | Template Name                                  | Notes                 |
   |---|-----------------------|------------------------------------------------|-----------------------|
   | 10| Underline VS          | compare-binary-horizontal-underline-text-vs    | Text underline VS     |
   | 11| Underline Arrow       | compare-binary-horizontal-underline-text-arrow | Text underline arrow  |
   | 12| Underline Fold        | compare-binary-horizontal-underline-text-fold  | Text underline fold   |

   ### Hierarchy Comparisons
   | # | Design                | Template Name                                  | Notes                 |
   |---|-----------------------|------------------------------------------------|-----------------------|
   | 13| Hierarchy Pill Badge  | compare-hierarchy-left-right-circle-node-pill-badge | Tree comparison  |
   | 14| Hierarchy Plain       | compare-hierarchy-left-right-circle-node-plain-text | Plain tree       |
   | 15| Hierarchy Row Letter  | compare-hierarchy-row-letter-card-compact-card | Row with letters      |
   | 16| Hierarchy Row Rounded | compare-hierarchy-row-letter-card-rounded-rect-node | Rounded nodes    |

   ### Special
   | # | Design                | Template Name                                  | Notes                 |
   |---|-----------------------|------------------------------------------------|-----------------------|
   | 17| SWOT Analysis         | compare-swot                                   | 4-quadrant SWOT       |

   **Which design?** (enter number or name)
   ```

   **If HIERARCHY selected:**
   ```
   ## Hierarchy Designs (25 templates)

   ### Curved Line Style
   | # | Design              | Template Name                          | Notes              |
   |---|---------------------|----------------------------------------|--------------------|
   | 1 | Curved Badge Card   | hierarchy-tree-curved-line-badge-card  | Cards with badges  |
   | 2 | Curved Capsule      | hierarchy-tree-curved-line-capsule-item | Capsule items     |
   | 3 | Curved Compact      | hierarchy-tree-curved-line-compact-card | Compact cards     |
   | 4 | Curved Ribbon       | hierarchy-tree-curved-line-ribbon-card | Ribbon-style       |
   | 5 | Curved Rounded      | hierarchy-tree-curved-line-rounded-rect-node | Rounded nodes |

   ### Dashed Arrow Style
   | # | Design              | Template Name                          | Notes              |
   |---|---------------------|----------------------------------------|--------------------|
   | 6 | Dashed Arrow Badge  | hierarchy-tree-dashed-arrow-badge-card | Badge cards        |
   | 7 | Dashed Arrow Capsule| hierarchy-tree-dashed-arrow-capsule-item | Capsule items    |
   | 8 | Dashed Arrow Compact| hierarchy-tree-dashed-arrow-compact-card | Compact cards    |
   | 9 | Dashed Arrow Ribbon | hierarchy-tree-dashed-arrow-ribbon-card | Ribbon cards      |
   | 10| Dashed Arrow Rounded| hierarchy-tree-dashed-arrow-rounded-rect-node | Rounded nodes|

   ### Dashed Line Style
   | # | Design              | Template Name                          | Notes              |
   |---|---------------------|----------------------------------------|--------------------|
   | 11| Dashed Line Badge   | hierarchy-tree-dashed-line-badge-card  | Badge cards        |
   | 12| Dashed Line Capsule | hierarchy-tree-dashed-line-capsule-item | Capsule items     |
   | 13| Dashed Line Compact | hierarchy-tree-dashed-line-compact-card | Compact cards     |
   | 14| Dashed Line Ribbon  | hierarchy-tree-dashed-line-ribbon-card | Ribbon cards       |
   | 15| Dashed Line Rounded | hierarchy-tree-dashed-line-rounded-rect-node | Rounded nodes |

   ### Distributed Origin Style
   | # | Design              | Template Name                          | Notes              |
   |---|---------------------|----------------------------------------|--------------------|
   | 16| Distrib Badge Card  | hierarchy-tree-distributed-origin-badge-card | Badge cards   |
   | 17| Distrib Capsule     | hierarchy-tree-distributed-origin-capsule-item | Capsules     |
   | 18| Distrib Compact     | hierarchy-tree-distributed-origin-compact-card | Compact      |
   | 19| Distrib Ribbon      | hierarchy-tree-distributed-origin-ribbon-card | Ribbon        |
   | 20| Distrib Rounded     | hierarchy-tree-distributed-origin-rounded-rect-node | Rounded |

   ### Tech Style
   | # | Design              | Template Name                          | Notes              |
   |---|---------------------|----------------------------------------|--------------------|
   | 21| Tech Badge Card     | hierarchy-tree-tech-style-badge-card   | Tech-look badges   |
   | 22| Tech Capsule        | hierarchy-tree-tech-style-capsule-item | Tech capsules      |
   | 23| Tech Compact        | hierarchy-tree-tech-style-compact-card | Tech compact       |
   | 24| Tech Ribbon         | hierarchy-tree-tech-style-ribbon-card  | Tech ribbon        |
   | 25| Tech Rounded        | hierarchy-tree-tech-style-rounded-rect-node | Tech rounded  |

   **Which design?** (enter number or name)
   ```

   **If CHART selected:**
   ```
   ## Chart Designs (1 template)

   | # | Design        | Template Name       | Notes               |
   |---|---------------|---------------------|---------------------|
   | 1 | Column Chart  | chart-column-simple | Vertical bar chart  |

   **Which design?** (enter number or name)
   ```

   **If QUADRANT selected:**
   ```
   ## Quadrant Designs (3 templates)

   | # | Design           | Template Name              | Notes                            |
   |---|------------------|----------------------------|----------------------------------|
   | 1 | Quarter Card     | quadrant-quarter-simple-card | Simple 4-quadrant cards        |
   | 2 | Quarter Circular | quadrant-quarter-circular    | Circular quadrant              |
   | 3 | Quadrant Illus   | quadrant-simple-illus        | Visual quadrants | **illus**   |

   **Which design?** (enter number or name)
   ```

   **If RELATION selected:**
   ```
   ## Relation Designs (2 templates)

   | # | Design            | Template Name                  | Notes                          |
   |---|-------------------|--------------------------------|--------------------------------|
   | 1 | Circle Progress   | relation-circle-circular-progress | Circular progress nodes     |
   | 2 | Circle Icon Badge | relation-circle-icon-badge        | Badge circle | **icons**    |

   **Which design?** (enter number or name)
   ```

   Parse user input to get the template name.

6. **Template name** (CREATE MODE only)
   Ask: "What name for this template? (e.g., company-timeline, feature-grid)"
   - Suggest a name based on the selected design (e.g., if they chose "sequence-timeline-simple", suggest "timeline" or similar)
   - Accept user input or "auto" to use suggestion
   - Sanitize: lowercase, hyphens, no special chars
   - Validate unique name (not already in templates folder)

### Phase 3: Style Configuration

7. **Choose Color Palette**

   Extract palettes from brand-philosophy.md (Brand colors + Alternative Palettes section).

   Display available palettes:
   ```
   ## Color Palettes

   | # | Palette         | Colors                                    |
   |---|-----------------|-------------------------------------------|
   | 1 | Brand (default) | Primary: #194582, Accent: #00f3ff         |
   | 2 | Monochromatic   | #0C2341, #194582, #3773B4, #78A5D7        |
   | 3 | Complementary   | #194582, #825A19, #B47D23, #D7A041        |
   | 4 | Triadic         | #194582, #821950, #508219                 |
   | 5 | Bold            | #0D2B5C, #00E5FF, #FF6B4A                 |
   | ... (list all from brand-philosophy.md)

   **Which palette?** (enter number or name, default: 1)
   ```

8. **Choose Background**

   Display options:
   ```
   ## Background Style

   ### Layered (gradient + pattern overlay) - Recommended
   | # | Preset              | Effect                              |
   |---|---------------------|-------------------------------------|
   | 1 | spotlight-dots      | Radial spotlight + subtle dots (recommended) |
   | 2 | spotlight-grid      | Radial spotlight + grid lines       |
   | 3 | diagonal-crosshatch | Diagonal fade + crosshatch          |
   | 4 | tech-matrix         | Tech gradient + dense grid          |

   ### Simple (gradient or pattern only)
   | # | Preset        | Effect                    |
   |---|---------------|---------------------------|
   | 5 | spotlight     | Radial spotlight gradient |
   | 6 | diagonal-fade | Corner to corner fade     |
   | 7 | top-down      | Vertical fade             |
   | 8 | subtle-dots   | Light dot pattern         |
   | 9 | tech-grid     | Grid lines                |
   | 10| crosshatch    | Diagonal crosshatch       |
   | 11| solid         | Plain solid color         |

   **Which background?** (enter number or name, default: 1)
   ```

9. **Choose Shape Style** (optional)

   Display options:
   ```
   ## Shape Style

   | # | Style       | Description                        |
   |---|-------------|------------------------------------|
   | 1 | Clean       | Sharp, professional (default)      |
   | 2 | Hand-drawn  | Sketchy, informal, rough edges     |
   | 3 | Gradient    | Modern gradient fills on shapes    |
   | 4 | Pattern     | Textured pattern fills on shapes   |

   **Which style?** (enter number or name, default: 1)
   ```

10. **Choose Dimensions**

   Display options:
   ```
   ## Output Dimensions

   | # | Size              | Dimensions  | Use Case                    |
   |---|-------------------|-------------|-----------------------------|
   | 1 | Slide             | 1920×1080   | Presentations (16:9)        |
   | 2 | Social Square     | 1080×1080   | Instagram/LinkedIn square   |
   | 3 | Social Portrait   | 1080×1350   | Instagram/LinkedIn (4:5)    |
   | 4 | Auto-height       | 800×auto    | Blog, flexible height       |

   **Which size?** (enter number or name, default: 1)
   ```

### Phase 4: Generate Template Assets

11. **Create template directory**
    ```bash
    mkdir -p "{PROJECT_PATH}/templates/infographics/{template-name}"
    ```

12. **Generate config.json**

    Build configuration based on selections:
    ```json
    {
      "type": "{category}",
      "template": "{antv-template-name}",
      "background": "{background-preset}",
      "themeConfig": {
        "colorPrimary": "{primary-color}",
        "colorBg": "#FFFFFF",
        "palette": ["{palette-colors}"],
        "stylize": {stylize-config-or-null}
      },
      "width": {width},
      "height": {height-or-null}
    }
    ```

    **Background presets:**
    - Layered: `"spotlight-dots"`, `"spotlight-grid"`, `"diagonal-crosshatch"`, `"tech-matrix"`
    - Simple: `"spotlight"`, `"diagonal-fade"`, `"top-down"`, `"subtle-dots"`, `"tech-grid"`, `"crosshatch"`, `"solid"`

    **Stylize configurations (shape effects):**
    - Clean: `"stylize": null`
    - Hand-drawn: `"stylize": {"type": "rough", "roughness": 1.5, "bowing": 1}`
    - Gradient: `"stylize": {"type": "linear-gradient", "angle": 135}`
    - Pattern: `"stylize": {"type": "pattern", "pattern": "diagonal-stripe"}`

13. **Generate template.md**

    Create template documentation with type, design, brand mapping, data format.

14. **Generate outline-template.md**

    Create content slot template based on infographic type:
    - Sequence: title, description, items with label+desc
    - List: title, items with label+desc
    - Compare: title, two groups with children
    - Chart: title, items with label+value
    - Quadrant: title, 4 quadrant items

    **For illustrated templates** (template name ends in `-illus`), add illustration field:
    ```markdown
    ## Item 1
    - Label: ___
    - Description: ___
    - Illustration concept: ___ (describe what visual should represent this item)
    ```

15. **Generate outline-prompt.txt**

    Create AI prompt for filling the outline.

    **For illustrated templates** (template name ends in `-illus`), include special instructions:

    ```
    ## ILLUSTRATION REQUIREMENTS

    This infographic uses illustrated items. For each item you need:
    1. Label text (1-2 words)
    2. Description text (2-4 words)
    3. Illustration concept (describe what the SVG should depict)

    The illustrations should be:
    - Simple and iconic (not complex scenes)
    - Consistent style across all items
    - Recognizable at small sizes

    Example:
    - Label: "Discovery"
    - Description: "Research & analysis"
    - Illustration: "Magnifying glass over documents"

    ## HOW TO GET SVG ILLUSTRATIONS

    After filling this outline, you'll need SVG files. Options:
    1. Search icon libraries (Lucide, Heroicons) for matching concepts
    2. Use AI image tools to generate icons, then convert to SVG
    3. Create in Figma/Illustrator/Inkscape
    4. Commission from a designer using these descriptions

    ## OUTPUT FORMAT

    For each item:
    - Label: {1-2 words}
    - Description: {2-4 words}
    - Illustration: {visual concept description}
    ```

    **For icon templates** (template name contains `icon`), include:

    ```
    ## ICON REQUIREMENTS

    This template uses icons. Use the `icon:name` syntax for labels.

    Available icons: rocket, cloud, shield, chart-bar, code, users, check, star, etc.
    Full list: https://lucide.dev/icons/

    Example:
    - Label: "icon:rocket"
    - Description: "Fast deployment"

    Keep descriptions SHORT (2-4 words) - icons take up space.
    ```

16. **Generate sample infographic**

    Run the Node.js generator with sample data:
    ```bash
    cd {PLUGIN_PATH}/skills/infographic-generator
    node generate.js \
      --config "{PROJECT_PATH}/templates/infographics/{template-name}/config.json" \
      --data '{sample-data-json}' \
      --output "{PROJECT_PATH}/templates/infographics/{template-name}/sample.png"
    ```

    Also generate SVG:
    ```bash
    node generate.js \
      --config "{PROJECT_PATH}/templates/infographics/{template-name}/config.json" \
      --data '{sample-data-json}' \
      --output "{PROJECT_PATH}/templates/infographics/{template-name}/sample.svg"
    ```

### Phase 5: Completion

17. **Confirm and show results**

    Display:
    ```
    ## Template Created! ✅

    **Location:** {PROJECT_PATH}/templates/infographics/{template-name}/

    **Files:**
    - config.json - Template configuration
    - template.md - Template documentation
    - outline-template.md - Content slots to fill
    - outline-prompt.txt - AI prompt for content
    - sample.png - Preview image
    - sample.svg - Vector version

    **Next steps:**
    1. View sample: open sample.png
    2. Create infographic: `/infographic` and select this template
    3. Quick create: `/infographic-quick`
    ```

---

## Sample Data by Type

### Sequence
```json
{
  "title": "Company Milestones",
  "desc": "Our journey from startup to scale",
  "items": [
    { "label": "2020", "desc": "Founded in Seattle" },
    { "label": "2021", "desc": "Seed funding ($2M)" },
    { "label": "2022", "desc": "Series A ($15M)" },
    { "label": "2023", "desc": "100K users" },
    { "label": "2024", "desc": "Global expansion" }
  ]
}
```

### List
```json
{
  "title": "Key Features",
  "desc": "Everything you need",
  "items": [
    { "label": "Fast", "desc": "Lightning quick performance" },
    { "label": "Secure", "desc": "Enterprise-grade security" },
    { "label": "Simple", "desc": "Easy to use interface" },
    { "label": "Scalable", "desc": "Grows with your needs" },
    { "label": "Support", "desc": "24/7 customer care" },
    { "label": "API", "desc": "Developer friendly" }
  ]
}
```

### Compare
```json
{
  "title": "Before vs After",
  "desc": "The transformation",
  "items": [
    {
      "label": "Before",
      "children": [
        { "label": "Slow processes" },
        { "label": "Manual work" },
        { "label": "High costs" },
        { "label": "Error-prone" }
      ]
    },
    {
      "label": "After",
      "children": [
        { "label": "Fast automation" },
        { "label": "AI-powered" },
        { "label": "Cost savings" },
        { "label": "99.9% accuracy" }
      ]
    }
  ]
}
```

### Chart
```json
{
  "title": "Quarterly Revenue",
  "desc": "2024 Performance (in millions)",
  "items": [
    { "label": "Q1", "value": 120 },
    { "label": "Q2", "value": 150 },
    { "label": "Q3", "value": 180 },
    { "label": "Q4", "value": 210 }
  ]
}
```

### Quadrant
```json
{
  "title": "Priority Matrix",
  "desc": "What to focus on",
  "items": [
    { "label": "Do First", "desc": "High impact, low effort" },
    { "label": "Schedule", "desc": "High impact, high effort" },
    { "label": "Delegate", "desc": "Low impact, low effort" },
    { "label": "Eliminate", "desc": "Low impact, high effort" }
  ]
}
```

### Hierarchy
```json
{
  "title": "Organization",
  "desc": "Company structure",
  "items": [
    {
      "label": "CEO",
      "children": [
        {
          "label": "CTO",
          "children": [
            { "label": "Engineering" },
            { "label": "DevOps" }
          ]
        },
        {
          "label": "CFO",
          "children": [
            { "label": "Finance" },
            { "label": "Legal" }
          ]
        }
      ]
    }
  ]
}
```

### Relation
```json
{
  "title": "Core Values",
  "desc": "What drives us",
  "items": [
    { "label": "Innovation", "desc": "Always improving" },
    { "label": "Quality", "desc": "Excellence in everything" },
    { "label": "Trust", "desc": "Reliability first" },
    { "label": "Growth", "desc": "Continuous learning" }
  ]
}
```
