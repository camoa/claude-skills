---
name: generating-infographics
description: Use when creating infographics, data visualizations, process diagrams, timelines, or comparisons - generates branded infographics using @antv/infographic with 114 templates across 7 categories. Triggers on "create infographic", "make infographic", "visualize data", "timeline", "process diagram".
---

# Generating Infographics

Generate branded infographics with custom themes and backgrounds using @antv/infographic.

## Prerequisites

1. Run `/brand-init` to create project structure
2. Run `/brand-extract` to generate brand-philosophy.md
3. Run `/template-infographic` to create an infographic template

## When to Use

- "Create an infographic"
- "Make a process diagram"
- "Visualize this data"
- "Create a timeline"
- "Show comparison infographic"
- NOT for: Charts/graphs (use charting library), presentations (use visual-content skill)

## Commands

| Command | Purpose |
|---------|---------|
| `/template-infographic` | Create infographic template |
| `/infographic` | Generate infographic (guided) |
| `/infographic-quick` | Generate infographic (fast) |

## Template Categories (114 Total)

| Category | Count | Use Cases | Icons | Illustrated |
|----------|-------|-----------|-------|-------------|
| Sequence | 43 | Timelines, steps, processes, roadmaps | ✓ (2) | ✓ (5) |
| List | 23 | Features, grids, pyramids, sectors | ✓ (4) | ✓ (1) |
| Hierarchy | 25 | Org charts, tree structures | — | — |
| Compare | 17 | VS, before/after, SWOT | — | — |
| Quadrant | 3 | 2x2 matrices | — | ✓ (1) |
| Relation | 2 | Networks, connections | ✓ (1) | — |
| Chart | 1 | Bar charts | — | — |

## Template Asset Types

| Type | Count | Identifier | Data Format |
|------|-------|------------|-------------|
| **Text-only** | 100+ | (default) | `{ "label": "Cloud", "desc": "Infrastructure" }` |
| **Icon-based** | 8 | `icon` in name | `{ "label": "icon:rocket", "desc": "Fast" }` |
| **Illustrated** | 9 | `-illus` suffix | `{ "label": "Step 1", "desc": "Discovery", "illus": "step-1" }` |

**Recommendation:** Start with text-only templates. Illustrated templates require custom image files.

### Illustrated Template Workflow

When using `-illus` templates:
1. Content includes `illus` field referencing image filename
2. Supported formats: SVG (recommended), PNG, JPG
3. Options: provide your own images, find icons, or use placeholders
4. Images stored with infographic output: `infographics/{date}-{name}/illustrations/`
5. See `references/illustrations.md` for detailed workflow

## Text Guidelines (Avoiding Overlap)

| Element | Max | Good | Bad |
|---------|-----|------|-----|
| Labels | 1-2 words | "Cloud" | "Cloud Computing Services" |
| Descriptions | 2-4 words | "Infrastructure design" | "Complete infrastructure design and implementation" |

If overlap occurs: shorten text, use wider canvas (1200px+), or use column/grid templates.

## Quick Reference

| Task | How |
|------|-----|
| Generate infographic | `node generate.js --config config.json --data '{...}' --output output.png` |
| Set background | `--background "spotlight-dots"` |
| SVG output | `--format svg` |

## Background Presets

**Layered (gradient + pattern):**
| Preset | Effect |
|--------|--------|
| `spotlight-dots` | Radial spotlight + subtle dots (recommended) |
| `spotlight-grid` | Radial spotlight + grid lines |
| `diagonal-crosshatch` | Diagonal fade + crosshatch |
| `tech-matrix` | Tech gradient + dense grid |

**Simple (gradient or pattern only):**
| Preset | Effect |
|--------|--------|
| `spotlight` | Radial gradient only |
| `diagonal-fade` | Corner to corner fade |
| `top-down` | Vertical fade |
| `subtle-dots` | Light dot pattern |
| `tech-grid` | Grid lines |
| `crosshatch` | Diagonal crosshatch |
| `solid` | Plain solid color |

## Workflow

### 1. Create Template (once)
```
/template-infographic
```
Select: category → design → palette → background → style

### 2. Generate Infographic (repeat)
```
/infographic-quick
```
Select template → paste content → name → get PNG

## Color Contrast Rules

**Key principle:** Palette colors are for SHAPES and FILLS, not text. Text needs explicit high-contrast colors.

### Dark Backgrounds (spotlight-dots, tech-matrix, etc.)
- `colorBg`: Dark base color (e.g., `#0D2B5C`)
- `colorPrimary`: Accent color for shapes
- `title`: `{ "fill": "#FFFFFF" }`
- `desc`: `{ "fill": "{accent-color}" }` or `"rgba(255,255,255,0.85)"`
- `item.label`: `{ "fill": "#FFFFFF" }`
- `item.desc`: `{ "fill": "rgba(255,255,255,0.7)" }`

### Light Backgrounds (solid, subtle-dots, etc.)
- `colorBg`: Light base color (e.g., `#FFFFFF`, `#F7F9FC`)
- `colorPrimary`: Accent color for shapes (can be pastel)
- `title`: `{ "fill": "#1A202C" }` (near black)
- `desc`: `{ "fill": "#4A5568" }` (dark gray)
- `item.label`: `{ "fill": "#1A202C" }`
- `item.desc`: `{ "fill": "#4A5568" }`

**Common mistake:** Using pastel palette colors for text on light backgrounds. Pastels are for decorative shapes only.

See template-infographic.md for complete config examples.

## Data Structure by Type

### Sequence/List
```json
{
  "title": "Our Process",
  "items": [
    { "label": "Step 1", "desc": "Discovery" },
    { "label": "Step 2", "desc": "Design" }
  ]
}
```

### Compare
```json
{
  "title": "Before vs After",
  "items": [
    { "label": "Before", "children": [{ "label": "Slow" }] },
    { "label": "After", "children": [{ "label": "Fast" }] }
  ]
}
```

### Hierarchy
```json
{
  "title": "Organization",
  "items": [{
    "label": "CEO",
    "children": [{ "label": "CTO" }, { "label": "CFO" }]
  }]
}
```

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Text overlapping | Shorten labels (1-2 words), descriptions (2-4 words) |
| Missing illustrations | Check template ends in `-illus`, provide SVG/PNG/JPG files |
| Icon not showing | Use `icon:name` syntax, only for icon templates |
| Background not applied | Pass `--background` flag to generate.js |
| Text invisible on light bg | Add explicit `title`/`desc`/`item` fills with dark colors (#1A202C, #4A5568) |
| Pastel text unreadable | Palette colors are for shapes only; text needs high contrast (~4.5:1) |

## References

- `references/templates.md` - Complete 114 template catalog with asset requirements
- `references/theming.md` - Theme configuration details
- `references/backgrounds.md` - Background customization guide
- `references/icons.md` - Available icons for icon-based templates
- `references/illustrations.md` - Illustrated template workflow and SVG requirements

## Module Structure

```
lib/
├── renderer.js       # Main entry point
├── dom-setup.js      # JSDOM environment
├── infographic.js    # Infographic creation
├── exporter.js       # SVG/PNG export
├── backgrounds.js    # Gradient/pattern backgrounds
└── icons.js          # Icon utilities
```
