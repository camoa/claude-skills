---
name: visual-content
description: Use when creating branded presentations or carousels. Generates museum-quality visual output from canvas philosophy, enforcing style constraints. Outputs PDF first, then converts to PPTX for editability.
---

# Visual Content Skill

Create gallery-quality branded presentations and carousels through artistic design philosophy.

## Trigger Phrases

- "generate presentation slides"
- "create carousel cards"
- "design slides from philosophy"
- "render visual content"

## Core Philosophy

Visual content creation is an act of **artistic expression**, not template filling. Every slide or card should appear as if crafted by a designer at the absolute top of their field—meticulous, intentional, worthy of display.

### The Artistic Standard

- **Museum-quality execution**: Work that appears labored over with care
- **90% visual, 10% text**: Information lives in design choices, not paragraphs
- **Spatial communication**: Whitespace, placement, and proportion carry meaning
- **Niche conceptual depth**: Sophisticated references embedded subtly
- **Expert craftsmanship**: Every detail reflects countless hours of refinement

## Two-Phase Process

### Phase 1: Canvas Philosophy (Input)

You receive a `canvas-philosophy.md` containing:
- **Aesthetic movement**: The artistic worldview guiding this content
- **Brand DNA**: Colors, typography, imagery style
- **Style constraints**: Whitespace %, word limits, element counts
- **Slide/card structure**: Sequence and purpose of each

**Read the canvas philosophy as an artist reads a creative brief—internalize its spirit, not just its rules.**

### Phase 2: Visual Expression (Output)

Transform the philosophy into visual artifacts:

1. **Generate PDF first** (source of truth)
   - Use the `pdf` skill for multi-page output
   - Exact positioning, no reflowing
   - Visual fidelity preserved

2. **Convert to PPTX** (for editability)
   - Use the `pptx` skill
   - Maintains design from PDF
   - Allows user edits

## Style Enforcement

Each piece must respect its style's **hard constraints**:

| Constraint | What to Check |
|------------|---------------|
| Whitespace % | Measure empty space vs content |
| Word limit | Count words per slide/card |
| Element count | Count visual elements |
| Layout rules | Centered, asymmetric, grid, etc. |
| Typography weight | Light, medium, bold ranges |

**If content exceeds constraints, reduce. Never violate the style.**

## Content Type Specifications

### Presentations (16:9)

- **Dimensions**: 1920 x 1080 pixels
- **Format**: PDF → PPTX
- **Character**: Each slide = one clear message (3-second test)
- **Text treatment**: Sparse, integrated as visual element
- **Safe zones**: Respect PowerPoint margin guidelines

### Carousels (Mobile-First)

- **LinkedIn**: 1080 x 1350 (4:5 portrait)
- **Instagram Square**: 1080 x 1080 (1:1)
- **Instagram Portrait**: 1080 x 1350 (4:5)
- **Format**: Multi-page PDF
- **Character**: Each card = 2-second comprehension
- **Text treatment**: Bold, scannable, thumb-stopping

## Execution Standards

### Visual Hierarchy

```
1. Single focal point per slide/card
2. Clear reading order (F-pattern or Z-pattern)
3. Contrast guides attention
4. Nothing competes with the message
```

### Typography

```
- Headlines: Bold, commanding, minimal
- Body: Avoid entirely when possible
- Numbers: Large, prominent, contextualized
- Labels: Small, quiet, supportive
```

### Color Application

```
- Use brand palette or selected alternative palette
- Primary: 60% of color usage
- Secondary: 30% of color usage
- Accent: 10% for emphasis only
- Never introduce off-brand colors
```

### Imagery

```
- Full-bleed when emotional impact needed
- Contained when supporting text
- Always high-resolution (no pixelation)
- Consistent treatment across slides/cards
```

## Anti-Patterns (Never Do)

- Bullet point lists (death to presentations)
- Wall of text (breaks 3-second rule)
- Clip art or stock photo clichés
- Competing focal points
- Decoration without purpose
- Violating whitespace minimums
- Exceeding word limits
- Generic templates feel

## Workflow Integration

This skill is called by:
- `/template-presentation` - Generate sample.pdf + sample.pptx
- `/template-carousel` - Generate sample.pdf
- `/presentation` - Generate final presentation
- `/presentation-quick` - Generate final presentation
- `/carousel` - Generate final carousel
- `/carousel-quick` - Generate final carousel

## Input Requirements

When invoking this skill, provide:

1. **Canvas philosophy content** (from template's canvas-philosophy.md)
2. **Style enforcement block** (from style-constraints.md)
3. **Content outline** (slide/card content to render)
4. **Logo path** (from brand-philosophy.md)
5. **Output format** (presentation or carousel)
6. **Dimensions** (based on content type)

## Output

- **PDF**: Visual source of truth, exact rendering
- **PPTX**: Editable version (presentations only)

## Quality Checklist

Before finalizing, verify:

- [ ] Whitespace % meets style minimum
- [ ] Word count within style limit per slide/card
- [ ] Element count within style limit
- [ ] Single focal point per slide/card
- [ ] Brand colors only (no off-brand)
- [ ] Typography weights match style
- [ ] No overlapping elements
- [ ] No content outside safe zones
- [ ] Logo properly placed
- [ ] Consistent visual language throughout

## The Ultimate Test

> Would this work hang in a design museum?
> Would a creative director approve this for a premium client?
> Does every pixel serve the message?

If yes to all three, the work is ready.
