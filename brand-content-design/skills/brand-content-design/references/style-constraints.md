# Style Constraints

18 distinct visual styles across 5 aesthetic families. Each produces fundamentally different visual results.

---

## Style Families Overview

| Family | Origin | Character | Styles |
|--------|--------|-----------|--------|
| **Japanese Zen** | Japan | Restraint, essence, intentionality | Minimal, Dramatic, Organic, Wabi-Sabi, Shibui, Iki, Ma |
| **Scandinavian Nordic** | Denmark/Sweden | Warmth, balance, functionality | Hygge, Lagom |
| **European Modernist** | Germany/Switzerland/Italy | Grid, clarity, expression | Swiss, Memphis |
| **East Asian Harmony** | Korea/China | Space, balance, energy | Yeo-baek, Feng Shui |
| **Contemporary Professional** | Global | Clean, data-aware, business-forward | Tech-Modern, Data-Forward, Corporate-Confident, Pitch-Velocity, Narrative-Clean |

---

## Quick Reference Card

| Style | Family | Whitespace | Words | Elements | Layout | Type Weight |
|-------|--------|------------|-------|----------|--------|-------------|
| Minimal | Japanese | 60-70% | ≤8 | ≤3 | Centered | Light 300-400 |
| Dramatic | Japanese | 35-45% | ≤12 | ≤5 | Asymmetric | Bold 700-900 |
| Organic | Japanese | 50-60% | ≤10 | ≤4 | Flowing | Medium 400-600 |
| Wabi-Sabi | Japanese | 45-55% | ≤10 | ≤4 | Imperfect | Medium 400-500 |
| Shibui | Japanese | 55-65% | ≤6 | ≤3 | Refined | Light 300-400 |
| Iki | Japanese | 50-60% | ≤8 | ≤4 | Editorial | Medium 400-600 |
| Ma | Japanese | 70-80% | ≤5 | ≤2 | Floating | Light 200-300 |
| Hygge | Scandinavian | 40-50% | ≤12 | ≤5 | Cozy | Medium 400-500 |
| Lagom | Scandinavian | 50-60% | ≤10 | ≤4 | Balanced | Regular 400 |
| Swiss | European | 45-55% | ≤10 | ≤5 | Grid | Medium 400-500 |
| Memphis | European | 25-35% | ≤15 | ≤7 | Playful | Bold 600-800 |
| Yeo-baek | East Asian | 65-75% | ≤6 | ≤2 | Empty | Light 300-400 |
| Feng Shui | East Asian | 50-60% | ≤10 | ≤4 | Balanced | Medium 400-500 |
| Tech-Modern | Contemporary | 45-55% | ≤12 | ≤5 | Grid | Medium 400-600 |
| Data-Forward | Contemporary | 40-50% | ≤15 | ≤6 | Data-center | Bold/Regular 400-800 |
| Corporate-Confident | Contemporary | 50-60% | ≤10 | ≤4 | Centered | Medium 500-700 |
| Pitch-Velocity | Contemporary | 35-45% | ≤12 | ≤5 | Asymmetric | Bold 700-900 |
| Narrative-Clean | Contemporary | 50-60% | ≤12 | ≤4 | Left-aligned | Regular 400-500 |

---

## Visual Components Quick Reference

Components available per style. See `references/visual-components.md` for full documentation.

| Style | Cards | Icons | Gradients | Notes |
|-------|:-----:|:-----:|:---------:|-------|
| Minimal | ◐ | ✗ | ✗ | Cards: thin border only, no fill |
| Dramatic | ✓ | ✓ | ✓ | Bold fills, high contrast |
| Organic | ✓ | ✓ | ✓ | Soft, natural, brand colors muted |
| Wabi-Sabi | ◐ | ✗ | ✗ | Cards: textured, imperfect edges |
| Shibui | ◐ | ✗ | ✗ | Cards: hairline borders only |
| Iki | ✓ | ✓ | ✗ | B&W cards + pop color |
| Ma | ✗ | ✗ | ✗ | No components - emptiness only |
| Hygge | ✓ | ✓ | ✓ | Cozy, soft corners, brand colors softened |
| Lagom | ✓ | ✓ | ✗ | Functional, balanced |
| Swiss | ✓ | ✓ | ✗ | Grid-aligned, precise |
| Memphis | ✓ | ✓ | ✓ | Colorful, playful, geometric |
| Yeo-baek | ✗ | ✗ | ✗ | No components - void is design |
| Feng Shui | ✓ | ✓ | ✓ | Balanced, harmonious |
| Tech-Modern | ✓ | ✓ | ◐ | Subtle fills, outline icons, subtle gradients (max 1) |
| Data-Forward | ✓ | ◐ | ✗ | Stat cards, trend icons only |
| Corporate-Confident | ✓ | ✗ | ✗ | Clean bordered cards, no icons/gradients |
| Pitch-Velocity | ✓ | ✓ | ✓ | Bold cards, bold icons, energetic gradients |
| Narrative-Clean | ◐ | ✗ | ✗ | Thin border editorial cards only |

**Legend:** ✓ = Full support | ◐ = Limited/subtle | ✗ = Not allowed

---

# Japanese Zen Family

Seven styles based on traditional Japanese aesthetic principles emphasizing restraint, essence, and intentional simplicity.

**Learn more**: [Japanese Aesthetics (Wikipedia)](https://en.wikipedia.org/wiki/Japanese_aesthetics)

---

## Minimal

Based on **Kanso** (simplicity) and **Seijaku** (tranquil stillness). Profound clarity through absence.

**Learn more**: [Kanso](https://en.wikipedia.org/wiki/Japanese_aesthetics#Kanso) | [Seijaku](https://en.wikipedia.org/wiki/Japanese_aesthetics#Seijaku)

**Best for**: Executive presentations, data-driven content, technical audiences

### Constraints

| Parameter | Value | Enforcement |
|-----------|-------|-------------|
| Whitespace | 60-70% | HARD LIMIT |
| Max words/slide | 8 | HARD LIMIT |
| Max elements | 3 | HARD LIMIT |
| Colors | 3 maximum | HARD LIMIT |

### Layout Rules
- Center all primary elements OR single strong left alignment
- Strict 8-point grid, no exceptions
- ONE focal point per slide at optical center
- Uniform, generous margins (10%+ on all sides)

### Typography
- Weight: Light (300-400)
- Headlines: 48-56pt
- Scale: 1.2x (tight progression)

### Anti-Patterns (NEVER)
- Multiple focal points
- Decorative elements
- Bullet points
- Drop shadows

### Example
> White slide, generous margins. Single light-weight headline at optical center. Thin accent line in brand color. 65% empty space. The emptiness IS the design.

### Visual Components
- **Cards**: Limited - thin border only (1px), no fill, no shadow
- **Icons**: Not allowed
- **Gradients**: Not allowed

### Enforcement Block
```
STYLE: Minimal (Japanese Zen)
- HARD LIMIT: Max 8 words/slide. Truncate if exceeded.
- HARD LIMIT: Min 60% whitespace.
- HARD LIMIT: Max 3 elements, 3 colors.
- Layout: Center primary elements. Strict 8pt grid.
- Typography: Light weights (300-400), headlines 48-56pt.
- Components: Cards (thin border only), no icons, no gradients.
- NEVER: Multiple focal points, decorative elements, bullet points, filled cards.
```

---

## Dramatic

Based on **Datsuzoku** (freedom from convention) and **Fukinsei** (asymmetry). Impact through controlled tension.

**Learn more**: [Fukinsei](https://en.wikipedia.org/wiki/Japanese_aesthetics#Fukinsei)

**Best for**: Pitch decks, announcements, creative industries

### Constraints

| Parameter | Value | Enforcement |
|-----------|-------|-------------|
| Whitespace | 35-45% | HARD LIMIT |
| Max words/slide | 12 | HARD LIMIT |
| Max elements | 5 | HARD LIMIT |
| Colors | 4-5 | Full range for contrast |

### Layout Rules
- Asymmetrical, intentionally off-center
- Intentional grid breaks for tension
- Strong focal with supporting elements in tension
- Varied spacing - tight groupings against open space

### Typography
- Weight: Bold to Black (700-900)
- Headlines: 56-72pt (largest of all styles)
- Scale: 1.5x (dramatic jumps)

### Anti-Patterns (NEVER)
- Perfect centering of all elements
- Uniform spacing
- Muted colors
- Small headlines
- Symmetrical layouts

### Example
> Deep navy slide. Massive bold headline high and left, breaking center. Vibrant cyan accent creates tension. Image bleeds off right edge. Asymmetry intentional, contrast striking.

### Visual Components
- **Cards**: Full support - bold fills, high contrast, sharp or rounded corners
- **Icons**: Allowed - bold, high contrast colors
- **Gradients**: Allowed - bold angles, dramatic transitions

### Enforcement Block
```
STYLE: Dramatic (Japanese Zen)
- HARD LIMIT: Max 12 words/slide.
- HARD LIMIT: Min 35% whitespace.
- HARD LIMIT: Max 5 elements.
- Layout: Asymmetrical. Focal elements OFF-CENTER.
- Typography: Bold/black (700-900), headlines 56-72pt.
- Color: 4-5 colors, high contrast.
- Components: Bold cards, icons allowed, dramatic gradients.
- NEVER: Center all elements, uniform spacing, muted colors, subtle cards.
```

---

## Organic

Based on **Shizen** (naturalness) and **Yugen** (hidden depth). Humanity and approachability over precision.

**Learn more**: [Yugen](https://en.wikipedia.org/wiki/Y%C5%ABgen) | [Shizen](https://en.wikipedia.org/wiki/Japanese_aesthetics#Shizen)

**Best for**: Storytelling, education, wellbeing content

### Constraints

| Parameter | Value | Enforcement |
|-----------|-------|-------------|
| Whitespace | 50-60% | HARD LIMIT |
| Max words/slide | 10 | HARD LIMIT |
| Max elements | 4 | HARD LIMIT |
| Colors | 5-6 from brand, muted/softened | Soften brand palette — reduce saturation, not change hue |

### Layout Rules
- Natural groupings, organic flow
- Loose 8-point grid
- Clear focal integrated with supporting elements
- Gentle spacing progression

### Typography
- Weight: Medium to SemiBold (400-600)
- Headlines: 48-60pt
- Scale: 1.35x (gentle progression)

### Texture
- Subtle paper/linen background at 3-5% opacity
- Soft, organic borders

### Anti-Patterns (NEVER)
- Stark black/white contrast
- Rigid grid alignment
- Sharp geometric shapes
- Pure white backgrounds

### Example
> Soft-toned slide with subtle paper texture. Headline in muted brand primary, naturally off-center. Documentary image integrates with text. Everything feels connected, human. Colors drawn from brand palette, softened to feel natural.

### Visual Components
- **Cards**: Full support - soft fills from brand palette (muted), large radius (16-24px), no sharp corners
- **Icons**: Allowed - brand colors, organic feel
- **Gradients**: Allowed - subtle transitions between brand palette tones

### Enforcement Block
```
STYLE: Organic (Japanese Zen)
- HARD LIMIT: Max 10 words/slide.
- HARD LIMIT: Min 50% whitespace.
- HARD LIMIT: Max 4 elements.
- Layout: Natural groupings, organic flow.
- Typography: Medium weights (400-600), headlines 48-60pt.
- Color: Brand palette softened (reduce saturation 20-30%). No stark black or pure white.
- Texture: Subtle background texture (3-5% opacity).
- Components: Soft cards (muted brand fills, large radius), brand-colored icons, subtle gradients.
- NEVER: Stark contrast, rigid grids, sharp-cornered cards.
```

---

---

## Wabi-Sabi

Beauty in imperfection, impermanence, and incompleteness. Embraces texture, age, and handcraft.

**Learn more**: [Wabi-Sabi (Wikipedia)](https://en.wikipedia.org/wiki/Wabi-sabi)

**Best for**: Artisan brands, craft products, sustainability, wellness

### Constraints

| Parameter | Value | Enforcement |
|-----------|-------|-------------|
| Whitespace | 45-55% | HARD LIMIT |
| Max words/slide | 10 | HARD LIMIT |
| Max elements | 4 | HARD LIMIT |
| Colors | 4-5 from brand, heavily muted | Desaturate brand palette 30-40% for aged feel |

### Layout Rules
- Intentionally imperfect alignment
- Visible texture and grain
- Asymmetrical but grounded
- Handcrafted feel

### Typography
- Weight: Medium (400-500)
- Headlines: 44-54pt
- Style: Slightly irregular, humanist fonts preferred
- Allow natural variation

### Texture
- Prominent paper, cloth, or stone texture (5-10% opacity)
- Rough edges allowed
- Aged, weathered feel
- Natural materials aesthetic

### Anti-Patterns (NEVER)
- Perfect geometry
- Pristine, polished surfaces
- Neon or saturated colors (desaturate first)
- Machine-precision alignment
- Glossy finishes

### Example
> Textured paper background with visible grain. Headline slightly off-axis in humanist typeface. Brand colors heavily muted to feel aged and natural. Image with natural grain, edges soft and imperfect. Beauty in the imperfect.

### Visual Components
- **Cards**: Limited - textured/rough edges, imperfect corners, muted brand palette fills
- **Icons**: Not allowed (too precise/synthetic)
- **Gradients**: Not allowed (too smooth/perfect)

### Enforcement Block
```
STYLE: Wabi-Sabi (Japanese Zen)
- HARD LIMIT: Max 10 words/slide.
- HARD LIMIT: Min 45% whitespace.
- HARD LIMIT: Max 4 elements.
- Layout: Intentionally imperfect. Visible texture.
- Typography: Medium (400-500), humanist fonts, 44-54pt headlines.
- Color: Brand palette desaturated 30-40%. Muted, low-chroma versions of brand colors.
- Texture: Paper/cloth texture 5-10% opacity.
- Components: Textured cards only (rough edges), no icons, no gradients.
- NEVER: Perfect geometry, neon/saturated colors, glossy finishes, precise icons.
```

---

## Shibui

Quiet elegance that deepens with attention. Ultra-refined, understated luxury.

**Learn more**: [Shibui (Wikipedia)](https://en.wikipedia.org/wiki/Shibui)

**Best for**: Luxury brands, professional services, mature audiences

### Constraints

| Parameter | Value | Enforcement |
|-----------|-------|-------------|
| Whitespace | 55-65% | HARD LIMIT |
| Max words/slide | 6 | HARD LIMIT - strictest |
| Max elements | 3 | HARD LIMIT |
| Colors | 2-3 muted | Extremely restrained |

### Layout Rules
- Refined, precise placement
- Sophisticated grid with subtle breaks
- Single focal point with quiet support
- Premium spacing

### Typography
- Weight: Light (300-400)
- Headlines: 44-52pt
- Style: Elegant, refined serif or premium sans
- Exceptional letter-spacing

### Color
- Ultra-muted palette
- Sophisticated grays, taupes, muted navies
- Almost no accent - subtlety is key
- No bright or saturated colors

### Anti-Patterns (NEVER)
- Bright colors
- Bold typography
- Multiple focal points
- Busy compositions
- Obvious design moves

### Example
> Soft gray background. Refined serif headline in muted charcoal, perfectly spaced. Minimal supporting text in sophisticated small caps. 60% empty. Elegance so subtle it reveals itself slowly.

### Visual Components
- **Cards**: Limited - hairline borders only (0.5px), no fill, ultra-refined
- **Icons**: Not allowed (too obvious)
- **Gradients**: Not allowed (too bold)

### Enforcement Block
```
STYLE: Shibui (Japanese Zen)
- HARD LIMIT: Max 6 words/slide. Extreme brevity.
- HARD LIMIT: Min 55% whitespace.
- HARD LIMIT: Max 3 elements, 2-3 colors.
- Layout: Refined, sophisticated placement.
- Typography: Light (300-400), elegant fonts, 44-52pt headlines.
- Color: Ultra-muted only. No bright or saturated.
- Components: Hairline cards only (no fill), no icons, no gradients.
- NEVER: Bold type, bright colors, busy compositions, obvious design moves.
```

---

## Iki

Urban sophistication with confident flair. Editorial elegance, B&W with striking color pop.

**Learn more**: [Iki (Wikipedia)](https://en.wikipedia.org/wiki/Iki_(aesthetic_ideal))

**Best for**: Fashion, lifestyle, editorial content, urban brands

### Constraints

| Parameter | Value | Enforcement |
|-----------|-------|-------------|
| Whitespace | 50-60% | HARD LIMIT |
| Max words/slide | 8 | HARD LIMIT |
| Max elements | 4 | HARD LIMIT |
| Colors | B&W + 1 pop | Monochrome base + single accent |

### Layout Rules
- Editorial grid structure
- Confident asymmetry
- Magazine-style composition
- Bold negative space use

### Typography
- Weight: Medium to SemiBold (400-600)
- Headlines: 48-60pt
- Style: Stylish sans-serif, editorial feel
- Strong contrast between sizes

### Color
- Primarily black and white
- ONE bold accent color
- High contrast
- Confident, not subtle

### Anti-Patterns (NEVER)
- Multiple accent colors
- Muted palette
- Safe, corporate layouts
- Timid type choices
- Cluttered compositions

### Example
> Stark white slide. Bold black headline positioned with editorial confidence. Single vibrant red element creates striking contrast. Black and white photography with red accent detail. Stylish, confident, urban.

### Visual Components
- **Cards**: Full support - B&W fills with pop color accents, sharp corners (0-8px)
- **Icons**: Allowed - black, white, or pop color only
- **Gradients**: Not allowed (breaks B&W + pop aesthetic)

### Enforcement Block
```
STYLE: Iki (Japanese Zen)
- HARD LIMIT: Max 8 words/slide.
- HARD LIMIT: Min 50% whitespace.
- HARD LIMIT: Max 4 elements.
- Layout: Editorial grid. Confident asymmetry.
- Typography: Medium (400-600), stylish sans, 48-60pt headlines.
- Color: B&W base + ONE pop color only.
- Components: B&W cards (sharp), icons (B&W or pop), no gradients.
- NEVER: Multiple accents, muted colors, safe layouts, colorful cards.
```

---

## Ma

The space between. Extreme negative space where emptiness itself is the design.

**Learn more**: [Ma (Wikipedia)](https://en.wikipedia.org/wiki/Ma_(negative_space))

**Best for**: Meditation apps, luxury minimalism, architecture, high-end brands

### Constraints

| Parameter | Value | Enforcement |
|-----------|-------|-------------|
| Whitespace | 70-80% | HARD LIMIT - highest of all |
| Max words/slide | 5 | HARD LIMIT - most minimal |
| Max elements | 2 | HARD LIMIT |
| Colors | 2 maximum | Extreme restraint |

### Layout Rules
- Elements float in vast space
- Negative space is primary design element
- Extreme margins (15%+ all sides)
- Single focal point or nothing

### Typography
- Weight: Extra Light to Light (200-300)
- Headlines: 40-50pt
- Generous letter-spacing
- Words feel like they're breathing

### Color
- Near-monochromatic
- Subtle tonal shifts only
- No strong accents
- The space provides contrast

### Anti-Patterns (NEVER)
- Filling space
- Multiple elements
- Strong colors
- Dense typography
- Any sense of crowding

### Example
> Almost entirely white slide. Single word in extra-light weight floats in center. 75% pure emptiness. The pause between thoughts. The space speaks.

### Visual Components
- **Cards**: Not allowed (fills the void)
- **Icons**: Not allowed (too many elements)
- **Gradients**: Not allowed (disrupts emptiness)

### Enforcement Block
```
STYLE: Ma (Japanese Zen)
- HARD LIMIT: Max 5 words/slide. Extreme minimalism.
- HARD LIMIT: Min 70% whitespace. Emptiness is design.
- HARD LIMIT: Max 2 elements, 2 colors.
- Layout: Floating elements. 15%+ margins.
- Typography: Extra light (200-300), 40-50pt headlines.
- Color: Near-monochromatic. No strong accents.
- Components: NONE. No cards, icons, or gradients.
- NEVER: Fill space, multiple elements, dense typography, visual components.
```

---

# Scandinavian Nordic Family

Two styles based on Nordic design philosophy emphasizing warmth, balance, and intentional living.

**Learn more**: [Scandinavian Design](https://en.wikipedia.org/wiki/Scandinavian_design)

---

## Hygge

Danish concept of cozy togetherness and contentment. Inviting, comfortable, approachable.

**Learn more**: [Hygge (Wikipedia)](https://en.wikipedia.org/wiki/Hygge)

**Best for**: Wellness brands, community content, lifestyle, hospitality

### Constraints

| Parameter | Value | Enforcement |
|-----------|-------|-------------|
| Whitespace | 40-50% | HARD LIMIT |
| Max words/slide | 12 | HARD LIMIT |
| Max elements | 5 | HARD LIMIT |
| Colors | 5-6 from brand, softened | Reduce saturation 15-25%, lighten for cozy feel |

### Layout Rules
- Comfortable, inviting arrangement
- Soft groupings
- Intimate feel, not distant
- Approachable hierarchy

### Typography
- Weight: Medium (400-500)
- Headlines: 44-56pt
- Style: Friendly, rounded sans or brand serif
- Comfortable reading

### Color
- Brand palette softened and lightened for cozy feel
- Add slight warmth shift if brand allows (shift hue 5-10° toward amber)
- Background: lightest brand color or tinted off-white from brand primary
- Nothing harsh or high-saturation

### Texture
- Soft textures (wool, knit, wood grain)
- Soft gradients between brand tones allowed
- Inviting surfaces
- Tactile feel

### Anti-Patterns (NEVER)
- Sharp edges
- Clinical layouts
- Distant, corporate feel
- High contrast
- Neon or fully saturated colors

### Example
> Soft background tinted with lightest brand color. Friendly headline in muted brand primary. Image of welcoming scene with soft focus. Brand accent softened. Everything invites you in — cozy, approachable.

### Visual Components
- **Cards**: Full support - soft brand fills, large radius (20-24px), soft shadows allowed
- **Icons**: Allowed - brand colors (softened), friendly/rounded icons
- **Gradients**: Allowed - subtle transitions between softened brand colors

### Enforcement Block
```
STYLE: Hygge (Scandinavian)
- HARD LIMIT: Max 12 words/slide.
- HARD LIMIT: Min 40% whitespace.
- HARD LIMIT: Max 5 elements.
- Layout: Comfortable, intimate arrangement.
- Typography: Medium (400-500), friendly fonts, 44-56pt headlines.
- Color: Brand palette softened (reduce saturation 15-25%, lighten). Slight warmth shift OK if brand allows.
- Texture: Soft, tactile (wool, wood grain).
- Components: Soft cards (large radius, soft shadows), friendly icons, subtle gradients.
- NEVER: Sharp edges, clinical feel, neon colors, sharp-cornered cards.
```

---

## Lagom

Swedish "just the right amount." Perfect balance, neither excess nor lacking.

**Learn more**: [Lagom (Wikipedia)](https://en.wikipedia.org/wiki/Lagom)

**Best for**: Corporate communications, balanced messaging, sustainable brands

### Constraints

| Parameter | Value | Enforcement |
|-----------|-------|-------------|
| Whitespace | 50-60% | HARD LIMIT |
| Max words/slide | 10 | HARD LIMIT |
| Max elements | 4 | HARD LIMIT |
| Colors | 4-5 neutral | Balanced palette |

### Layout Rules
- Perfect balance without symmetry
- Functional arrangement
- Clear but not minimal
- Purposeful placement

### Typography
- Weight: Regular (400)
- Headlines: 44-54pt
- Style: Clean, functional sans-serif
- Neither bold nor light - balanced

### Color
- Balanced neutrals
- Soft whites, light grays, natural wood tones
- One gentle accent
- Nothing extreme

### Anti-Patterns (NEVER)
- Extremes of any kind
- Too minimal or too full
- Bold, attention-seeking colors
- Dramatic layouts
- Excessive decoration

### Example
> Clean white-gray background. Balanced headline at comfortable weight. Elements arranged with functional clarity. Not minimal, not full - just right. Sustainable, sensible design.

### Visual Components
- **Cards**: Full support - neutral fills, medium radius (12-16px), functional borders
- **Icons**: Allowed - neutral or gentle accent colors
- **Gradients**: Not allowed (too dramatic)

### Enforcement Block
```
STYLE: Lagom (Scandinavian)
- HARD LIMIT: Max 10 words/slide.
- HARD LIMIT: Min 50% whitespace.
- HARD LIMIT: Max 4 elements.
- Layout: Balanced, functional. Neither minimal nor full.
- Typography: Regular weight (400), clean sans, 44-54pt headlines.
- Color: Balanced neutrals. One gentle accent. No extremes.
- Components: Functional cards (neutral, medium radius), icons, no gradients.
- NEVER: Extremes, dramatic layouts, bold colors, dramatic gradients.
```

---

# European Modernist Family

Two styles spanning rational modernism to postmodern expression.

---

## Swiss

International Typographic Style. Mathematical precision, objective clarity, grid perfection.

**Learn more**: [Swiss Style (Wikipedia)](https://en.wikipedia.org/wiki/Swiss_Style_(design))

**Best for**: Tech companies, corporate identity, data visualization, professional

### Constraints

| Parameter | Value | Enforcement |
|-----------|-------|-------------|
| Whitespace | 45-55% | HARD LIMIT |
| Max words/slide | 10 | HARD LIMIT |
| Max elements | 5 | HARD LIMIT |
| Colors | 3-4 | Rational selection |

### Layout Rules
- Strict modular grid
- Mathematical spacing
- Left-aligned typography
- Objective, rational arrangement

### Typography
- Weight: Medium (400-500)
- Headlines: 48-60pt
- Style: Grotesque sans-serif (brand's heading font if grotesque, or Helvetica-family)
- Flush left, ragged right

### Color
- Primary colors or systematic palette
- High contrast for readability
- Functional color use
- Red and black classic combination

### Anti-Patterns (NEVER)
- Centered text
- Decorative elements
- Organic shapes
- Irregular spacing
- Emotional design choices

### Example
> White slide with visible grid structure. Bold Helvetica headline flush left. Black text, red accent. Mathematical precision in every measurement. Objective, universal, rational.

### Visual Components
- **Cards**: Full support - grid-aligned, precise borders, sharp corners (0-4px)
- **Icons**: Allowed - geometric, grid-aligned, functional
- **Gradients**: Not allowed (not objective/rational)

### Enforcement Block
```
STYLE: Swiss (European Modernist)
- HARD LIMIT: Max 10 words/slide.
- HARD LIMIT: Min 45% whitespace.
- HARD LIMIT: Max 5 elements.
- Layout: Strict modular grid. Mathematical spacing.
- Typography: Medium (400-500), grotesque sans, 48-60pt headlines.
- Alignment: Flush left only. Never centered.
- Color: 3-4 colors. Functional use.
- Components: Grid-aligned cards (sharp), geometric icons, no gradients.
- NEVER: Centered text, decoration, organic shapes, rounded cards, gradients.
```

---

## Memphis

Postmodern "less is bore." Bold colors, geometric shapes, playful rule-breaking.

**Learn more**: [Memphis Group (Wikipedia)](https://en.wikipedia.org/wiki/Memphis_Group)

**Best for**: Creative agencies, youth brands, entertainment, disruptive startups

### Constraints

| Parameter | Value | Enforcement |
|-----------|-------|-------------|
| Whitespace | 25-35% | HARD LIMIT - lowest |
| Max words/slide | 15 | HARD LIMIT - most generous |
| Max elements | 7 | HARD LIMIT - most allowed |
| Colors | 5-7 bold | Vibrant, clashing |

### Layout Rules
- Intentional chaos
- Geometric shapes as decoration
- Layered elements
- Playful, rule-breaking

### Typography
- Weight: Bold to Black (600-800)
- Headlines: 52-72pt
- Style: Playful, geometric, or bold sans
- Can be tilted, stacked, layered

### Color
- Neon and pastel combinations
- Clashing colors celebrated
- Patterns allowed (terrazzo, squiggles)
- No neutral palettes

### Shapes
- Circles, triangles, squiggles
- Geometric decorative elements
- Patterns and textures
- 80s-inspired graphics

### Anti-Patterns (NEVER)
- Minimalism
- Neutral colors
- Corporate restraint
- Predictable layouts
- Taking itself too seriously

### Example
> Hot pink background with yellow geometric shapes. Bold black headline at an angle. Turquoise squiggle accent. Terrazzo pattern element. Joyful, irreverent, impossible to ignore.

### Visual Components
- **Cards**: Full support - colorful fills, any radius, can overlap/layer
- **Icons**: Allowed - bold colors, playful, can be tilted
- **Gradients**: Allowed - vibrant, multi-color, playful angles

### Enforcement Block
```
STYLE: Memphis (European Modernist)
- HARD LIMIT: Max 15 words/slide.
- HARD LIMIT: Min 25% whitespace.
- HARD LIMIT: Max 7 elements.
- Layout: Playful chaos. Layer elements. Break rules.
- Typography: Bold (600-800), playful fonts, 52-72pt. Can tilt/stack.
- Color: 5-7 bold colors. Neons + pastels. Clashing OK.
- Shapes: Geometric decoration (circles, squiggles, terrazzo).
- Components: Colorful cards (layered OK), bold icons, vibrant gradients.
- NEVER: Minimalism, neutral colors, corporate restraint, subtle cards.
```

---

# East Asian Harmony Family

Two styles based on Korean and Chinese principles of space, balance, and energy.

---

## Yeo-baek

Korean concept of meaningful negative space. Emptiness that allows rest and contemplation.

**Learn more**: [Korean Design Aesthetics](https://adorno.design/editorial/why-korean-design-is-the-next-global-obsession/)

**Best for**: Premium brands, meditation apps, luxury products, art galleries

### Constraints

| Parameter | Value | Enforcement |
|-----------|-------|-------------|
| Whitespace | 65-75% | HARD LIMIT |
| Max words/slide | 6 | HARD LIMIT |
| Max elements | 2 | HARD LIMIT |
| Colors | 2-3 | Minimal palette |

### Layout Rules
- Emptiness is primary
- Elements exist in relationship to void
- Extreme margins
- Single or no focal point

### Typography
- Weight: Light (300-400)
- Headlines: 42-52pt
- Style: Clean, refined
- Generous spacing

### Color
- Near white (cheong-baek - purity)
- Soft grays
- Single muted accent if any
- Imperfect white, not stark

### Anti-Patterns (NEVER)
- Filling the void
- Multiple elements
- Strong colors
- Dense compositions
- Western compositional rules

### Example
> Almost entirely empty off-white slide. Single refined element in soft gray. 70% pure space. The emptiness is the message - space for thought, rest for the eye.

### Visual Components
- **Cards**: Not allowed (disrupts void)
- **Icons**: Not allowed (too many elements)
- **Gradients**: Not allowed (disturbs purity)

### Enforcement Block
```
STYLE: Yeo-baek (East Asian)
- HARD LIMIT: Max 6 words/slide.
- HARD LIMIT: Min 65% whitespace. Emptiness primary.
- HARD LIMIT: Max 2 elements, 2-3 colors.
- Layout: Void is design. Extreme margins.
- Typography: Light (300-400), refined, 42-52pt headlines.
- Color: Near-white, soft grays. Imperfect purity.
- Components: NONE. No cards, icons, or gradients.
- NEVER: Fill void, multiple elements, strong colors, visual components.
```

---

## Feng Shui

Chinese Yin-Yang balance. Harmonious energy flow through balanced opposing forces.

**Learn more**: [Feng Shui (Wikipedia)](https://en.wikipedia.org/wiki/Feng_shui)

**Best for**: Wellness brands, holistic health, spa/retreat, harmony-focused messaging

### Constraints

| Parameter | Value | Enforcement |
|-----------|-------|-------------|
| Whitespace | 50-60% | HARD LIMIT |
| Max words/slide | 10 | HARD LIMIT |
| Max elements | 4 | HARD LIMIT |
| Colors | 5 from brand palette | Map brand colors to Five Element roles |

### Layout Rules
- Balance curved and angular
- Energy flow consideration
- Yin (soft) and Yang (strong) in equilibrium
- Natural movement path for eye

### Typography
- Weight: Medium (400-500)
- Headlines: 46-56pt
- Mix of curved and angular letterforms
- Balanced sizing

### Color (Five Elements — mapped from brand)
- Map brand palette to Element roles by hue proximity:
  - Earth role: warm brand colors (yellows, browns, oranges)
  - Fire role: energetic brand colors (reds, oranges)
  - Water role: cool brand colors (blues, blacks)
  - Wood role: growth brand colors (greens, teals)
  - Metal role: neutral brand colors (whites, grays, silvers)
- Not all Elements required — use 3-5 from brand palette as available

### Anti-Patterns (NEVER)
- All angular or all curved
- Blocked energy (cluttered corners)
- Imbalanced compositions
- Single element dominance
- Sharp, aggressive shapes

### Example
> Soft background in lightest brand color. Headline balances curved and angular forms. Circular image element balanced by rectangular text block. Brand colors mapped to complementary Element roles. Energy flows naturally through the composition.

### Visual Components
- **Cards**: Full support - mix curved and angular shapes, balanced fills
- **Icons**: Allowed - balanced placement, brand colors
- **Gradients**: Allowed - harmonious transitions, balanced Yin-Yang

### Enforcement Block
```
STYLE: Feng Shui (East Asian)
- HARD LIMIT: Max 10 words/slide.
- HARD LIMIT: Min 50% whitespace.
- HARD LIMIT: Max 4 elements.
- Layout: Balance Yin (curved/soft) and Yang (angular/strong).
- Typography: Medium (400-500), 46-56pt headlines.
- Color: Brand palette mapped to Five Element roles by hue proximity.
- Energy: Natural eye flow. No blocked corners.
- Components: Balanced cards (curved + angular), icons, harmonious gradients.
- NEVER: All angular or curved, imbalanced, cluttered, one-sided designs.
```

---

# Contemporary Professional Family

Five styles covering the modern business landscape—from tech keynotes to investor pitches. Clean, systematic, grounded in data-forward and narrative-driven design.

---

## Tech-Modern

Clean, systematic, data-aware design inspired by Apple, Stripe, and Linear keynote aesthetics. Cards with subtle fills, icons allowed, subtle gradients. Sharp and precise.

**Best for**: SaaS decks, product launches, tech keynotes, developer conferences

### Constraints

| Parameter | Value | Enforcement |
|-----------|-------|-------------|
| Whitespace | 45-55% | HARD LIMIT |
| Max words/slide | 12 | HARD LIMIT |
| Max elements | 5 | HARD LIMIT |
| Colors | 3-4 from brand | Systematic, functional use |

### Layout Rules
- Modular grid (12-column or 8pt)
- Clean alignment, snapped elements
- Cards as primary content containers
- Consistent spacing between sections

### Typography
- Weight: Medium to SemiBold (400-600)
- Headlines: 48-60pt
- Style: Clean sans-serif (brand's heading font)
- Monospace accent for code/data elements

### Color
- Brand palette at full saturation for primaries
- Light gray backgrounds for cards (brand tint at 5-8%)
- High contrast text
- Accent for interactive/highlight elements only

### Anti-Patterns (NEVER)
- Decorative flourishes or ornamental elements
- Serif fonts for headlines
- More than one gradient per slide
- Drop shadows heavier than 2px blur
- Centered body text

### Example
> Clean white slide with subtle grid structure. Sharp sans-serif headline top-left. Two feature cards below with light brand-tinted fills, each with a small icon and 2-line description. Single accent color highlights the key metric. Everything snaps to grid—systematic, precise, modern.

### Visual Components
- **Cards**: Full support - subtle brand-tinted fills (5-8%), sharp corners (4-8px), thin borders optional
- **Icons**: Allowed - outline style, brand colors, functional placement
- **Gradients**: Allowed - subtle only (brand primary to near-white), max 1 per slide

### Enforcement Block
```
STYLE: Tech-Modern (Contemporary Professional)
- HARD LIMIT: Max 12 words/slide.
- HARD LIMIT: Min 45% whitespace.
- HARD LIMIT: Max 5 elements.
- Layout: Modular grid. Snapped alignment. Cards as containers.
- Typography: Medium/SemiBold (400-600), clean sans, 48-60pt headlines.
- Color: 3-4 brand colors. Systematic functional use. Accent for highlights only.
- Components: Subtle cards (light fills, sharp corners), outline icons, subtle gradients (max 1).
- NEVER: Decorative elements, serif headlines, heavy shadows, centered body text.
```

---

## Data-Forward

Numbers as visual anchors, inspired by data journalism (NYT, Bloomberg). Large number heroes (72-96pt), supporting context small. Cards for stat grouping, no gradients (compete with data).

**Best for**: Quarterly reviews, investor updates, analytics dashboards, annual reports

### Constraints

| Parameter | Value | Enforcement |
|-----------|-------|-------------|
| Whitespace | 40-50% | HARD LIMIT |
| Max words/slide | 15 | HARD LIMIT |
| Max elements | 6 | HARD LIMIT |
| Colors | 3-4 | Data-functional (encode meaning) |

### Layout Rules
- Data occupies center 60% width
- Headline top 20% for context
- Insight callout bottom-left for interpretation
- Charts simplified—direct labeling, no legends when possible

### Typography
- Weight: Bold for numbers (700-800), Regular for context (400)
- Headlines: 44-54pt
- Numbers/stats: 72-96pt (hero treatment)
- Labels: 16-20pt, subtle

### Color
- Encode data meaning (green=up, red=down, blue=neutral)
- Background: white or very light gray
- Minimal accent—data IS the visual interest
- Chart colors from brand palette

### Anti-Patterns (NEVER)
- Gradients (compete with data readability)
- Decorative elements on data slides
- More than one chart per slide
- 3D chart effects
- Legends when direct labeling works

### Example
> White slide, clean structure. Large "47%" in bold brand primary dominates center. Below: small context line "increase in user retention." Simple bar chart right-side showing trend. Bottom-left: insight callout "Best quarter since launch." Data speaks—everything else whispers.

### Visual Components
- **Cards**: Full support - stat cards (large number + label), grouped metrics, thin borders
- **Icons**: Allowed - sparingly, for trend indicators (arrow-up, trending-up) only
- **Gradients**: Not allowed (distracts from data)

### Enforcement Block
```
STYLE: Data-Forward (Contemporary Professional)
- HARD LIMIT: Max 15 words/slide.
- HARD LIMIT: Min 40% whitespace.
- HARD LIMIT: Max 6 elements.
- Layout: Data center (60% width). Headline top. Insight bottom-left.
- Typography: Bold numbers (700-800, 72-96pt hero), regular context (400, 44-54pt).
- Color: Data-functional. Encode meaning. Minimal decoration.
- Components: Stat cards (large numbers), trend icons only, NO gradients.
- NEVER: Gradients, decorative elements, 3D charts, multiple charts per slide, legends.
```

---

## Corporate-Confident

Authoritative, polished, trustworthy. Inspired by McKinsey/Deloitte presentation standards. Centered headlines, structured grids, premium spacing. Muted professional palette.

**Best for**: Board presentations, annual reports, company communications, stakeholder updates

### Constraints

| Parameter | Value | Enforcement |
|-----------|-------|-------------|
| Whitespace | 50-60% | HARD LIMIT |
| Max words/slide | 10 | HARD LIMIT |
| Max elements | 4 | HARD LIMIT |
| Colors | 3 from brand | Muted, authoritative |

### Layout Rules
- Centered primary elements
- Structured grid with generous margins (10%+)
- Clear hierarchy: headline → supporting point → evidence
- Consistent positioning across all slides

### Typography
- Weight: Medium to Bold (500-700)
- Headlines: 48-60pt
- Style: Premium sans-serif or refined serif (brand font)
- Consistent capitalization (title case or sentence case)

### Color
- Muted brand palette (reduce saturation 10-15%)
- Navy, charcoal, or deep brand primary for text
- Background: white or very light neutral
- Accent: one brand color at controlled intensity

### Anti-Patterns (NEVER)
- Playful or casual design elements
- Bright or neon colors
- Asymmetric layouts
- More than 2 font sizes per slide
- Informal icons or illustrations

### Example
> Clean white slide with generous margins. Centered headline in medium-weight brand navy: "Operational Excellence." Below: three aligned text blocks showing key metrics with subtle brand accent dividers. Bottom-right: discreet logo. Authority radiates from restraint and precision.

### Visual Components
- **Cards**: Full support - clean borders (1-2px), white or very light fills, consistent radius (8px)
- **Icons**: Not allowed (too casual for corporate authority)
- **Gradients**: Not allowed (too flashy)

### Enforcement Block
```
STYLE: Corporate-Confident (Contemporary Professional)
- HARD LIMIT: Max 10 words/slide.
- HARD LIMIT: Min 50% whitespace.
- HARD LIMIT: Max 4 elements.
- Layout: Centered. Structured grid. Generous margins (10%+).
- Typography: Medium/Bold (500-700), premium fonts, 48-60pt headlines.
- Color: 3 muted brand colors. Authoritative. Controlled accent.
- Components: Clean cards (thin borders, light fills), no icons, no gradients.
- NEVER: Playful elements, bright colors, asymmetry, informal icons.
```

---

## Pitch-Velocity

High-energy, momentum-driven design. Inspired by Sequoia deck format energy. Asymmetric with forward momentum. Bold cards, icons, gradients all allowed. High contrast.

**Best for**: Fundraising decks, sales pitches, launch announcements, competitive positioning

### Constraints

| Parameter | Value | Enforcement |
|-----------|-------|-------------|
| Whitespace | 35-45% | HARD LIMIT |
| Max words/slide | 12 | HARD LIMIT |
| Max elements | 5 | HARD LIMIT |
| Colors | 4-5 | High contrast, energetic |

### Layout Rules
- Asymmetric with forward momentum (left-to-right energy)
- Bold focal points with supporting evidence
- Headlines large and commanding
- Content builds toward a conclusion

### Typography
- Weight: Bold to Black (700-900)
- Headlines: 52-68pt
- Style: Bold sans-serif, commanding
- Numbers large and prominent (64-80pt for key stats)

### Color
- Full saturation brand palette
- High contrast (dark backgrounds with bright text acceptable)
- Gradient accent for energy (diagonal preferred)
- Bold card fills

### Anti-Patterns (NEVER)
- Passive or quiet layouts
- Light font weights
- Centered, symmetrical compositions
- Muted or desaturated colors
- Small, understated typography

### Example
> Dark brand-primary background with diagonal gradient accent. Bold white headline high-left: "10x Faster." Large number "147%" in brand accent below. Supporting stat cards right-side with bold fills. Energy flows left to right—momentum, confidence, urgency.

### Visual Components
- **Cards**: Full support - bold brand fills, medium radius (8-12px), can overlap slightly
- **Icons**: Allowed - bold, brand accent colors, larger sizes (48-64px)
- **Gradients**: Allowed - bold diagonal transitions, high energy

### Enforcement Block
```
STYLE: Pitch-Velocity (Contemporary Professional)
- HARD LIMIT: Max 12 words/slide.
- HARD LIMIT: Min 35% whitespace.
- HARD LIMIT: Max 5 elements.
- Layout: Asymmetric. Forward momentum (left → right energy).
- Typography: Bold/Black (700-900), commanding sans, 52-68pt headlines.
- Color: 4-5 colors. Full saturation. High contrast. Dark backgrounds OK.
- Components: Bold cards (brand fills), bold icons (48-64px), energetic gradients.
- NEVER: Passive layouts, light fonts, symmetry, muted colors, small type.
```

---

## Narrative-Clean

Story-driven, editorial clarity inspired by TED talks and long-form editorial. Left-aligned text blocks, generous right margins for imagery. Serif option. Warm neutrals + one accent.

**Best for**: Case studies, thought leadership, keynote stories, brand narratives

### Constraints

| Parameter | Value | Enforcement |
|-----------|-------|-------------|
| Whitespace | 50-60% | HARD LIMIT |
| Max words/slide | 12 | HARD LIMIT |
| Max elements | 4 | HARD LIMIT |
| Colors | 3-4 | Warm neutrals + one accent |

### Layout Rules
- Left-aligned text with generous right margin (30-40% for imagery)
- Story flow: each slide advances the narrative
- Single focal point per slide
- Editorial pacing—some slides are pause moments (minimal content)

### Typography
- Weight: Regular to Medium (400-500)
- Headlines: 44-56pt
- Style: Refined serif OR clean sans (brand's heading font)—serif option for editorial warmth
- Body text allowed in small amounts (24-28pt) for narrative flow

### Color
- Warm neutral base (off-white, cream, light warm gray)
- One strong accent color from brand palette
- Dark warm text (charcoal, not pure black)
- Accent used sparingly for emphasis

### Anti-Patterns (NEVER)
- Bullet point lists
- Multiple accent colors
- Dense data without narrative context
- Aggressive or high-energy layouts
- Pure white or pure black backgrounds

### Example
> Warm off-white slide. Left-aligned serif headline: "The moment everything changed." Below: two lines of body text (24pt) advancing the story. Right 35%: evocative image with soft edges. Single brand accent underline beneath headline. Editorial. Intentional. Every word matters.

### Visual Components
- **Cards**: Limited - thin border only (1px), warm neutral fill, editorial feel
- **Icons**: Not allowed (break narrative flow)
- **Gradients**: Not allowed (too flashy for editorial)

### Enforcement Block
```
STYLE: Narrative-Clean (Contemporary Professional)
- HARD LIMIT: Max 12 words/slide.
- HARD LIMIT: Min 50% whitespace.
- HARD LIMIT: Max 4 elements.
- Layout: Left-aligned. Generous right margin (30-40%). Editorial pacing.
- Typography: Regular/Medium (400-500), serif or clean sans, 44-56pt headlines.
- Color: Warm neutrals + one brand accent. Dark warm text (not pure black).
- Components: Subtle cards (thin border, warm fill), no icons, no gradients.
- NEVER: Bullet points, multiple accents, dense data, aggressive layouts, pure B&W.
```

---

## Style Selection Workflow

### Step 1: Choose Aesthetic Family

"Which design aesthetic resonates with your brand/content?"

| Family | Choose if you want... |
|--------|----------------------|
| **Japanese Zen** | Restraint, intentionality, essence |
| **Scandinavian Nordic** | Warmth, balance, functionality |
| **European Modernist** | Precision or playfulness |
| **East Asian Harmony** | Space, balance, energy |
| **Contemporary Professional** | Clean, data-aware, business-forward |

### Step 2: Choose Specific Style

Based on family selection, present relevant options with "Best for" guidance.

#### Contemporary Professional

| Style | Best for |
|-------|----------|
| Tech-Modern | SaaS decks, product launches, tech keynotes, developer conferences |
| Data-Forward | Quarterly reviews, investor updates, analytics dashboards, annual reports |
| Corporate-Confident | Board presentations, annual reports, company communications, stakeholder updates |
| Pitch-Velocity | Fundraising decks, sales pitches, launch announcements, competitive positioning |
| Narrative-Clean | Case studies, thought leadership, keynote stories, brand narratives |

---

*Each style produces meaningfully different visual results while maintaining professional quality.*
