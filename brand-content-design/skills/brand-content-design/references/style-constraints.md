# Style Constraints

13 distinct visual styles across 4 aesthetic families. Each produces fundamentally different visual results.

---

## Style Families Overview

| Family | Origin | Character | Styles |
|--------|--------|-----------|--------|
| **Japanese Zen** | Japan | Restraint, essence, intentionality | Minimal, Dramatic, Organic, Wabi-Sabi, Shibui, Iki, Ma |
| **Scandinavian Nordic** | Denmark/Sweden | Warmth, balance, functionality | Hygge, Lagom |
| **European Modernist** | Germany/Switzerland/Italy | Grid, clarity, expression | Swiss, Memphis |
| **East Asian Harmony** | Korea/China | Space, balance, energy | Yeo-baek, Feng Shui |

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

### Enforcement Block
```
STYLE: Minimal (Japanese Zen)
- HARD LIMIT: Max 8 words/slide. Truncate if exceeded.
- HARD LIMIT: Min 60% whitespace.
- HARD LIMIT: Max 3 elements, 3 colors.
- Layout: Center primary elements. Strict 8pt grid.
- Typography: Light weights (300-400), headlines 48-56pt.
- NEVER: Multiple focal points, decorative elements, bullet points.
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

### Enforcement Block
```
STYLE: Dramatic (Japanese Zen)
- HARD LIMIT: Max 12 words/slide.
- HARD LIMIT: Min 35% whitespace.
- HARD LIMIT: Max 5 elements.
- Layout: Asymmetrical. Focal elements OFF-CENTER.
- Typography: Bold/black (700-900), headlines 56-72pt.
- Color: 4-5 colors, high contrast.
- NEVER: Center all elements, uniform spacing, muted colors.
```

---

## Organic

Based on **Shizen** (naturalness) and **Yugen** (hidden depth). Warmth and humanity over precision.

**Learn more**: [Yugen](https://en.wikipedia.org/wiki/Y%C5%ABgen) | [Shizen](https://en.wikipedia.org/wiki/Japanese_aesthetics#Shizen)

**Best for**: Storytelling, education, wellbeing content

### Constraints

| Parameter | Value | Enforcement |
|-----------|-------|-------------|
| Whitespace | 50-60% | HARD LIMIT |
| Max words/slide | 10 | HARD LIMIT |
| Max elements | 4 | HARD LIMIT |
| Colors | 5-6 warm tones | Warm spectrum only |

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
- Warm filters on images
- Soft, organic borders

### Anti-Patterns (NEVER)
- Stark black/white contrast
- Rigid grid alignment
- Cold colors
- Sharp geometric shapes
- Pure white backgrounds

### Example
> Warm cream slide with subtle paper texture. Headline in warm charcoal, naturally off-center. Documentary image integrates with text. Everything feels connected, human.

### Enforcement Block
```
STYLE: Organic (Japanese Zen)
- HARD LIMIT: Max 10 words/slide.
- HARD LIMIT: Min 50% whitespace.
- HARD LIMIT: Max 4 elements.
- Layout: Natural groupings, organic flow.
- Typography: Medium weights (400-600), headlines 48-60pt.
- Color: Warm palette only. No stark black or white.
- Texture: Subtle background texture (3-5% opacity).
- NEVER: Stark contrast, rigid grids, cold colors.
```

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
| Colors | 4-5 earth tones | Muted, natural only |

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
- Synthetic colors
- Machine-precision alignment
- Glossy finishes

### Example
> Textured paper background with visible grain. Headline slightly off-axis in humanist typeface. Muted earth colors. Image with natural grain, edges soft and imperfect. Beauty in the imperfect.

### Enforcement Block
```
STYLE: Wabi-Sabi (Japanese Zen)
- HARD LIMIT: Max 10 words/slide.
- HARD LIMIT: Min 45% whitespace.
- HARD LIMIT: Max 4 elements.
- Layout: Intentionally imperfect. Visible texture.
- Typography: Medium (400-500), humanist fonts, 44-54pt headlines.
- Color: Earth tones only. Muted, natural.
- Texture: Paper/cloth texture 5-10% opacity.
- NEVER: Perfect geometry, synthetic colors, glossy finishes.
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

### Enforcement Block
```
STYLE: Shibui (Japanese Zen)
- HARD LIMIT: Max 6 words/slide. Extreme brevity.
- HARD LIMIT: Min 55% whitespace.
- HARD LIMIT: Max 3 elements, 2-3 colors.
- Layout: Refined, sophisticated placement.
- Typography: Light (300-400), elegant fonts, 44-52pt headlines.
- Color: Ultra-muted only. No bright or saturated.
- NEVER: Bold type, bright colors, busy compositions.
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

### Enforcement Block
```
STYLE: Iki (Japanese Zen)
- HARD LIMIT: Max 8 words/slide.
- HARD LIMIT: Min 50% whitespace.
- HARD LIMIT: Max 4 elements.
- Layout: Editorial grid. Confident asymmetry.
- Typography: Medium (400-600), stylish sans, 48-60pt headlines.
- Color: B&W base + ONE pop color only.
- NEVER: Multiple accents, muted colors, safe layouts.
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

### Enforcement Block
```
STYLE: Ma (Japanese Zen)
- HARD LIMIT: Max 5 words/slide. Extreme minimalism.
- HARD LIMIT: Min 70% whitespace. Emptiness is design.
- HARD LIMIT: Max 2 elements, 2 colors.
- Layout: Floating elements. 15%+ margins.
- Typography: Extra light (200-300), 40-50pt headlines.
- Color: Near-monochromatic. No strong accents.
- NEVER: Fill space, multiple elements, dense typography.
```

---

# Scandinavian Nordic Family

Two styles based on Nordic design philosophy emphasizing warmth, balance, and intentional living.

**Learn more**: [Scandinavian Design](https://en.wikipedia.org/wiki/Scandinavian_design)

---

## Hygge

Danish concept of cozy togetherness and contentment. Warm, inviting, comfortable.

**Learn more**: [Hygge (Wikipedia)](https://en.wikipedia.org/wiki/Hygge)

**Best for**: Wellness brands, community content, lifestyle, hospitality

### Constraints

| Parameter | Value | Enforcement |
|-----------|-------|-------------|
| Whitespace | 40-50% | HARD LIMIT |
| Max words/slide | 12 | HARD LIMIT |
| Max elements | 5 | HARD LIMIT |
| Colors | 5-6 warm | Cozy palette |

### Layout Rules
- Comfortable, inviting arrangement
- Soft groupings
- Intimate feel, not distant
- Approachable hierarchy

### Typography
- Weight: Medium (400-500)
- Headlines: 44-56pt
- Style: Friendly, rounded sans or warm serif
- Comfortable reading

### Color
- Warm candlelight palette
- Soft oranges, warm browns, cream
- Muted reds, gentle yellows
- Nothing cold or harsh

### Texture
- Soft textures (wool, knit, wood grain)
- Warm gradients allowed
- Inviting surfaces
- Tactile feel

### Anti-Patterns (NEVER)
- Cold colors (blue, gray, white)
- Sharp edges
- Clinical layouts
- Distant, corporate feel
- High contrast

### Example
> Soft cream background with subtle warmth. Friendly headline in warm brown. Image of cozy scene with soft focus. Warm orange accent. Everything invites you in like a warm blanket.

### Enforcement Block
```
STYLE: Hygge (Scandinavian)
- HARD LIMIT: Max 12 words/slide.
- HARD LIMIT: Min 40% whitespace.
- HARD LIMIT: Max 5 elements.
- Layout: Comfortable, intimate arrangement.
- Typography: Medium (400-500), friendly fonts, 44-56pt headlines.
- Color: Warm candlelight palette. No cold colors.
- Texture: Soft, tactile (wool, wood grain).
- NEVER: Cold colors, sharp edges, clinical feel.
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

### Enforcement Block
```
STYLE: Lagom (Scandinavian)
- HARD LIMIT: Max 10 words/slide.
- HARD LIMIT: Min 50% whitespace.
- HARD LIMIT: Max 4 elements.
- Layout: Balanced, functional. Neither minimal nor full.
- Typography: Regular weight (400), clean sans, 44-54pt headlines.
- Color: Balanced neutrals. One gentle accent. No extremes.
- NEVER: Extremes, dramatic layouts, bold colors.
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
- Style: Helvetica, Univers, or similar grotesque
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
- NEVER: Centered text, decoration, organic shapes.
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
- NEVER: Minimalism, neutral colors, corporate restraint.
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

### Enforcement Block
```
STYLE: Yeo-baek (East Asian)
- HARD LIMIT: Max 6 words/slide.
- HARD LIMIT: Min 65% whitespace. Emptiness primary.
- HARD LIMIT: Max 2 elements, 2-3 colors.
- Layout: Void is design. Extreme margins.
- Typography: Light (300-400), refined, 42-52pt headlines.
- Color: Near-white, soft grays. Imperfect purity.
- NEVER: Fill void, multiple elements, strong colors.
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
| Colors | 5 (Five Elements) | Earth, Fire, Water, Wood, Metal |

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

### Color (Five Elements)
- Earth: Yellow, brown, beige
- Fire: Red, orange, pink
- Water: Blue, black
- Wood: Green, teal
- Metal: White, gray, metallic

### Anti-Patterns (NEVER)
- All angular or all curved
- Blocked energy (cluttered corners)
- Imbalanced compositions
- Single element dominance
- Sharp, aggressive shapes

### Example
> Soft earth-tone background. Headline balances curved and angular forms. Circular image element balanced by rectangular text block. Colors from complementary elements. Energy flows naturally through the composition.

### Enforcement Block
```
STYLE: Feng Shui (East Asian)
- HARD LIMIT: Max 10 words/slide.
- HARD LIMIT: Min 50% whitespace.
- HARD LIMIT: Max 4 elements.
- Layout: Balance Yin (curved/soft) and Yang (angular/strong).
- Typography: Medium (400-500), 46-56pt headlines.
- Color: Five Elements palette (earth, fire, water, wood, metal).
- Energy: Natural eye flow. No blocked corners.
- NEVER: All angular or curved, imbalanced, cluttered.
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

### Step 2: Choose Specific Style

Based on family selection, present relevant options with "Best for" guidance.

---

*Each style produces meaningfully different visual results while maintaining professional quality.*
