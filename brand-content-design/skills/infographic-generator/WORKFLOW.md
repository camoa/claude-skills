# Infographic Generator Workflow

Complete guide to creating infographics with this skill.

## Overview

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  1. TEMPLATE    │ ──► │   2. OUTLINE    │ ──► │  3. GENERATE    │
│   (once)        │     │   (optional)    │     │   (repeat)      │
└─────────────────┘     └─────────────────┘     └─────────────────┘
/template-infographic    /outline {template}    /infographic
                                                /infographic-quick
```

---

## Phase 1: Template Creation (`/template-infographic`)

### Purpose
Create a reusable template that locks in: category, design, colors, background style.

### Questions Asked

| Step | Question | Guidance |
|------|----------|----------|
| **1. Category** | "Which category fits your infographic?" | Choose based on content type - see table below |
| **2. Design** | "Which design?" (shows designs for chosen category) | Pick based on visual style needed |
| **3. Palette** | "Which color palette?" | Brand colors (default) or alternative palette |
| **4. Background** | "Which background style?" | Dark backgrounds for impact, light for readability |
| **5. Style** | "Add visual style?" | Optional: rough (hand-drawn), gradient, pattern |
| **6. Name** | "Template name?" | Short, descriptive (e.g., "process-timeline", "feature-grid") |

### Category Selection Guide

| Category | Choose When You Have... | Item Count |
|----------|------------------------|------------|
| **Sequence** | Steps, timeline, process flow, roadmap | 3-10 items |
| **List** | Features, tips, bullet points, grid items | 4-12 items |
| **Hierarchy** | Org chart, tree structure, nested levels | Varies |
| **Compare** | Before/after, VS, pros/cons, SWOT | 2 groups |
| **Quadrant** | 2x2 matrix, priority grid | Exactly 4 |
| **Relation** | Circular relationships, network | 3-8 items |
| **Chart** | Bar chart with numeric values | 3-10 items |

### Design Selection Tips

- **Text-only** (no tag): Simplest, works for any content
- **Icons** (`icon` tag): Good for features, processes with clear concepts
- **Illustrated** (`-illus` suffix): Best visual impact, requires image files

### Background Selection Guide

| Background | Effect | Best For |
|------------|--------|----------|
| `spotlight-dots` | Dark radial gradient + dots | Professional, impact |
| `spotlight-grid` | Dark radial gradient + grid | Tech, modern |
| `tech-matrix` | Dense tech grid | Technical content |
| `solid` | Plain color | Clean, printable |
| `subtle-dots` | Light with dots | Light themes |

### Output

Template saved to: `{PROJECT}/templates/infographics/{template-name}/`
- `config.json` - Locked configuration
- `outline-template.md` - Content structure guide

---

## Phase 2: Outline Preparation (Optional)

### Purpose
Prepare content before generating. Useful for complex infographics or when using AI to draft content.

### Command
```
/outline infographic-{template-name}
```

### What It Generates

1. **outline-template.md** - Fill-in structure for your content
2. **outline-prompt.txt** - AI prompt for generating content

### Using the Outline Prompt

Copy `outline-prompt.txt` content to an AI assistant with your raw notes:

```
[Paste outline-prompt.txt content]

My content:
- Point 1: ...
- Point 2: ...
- Point 3: ...
```

The AI will format your content to match the template's data structure.

---

## Phase 3: Infographic Generation

### Option A: Guided Mode (`/infographic`)

Full control over all options.

| Step | Question | Options |
|------|----------|---------|
| **1. Template** | "Which template?" | List of your templates |
| **2. Content** | "How provide content?" | Paste / Use outline / Sample |
| **3. Images** | (If illustrated) "What images?" | I have images / Find icons / Placeholders |
| **4. Name** | "Infographic name?" | e.g., "q4-roadmap" |
| **5. Background** | "Background style?" | Override template default |
| **6. Format** | "Output format?" | PNG / SVG / Both |

### Option B: Quick Mode (`/infographic-quick`)

Minimal questions, uses defaults.

| Step | Question |
|------|----------|
| **1. Template** | "Which template?" |
| **2. Content** | "Paste your content:" |
| **3. Name** | "Infographic name?" |

Uses: default background, PNG output.

### Content Input Tips

**Good content format:**
```
Title: Our 4-Step Process
Subtitle: How we deliver results

1. Discovery: Research & analysis
2. Design: Create solutions
3. Build: Develop & test
4. Deploy: Launch & monitor
```

**Text length guidelines:**
- Labels: 1-2 words ("Discovery", "Step 1")
- Descriptions: 2-4 words ("Research & analysis")

### Output

Generated to: `{PROJECT}/infographics/{YYYY-MM-DD}-{name}/`
- `{name}.png` - The infographic image
- `data.json` - Content data (for regeneration)
- `illustrations/` - Image files (if illustrated template)

---

## Working with Icons

### When to Use
- Templates with `icon` in the name
- Content has clear, recognizable concepts

### How to Use

In your content, prefix labels with `icon:`:
```json
{
  "items": [
    { "label": "icon:search", "desc": "Research" },
    { "label": "icon:palette", "desc": "Design" },
    { "label": "icon:code", "desc": "Build" },
    { "label": "icon:rocket", "desc": "Launch" }
  ]
}
```

### Finding Icons

1900+ Lucide icons available. Common ones:

| Concept | Icon Name |
|---------|-----------|
| Start/Play | `play`, `play-circle` |
| Settings | `settings`, `sliders` |
| Users | `user`, `users`, `user-plus` |
| Communication | `mail`, `message-circle`, `phone` |
| Success | `check`, `check-circle`, `award` |
| Growth | `trending-up`, `chart-bar`, `target` |
| Time | `clock`, `calendar`, `timer` |
| Security | `lock`, `shield`, `key` |

Full list: `references/icons.md`

---

## Working with Illustrations

### When to Use
- Templates ending in `-illus`
- You have custom images or want visual storytelling

### Image Requirements

| Requirement | Specification |
|-------------|---------------|
| **Formats** | SVG (best), PNG, JPG |
| **Aspect ratio** | Square (1:1) recommended |
| **Size** | 200×200px minimum for raster |
| **Naming** | Must match `illus` field value |

### Workflow Options

1. **I have images** - Provide folder path with your files
2. **Find icons for me** - Get suggestions for free icon/image sources
3. **Use placeholders** - Generate with colored placeholders, replace later

### Image Sources

**Icons (SVG, free):**
- [Lucide](https://lucide.dev/icons/) - Minimal line icons
- [Heroicons](https://heroicons.com/) - Slightly bolder
- [Tabler](https://tabler.io/icons) - 4500+ icons

**Illustrations/Photos:**
- [Unsplash](https://unsplash.com/) - Free photos
- [unDraw](https://undraw.co/) - Free SVG illustrations
- [Storyset](https://storyset.com/) - Customizable illustrations

### File Naming

Your `data.json`:
```json
{ "illus": "discovery" }
```

Your file: `discovery.svg` or `discovery.png` or `discovery.jpg`

---

## Tweaking & Regeneration

### Modify Content

1. Edit `data.json` in the output folder
2. Regenerate:
   ```bash
   cd {PLUGIN}/skills/infographic-generator
   node generate.js \
     --config "{PROJECT}/templates/infographics/{template}/config.json" \
     --data "$(cat {PROJECT}/infographics/{date}-{name}/data.json)" \
     --output "{PROJECT}/infographics/{date}-{name}/{name}.png"
   ```

### Change Background

Add `--background` flag:
```bash
node generate.js ... --background "spotlight-dots"
```

### Change Format

For SVG output:
```bash
node generate.js ... --output "output.svg"
```

### Common Tweaks

| Issue | Solution |
|-------|----------|
| Text overlapping | Shorten labels/descriptions in data.json |
| Wrong colors | Edit template's config.json `themeConfig` |
| Missing image | Check filename matches `illus` field |
| Too crowded | Reduce number of items |

---

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| Text invisible | Low contrast | Check `title.fill` and `item.label.fill` in config.json |
| Image not showing | Wrong filename | Ensure filename matches `illus` value exactly |
| Icon not rendering | Wrong template | Use template with `icon` in name |
| Placeholder shown | Missing file | Add image file to illustrations folder |
| SVG not rendering | Complex SVG | Convert to PNG, or simplify SVG |

---

## Quick Reference

### Commands
| Command | Purpose |
|---------|---------|
| `/template-infographic` | Create template (once) |
| `/infographic` | Generate (guided) |
| `/infographic-quick` | Generate (fast) |
| `/outline infographic-{name}` | Create outline files |

### File Locations
| What | Where |
|------|-------|
| Templates | `{PROJECT}/templates/infographics/{name}/` |
| Outputs | `{PROJECT}/infographics/{date}-{name}/` |
| Skill | `{PLUGIN}/skills/infographic-generator/` |

### Data Structure
```json
{
  "title": "Main Title",
  "desc": "Subtitle",
  "items": [
    { "label": "Label", "desc": "Description" }
  ]
}
```
