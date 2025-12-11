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

## SVG Requirements

| Requirement | Specification |
|-------------|---------------|
| Format | SVG (scalable vector) |
| Size | 100×100 to 200×200 pixels recommended |
| Colors | Monochrome or brand colors preferred |
| Style | Simple, iconic, consistent across set |
| File location | Same folder as the infographic output |

## Workflow: Using Illustrated Templates

### Option 1: Provide Your Own SVGs

1. Select an illustrated template
2. Create SVG files for each item
3. Name them to match the `illus` field values
4. Place in output folder before generating

### Option 2: Use AI-Generated Suggestions

When using `/outline infographic-{template}` with an illustrated template:

1. The outline prompt will ask about visual concepts
2. Provide descriptions of what each illustration should show
3. Use the descriptions with an AI image tool or find matching icons
4. Convert to SVG format

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

## Converting Descriptions to SVGs

After getting illustration concepts:

1. **Find existing icons**: Search icon libraries (Lucide, Heroicons, etc.) for matching concepts
2. **AI generation**: Use AI image tools to generate simple icons, then vectorize
3. **Manual creation**: Create in Figma, Illustrator, or Inkscape
4. **Commission**: Use the descriptions as briefs for a designer

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
