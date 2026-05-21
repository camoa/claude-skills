# Visual Craft Detail

Extended detail for the `visual-content` skill: canvas-philosophy example
language, the full visual-component decision gates, and the accessibility &
safety procedures. `SKILL.md` carries the workflow and the mandatory
checklists; this file is the depth behind them.

## Canvas Philosophy — Example Language

These illustrate the language and depth expected in a `canvas-philosophy.md`.
Read a canvas philosophy as an artist reads a creative brief — absorb the
worldview, then express it.

**"Concrete Poetry"**
Communication through monumental form and bold geometry. Massive color blocks, sculptural typography (huge single words, tiny labels), Brutalist spatial divisions. Ideas expressed through visual weight and spatial tension, not explanation. Text as rare, powerful gesture — never paragraphs, only essential words integrated into visual architecture. Every element placed with the precision of a master craftsman who has labored over each decision.

**"Chromatic Language"**
Color as the primary information system. Geometric precision where color zones create meaning. Typography minimal — small sans-serif labels letting chromatic fields communicate. Information encoded spatially and chromatically. Words only anchor what color already shows. The result of painstaking chromatic calibration by someone at the top of their field.

**"Analog Meditation"**
Quiet visual contemplation through texture and breathing room. Paper grain, ink bleeds, vast negative space. Photography and illustration dominate. Typography whispered (small, restrained, serving the visual). Images breathe across pages. Text appears sparingly — short phrases, never explanatory blocks. Each composition balanced with the care of a meditation practice, meticulously crafted over countless hours.

**"Geometric Silence"**
Pure order and restraint. Grid-based precision, bold photography or stark graphics, dramatic negative space. Typography precise but minimal — small essential text, large quiet zones. Swiss formalism meets Brutalist material honesty. Structure communicates, not words. Every alignment the work of countless refinements by an expert hand.

## Visual Components — Decision Gates (MANDATORY)

Components are opt-in (the user enables them during template creation) but must
be used intelligently based on content — not on every slide just because they
are enabled. Before using ANY visual component on a slide, pass these gates IN
ORDER:

**Gate 1: Style Permission**
Does the selected style allow this component? (Check style-constraints.md or the enforcement block.)
- NO → skip the component entirely.
- YES → proceed to Gate 2.

**Gate 2: Content + Personality Justification**
Does the slide's content warrant this component? Also weigh the brand's primary Aaker dimension (from SKILL.md Part 2b):
- **Cards**: Does the slide have 2+ related points that benefit from grouping? Single message → no cards. *Personality modifier: Excitement → lower threshold (cards add visual energy); Sophistication → higher threshold (prefer negative space).*
- **Icons**: Is there a clear, unforced visual metaphor? If you have to think about it → no icon. *Personality modifier: Sincerity/Excitement → icons add warmth/energy; Sophistication → icons risk feeling casual, prefer typographic emphasis.*
- **Gradients**: Is this a hook, transition, or CTA slide? Content slide → no gradient. *Personality modifier: Excitement → gradients add dynamism; Competence → solid colors communicate precision.*
- No justification → skip the component. YES → proceed to Gate 3.

**Gate 3: Frequency Budget**
Is this component within its presentation-wide budget?
- Cards: used on ≤60% of slides so far?
- Icons: used on ≤50% of slides so far?
- Gradients: used on ≤3 slides total?
- OVER budget → skip, use an alternative treatment. WITHIN budget → proceed to Gate 4.

**Gate 4: Density Check**
Will adding this component exceed 3 visual layers on this slide?
- Background + content + this component = 3 layers max.
- Cards + gradient on the same slide is usually too dense (exception: Pitch-Velocity, Memphis).
- TOO dense → skip. OK → use the component.

**When a component fails a gate**, use these alternatives:
- Instead of a card → bold text with an accent underline or increased font size.
- Instead of an icon → typographic emphasis, a number, or additional whitespace.
- Instead of a gradient → a solid brand-tinted background color.

### Component Availability by Style

Verify the style supports the component (see `style-constraints.md`):

| Component | Supported Styles | Not Allowed |
|-----------|-----------------|-------------|
| **Cards** | Dramatic, Organic, Hygge, Lagom, Swiss, Memphis, Feng Shui, Iki, Tech-Modern, Data-Forward, Corporate-Confident, Pitch-Velocity, Narrative-Clean (subtle) | Ma, Yeo-baek |
| **Icons** | Dramatic, Organic, Hygge, Lagom, Swiss, Memphis, Feng Shui, Iki, Tech-Modern, Pitch-Velocity, Data-Forward (trend only) | Minimal, Wabi-Sabi, Shibui, Ma, Yeo-baek, Corporate-Confident, Narrative-Clean |
| **Gradients** | Dramatic, Organic, Hygge, Memphis, Feng Shui, Pitch-Velocity, Tech-Modern (subtle only) | Minimal, Swiss, Ma, Yeo-baek, Lagom, Data-Forward, Corporate-Confident, Narrative-Clean |

### Using Components

**Cards** — rounded containers for content grouping. See `technical-implementation.md` for `draw_content_card()`, `draw_icon_card()`, `draw_feature_card()`.

**Icons** — Lucide icons via the icon helper. The plugin sets `BRAND_CONTENT_DESIGN_DIR` via the SessionStart hook:

```python
import os, sys
from pathlib import Path

plugin_dir = os.environ.get('BRAND_CONTENT_DESIGN_DIR')
if plugin_dir:
    sys.path.insert(0, str(Path(plugin_dir) / "scripts"))

from icons import get_icon_png, search_icons, ICON_CATEGORIES

icon_path = get_icon_png('lightbulb', color='#3B82F6', size=48)
canvas.drawImage(icon_path, x, y, width=48, height=48, mask='auto')
```

**Gradients** — background transitions for depth; see `technical-implementation.md` for `draw_gradient_background`.

### Slide-Type Quick Reference

| Slide Type | Cards | Icons | Gradient |
|------------|:-----:|:-----:|:--------:|
| Hook/Opening | ✗ | ✗ | ✓ |
| Features/Steps | ✓ | ✓ | ✗ |
| Data/Stats | ◐ | ✗ | ✗ |
| Quote | ◐ | ✗ | ✗ |
| CTA/Closing | ✗ | ✗ | ✓ |

**Legend:** ✓ = Use | ◐ = If content warrants | ✗ = Avoid. When in doubt, use fewer.

## Accessibility & Safety Procedures (MANDATORY)

These checks are NON-NEGOTIABLE before any output is finalized. `SKILL.md`
Part 6b carries the Pre-Render Checklist; the procedures behind each item are
here. `validate_contrast()` code is in `technical-implementation.md` →
"Accessibility & Safety Checks".

### Contrast Validation (WCAG AA)

| Requirement | Value |
|-------------|-------|
| Minimum contrast ratio | **4.5:1** for all text |
| Large text (24px+) | 3:1 acceptable |
| Standard | WCAG 2.1 AA |

Before rendering ANY text:
1. Calculate the contrast ratio between text color and background.
2. If ratio < 4.5:1, auto-fix with a safe alternative (white on dark, near-black on light).
3. Log a warning if an auto-fix was needed.

### No Overlap Rule (ABSOLUTE)

Text elements MUST NEVER overlap — not text on text, text on logos, text on
icons, or text bleeding into margins. Before placing ANY element:
1. Calculate its bounding box (position + dimensions).
2. Check against all existing elements for collision.
3. Check against safe-zone margins.
4. If a collision is detected → STOP and adjust position or reduce content.

### Safe Zone Enforcement

| Format | Margin | Safe Area |
|--------|--------|-----------|
| Presentation (1920×1080) | 50px | 1820×980 usable |
| Carousel (1080×1350) | 54px (5%) | 972×1242 usable |

Nothing may cross these boundaries — no text, no logos (except intentional
bleed designs), no icons, no cards.

### Gradient Text Safety

When text appears on gradients: test contrast at **both ends** of the gradient,
require a minimum 4.5:1 at the lowest-contrast point, and if it fails add a
semi-transparent backing behind the text or use a text shadow.
