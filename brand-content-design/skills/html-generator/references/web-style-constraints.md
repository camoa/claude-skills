# Web Style Constraints

21 distinct visual styles across 5 aesthetic families, adapted for web (per-section constraints instead of per-slide). Each style produces fundamentally different HTML/CSS output.

---

## Style Families Overview

| Family | Origin | Character | Styles |
|--------|--------|-----------|--------|
| **Japanese Zen** | Japan | Restraint, essence, intentionality | Minimal, Dramatic, Organic, Wabi-Sabi, Shibui, Iki, Ma |
| **Scandinavian Nordic** | Denmark/Sweden | Warmth, balance, functionality | Hygge, Lagom |
| **European Modernist** | Germany/Switzerland/Italy | Grid, clarity, expression | Swiss, Memphis |
| **East Asian Harmony** | Korea/China | Space, balance, energy | Yeo-baek, Feng Shui |
| **Digital Native** | Web-born | Technology-driven aesthetics | Neobrutalist, Glassmorphism, Dark Mode, Bento Grid, Retro/Y2K, Kinetic, Neumorphism, 3D/Immersive |

---

## Quick Reference Card

| Style | Family | Padding | Max Words/Section | Max Blocks | Layout | Type Weight | JS Needed |
|-------|--------|---------|-------------------|------------|--------|-------------|-----------|
| Minimal | Japanese | 80-120px | 40 | 3 | Centered | Light 300-400 | No |
| Dramatic | Japanese | 60-100px | 60 | 5 | Asymmetric | Bold 700-900 | No |
| Organic | Japanese | 60-80px | 50 | 4 | Flowing | Medium 400-600 | No |
| Wabi-Sabi | Japanese | 60-80px | 50 | 4 | Imperfect | Medium 400-500 | No |
| Shibui | Japanese | 80-100px | 30 | 3 | Refined | Light 300-400 | No |
| Iki | Japanese | 60-80px | 40 | 4 | Editorial | Medium 400-600 | No |
| Ma | Japanese | 100-160px | 25 | 2 | Floating | Light 200-300 | No |
| Hygge | Scandinavian | 60-80px | 60 | 5 | Cozy grid | Medium 400-500 | No |
| Lagom | Scandinavian | 60-80px | 50 | 4 | Balanced grid | Regular 400 | No |
| Swiss | European | 60-80px | 50 | 5 | 12-col grid | Medium 400-500 | No |
| Memphis | European | 40-60px | 80 | 7 | Playful | Bold 600-800 | Optional |
| Yeo-baek | East Asian | 120-180px | 30 | 2 | Empty | Light 300-400 | No |
| Feng Shui | East Asian | 60-80px | 50 | 4 | Balanced flex | Medium 400-500 | No |
| Neobrutalist | Digital | 40-60px | 70 | 6 | Stacked/grid | Bold 700-900 | No |
| Glassmorphism | Digital | 60-80px | 50 | 5 | Layered | Light-Medium 300-500 | Optional |
| Dark Mode | Digital | 60-80px | 60 | 5 | Layered cards | Regular 400-500 | No |
| Bento Grid | Digital | 40-60px | 60 | 8 | CSS Grid | Medium 400-600 | No |
| Retro/Y2K | Digital | 40-60px | 70 | 6 | Mixed | Bold 600-800 | Optional |
| Kinetic | Digital | 80-100px | 50 | 4 | Scroll-driven | Medium 400-600 | Yes |
| Neumorphism | Digital | 60-80px | 50 | 5 | Soft cards | Regular 400-500 | No |
| 3D/Immersive | Digital | 60-100px | 50 | 5 | Perspective | Medium 400-600 | Yes |

---

# Japanese Zen Family

Seven styles based on traditional Japanese aesthetic principles.

---

## Minimal

Based on **Kanso** (simplicity) and **Seijaku** (tranquil stillness).

**Best for**: Executive pages, SaaS, professional services

### Web Constraints

| Parameter | Value | Enforcement |
|-----------|-------|-------------|
| Section padding | 80-120px vertical | HARD LIMIT |
| Max words/section heading | 6 | HARD LIMIT |
| Max words/section body | 40 | HARD LIMIT |
| Max content blocks/section | 3 | HARD LIMIT |
| Colors | 3 maximum | HARD LIMIT |

### CSS Patterns
- Layout: `text-align: center` or single strong left alignment
- Container: narrow `max-width: 800px` for content
- Spacing: `gap: var(--space-lg)` minimum between elements
- Sections: single background color, no patterns

### Typography
- Weight: 300-400 (Light)
- Headings: `clamp(2rem, 4vw, 3.5rem)`
- Scale: 1.2x progression
- Letter-spacing: `0.02em` on headings

### Anti-Patterns (NEVER)
- Multiple focal points per section
- Decorative CSS elements (shapes, patterns)
- More than one CTA per section
- Drop shadows or gradients on sections

### Enforcement Block
```
STYLE: Minimal (Japanese Zen) — Web
- HARD LIMIT: Max 40 words per section body.
- HARD LIMIT: Max 6 words per heading.
- HARD LIMIT: Max 3 content blocks per section, 3 colors.
- HARD LIMIT: Section padding 80-120px.
- Layout: Centered or single left alignment. Narrow container (800px).
- Typography: Light weights (300-400), large headings with tight scale.
- Backgrounds: Single flat colors only. No patterns, no gradients.
- NEVER: Multiple focal points, decorative elements, heavy shadows.
- JS: Not needed.
```

---

## Dramatic

Based on **Datsuzoku** (freedom from convention) and **Fukinsei** (asymmetry).

**Best for**: Agency sites, pitch pages, creative portfolios, product launches

### Web Constraints

| Parameter | Value | Enforcement |
|-----------|-------|-------------|
| Section padding | 60-100px vertical | HARD LIMIT |
| Max words/section heading | 8 | HARD LIMIT |
| Max words/section body | 60 | HARD LIMIT |
| Max content blocks/section | 5 | HARD LIMIT |
| Colors | 4-5 | Full range for contrast |

### CSS Patterns
- Layout: Asymmetric via `margin-left: 10%` or `grid-column: 2 / span 3`
- Full-bleed sections with edge-bleeding elements
- Overlapping elements via negative margins or `position: relative; z-index`
- Large images extending beyond container width

### Typography
- Weight: 700-900 (Bold to Black)
- Headings: `clamp(3rem, 6vw, 5rem)` — largest of all styles
- Scale: 1.5x dramatic jumps
- Letter-spacing: `-0.02em` on large headings (tight)

### Anti-Patterns (NEVER)
- Perfect centering of all elements
- Uniform section spacing
- Muted colors only
- Small headings
- Symmetrical layouts

### Enforcement Block
```
STYLE: Dramatic (Japanese Zen) — Web
- HARD LIMIT: Max 60 words per section body.
- HARD LIMIT: Max 8 words per heading.
- HARD LIMIT: Max 5 content blocks per section.
- HARD LIMIT: Section padding 60-100px.
- Layout: Asymmetric. Elements OFF-CENTER. Full-bleed moments.
- Typography: Bold/black (700-900), headings dramatically larger.
- Color: 4-5 colors, high contrast pairings.
- CSS: Negative margins, overlapping elements, edge bleeds.
- NEVER: Centered everything, uniform spacing, muted palette, symmetry.
- JS: Not needed (CSS transitions sufficient).
```

---

## Organic

Based on **Shizen** (naturalness) and **Yugen** (hidden depth).

**Best for**: Wellness, education, storytelling, community sites

### Web Constraints

| Parameter | Value | Enforcement |
|-----------|-------|-------------|
| Section padding | 60-80px vertical | HARD LIMIT |
| Max words/section body | 50 | HARD LIMIT |
| Max content blocks/section | 4 | HARD LIMIT |
| Colors | 5-6 warm tones | Warm spectrum only |

### CSS Patterns
- Rounded elements: `border-radius: 16px` to `24px`
- Soft shadows: `box-shadow: 0 4px 20px rgba(0,0,0,0.08)`
- Flowing layouts: asymmetric flex/grid, not rigid
- Warm gradient backgrounds: subtle warm-tone gradients

### Typography
- Weight: 400-600 (Medium)
- Headings: `clamp(1.75rem, 3.5vw, 3rem)`
- Body: generous line-height (1.7-1.8)
- Serif or rounded sans-serif preferred

### Enforcement Block
```
STYLE: Organic (Japanese Zen) — Web
- HARD LIMIT: Max 50 words per section body.
- HARD LIMIT: Max 4 content blocks per section.
- HARD LIMIT: Warm colors only (no cold blues, pure grays).
- Layout: Flowing, rounded, soft. No sharp angles.
- Typography: Medium weights, serif or rounded sans-serif.
- CSS: border-radius 16-24px, soft shadows, warm gradients.
- NEVER: Sharp corners, cold palette, rigid grid, industrial feel.
- JS: Not needed.
```

---

## Wabi-Sabi

Beauty in imperfection, transience, and incompleteness.

**Best for**: Artisan brands, craft, heritage, sustainable products

### Web Constraints

| Parameter | Value | Enforcement |
|-----------|-------|-------------|
| Section padding | 60-80px vertical | HARD LIMIT |
| Max words/section body | 50 | HARD LIMIT |
| Max content blocks/section | 4 | HARD LIMIT |
| Colors | 4-5 muted/earthy | Natural palette only |

### CSS Patterns
- Textured backgrounds: subtle noise overlays, grain effects
- Imperfect borders: `border-radius` with varied values (e.g., `30% 70% 70% 30%`)
- Muted shadows: `box-shadow: 0 2px 12px rgba(0,0,0,0.06)`
- Handmade feel: irregular spacing, slightly off-grid

### Typography
- Weight: 400-500
- Serif or humanist sans-serif
- Slightly irregular letter-spacing
- Generous margins around text blocks

### Enforcement Block
```
STYLE: Wabi-Sabi (Japanese Zen) — Web
- HARD LIMIT: Max 50 words per section body.
- HARD LIMIT: Max 4 content blocks per section.
- HARD LIMIT: Natural/earthy palette only.
- Layout: Slightly imperfect, humanistic. Avoid mathematical precision.
- Typography: Serif or humanist sans. Medium weight.
- CSS: Texture overlays, irregular border-radius, muted shadows.
- NEVER: Perfect geometry, sharp corners, bright/neon colors, high-gloss feel.
- JS: Not needed.
```

---

## Shibui

Quiet elegance and ultra-refinement. Less is sophistication.

**Best for**: Luxury brands, high-end services, premium portfolios

### Web Constraints

| Parameter | Value | Enforcement |
|-----------|-------|-------------|
| Section padding | 80-100px vertical | HARD LIMIT |
| Max words/section body | 30 | HARD LIMIT |
| Max content blocks/section | 3 | HARD LIMIT |
| Colors | 3-4 refined tones | Understated palette |

### CSS Patterns
- Hairline borders: `border: 1px solid rgba(0,0,0,0.1)`
- Refined spacing: mathematical precision with golden ratio
- Minimal decoration: almost no visual ornamentation
- Subtle hover states: opacity or slight translate

### Typography
- Weight: 300-400 (Light)
- Elegant serif or thin grotesque
- Large letter-spacing on headings: `0.05em`
- Small body text with generous leading

### Enforcement Block
```
STYLE: Shibui (Japanese Zen) — Web
- HARD LIMIT: Max 30 words per section body.
- HARD LIMIT: Max 3 content blocks per section.
- HARD LIMIT: 3-4 refined colors only.
- Layout: Refined precision. Golden-ratio spacing.
- Typography: Light weights, elegant serif or thin sans. Wide letter-spacing.
- CSS: Hairline borders, subtle hovers, minimal decoration.
- NEVER: Bold colors, heavy shadows, decorative elements, loud typography.
- JS: Not needed.
```

---

## Iki

Stylish sophistication with edge. B&W + one pop color.

**Best for**: Fashion, editorial, magazines, creative agencies

### Web Constraints

| Parameter | Value | Enforcement |
|-----------|-------|-------------|
| Section padding | 60-80px vertical | HARD LIMIT |
| Max words/section body | 40 | HARD LIMIT |
| Max content blocks/section | 4 | HARD LIMIT |
| Colors | B&W + 1 accent | Strict color rule |

### CSS Patterns
- High contrast: `color: #000; background: #fff` (or inverse)
- Single accent color for CTAs, links, highlights only
- Editorial layout: mix of full-width and column layouts
- Magazine-style typography: mix of sizes and weights

### Typography
- Weight: 400-600 (Medium, with bold for contrast)
- Mix serif headings + sans body (editorial pairing)
- Large display type for hero sections
- All-caps with wide letter-spacing for labels

### Enforcement Block
```
STYLE: Iki (Japanese Zen) — Web
- HARD LIMIT: Max 40 words per section body.
- HARD LIMIT: B&W + exactly 1 accent color.
- HARD LIMIT: Max 4 content blocks per section.
- Layout: Editorial. Mix full-width and columns. Magazine feel.
- Typography: Contrasting pairs (serif + sans). Display type for heroes.
- Color: Black, white, and ONE accent (used sparingly for emphasis).
- CSS: High contrast, editorial spacing, bold type mixing.
- NEVER: Multiple colors, gradients, soft/pastel tones, uniform type weight.
- JS: Not needed.
```

---

## Ma

70%+ emptiness. The void IS the design.

**Best for**: Meditation apps, luxury minimalism, art galleries, premium experiences

### Web Constraints

| Parameter | Value | Enforcement |
|-----------|-------|-------------|
| Section padding | 100-160px vertical | HARD LIMIT |
| Max words/section body | 25 | HARD LIMIT |
| Max content blocks/section | 2 | HARD LIMIT |
| Colors | 2-3 | Near-monochrome |

### CSS Patterns
- Extreme padding: `min-height: 100vh` on key sections
- Near-empty sections with single centered element
- Ultra-thin typography, nearly transparent borders
- Fade transitions on scroll

### Typography
- Weight: 200-300 (Thin to Light)
- Whisper-sized body: `0.875rem` to `1rem`
- Large headings with extreme letter-spacing: `0.1em`
- Single typeface, minimal weight variation

### Enforcement Block
```
STYLE: Ma (Japanese Zen) — Web
- HARD LIMIT: Max 25 words per section body.
- HARD LIMIT: Max 2 elements per section.
- HARD LIMIT: Min 70% empty space per section.
- HARD LIMIT: Section padding 100-160px.
- Layout: Single centered element per section. Near-empty.
- Typography: Ultra-thin (200-300), whisper-sized body, wide letter-spacing.
- Color: 2-3 near-monochrome tones.
- CSS: min-height: 100vh, extreme padding, subtle fade transitions.
- NEVER: Busy sections, multiple elements, heavy type, decoration.
- JS: Not needed (CSS transitions for fades).
```

---

# Scandinavian Nordic Family

Two styles based on Nordic concepts of warmth and balance.

---

## Hygge

Cozy, warm, inviting — like a warm drink by a fire.

**Best for**: Wellness, community, food/beverage, lifestyle brands

### Web Constraints

| Parameter | Value | Enforcement |
|-----------|-------|-------------|
| Section padding | 60-80px vertical | HARD LIMIT |
| Max words/section body | 60 | HARD LIMIT |
| Max content blocks/section | 5 | HARD LIMIT |
| Colors | 5-6 warm | No cold tones |

### CSS Patterns
- Warm backgrounds: soft cream, warm gray, blush
- Rounded cards: `border-radius: 16px` with subtle shadow
- Cozy grid: `gap: var(--space-md)` with comfortable spacing
- Soft gradients: warm-tone linear gradients

### Typography
- Weight: 400-500 (Medium)
- Rounded sans-serif or friendly serif
- Comfortable reading sizes: `1.125rem` body
- Generous line-height: 1.7

### Enforcement Block
```
STYLE: Hygge (Scandinavian Nordic) — Web
- HARD LIMIT: Max 60 words per section body.
- HARD LIMIT: Max 5 content blocks per section.
- HARD LIMIT: Warm palette only (no cold blues, stark blacks).
- Layout: Cozy grid with comfortable spacing. Rounded elements.
- Typography: Rounded/friendly fonts, medium weight, generous line-height.
- CSS: border-radius 16px, warm backgrounds, soft shadows.
- NEVER: Cold colors, sharp corners, industrial feel, stark contrast.
- JS: Not needed.
```

---

## Lagom

"Just the right amount" — balanced, functional, nothing excess.

**Best for**: Corporate, SaaS, professional services, balanced brands

### Web Constraints

| Parameter | Value | Enforcement |
|-----------|-------|-------------|
| Section padding | 60-80px vertical | HARD LIMIT |
| Max words/section body | 50 | HARD LIMIT |
| Max content blocks/section | 4 | HARD LIMIT |
| Colors | 4-5 balanced | Neutral with muted accent |

### CSS Patterns
- Balanced grid: equal columns with consistent gaps
- Moderate border-radius: `8px`
- Functional design: clear information hierarchy
- Subtle hover states: background-color shift

### Typography
- Weight: 400 (Regular)
- Clean sans-serif
- Uniform scale: 1.25x progression
- Standard line-height: 1.6

### Enforcement Block
```
STYLE: Lagom (Scandinavian Nordic) — Web
- HARD LIMIT: Max 50 words per section body.
- HARD LIMIT: Max 4 content blocks per section.
- Layout: Balanced grid. Equal spacing. Nothing excessive.
- Typography: Clean sans-serif, regular weight, uniform scale.
- Color: 4-5 balanced colors. Neutral base + muted accent.
- CSS: Moderate border-radius, subtle hovers, functional design.
- NEVER: Excess decoration, dramatic size contrasts, flashy animations.
- JS: Not needed.
```

---

# European Modernist Family

Two styles: precision vs. playfulness.

---

## Swiss

International Typographic Style. Grid, clarity, mathematical precision.

**Best for**: Tech companies, corporate, finance, data-driven brands

### Web Constraints

| Parameter | Value | Enforcement |
|-----------|-------|-------------|
| Section padding | 60-80px vertical | HARD LIMIT |
| Max words/section body | 50 | HARD LIMIT |
| Max content blocks/section | 5 | HARD LIMIT |
| Colors | 4-5 | Primary + neutral grid |

### CSS Patterns
- 12-column CSS Grid: `display: grid; grid-template-columns: repeat(12, 1fr)`
- Mathematical spacing: 8px base unit
- Strict alignment: all elements snap to grid
- Rules and dividers: thin horizontal lines between sections

### Typography
- Weight: 400-500 (Medium)
- Grotesque sans-serif (Helvetica-adjacent, but distinctive)
- Strict hierarchy: clear size/weight ladder
- Left-aligned with flush margins

### Enforcement Block
```
STYLE: Swiss (European Modernist) — Web
- HARD LIMIT: Max 50 words per section body.
- HARD LIMIT: Max 5 content blocks per section.
- Layout: 12-column CSS Grid. All elements grid-aligned.
- Typography: Grotesque sans-serif. Strict size hierarchy. Left-aligned.
- Spacing: 8px base unit. Mathematical precision.
- CSS: Grid, thin dividers, flush margins, strict alignment.
- NEVER: Rounded corners, soft shadows, organic shapes, casual fonts.
- JS: Not needed.
```

---

## Memphis

Bold, playful, colorful chaos with geometric shapes.

**Best for**: Creative agencies, youth brands, entertainment, startups

### Web Constraints

| Parameter | Value | Enforcement |
|-----------|-------|-------------|
| Section padding | 40-60px vertical | HARD LIMIT |
| Max words/section body | 80 | HARD LIMIT |
| Max content blocks/section | 7 | HARD LIMIT |
| Colors | 6-8 | Bright, clashing encouraged |

### CSS Patterns
- Geometric shapes: CSS `clip-path`, `::before`/`::after` pseudo-elements
- Bold borders: `border: 3px solid` in contrasting colors
- Tilted elements: `transform: rotate(-2deg)` to `rotate(3deg)`
- Pattern backgrounds: CSS-generated dots, zigzags, squiggles

### Typography
- Weight: 600-800 (Bold)
- Mix of display, serif, sans-serif — playful variety
- Tilted text: `transform: rotate()` on headings
- Varied colors per heading

### Enforcement Block
```
STYLE: Memphis (European Modernist) — Web
- HARD LIMIT: Max 80 words per section body.
- HARD LIMIT: Max 7 content blocks per section.
- Layout: Playful. Tilted elements, broken grids, geometric shapes.
- Typography: Bold, varied fonts, colored headings, tilted text.
- Color: 6-8 bright colors. Clashing combinations encouraged.
- CSS: clip-path, transforms, bold borders, pattern backgrounds.
- NEVER: Muted palettes, strict grids, serious tone, minimal design.
- JS: Optional (for playful hover effects).
```

---

# East Asian Harmony Family

Two styles based on Korean and Chinese aesthetic principles.

---

## Yeo-baek

Korean concept of purposeful emptiness and purity.

**Best for**: Premium products, meditation, art, luxury minimalism

### Web Constraints

| Parameter | Value | Enforcement |
|-----------|-------|-------------|
| Section padding | 120-180px vertical | HARD LIMIT |
| Max words/section body | 30 | HARD LIMIT |
| Max content blocks/section | 2 | HARD LIMIT |
| Colors | 2-3 | Near-white palette |

### CSS Patterns
- Extreme whitespace: `min-height: 100vh` on most sections
- Near-white backgrounds: `#fafafa`, `#f5f5f0`, `#fff`
- Ultra-minimal: almost no borders, shadows, or decoration
- Single-element sections: one text block or one image

### Typography
- Weight: 300-400 (Light)
- Elegant serif with extreme letter-spacing
- Body near-invisible: small, light gray on white
- Headings as lone sculptural elements

### Enforcement Block
```
STYLE: Yeo-baek (East Asian Harmony) — Web
- HARD LIMIT: Max 30 words per section body.
- HARD LIMIT: Max 2 elements per section.
- HARD LIMIT: Near-white palette (2-3 colors, all light).
- HARD LIMIT: Section padding 120-180px.
- Layout: Extreme emptiness. Single element per section.
- Typography: Light, elegant, extreme letter-spacing.
- CSS: min-height: 100vh, near-white backgrounds, no decoration.
- NEVER: Busy layouts, dark backgrounds, heavy type, decorative elements.
- JS: Not needed.
```

---

## Feng Shui

Balance, harmony, and energy flow based on Chinese principles.

**Best for**: Wellness, yoga, holistic health, harmony-focused brands

### Web Constraints

| Parameter | Value | Enforcement |
|-----------|-------|-------------|
| Section padding | 60-80px vertical | HARD LIMIT |
| Max words/section body | 50 | HARD LIMIT |
| Max content blocks/section | 4 | HARD LIMIT |
| Colors | 5 balanced | Yin-yang balance (warm + cool) |

### CSS Patterns
- Balanced flexbox: `justify-content: space-between` or `space-around`
- Yin-yang pairing: alternating light/dark sections
- Circular elements: `border-radius: 50%` for images/icons
- Flowing curves: `clip-path: ellipse()` section dividers

### Typography
- Weight: 400-500 (Medium)
- Balanced serif + sans pairing
- Centered alignment with breathing room
- Harmonious size progression

### Enforcement Block
```
STYLE: Feng Shui (East Asian Harmony) — Web
- HARD LIMIT: Max 50 words per section body.
- HARD LIMIT: Max 4 content blocks per section.
- Layout: Balanced. Yin-yang pairing (light/dark alternation).
- Typography: Medium weight, centered, harmonious progression.
- Color: 5 balanced colors (warm + cool in harmony).
- CSS: Flex justify, circular elements, flowing clip-paths.
- NEVER: All-dark or all-light, harsh asymmetry, angular shapes, cold-only palette.
- JS: Not needed.
```

---

# Digital Native Family

Eight web-born styles that leverage CSS/JS capabilities. NEW in v2.1.0.

---

## Neobrutalist

Raw, unpolished, deliberately anti-design. Thick borders, hard shadows, monospace typography.

**Best for**: Creative agencies, dev portfolios, indie projects, satire, experimental

### Web Constraints

| Parameter | Value | Enforcement |
|-----------|-------|-------------|
| Section padding | 40-60px vertical | HARD LIMIT |
| Max words/section body | 70 | HARD LIMIT |
| Max content blocks/section | 6 | HARD LIMIT |
| Colors | 4-6 | High-contrast, clashing OK |

### CSS Patterns
- Hard shadows: `box-shadow: 4px 4px 0 #000` (no blur)
- Thick borders: `border: 3px solid #000`
- Monospace or brutalist fonts
- Raw backgrounds: solid bright colors, no gradients
- Stacked/overlapping elements with visible structure

### Typography
- Weight: 700-900 (Bold to Black)
- Monospace for body, black-weight sans for headings
- Large, confrontational headings
- ALL-CAPS with wide letter-spacing for labels

### Enforcement Block
```
STYLE: Neobrutalist (Digital Native) — Web
- HARD LIMIT: Max 70 words per section body.
- HARD LIMIT: Max 6 content blocks per section.
- Layout: Stacked blocks, visible structure, deliberate rawness.
- Typography: Monospace body, black-weight headings, ALL-CAPS labels.
- Color: High contrast, clashing combinations allowed. Bright solid backgrounds.
- CSS: Hard shadows (no blur), thick borders (3px+), no border-radius.
- NEVER: Soft shadows, gradients, rounded corners, polished feel, subtle colors.
- JS: Not needed.
```

---

## Glassmorphism

Frosted glass panels, translucent layers, depth through blur.

**Best for**: SaaS products, premium tech, fintech, modern apps

### Web Constraints

| Parameter | Value | Enforcement |
|-----------|-------|-------------|
| Section padding | 60-80px vertical | HARD LIMIT |
| Max words/section body | 50 | HARD LIMIT |
| Max content blocks/section | 5 | HARD LIMIT |
| Colors | 4-5 | Light + translucent layers |

### CSS Patterns
- Frosted glass: `backdrop-filter: blur(10px); background: rgba(255,255,255,0.15)`
- Layered depth: multiple translucent panels at different z-index
- Gradient mesh backgrounds behind glass panels
- Thin borders: `border: 1px solid rgba(255,255,255,0.2)`
- Subtle shadow: `box-shadow: 0 8px 32px rgba(0,0,0,0.1)`

### Typography
- Weight: 300-500 (Light to Medium)
- Clean sans-serif with high readability
- White or light text on glass panels
- Ensure contrast against translucent backgrounds

### Enforcement Block
```
STYLE: Glassmorphism (Digital Native) — Web
- HARD LIMIT: Max 50 words per section body.
- HARD LIMIT: Max 5 content blocks per section.
- Layout: Layered glass panels over gradient backgrounds.
- Typography: Light-medium weight, clean sans-serif. Ensure readability on glass.
- Color: Gradient mesh backgrounds + translucent white/light panels.
- CSS: backdrop-filter: blur(10px), rgba backgrounds, thin borders, layered z-index.
- WARNING: Check text contrast against translucent backgrounds (WCAG AA).
- NEVER: Opaque solid backgrounds, heavy shadows, thick borders, no-blur panels.
- JS: Optional (for parallax movement of glass layers).
```

---

## Dark Mode

Layered darkness with elevated surfaces. Material Design elevation principles.

**Best for**: Tech products, developer tools, SaaS dashboards, any brand wanting a modern feel

### Web Constraints

| Parameter | Value | Enforcement |
|-----------|-------|-------------|
| Section padding | 60-80px vertical | HARD LIMIT |
| Max words/section body | 60 | HARD LIMIT |
| Max content blocks/section | 5 | HARD LIMIT |
| Colors | Dark surfaces + 2-3 accents | Layered darkness |

### CSS Patterns
- Surface elevation: `--surface-0: #0a0a0a; --surface-1: #141414; --surface-2: #1e1e1e; --surface-3: #282828`
- Elevated cards: lighter surface + subtle shadow
- Accent colors for CTAs, links, active states
- Thin borders: `border: 1px solid rgba(255,255,255,0.08)`

### Typography
- Weight: 400-500
- Clean sans-serif
- Light text on dark: `color: rgba(255,255,255,0.87)` for primary, `0.6` for secondary
- Slightly increased letter-spacing for readability on dark

### Enforcement Block
```
STYLE: Dark Mode (Digital Native) — Web
- HARD LIMIT: Max 60 words per section body.
- HARD LIMIT: Max 5 content blocks per section.
- Layout: Layered dark surfaces with elevation. Cards elevate.
- Typography: Clean sans-serif, light text with opacity layers (0.87/0.6/0.38).
- Color: Dark surface stack (#0a → #14 → #1e → #28) + 2-3 accent colors.
- CSS: Surface elevation tokens, subtle borders, accent-colored CTAs.
- WARNING: Ensure WCAG AA contrast for text on dark surfaces.
- NEVER: Bright backgrounds, heavy white text, no-elevation flat dark, pure black #000.
- JS: Not needed.
```

---

## Bento Grid

Asymmetric card grid inspired by Japanese bento boxes. Modular, information-dense.

**Best for**: SaaS features, dashboards, portfolio showcases, feature overviews

### Web Constraints

| Parameter | Value | Enforcement |
|-----------|-------|-------------|
| Section padding | 40-60px vertical | HARD LIMIT |
| Max words/section body | 60 | HARD LIMIT |
| Max content blocks/section | 8 | HARD LIMIT |
| Colors | 4-6 | Card backgrounds vary |

### CSS Patterns
- CSS Grid with varied spans: `grid-template-columns: repeat(4, 1fr)` + `grid-column: span 2`
- Mixed card sizes: some 1x1, some 2x1, some 1x2
- Consistent gap: `gap: var(--space-sm)` (tight)
- Cards with individual background colors/images
- `border-radius: 16px` on all cards

### Typography
- Weight: 400-600
- Clean sans-serif
- Varied sizes per card (larger for featured)
- Short labels + minimal description per card

### Enforcement Block
```
STYLE: Bento Grid (Digital Native) — Web
- HARD LIMIT: Max 60 words per section body.
- HARD LIMIT: Max 8 content blocks per section.
- Layout: CSS Grid with varied column/row spans. Asymmetric card sizes.
- Typography: Clean sans-serif, varied sizes per card importance.
- Color: 4-6 colors, different card backgrounds for variety.
- CSS: Grid with span variations, 16px border-radius, tight gaps, individual card styling.
- NEVER: Equal-sized cards, wide gaps, single background color, non-grid layout.
- JS: Not needed.
```

---

## Retro / Y2K

Neon gradients, chrome effects, pixel elements, early-internet nostalgia.

**Best for**: Creative brands, music, gaming, entertainment, nostalgia projects

### Web Constraints

| Parameter | Value | Enforcement |
|-----------|-------|-------------|
| Section padding | 40-60px vertical | HARD LIMIT |
| Max words/section body | 70 | HARD LIMIT |
| Max content blocks/section | 6 | HARD LIMIT |
| Colors | 5-8 | Neon + dark backgrounds |

### CSS Patterns
- Neon glow: `box-shadow: 0 0 20px #ff00ff, 0 0 40px #ff00ff`
- Gradient text: `background: linear-gradient(...); -webkit-background-clip: text`
- Chrome/metallic: linear-gradient with sharp color stops
- Pixel-style borders or decorative elements
- Dark backgrounds with vivid neon overlays

### Typography
- Weight: 600-800
- Display/tech fonts (Orbitron, Press Start 2P, or similar)
- Neon-colored headings with glow effects
- Pixel fonts for labels/captions optional

### Enforcement Block
```
STYLE: Retro / Y2K (Digital Native) — Web
- HARD LIMIT: Max 70 words per section body.
- HARD LIMIT: Max 6 content blocks per section.
- Layout: Mixed — neon-lit sections on dark backgrounds.
- Typography: Display/tech fonts, neon colors, glow effects.
- Color: 5-8 colors. Dark backgrounds + neon accents (magenta, cyan, lime).
- CSS: Neon box-shadow glows, gradient text, chrome gradients, dark bases.
- NEVER: Pastel colors, muted tones, clean minimalism, serious corporate feel.
- JS: Optional (for flickering neon or scan-line effects).
```

---

## Kinetic

Motion-driven design. Animated reveals, scroll effects, dynamic transitions.

**Best for**: Storytelling, portfolios, product launches, immersive brand experiences

### Web Constraints

| Parameter | Value | Enforcement |
|-----------|-------|-------------|
| Section padding | 80-100px vertical | HARD LIMIT |
| Max words/section body | 50 | HARD LIMIT |
| Max content blocks/section | 4 | HARD LIMIT |
| Colors | 4-5 | Style-dependent |

### CSS Patterns
- Scroll-snap sections: `scroll-snap-type: y mandatory` on container
- CSS keyframe animations for reveals: `@keyframes fadeSlideIn`
- Transition on scroll: elements transform as they enter viewport
- Staggered reveals: `animation-delay` incrementing per element
- Parallax-like: background moves at different speed via `background-attachment: fixed`

### Typography
- Weight: 400-600
- Large, cinematic headings that animate in
- Body reveals line-by-line or section-by-section
- Scale changes on scroll

### Enforcement Block
```
STYLE: Kinetic (Digital Native) — Web
- HARD LIMIT: Max 50 words per section body.
- HARD LIMIT: Max 4 content blocks per section.
- Layout: Scroll-driven narrative. Sections reveal as user scrolls.
- Typography: Cinematic headings, animated reveals, scale transitions.
- Color: 4-5 colors, supporting the motion narrative.
- CSS: @keyframes, scroll-snap, transition, animation-delay, background-attachment.
- MANDATORY: prefers-reduced-motion media query disabling all animations.
- JS: YES — Intersection Observer for scroll triggers (progressive enhancement).
- NEVER: Static layouts, no animation, instant content display, JS-dependent content.
```

---

## Neumorphism

Soft UI with extruded/inset elements. Subtle depth through light/dark shadows.

**Best for**: Dashboards, settings pages, calculators, tools, personal projects

### Web Constraints

| Parameter | Value | Enforcement |
|-----------|-------|-------------|
| Section padding | 60-80px vertical | HARD LIMIT |
| Max words/section body | 50 | HARD LIMIT |
| Max content blocks/section | 5 | HARD LIMIT |
| Colors | 3-4 | Monochromatic base |

### CSS Patterns
- Dual shadow: `box-shadow: 8px 8px 16px #d1d1d1, -8px -8px 16px #ffffff`
- Background matches element base: same hue, slight variation
- Inset elements: `box-shadow: inset 4px 4px 8px #d1d1d1, inset -4px -4px 8px #ffffff`
- Soft/round: `border-radius: 16px` to `24px`
- No visible borders

### Typography
- Weight: 400-500
- Clean sans-serif
- Muted text colors (never pure black)
- Clear hierarchy through size, not weight

### Enforcement Block
```
STYLE: Neumorphism (Digital Native) — Web
- HARD LIMIT: Max 50 words per section body.
- HARD LIMIT: Max 5 content blocks per section.
- Layout: Soft extruded elements on monochromatic backgrounds.
- Typography: Clean sans-serif, muted text (never pure black), size-based hierarchy.
- Color: Monochromatic base + subtle variations. 3-4 colors max.
- CSS: Dual box-shadow (light + dark), matching bg/element colors, large border-radius.
- CRITICAL WARNING: Neumorphism risks WCAG AA contrast failures. ALWAYS validate:
  - Element edges visible against background (add subtle border if needed)
  - Text contrast meets 4.5:1 on soft backgrounds
  - Interactive elements distinguishable from static
- NEVER: High-contrast colors, sharp shadows, visible borders, flat design mixing.
- JS: Not needed.
```

---

## 3D / Immersive

Perspective transforms, layered depth, parallax scrolling. Premium spatial experience.

**Best for**: Premium products, brand showcases, product launches, creative experiences

### Web Constraints

| Parameter | Value | Enforcement |
|-----------|-------|-------------|
| Section padding | 60-100px vertical | HARD LIMIT |
| Max words/section body | 50 | HARD LIMIT |
| Max content blocks/section | 5 | HARD LIMIT |
| Colors | 4-5 | Depth-supporting palette |

### CSS Patterns
- Perspective container: `perspective: 1000px` on parent
- 3D transforms: `transform: rotateX(5deg) rotateY(-3deg)`
- Layered depth: elements at different `translateZ()` values
- Parallax: elements move at different speeds on scroll
- Gradient depth: darker at edges, lighter at center

### Typography
- Weight: 400-600
- Clean, readable fonts (3D effects already add visual complexity)
- Large headings that benefit from perspective
- Standard body text (don't apply 3D to body copy)

### Enforcement Block
```
STYLE: 3D / Immersive (Digital Native) — Web
- HARD LIMIT: Max 50 words per section body.
- HARD LIMIT: Max 5 content blocks per section.
- Layout: Perspective transforms, layered depth, spatial composition.
- Typography: Clean and readable (3D effects add enough complexity).
- Color: 4-5 depth-supporting colors (darker = further, lighter = closer).
- CSS: perspective, transform: rotateX/Y, translateZ, layered elements.
- MANDATORY: prefers-reduced-motion disabling 3D transforms and parallax.
- JS: YES — for parallax scroll effects and dynamic perspective shifts.
- NEVER: Flat layouts, no depth, all elements on same plane, heavy body text rotation.
```

---

## Component Support Matrix

Which components work best with which styles:

| Component | All Styles | Best With | Avoid With |
|-----------|-----------|-----------|------------|
| Navigation | Yes | All | — |
| Hero | Yes | All | — |
| Feature Grid | Yes | Swiss, Bento, Dark Mode | Ma, Yeo-baek |
| Content Block | Yes | All | — |
| Testimonials | Yes | Organic, Hygge, Glassmorphism | Ma, Yeo-baek |
| CTA | Yes | All | — |
| Stats Bar | Yes | Swiss, Dark Mode, Neobrutalist | Ma |
| Team Grid | Yes | Hygge, Lagom, Swiss | Ma, Yeo-baek |
| FAQ Accordion | Yes | Lagom, Swiss, Dark Mode | Ma |
| Pricing Cards | Yes | Swiss, Dark Mode, Bento | Ma, Yeo-baek |
| Gallery | Yes | Dramatic, Iki, Bento | Yeo-baek |
| Process Steps | Yes | Swiss, Lagom, Organic | Ma |
| Contact | Yes | Hygge, Lagom, Organic | Ma |
| Footer | Yes | All | — |
| Logo Bar | Yes | Swiss, Lagom, Dark Mode | Ma, Yeo-baek |

**Note:** "Avoid With" means the component conflicts with the style's philosophy (e.g., Ma demands emptiness, so a dense feature grid contradicts it). The component technically works but undermines the style.
