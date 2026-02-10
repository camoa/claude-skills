---
name: brand-content-design
description: Use when user says "create presentation", "make carousel", "create HTML page", "make landing page", "build web page", "html design system", "design system", "setup brand", "brand init", "extract brand", "get outline", or wants to create visual content with consistent branding. Creates branded presentations, carousels, and HTML pages using a layered philosophy system.
version: 2.1.0
model: sonnet
---

# Brand Content Design

Create branded visual content (presentations, LinkedIn carousels, HTML pages) with consistent brand identity.

## Trigger Phrases

- "create presentation" / "make slides"
- "create carousel" / "LinkedIn carousel"
- "create HTML page" / "make landing page" / "build web page"
- "html design system" / "design system"
- "setup brand" / "brand init" / "extract brand"
- "create template" / "new template"
- "get outline" / "outline for template" / "prepare content"
- "color palette" / "generate palette" / "alternative colors"
- NOT for: General design questions, non-branded content

## Project Detection

Before ANY operation, find the PROJECT_PATH using this search order:

1. **Current directory** - Check if `./brand-philosophy.md` exists
2. **Parent directory** - Check if `../brand-philosophy.md` exists
3. **Subdirectories** - Use `find . -maxdepth 2 -name "brand-philosophy.md"` to find nearby projects
4. **If multiple found** - Ask user which project to use
5. **If none found** - Direct user to run `/brand-init` first

**Once PROJECT_PATH is set**, the folder structure is:
```
{PROJECT_PATH}/
├── brand-philosophy.md          # Always exists
├── templates/
│   ├── presentations/
│   │   └── {template-name}/
│   │       ├── template.md
│   │       ├── canvas-philosophy.md
│   │       └── sample.pptx
│   ├── carousels/
│   │   └── {template-name}/
│   │       ├── template.md
│   │       ├── canvas-philosophy.md
│   │       └── sample.pdf
│   └── html/
│       └── {design-system-name}/
│           ├── canvas-philosophy.md
│           ├── design-system.md
│           └── components/      # Reusable HTML components
├── presentations/               # Output folder
├── carousels/                   # Output folder
├── html-pages/                  # Output folder (HTML pages)
└── assets/                      # Brand assets
```

**Finding templates:**
- Presentations: `find {PROJECT_PATH}/templates/presentations -name "template.md"`
- Carousels: `find {PROJECT_PATH}/templates/carousels -name "template.md"`

## Three-Layer System

Apply this layered approach when creating content:

1. **Layer 1 - Brand Philosophy** (`brand-philosophy.md` in project)
   - Load and apply visual DNA (colors, typography, imagery)
   - Load and apply verbal DNA (voice, tone, vocabulary)

2. **Layer 2 - Content Type Guide** (from plugin `references/`)
   - Read `references/presentations-guide.md` for presentations
   - Read `references/carousels-guide.md` for carousels

3. **Layer 3 - Template** (from project `templates/`)
   - Load template's `canvas-philosophy.md` for visual design rules
   - Follow template's structure for slide/card sequence

## Commands

Route user requests to the appropriate command:

| User Intent | Command |
|-------------|---------|
| Status, switch projects, or start | `/brand` |
| Initialize new project | `/brand-init` |
| Extract brand from sources | `/brand-extract` |
| Generate alternative color palettes | `/brand-palette` |
| Manage assets (logos, icons, fonts) | `/brand-assets` |
| Create presentation template | `/template-presentation` |
| Create carousel template | `/template-carousel` |
| Get outline template + AI prompt with slide/card definitions | `/outline` |
| Create presentation (guided) | `/presentation` |
| Create presentation (quick) | `/presentation-quick` |
| Create carousel (guided) | `/carousel` |
| Create carousel (quick) | `/carousel-quick` |
| Create HTML design system | `/design-html` |
| Create HTML page (guided) | `/html-page` |
| Create HTML page (quick) | `/html-page-quick` |
| Add new content type | `/content-type-new` |

## Underlying Skills

Use these skills during content generation:

| Skill | When to Use |
|-------|-------------|
| **visual-content** | Generate visual output from canvas philosophy (bundled) |
| **html-generator** | Generate HTML pages and components from design system (bundled) |
| **pptx** | Convert presentation PDFs to PowerPoint |
| **pdf** | Create multi-page carousel PDFs |

The `visual-content` skill is bundled with this plugin - no external dependencies required for visual generation.

## References

- `references/brand-philosophy-template.md` - Template for brand philosophy
- `references/template-structure.md` - Template for template.md files
- `references/canvas-philosophy-template.md` - Template for canvas philosophy
- `references/presentations-guide.md` - Presentation best practices
- `references/carousels-guide.md` - Carousel best practices
- `references/style-constraints.md` - 13 visual styles with enforcement blocks
- `references/color-palettes.md` - Color theory and palette types
- `references/output-specs.md` - Dimensions, formats, file sizes
