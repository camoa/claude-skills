---
name: visual-content
description: "Use when creating branded presentations, slide decks, or LinkedIn/Instagram carousels. Applies canvas philosophy and brand colors to generate slides with consistent visual hierarchy, typography, and layout. Outputs PDF first, then converts to PPTX for editability. Enforces WCAG AA contrast, safe zones, and style constraints from design system. Use when user says 'create presentation', 'make slides', 'slide deck', 'LinkedIn carousel', or 'branded deck'."
version: 3.1.0
allowed-tools: Read, Write, Glob, Bash
user-invocable: false
---

# Visual Content Skill

Create branded presentations and carousels driven by canvas philosophy and brand identity.

## Part 1: Canvas Philosophy

Read `canvas-philosophy.md` and extract:
- **Movement name** — defines the aesthetic tone (e.g., "Chromatic Silence" = restraint, "Brutalist Joy" = boldness)
- **Philosophy paragraphs** — how ideas manifest through form, space, color, composition
- **Constraints** — hard boundaries that define the style's character (whitespace %, word limits, element count)

## Part 2: Conceptual Thread

Before creating visuals, identify a subtle conceptual reference from the content topic. Embed it into the design through color choices, spatial relationships, or compositional decisions — never literally.

---

## Part 2b: Brand Personality Loading

Before creating visuals, check `brand-philosophy.md` for `## Brand Depth` > `### Personality (Aaker Framework)`:

**If present and populated**: Read the Aaker scores and primary/secondary dimensions. Store in working context — these inform component decisions (Part 7), color intensity (Part 4), and spatial choices throughout.

**If not present**: Read voice traits from `## Verbal Identity` > `### Voice Personality`. Map to Aaker dimensions using proximity:
- precise, reliable, expert, professional → **Competence**
- warm, friendly, approachable, genuine → **Sincerity**
- bold, innovative, daring, creative → **Excitement**
- elegant, refined, luxurious, polished → **Sophistication**
- rugged, authentic, tough, adventurous → **Ruggedness**

Also check for `### Spatial & Surface Profile` — if present, use its values (spacing rhythm, border radius, shadow style, layout density) to inform element placement and styling decisions.

---

## Part 3: Visual Expression

### Composition Rules (MANDATORY)

For every slide:
1. **Identify slide type** — Title, Content, Image, Data/Chart, Quote, CTA, or Transition
2. **Look up focal point** — from canvas-philosophy.md Composition Rules (fallback: `references/slide-composition-rules.md`)
3. **Place focal element FIRST** — primary visual anchor before anything else
4. **Apply style modifier** — centered, asymmetric, grid, or flowing per style
5. **Check component frequency** — within budget across all slides (see Part 7)
6. **Verify density** — max 3 visual layers, no collisions, 24px minimum spacing

### Creating Presentations (16:9)

- **Dimensions**: 1920 x 1080 pixels
- **Format**: PDF first (source of truth) → PPTX (for editability)
- **Character**: Each slide = one clear message (3-second test)
- **Text treatment**: Sparse, integrated as visual element—never paragraphs
- **Safe zones**: Nothing within 50px of edges

**The slide is a canvas, not a document.** Information lives in design choices: scale, position, color, whitespace. Words are visual accents, not content delivery.

### Creating Carousels (Mobile-First)

- **LinkedIn**: 1080 x 1350 (4:5 portrait)
- **Instagram Square**: 1080 x 1080 (1:1)
- **Instagram Portrait**: 1080 x 1350 (4:5)
- **Format**: Multi-page PDF
- **Character**: Each card = 2-second comprehension (thumb-stopping)
- **Text treatment**: Bold, scannable, commanding

**The card is a poster glimpsed while scrolling.** It must arrest attention instantly through visual impact, not dense information.

### Style Enforcement

Each piece must respect its style's **hard constraints**:

| Constraint | Purpose |
|------------|---------|
| Whitespace % | Defines the breathing room—the silence between notes |
| Word limit | Forces economy—every word must earn its place |
| Element count | Prevents visual noise—simplicity is sophistication |
| Layout rules | Establishes spatial grammar—centered, asymmetric, grid |
| Typography weight | Sets the voice—whispered, conversational, commanding |

**If content exceeds constraints, reduce. Never violate the style. The constraints ARE the style.**

---

## Part 4: Design Rules

### Visual Hierarchy
- Single focal point per slide/card
- Clear reading order (F-pattern or Z-pattern)
- Contrast guides attention to primary message

### Typography
| Element | Treatment |
|---------|-----------|
| Headlines | Bold, commanding, minimal — single powerful statement |
| Body | Avoid when possible; if needed, keep minimal |
| Numbers | Large, prominent, contextualized |
| Labels | Small, quiet, supportive |

### Color Application
- Primary: 60% of usage, Secondary: 30%, Accent: 10%
- Use brand palette exclusively — never introduce off-brand colors
- **Personality modifiers** (from Part 2b): Excitement → vibrant saturation; Sophistication → muted/desaturated; Sincerity → warm mid-tones; Competence → clean systematic hierarchy; Ruggedness → deep earthy values

### Anti-Patterns
Avoid: bullet point lists on slides, walls of text, clip art, competing focal points, decoration without purpose, exceeding word/whitespace limits.

---

## Part 5: Final Polish

Before finalizing, take a second pass: verify alignment, spacing, no overlaps, breathing room between elements. Refine what exists rather than adding more elements.

---

## Part 6: Accessibility & Safety (MANDATORY)

**These checks are NON-NEGOTIABLE before any output is finalized.**

### Contrast Validation (WCAG AA)

| Requirement | Value |
|-------------|-------|
| Minimum contrast ratio | **4.5:1** for all text |
| Large text (24px+) | 3:1 acceptable |
| Standard | WCAG 2.1 AA |

**Before rendering ANY text:**
1. Calculate contrast ratio between text color and background
2. If ratio < 4.5:1, auto-fix with safe alternative (white on dark, near-black on light)
3. Log warning if auto-fix was needed

See `references/technical-implementation.md` → "Accessibility & Safety Checks" for `validate_contrast()` code.

### No Overlap Rule (ABSOLUTE)

**Text elements MUST NEVER overlap.** This includes:
- Text on text
- Text on logos
- Text on icons
- Text bleeding into margins

**Before placing ANY element:**
1. Calculate bounding box (position + dimensions)
2. Check against all existing elements for collision
3. Check against safe zone margins
4. If collision detected → STOP and adjust position or reduce content

### Safe Zone Enforcement

| Format | Margin | Safe Area |
|--------|--------|-----------|
| Presentation (1920×1080) | 50px | 1820×980 usable |
| Carousel (1080×1350) | 54px (5%) | 972×1242 usable |

**Nothing may cross these boundaries:**
- No text
- No logos (except intentional bleed designs)
- No icons
- No cards

### Gradient Text Safety

When text appears on gradients:
- Test contrast at **BOTH ends** of the gradient
- Minimum 4.5:1 at the **lowest contrast point**
- If fail: add semi-transparent backing behind text OR use text shadow

### Pre-Render Checklist (EVERY slide/card)

```
□ All text passes 4.5:1 contrast check
□ No elements overlap
□ All elements within safe zone
□ Word count within style limit
□ Element count within style limit
□ Gradient text readable at both ends (if applicable)
```

**If ANY check fails, DO NOT render. Fix the issue first.**

---

## Part 7: Visual Components

Components are opt-in (user enables during template creation). Before using any component, pass these gates in order:

| Gate | Check | Fail Action |
|------|-------|-------------|
| 1. Style Permission | Does style allow this component? (Check style-constraints.md) | Skip component |
| 2. Content Justification | Does content warrant it? Cards: 2+ related points; Icons: clear metaphor; Gradients: hook/CTA slides only | Skip component |
| 3. Frequency Budget | Cards ≤60% of slides, Icons ≤50%, Gradients ≤3 total | Use alternative |
| 4. Density Check | ≤3 visual layers per slide | Skip component |

**Alternatives when gated out:** card → bold text with accent underline; icon → typographic emphasis; gradient → solid brand-tinted background.

### Component Availability by Style

Before using components, verify the style supports them (see `style-constraints.md`):

| Component | Supported Styles | Not Allowed |
|-----------|-----------------|-------------|
| **Cards** | Dramatic, Organic, Hygge, Lagom, Swiss, Memphis, Feng Shui, Iki, Tech-Modern, Data-Forward, Corporate-Confident, Pitch-Velocity, Narrative-Clean (subtle) | Ma, Yeo-baek |
| **Icons** | Dramatic, Organic, Hygge, Lagom, Swiss, Memphis, Feng Shui, Iki, Tech-Modern, Pitch-Velocity, Data-Forward (trend only) | Minimal, Wabi-Sabi, Shibui, Ma, Yeo-baek, Corporate-Confident, Narrative-Clean |
| **Gradients** | Dramatic, Organic, Hygge, Memphis, Feng Shui, Pitch-Velocity, Tech-Modern (subtle only) | Minimal, Swiss, Ma, Yeo-baek, Lagom, Data-Forward, Corporate-Confident, Narrative-Clean |

### Using Cards

Draw rounded containers for content grouping. See `references/technical-implementation.md` for:
- `draw_content_card()` - Basic rounded container
- `draw_icon_card()` - Square card with centered icon
- `draw_feature_card()` - Card with icon, title, description

### Using Icons

Lucide icons available via the icon helper. The plugin sets `BRAND_CONTENT_DESIGN_DIR` via SessionStart hook.

```python
import os
import sys
from pathlib import Path

# Plugin sets BRAND_CONTENT_DESIGN_DIR automatically
plugin_dir = os.environ.get('BRAND_CONTENT_DESIGN_DIR')
if plugin_dir:
    sys.path.insert(0, str(Path(plugin_dir) / "scripts"))

from icons import get_icon_png, search_icons, ICON_CATEGORIES

icon_path = get_icon_png('lightbulb', color='#3B82F6', size=48)
canvas.drawImage(icon_path, x, y, width=48, height=48, mask='auto')
```

See `references/technical-implementation.md` for full icon usage patterns.

### Using Gradients

Background transitions for depth:
```python
# See references/technical-implementation.md for draw_gradient_background
```

### Slide-Type Quick Reference

| Slide Type | Cards | Icons | Gradient |
|------------|:-----:|:-----:|:--------:|
| Hook/Opening | ✗ | ✗ | ✓ |
| Features/Steps | ✓ | ✓ | ✗ |
| Data/Stats | ◐ | ✗ | ✗ |
| Quote | ◐ | ✗ | ✗ |
| CTA/Closing | ✗ | ✗ | ✓ |

**Legend:** ✓ = Use | ◐ = If content warrants | ✗ = Avoid

**Remember**: Visual components must serve the message. When in doubt, use fewer.

---

## Part 8: Technical Implementation (Reference)

For PDF generation code patterns, see `references/technical-implementation.md`:
- Asset preparation (SVG→PNG conversion, font loading)
- reportlab patterns for presentations (1920x1080) and carousels (1080x1350)
- Color parsing from brand-philosophy.md
- Positioning patterns: Centered (Ma/Minimal), Asymmetric (Dramatic/Iki), Grid (Swiss)
- **Visual components: Cards, gradients, icons**

### Quick Reference

| Task | Action |
|------|--------|
| Logo format | **PNG or JPG only** - SVG not supported by reportlab |
| SVG logo | Convert to PNG with cairosvg (`/brand-extract` does this automatically) |
| Custom fonts | Load from `{PROJECT_PATH}/assets/fonts/` |
| Presentations | 1920x1080, 50px safe zones |
| Carousels | 1080x1350 (LinkedIn), 5% margins |
| Colors | Parse from brand-philosophy.md color table |

### Output Process

1. **Generate PDF** (source of truth) - Use `pdf` skill with reportlab
2. **Convert to PPTX** (presentations only) - Use `pptx` skill for editability

---

## Part 9: Workflow Integration

This skill is called by:
- `/template-presentation` - Generate sample.pdf + sample.pptx
- `/template-carousel` - Generate sample.pdf
- `/presentation` - Generate final presentation
- `/presentation-quick` - Generate final presentation (fast path)
- `/carousel` - Generate final carousel
- `/carousel-quick` - Generate final carousel (fast path)

## Part 10: Input Requirements

When invoking this skill, provide:

1. **Canvas philosophy content** (from template's canvas-philosophy.md)
2. **Style enforcement block** (from style-constraints.md)
3. **Content outline** (slide/card content to render)
4. **Brand philosophy** (colors, fonts, logo from brand-philosophy.md)
5. **Output format** (presentation or carousel)
6. **Dimensions** (based on content type)
7. **Visual components config** (optional - from canvas-philosophy.md Visual Components section)

### No-Brand Safeguard

If `brand-philosophy.md` is not found OR contains no `## Color Palette` section:
- **STOP generation** — inform user: "No brand colors found. Run `/brand-extract` first to analyze your brand."
- If user insists on proceeding: use deliberately bland neutrals (#1a1a1a, #666, #f5f5f5, system fonts)
- Never fall back to any recognizable brand colors

### Pre-Output Brand Bias Check

Before finalizing any presentation or carousel:
```
□ All colors derived from brand-philosophy.md color table
□ All fonts loaded from project assets/fonts/ or brand-philosophy.md
□ Colors traced to brand-philosophy.md (not copied from reference docs or runtime fallbacks)
□ No generic font defaults (unless brand actually uses them)
□ Text colors WCAG-validated against actual background
```

---

## Validation Checklist

Before finalizing, verify:
- [ ] Every pixel serves the message — no decorative noise
- [ ] Composition quality matches premium client standards
- [ ] All accessibility checks pass (Part 6)
- [ ] Component gates respected (Part 7)
- [ ] Style constraints enforced throughout

If any check fails, return to Part 5 and refine.
