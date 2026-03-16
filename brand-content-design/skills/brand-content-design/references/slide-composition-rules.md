# Slide Composition Rules

Structural grounding for presentation slides. Per-slide-type layout patterns with style-aware adaptations. These rules provide the skeleton underneath the creative manifesto—ensuring every slide has a clear focal point, proper element positioning, and controlled density.

---

## Section 1: Universal Composition Principles

These apply to ALL slides regardless of style:

1. **One focal point per slide** — Every slide has exactly ONE primary visual anchor. The eye must know where to land first.
2. **Eye tracking patterns** — Content follows F-pattern (text-heavy) or Z-pattern (visual + text) reading paths
3. **Safe zones** — Nothing within 50px of edges (1920x1080). All content within 1820x980 usable area.
4. **Spacing minimums** — At least 24px between any two elements. 48px between logical sections.
5. **Optical center** — The visual weight center of a slide sits at approximately 45% from top, 50% from left (slightly above geometric center).
6. **Maximum 3 visual layers** — Background layer + content layer + accent layer. Never more.
7. **Content-driven, not template-driven** — The content determines what elements appear, not a fixed template grid.

---

## Section 2: Focal Point Position Map

Where the primary visual anchor sits for each slide type:

| Slide Type | Focal Point Position | Secondary Zone | Tertiary Zone |
|------------|---------------------|----------------|---------------|
| **Title** | Optical center (45% top, 50% left) | Bottom-left: subtitle | Bottom-right: speaker/date |
| **Content** | Upper-left quadrant (30% top, 25% left) | Center: supporting visual | Bottom: detail/evidence |
| **Image (full-bleed)** | Image fills canvas; text overlay bottom-left | — | — |
| **Image (split)** | Image right 60%; text left 40% | Left: body zone below headline | — |
| **Data/Chart** | Chart center, 60% width | Headline top 20% | Insight callout bottom-left |
| **Quote** | Quote text at optical center, max 70% width | Attribution below quote, right-aligned | — |
| **CTA** | CTA text center, upper 40% | Action/button center, lower 40% | — |
| **Transition** | Section title at optical center | — | — |

---

## Section 3: Style-Aware Layout Modifiers

Different style families modify the base focal point positions. Apply these AFTER looking up the base position from Section 2.

### Centered Styles (Minimal, Ma, Corporate-Confident, Yeo-baek)
- Keep focal at optical center
- Symmetrical balance around center axis
- No off-center shifts
- Maximum whitespace emphasis

### Asymmetric Styles (Dramatic, Pitch-Velocity, Iki)
- Shift focal 15-20% off-center (prefer upper-left or upper-right)
- Create intentional tension between focal and supporting elements
- Allow one element to "break" the expected position
- Energy direction: left-to-right for Pitch-Velocity, variable for Dramatic

### Grid Styles (Swiss, Tech-Modern, Data-Forward)
- Snap all elements to modular grid (12-column or 8pt)
- Focal stays at grid intersection points
- Consistent gutters between elements (16px or 24px)
- Mathematical spacing—no organic variance

### Flowing Styles (Organic, Hygge, Narrative-Clean, Lagom)
- Allow 5-10% organic variance from strict positions
- Groupings feel natural, not rigid
- Focal point may be slightly off-grid
- Gentle spacing progression (not mechanical)

### Editorial Styles (Iki, Narrative-Clean)
- Left-heavy text composition (text left, visual right)
- Strong left margin alignment
- Right side reserved for imagery (30-40% width)
- Editorial pacing—some slides intentionally sparse

### Textured Styles (Wabi-Sabi, Organic)
- Intentionally imperfect alignment (±2-3% variance)
- Focal point grounded but not rigid
- Background texture influences spacing perception

### Void Styles (Ma, Yeo-baek)
- Focal point may be a single element or nothing at all
- Extreme margins (15%+ all sides)
- Space IS the design—do not fill it
- Maximum 2 elements, positioned to emphasize emptiness

### Bold Styles (Memphis, Pitch-Velocity, Dramatic)
- Larger focal elements (headlines at maximum allowed size)
- Tighter spacing between grouped elements
- Background fills and gradients allowed
- Higher density accepted within hard limits

---

## Section 4: Component Frequency Rules

Controls how often visual components appear across a presentation to prevent overuse:

| Component | Max per Slide | Max % of Slides | Notes |
|-----------|:------------:|:----------------:|-------|
| **Cards** | 4 | 60% | Cards lose impact when used on every slide |
| **Icons** | 4 (in cards) or 1 (standalone) | 50% | Only use when clear visual metaphor exists |
| **Gradients** | 1 (background only) | 3 slides total | Hook + one transition + CTA = the gradient budget |
| **Images** | 1 (hero) or 3 (gallery) | 40% | Let text-only slides breathe |
| **Data charts** | 1 per slide | 30% | One insight per chart, never stack charts |

### Frequency Enforcement

When generating a presentation, track component usage across all slides:

1. Before adding a component, check current count against limits
2. If a component would exceed its frequency limit, choose an alternative treatment:
   - Instead of a card → use bold text with accent underline
   - Instead of an icon → use typographic emphasis or a number
   - Instead of a gradient → use a solid brand-tinted background
3. Log the substitution for transparency

---

## Section 5: Image Treatment Specs

How images are treated per slide type:

| Slide Type | Treatment | Sizing | Position |
|------------|-----------|--------|----------|
| **Title** | Optional hero background (darken 30-40% for text overlay) | Full-bleed or contained (60-80% width) | Behind text or right half |
| **Content** | Supporting visual | 30-50% of slide area | Right or bottom, secondary to text |
| **Image (full-bleed)** | Hero treatment, text overlay with scrim | 100% of slide | Fill canvas |
| **Image (split)** | Clean crop, no border | 55-65% of slide width | Right side, edge-to-edge vertically |
| **Data/Chart** | Chart as image or rendered | 50-65% of slide area | Center, with headline above |
| **Quote** | Optional subtle texture or photo behind (very low opacity 5-10%) | Full-bleed at low opacity | Behind quote text |
| **CTA** | Optional background image (darken 40-50%) | Full-bleed | Behind CTA content |
| **Transition** | Optional atmospheric background | Full-bleed at low opacity | Behind section title |

### Image Quality Rules
- Minimum resolution: 1920x1080 for full-bleed, 960x540 for contained
- Never stretch images beyond native aspect ratio
- Text over images: always use scrim (semi-transparent overlay) for readability
- Scrim colors: brand primary at 40-60% opacity, or black at 30-50%

---

## Section 6: Per-Slide-Type Composition Blueprints

Detailed element maps for each slide type. These are DEFAULTS—style modifiers from Section 3 adjust positions.

### Title Slide Blueprint

```
┌─────────────────────────────────────┐
│                                     │
│                                     │
│         [HEADLINE]                  │  ← Optical center (45%, 50%)
│         Medium-large, commanding    │
│                                     │
│    [subtitle]                       │  ← Below headline, 60% size
│    lighter weight                   │
│                                     │
│                                     │
│                          [logo]     │  ← Bottom-right, max 150px
│    [speaker] [date]                 │  ← Bottom-left, small
└─────────────────────────────────────┘
```
- Headline: 100% of style's headline range (top end)
- Subtitle: 50-60% of headline size
- All content within 70% horizontal center zone
- Logo: consistent position, subtle, anchoring

### Content Slide Blueprint

```
┌─────────────────────────────────────┐
│                                     │
│  [HEADLINE]                         │  ← Top 20-25%, left-aligned
│                                     │
│  [supporting visual OR cards]       │  ← Center 50-60%
│  [2-4 cards or single image]        │
│                                     │
│  [detail / evidence]                │  ← Bottom 15-20%
│                          [logo]     │
└─────────────────────────────────────┘
```
- Headline: top 25% of slide
- Supporting content: middle zone
- If using cards: 2-4 cards in row or 2x2 grid
- Detail text: small, bottom, optional

### Data/Chart Slide Blueprint

```
┌─────────────────────────────────────┐
│                                     │
│  [Headline: The Key Insight]        │  ← Top 15-20%, contextualizes data
│                                     │
│        ┌──────────────────┐         │
│        │   CHART / DATA   │         │  ← Center, 60% width
│        │   (hero number   │         │
│        │    or chart)     │         │
│        └──────────────────┘         │
│                                     │
│  [insight callout]       [logo]     │  ← Bottom-left, interprets data
└─────────────────────────────────────┘
```
- Chart occupies center 60% of width
- Headline contextualizes ("What this means")
- Insight callout interprets ("Best quarter since launch")
- NO cards on data slides—data IS the visual
- NO icons competing with chart elements

### Quote Slide Blueprint

```
┌─────────────────────────────────────┐
│                                     │
│                                     │
│     "Quote text goes here,         │  ← Optical center
│      maximum 70% width,            │     Large, prominent
│      generous line height"          │
│                                     │
│              — Attribution          │  ← Below quote, right-aligned
│                Title, Company       │     50% of quote size
│                                     │
│                          [logo]     │
└─────────────────────────────────────┘
```
- Quote at optical center, max 70% slide width
- Large quotation marks optional (style-dependent)
- Attribution: right-aligned, below quote, subdued
- NO cards, icons, or gradients

### CTA Slide Blueprint

```
┌─────────────────────────────────────┐
│                                     │
│                                     │
│        [CTA HEADLINE]              │  ← Upper 40%, centered
│        Clear, direct               │
│                                     │
│        [action / next step]         │  ← Lower 40%, centered
│        [URL or instruction]         │
│                                     │
│                          [logo]     │
└─────────────────────────────────────┘
```
- Clean, uncluttered—single focus on the action
- Gradient background allowed (one of 3 total)
- NO cards or icons
- Maximum impact through simplicity

### Transition Slide Blueprint

```
┌─────────────────────────────────────┐
│                                     │
│                                     │
│                                     │
│        [SECTION TITLE]             │  ← Optical center
│                                     │
│                                     │
│                                     │
│                          [logo]     │
└─────────────────────────────────────┘
```
- Maximum whitespace
- Section title only (3-5 words)
- Gradient background allowed (one of 3 total)
- Signals "new chapter" — breathing room

### Image Slide Blueprint (Full-Bleed)

```
┌─────────────────────────────────────┐
│                                     │
│         [FULL IMAGE]                │
│                                     │
│                                     │
│                                     │
│▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│  ← Scrim overlay bottom 30%
│  [headline overlay]                 │
│  [caption]                 [logo]   │
└─────────────────────────────────────┘
```
- Image fills entire canvas
- Text overlay in bottom 30% with scrim
- Minimal text (5-10 words)
- Scrim: brand primary at 50-70% or black at 40-50%

### Image Slide Blueprint (Split)

```
┌───────────────────┬─────────────────┐
│                   │                 │
│  [HEADLINE]       │                 │
│                   │   [IMAGE]       │
│  [body text]      │   55-65% width  │
│  2-3 lines max    │                 │
│                   │                 │
│           [logo]  │                 │
└───────────────────┴─────────────────┘
```
- Text left 35-45%, image right 55-65%
- Image edge-to-edge vertically
- Text vertically centered in its zone
- Clean dividing line (or brand accent line)

---

## Applying Composition Rules

### During Template Creation (Step 12)

When generating `canvas-philosophy.md`, populate the Composition Rules section:

1. Look up the selected style in Section 3 (Style-Aware Layout Modifiers)
2. Apply the style's modifier to base positions from Section 2
3. Set grid system based on style (8pt, 12-column modular, or organic flow)
4. Set component frequency limits from Section 4
5. Set image treatment specs from Section 5
6. Write adapted rules into the canvas-philosophy.md Composition Rules section

### During Presentation Generation

When the visual-content skill generates each slide:

1. **Identify slide type** from the content outline
2. **Look up blueprint** in Section 6
3. **Apply style modifiers** from Section 3
4. **Place focal point FIRST** — everything else positions relative to focal
5. **Check component frequency** — is this component within its budget?
6. **Verify density** — max 3 visual layers, no element collisions
7. **Confirm safe zones** — nothing within 50px of edges

### Fallback for Legacy Templates

Templates created before composition rules was added will not have a Composition Rules section in their canvas-philosophy.md. In this case:

1. Read the style from the canvas-philosophy.md enforcement block
2. Look up the style in this document
3. Apply defaults from Sections 2-5
4. Continue with generation

---

*Slide composition rules for brand-content-design plugin*
*Covers 8 slide types with style-aware adaptations for 18 styles*
