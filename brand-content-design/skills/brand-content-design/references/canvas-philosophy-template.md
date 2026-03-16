# Canvas Philosophy Template

Use this template when creating canvas-philosophy.md files for templates. This generates the visual design philosophy that canvas-design skill will use to create visuals.

**IMPORTANT**: Select aesthetic family and style FIRST, then generate the philosophy based on that style's constraints from `style-constraints.md`.

---

## Style Selection (Two Steps)

### Step 1: Choose Aesthetic Family

| Family | Character | Styles |
|--------|-----------|--------|
| **Japanese Zen** | Restraint, intentionality, essence | Minimal, Dramatic, Organic, Wabi-Sabi, Shibui, Iki, Ma |
| **Scandinavian Nordic** | Warmth, balance, functionality | Hygge, Lagom |
| **European Modernist** | Precision or playfulness | Swiss, Memphis |
| **East Asian Harmony** | Space, balance, energy | Yeo-baek, Feng Shui |
| **Contemporary Professional** | Clean, data-aware, business-forward | Tech-Modern, Data-Forward, Corporate-Confident, Pitch-Velocity, Narrative-Clean |

**Selected Family**: [japanese-zen / scandinavian / european / east-asian / contemporary-professional]

### Step 2: Choose Specific Style

See `style-constraints.md` for full details on each style, or use quick reference:

| Style | Character | Best For |
|-------|-----------|----------|
| Minimal | Max whitespace, single focal | Executive, data |
| Dramatic | Asymmetrical, bold contrast | Pitch decks |
| Organic | Natural flow, warmth | Storytelling |
| Wabi-Sabi | Imperfect beauty, texture | Artisan, craft |
| Shibui | Quiet elegance, ultra-refined | Luxury |
| Iki | B&W + pop color, editorial | Fashion |
| Ma | 70%+ whitespace, floating | Meditation |
| Hygge | Warm, cozy, inviting | Wellness |
| Lagom | Balanced "just enough" | Corporate |
| Swiss | Strict grid, mathematical | Tech |
| Memphis | Bold colors, playful chaos | Creative |
| Yeo-baek | Extreme emptiness, purity | Premium |
| Feng Shui | Yin-Yang balance | Wellness |
| Tech-Modern | Clean, systematic, data-aware | SaaS, product demo |
| Data-Forward | Numbers as visual anchors | Quarterly reviews |
| Corporate-Confident | Authoritative, polished | Board, company comms |
| Pitch-Velocity | High-energy momentum | Fundraising, sales |
| Narrative-Clean | Story-driven editorial | Case studies, keynotes |

**Selected Style**: [style-name]

---

# Canvas Philosophy: [Template Name]

## Design Movement Name
**"[Creative Name]"** - [2-3 word description]

Example names by family:
- Japanese Zen: "Silent Precision", "Imperfect Beauty", "Floating Void"
- Scandinavian: "Warm Balance", "Cozy Clarity"
- European: "Grid Logic", "Playful Bold"
- East Asian: "Empty Resonance", "Balanced Flow"
- Contemporary Professional: "Systematic Clarity", "Data Precision", "Forward Momentum"

## Philosophy Statement

[4-6 paragraphs describing the visual philosophy. This is a manifesto for the design approach, not a specification. It should guide visual expression while leaving room for creative interpretation.]

**Paragraph 1 - Core Vision:**
[Describe the fundamental visual approach and what it represents. What feeling should viewers have?]

**Paragraph 2 - Space and Form:**
[Describe how space is used. Generous margins? Dramatic white space? Structured grids? Organic flow?]

**Paragraph 3 - Color and Material:**
[Describe color philosophy. Bold contrast? Subtle gradients? Monochromatic? How do brand colors manifest?]

**Paragraph 4 - Scale and Rhythm:**
[Describe size relationships. Large headlines with whispered body text? Consistent sizing? Dynamic variation?]

**Paragraph 5 - Composition and Balance:**
[Describe layout principles. Asymmetrical tension? Centered calm? Rule of thirds? Grid-based precision?]

**Paragraph 6 - Craftsmanship:**
[Emphasize quality. This work should appear meticulously crafted, labored over with care, the product of deep expertise and countless hours of refinement.]

## Brand Integration

### Colors Applied
- **Primary (#XXXXXX)**: [How it's used - e.g., "Headlines and key emphasis"]
- **Secondary (#XXXXXX)**: [How it's used - e.g., "Supporting elements and accents"]
- **Background (#XXXXXX)**: [How it's used - e.g., "Canvas base, breathing room"]

### Typography Applied
- **[Heading font]**: [How it's used - e.g., "Bold, large, sparse words"]
- **[Body font]**: [How it's used - e.g., "Small supporting labels when needed"]

### Voice Reflected
[How the brand's verbal personality translates to visual choices. A "confident" brand might use bold scale. A "warm" brand might use rounded shapes.]

## Text Treatment

- **Amount**: [Minimal/Very minimal/Almost none]
- **Role**: [Essential labels / Visual accent / Integrated into design]
- **Style**: [Whispered/Bold/Integrated as art]

## Visual Elements

- **Primary imagery**: [Photos/Illustrations/Abstract shapes/None]
- **Supporting graphics**: [Icons/Lines/Patterns/None]
- **Decorative elements**: [None/Minimal/Purposeful only]

## Anti-Patterns (Never)

- [What to avoid - e.g., "Clip art or obviously stock imagery"]
- [What to avoid - e.g., "Walls of text or bullet points"]
- [What to avoid - e.g., "Decorative elements that don't communicate"]
- [What to avoid - e.g., "Low-contrast or hard-to-read text"]

## Composition Rules (Structural Grounding)

Populated during template creation from `references/slide-composition-rules.md`, adapted for the selected style.

### Focal Point Rules
- Position: [from composition rules Section 2, adapted for selected style via Section 3]
- Single focus: every slide has ONE focal point
- Eye path: [F-pattern | Z-pattern | Center-out] based on style

### Element Positioning
- Grid system: [8pt | 12-column modular | organic flow] — based on style
- Headline zone: [Top 25% | Optical center | Upper-left] — from slide blueprints
- Supporting zone: [Below | Right of headline | Bottom half] — from slide blueprints
- Brand anchor: Bottom-right logo, accent color on every slide

### Component Frequency
- Cards: max [N] slides out of [total] (from composition rules Section 4)
- Icons: max [N] slides
- Gradients: exactly [N] slides (specify which: hook, transition, CTA)
- Images: [N] slides, treatment per slide type

### Image Treatment
- Per slide type: [from composition rules Section 5]
- Full-bleed: darken 30-40% for text overlay
- Split: image right 55-65%, text left 35-45%
- Supporting: 30-50% of slide area

### Density Control
- Max 3 visual layers per slide (background + content + accent)
- Never combine: cards + gradient on same slide (unless style explicitly allows)
- Minimum 24px between any two elements
- 48px between logical sections

## Visual Components (Style-Dependent)

**IMPORTANT**: Check `style-constraints.md` for which components your selected style supports.

| Component | Support Levels |
|-----------|---------------|
| **Cards** | ✓ Full, ◐ Subtle only, ✗ None |
| **Icons** | ✓ Allowed, ✗ Not allowed |
| **Gradients** | ✓ Allowed, ✗ Not allowed |

### Card System
*Skip this section if style doesn't support cards*

- **Card style**: [none | subtle | bold | warm | playful]
- **Corner radius**: [0 | 8 | 16 | 24]px
- **Fill approach**: [transparent | solid | gradient | border-only]
- **Usage**: [Feature grouping | Stats | Process steps | Tips]

### Icon Usage
*Skip this section if style doesn't support icons*

- **Icon style**: [outline | filled]
- **Icon placement**: [in-card | standalone | inline-with-text]
- **Icon color**: [primary | secondary | accent | contextual]
- **Icon size**: [24 | 32 | 48 | 64]px
- **Categories used**: [List relevant categories from: business, growth, people, technology, communication, actions, navigation, time, documents, security, money, nature, misc]

### Background Treatment
*Skip this section if style doesn't support gradients*

- **Background type**: [solid | gradient]
- **Gradient direction**: [horizontal | vertical | diagonal | diagonal-reverse]
- **Gradient colors**: [primary → secondary | primary → background | custom pair]
- **Gradient intensity**: [subtle (light tints) | moderate | bold (full colors)]

### Component Examples

If visual components are enabled, describe how they'll be used:

```markdown
Example: Feature Highlights with Icon Cards
- Gradient background (diagonal, primary → secondary)
- 3 feature cards with white fill and rounded corners (16px)
- Each card has: icon (48px, primary color) + title + description
- Icons: lightbulb, zap, shield (from 'misc' and 'security' categories)
```

## Brand Anchors (Always Present)

Regardless of style, these brand elements appear on every slide/card:

- **Logo**: Placed in a consistent position across all slides/cards
  - Presentations: bottom-right of every slide (subtle, small — max 150px wide)
  - Carousels: top-left of first card, bottom-center of last card (CTA)
  - Infographics: not applicable (too small)
- **Primary brand color**: Appears at least once per slide/card — as an accent line, icon color, card border, or text highlight. Even when using derived/special palettes, the primary brand color anchors brand recognition.
- **Brand font**: Heading font from brand-philosophy.md is mandatory. If font files are not in `assets/fonts/`, STOP and instruct user to run `/brand-extract` again or add fonts manually. Never silently fall back to system fonts.

## Quality Standards

- This work must appear as if created by a master craftsman
- Every element placed with painstaking precision
- The result of countless hours of refinement
- Museum or magazine quality execution
- Professional enough to prove expertise

---

## Style Constraints (ENFORCE STRICTLY)

**IMPORTANT**: Copy the exact Enforcement Block for your selected style from `style-constraints.md`.

Each style has a pre-defined enforcement block. Example format:

```
STYLE: [Style Name] ([Family])
- HARD LIMIT: Max X words/slide. Truncate if exceeded.
- HARD LIMIT: Min X% whitespace.
- HARD LIMIT: Max X elements.
- Layout: [Layout directive]
- Typography: [Typography directive]
- Color: [Color directive]
- NEVER: [Anti-patterns]
```

**Paste the enforcement block for your selected style here:**

```
[Copy from style-constraints.md]
```

---

*Philosophy created for [Template Name] template*
*Brand: [Brand Name]*
*Family: [aesthetic family]*
*Style: [style name]*
