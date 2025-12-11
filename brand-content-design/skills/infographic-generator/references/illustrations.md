# Illustrations Reference

## Overview

Illustrated templates (`-illus` suffix) require custom SVG illustrations for each item. These templates provide visual storytelling but need additional assets.

## Illustrated Templates (9 total)

| Template | Category | Items |
|----------|----------|-------|
| sequence-timeline-simple-illus | Sequence | 3-7 |
| sequence-steps-simple-illus | Sequence | 3-5 |
| sequence-snake-steps-simple-illus | Sequence | 4-6 |
| sequence-color-snake-steps-simple-illus | Sequence | 4-6 |
| sequence-horizontal-zigzag-simple-illus | Sequence | 3-5 |
| list-row-simple-illus | List | 3-6 |
| quadrant-simple-illus | Quadrant | 4 |

## Data Structure for Illustrated Templates

```json
{
  "title": "Our Process",
  "items": [
    { "label": "Step 1", "desc": "Discovery phase", "illus": "discovery" },
    { "label": "Step 2", "desc": "Design phase", "illus": "design" },
    { "label": "Step 3", "desc": "Build phase", "illus": "build" }
  ]
}
```

The `illus` field references an SVG file: `{illus}.svg`

## Image Requirements

### Supported Formats

| Format | Best For | Notes |
|--------|----------|-------|
| **SVG** (recommended) | Icons, illustrations | Scales perfectly, small file size |
| **PNG** | Photos, complex images | Supports transparency, use 200×200+ |
| **JPG** | Photos without transparency | Smaller files, no transparency |

### Specifications

| Requirement | Specification |
|-------------|---------------|
| Size | 200×200 pixels minimum for raster (PNG/JPG) |
| **Aspect ratio** | **Square (1:1) strongly recommended** |
| Colors | Monochrome or brand colors preferred for icons |
| Style | Simple, iconic, consistent across set |
| Naming | Match the `illus` field value (e.g., `alarm.svg`, `alarm.png`) |

### Image Sizing Behavior

Images use `preserveAspectRatio="xMidYMid slice"` which means:
- Images are **scaled to fill** their container (not letterboxed)
- Non-square images are **cropped from center**
- Best results with **square images** (1:1 aspect ratio)

| Image Shape | Result |
|-------------|--------|
| Square (1:1) | Perfect fit, no cropping |
| Portrait (3:4) | Left/right edges cropped |
| Landscape (4:3) | Top/bottom edges cropped |

**Recommendation:** Use square images or crop to square before using.

### SVG Pre-processing

Complex SVGs (e.g., Adobe Illustrator exports) are automatically sanitized:
- XML declarations removed
- DOCTYPE removed
- Comments stripped

This ensures compatibility with the @antv/infographic library.

### File Location

Images are stored with each **infographic output**, not in the template:

```
{PROJECT_PATH}/
├── templates/infographics/
│   └── my-template/           # Template config (no images here)
│       ├── config.json
│       └── outline-template.md
│
└── infographics/
    └── 2025-01-15-quarterly-report/   # Each infographic output
        ├── quarterly-report.png       # Generated infographic
        ├── data.json                  # Content data
        └── illustrations/             # Images for this infographic
            ├── growth.svg
            ├── team.png
            └── launch.jpg
```

**Why?** Each infographic may need different images even when using the same template. Storing images with the output keeps everything self-contained and reusable.

## Workflow: Using Illustrated Templates

### Option 1: Provide Your Own Images

1. Select an illustrated template
2. Prepare image files (SVG, PNG, or JPG) for each item
3. Name them to match the `illus` field values
4. Place in template's illustrations folder or specify path

**Examples:**
- Custom photos from a photoshoot
- Brand illustrations from your design team
- Screenshots or product images
- AI-generated images saved as PNG

### Option 2: Find Icons

Use free icon libraries:
- **Lucide**: https://lucide.dev/icons/ (minimal line icons)
- **Heroicons**: https://heroicons.com/ (slightly bolder)
- **Tabler**: https://tabler.io/icons (4500+ icons)

### Option 3: Find Illustrations/Photos

Use free image resources:
- **Unsplash**: https://unsplash.com/ (free photos)
- **unDraw**: https://undraw.co/ (free SVG illustrations)
- **Storyset**: https://storyset.com/ (customizable illustrations)

### Option 4: AI-Generated Images

1. Use an AI image tool (DALL-E, Midjourney, etc.)
2. Prompt: "simple icon of {concept}, minimal style, single color, white background"
3. Save as PNG
4. Place in illustrations folder

## Outline Prompt for Illustrated Templates

When generating outline-prompt.txt for illustrated templates, include:

```
## ILLUSTRATION REQUIREMENTS

This infographic uses illustrated items. For each item you need:
1. Label text (1-2 words)
2. Description text (2-4 words)
3. Illustration concept (describe what the SVG should depict)

Example:
- Label: "Discovery"
- Description: "Research & analysis"
- Illustration concept: "Magnifying glass over documents, representing research and investigation"

For each item in your content, describe what visual would best represent that concept.
The illustrations should be:
- Simple and iconic (not complex scenes)
- Consistent style across all items
- Recognizable at small sizes

## OUTPUT FORMAT

For each item, provide:
```
## Item {n}
- Label: {1-2 words}
- Description: {2-4 words}
- Illustration: {description of visual concept}
```
```

## Getting Images from Concepts

After defining what each illustration should show:

| Method | Best For | Time |
|--------|----------|------|
| **Icon libraries** | Simple concepts (alarm, calendar) | 2-5 min |
| **Stock photos** | Real-world scenes, people | 5-10 min |
| **AI generation** | Custom concepts, unique visuals | 5-10 min |
| **Design tools** | Brand-specific, precise control | 30+ min |
| **Commission** | High quality, brand consistency | Days |

**Quick path:** Most concepts can be found as icons in Lucide/Heroicons in under 5 minutes.

## Fallback: Text-Only Alternative

If illustrations aren't available:

1. Use the equivalent text-only template
2. Sequence-timeline-simple instead of sequence-timeline-simple-illus
3. List-row-simple-horizontal-arrow instead of list-row-simple-illus

## Example: Complete Illustrated Workflow

1. **Select template**: `sequence-steps-simple-illus`

2. **Prepare content with illustration concepts**:
```json
{
  "title": "Development Process",
  "items": [
    {
      "label": "Plan",
      "desc": "Define scope",
      "illus": "planning",
      "_concept": "Clipboard with checklist"
    },
    {
      "label": "Build",
      "desc": "Write code",
      "illus": "coding",
      "_concept": "Code brackets on screen"
    },
    {
      "label": "Test",
      "desc": "Quality assurance",
      "illus": "testing",
      "_concept": "Checkmark in circle"
    },
    {
      "label": "Deploy",
      "desc": "Go live",
      "illus": "deploy",
      "_concept": "Rocket launching upward"
    }
  ]
}
```

3. **Create SVG files**:
   - `planning.svg`
   - `coding.svg`
   - `testing.svg`
   - `deploy.svg`

4. **Generate infographic**: Place SVGs in output folder, run generator

## Tips

- Start with text-only templates until you have a library of SVGs
- Build a reusable illustration library for common concepts
- Consistent illustration style reinforces brand identity
- Simple icons work better than detailed illustrations at small sizes
