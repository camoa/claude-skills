---
name: brand-content-design
description: Use when user says "create presentation", "make carousel", "setup brand", "brand init", "extract brand", or wants to create visual content with consistent branding. Creates branded presentations and carousels using a layered philosophy system.
---

# Brand Content Design

Create branded visual content (presentations, LinkedIn carousels) with consistent brand identity.

## Trigger Phrases

- "create presentation" / "make slides"
- "create carousel" / "LinkedIn carousel"
- "setup brand" / "brand init" / "extract brand"
- "create template" / "new template"
- NOT for: General design questions, non-branded content

## Project Detection

Before ANY operation:

1. Check if current directory contains `brand-philosophy.md`
2. If YES → Load brand philosophy, proceed with requested operation
3. If NO → Direct user to run `/brand` or `/brand-init` first

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
| Manage assets (logos, icons, fonts) | `/brand-assets` |
| Create presentation template | `/template-presentation` |
| Create carousel template | `/template-carousel` |
| Create presentation (guided) | `/presentation` |
| Create presentation (quick) | `/presentation-quick` |
| Create carousel (guided) | `/carousel` |
| Create carousel (quick) | `/carousel-quick` |
| Add new content type | `/content-type-new` |

## Underlying Skills

Use these skills during content generation:

| Skill | When to Use |
|-------|-------------|
| **canvas-design** | Generate visual output from canvas philosophy |
| **pptx** | Convert presentation PDFs to PowerPoint |
| **pdf** | Create multi-page carousel PDFs |
| **theme-factory** | Optional: Generate theme from brand colors |

## References

- `references/brand-philosophy-template.md` - Template for brand philosophy
- `references/template-structure.md` - Template for template.md files
- `references/canvas-philosophy-template.md` - Template for canvas philosophy
- `references/presentations-guide.md` - Presentation best practices
- `references/carousels-guide.md` - Carousel best practices
- `references/output-specs.md` - Dimensions, formats, file sizes
