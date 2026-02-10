---
description: Create or edit an HTML design system through guided wizard
allowed-tools: Read, Write, Glob, Grep, AskUserQuestion
---

# Design HTML Command

Create a new HTML design system or edit an existing one. The design system defines visual identity (tokens) + component catalog for composing unlimited HTML pages.

## Prerequisites

- A brand project with `brand-philosophy.md` (run `/brand-init` + `/brand-extract` first)

---

## Workflow

### Step 1: Find Project

Search for `brand-philosophy.md` using this order:

1. Current directory — check `./brand-philosophy.md`
2. Parent directory — check `../brand-philosophy.md`
3. Subdirectories — `find . -maxdepth 2 -name "brand-philosophy.md"`
4. If multiple found — ask user which project
5. If none found — tell user to run `/brand-init` first

Set `PROJECT_PATH` to the directory containing `brand-philosophy.md`.

### Step 2: Check Existing Design Systems

Search for existing HTML design systems:
```
find {PROJECT_PATH}/templates/html -maxdepth 2 -name "design-system.md" 2>/dev/null
```

If found, ask:

**AskUserQuestion**: "What would you like to do?"
- **Create new design system** — Start fresh
- **Edit existing: {name}** — Modify an existing design system (show each found)

If editing, load the existing design-system.md and canvas-philosophy.md, then jump to the relevant step for what the user wants to change.

### Step 3: Design System Name

**AskUserQuestion**: "What should we name this design system?" (3-5 words)
- **Options**: Suggest based on brand (e.g., "{Brand} Main Site", "{Brand} Product", "{Brand} Launch")

The name becomes the directory: `templates/html/{kebab-case-name}/`

### Step 4: Project Context

**AskUserQuestion**: "Who is this website for? Tell me about the target audience."

Follow up with questions about:
- **Industry/sector** — What space does this product/brand operate in?
- **Goals** — What should visitors do? (convert, learn, buy, explore)
- **Tone** — How should the site feel? (professional, playful, bold, calm, luxurious)

Gather enough context to inform design decisions. 2-3 focused questions, not an interrogation.

### Step 5: Brand Relationship

Read `brand-philosophy.md` from the project, then ask:

**AskUserQuestion**: "How should this design system relate to the main brand?"
- **Use main brand** — Inherit all colors, fonts, and voice from brand-philosophy.md
- **Create sub-identity** — Based on main brand with overrides (different accent colors, adapted fonts)
- **Independent identity** — Fresh visual identity (you'll provide or we'll generate colors and fonts)

If **sub-identity**: ask what to override (accent color, font pairing, tone adjustment).
If **independent**: ask for color preferences and font mood, or offer to generate based on context.

### Step 6: Aesthetic Family

**AskUserQuestion**: "Which aesthetic family fits this project?"
- **Japanese Zen** — Restraint, intentionality, essence (7 styles)
- **Scandinavian Nordic** — Warmth, balance, functionality (2 styles)
- **European Modernist** — Precision or playfulness (2 styles)
- **East Asian Harmony** — Space, balance, energy (2 styles)

Then in a follow-up:
- **Digital Native** — Web-born, technology-driven aesthetics (8 styles)

### Step 7: Specific Style

Based on selected family, ask the user to choose a specific style. Split into multiple questions if family has more than 4 styles.

**Japanese Zen (first 4)**:
- **Minimal** — Max whitespace, single focal point
- **Dramatic** — Asymmetrical, bold contrast
- **Organic** — Natural flow, warmth
- **Wabi-Sabi** — Imperfect beauty, texture

**Japanese Zen (remaining 3)**:
- **Shibui** — Quiet elegance, ultra-refined
- **Iki** — B&W + pop color, editorial
- **Ma** — 70%+ whitespace, floating elements

**Scandinavian Nordic**:
- **Hygge** — Warm, cozy, inviting
- **Lagom** — Balanced "just enough"

**European Modernist**:
- **Swiss** — Strict grid, mathematical precision
- **Memphis** — Bold colors, playful chaos

**East Asian Harmony**:
- **Yeo-baek** — Extreme emptiness, purity
- **Feng Shui** — Yin-Yang balance, energy flow

**Digital Native (first 4)**:
- **Neobrutalist** — Raw, thick borders, hard shadows, monospace
- **Glassmorphism** — Frosted glass, translucent, blur
- **Dark Mode** — Layered darkness, elevated surfaces
- **Bento Grid** — Asymmetric card grid, modular

**Digital Native (remaining 4)**:
- **Retro / Y2K** — Neon gradients, chrome, pixel elements
- **Kinetic** — Motion-driven, animated reveals
- **Neumorphism** — Soft UI, extruded elements (WCAG warning)
- **3D / Immersive** — Perspective, parallax, depth

### Step 8: Color Palette

Based on brand relationship choice:

If **main brand**: show brand-philosophy.md colors and confirm.

If **sub-identity**: show brand colors and ask:
**AskUserQuestion**: "Which colors would you like to override?"
- **Accent color only** — Keep primary/secondary, change accent
- **Full palette override** — Provide new palette based on brand direction
- **Keep all colors** — Use main brand colors as-is

If **independent**: ask user to provide hex colors or describe the mood for auto-generation.

### Step 9: Visual Components Support

Read the selected style's enforcement block from `references/web-style-constraints.md`.

**AskUserQuestion**: "Which visual components do you want to enable?" (multi-select, filtered by style support)

Show only components allowed by the selected style:
- **CSS gradient backgrounds** — Depth through gradients
- **CSS patterns/textures** — Dots, lines, geometric shapes
- **Decorative shapes** — Clip-path, pseudo-element shapes
- **Animations** — CSS keyframes for reveals and transitions

### Step 10: Define Design Tokens

Using the selected colors, fonts, and style, define the CSS custom property token map.

Map from identity values → design tokens:
- Brand primary → `--color-primary`
- Brand secondary → `--color-secondary`
- Selected font pair → `--font-heading`, `--font-body`
- Style-appropriate spacing scale → `--space-*`
- Style-appropriate border-radius → `--border-radius`

Choose Google Fonts that match the style and brand personality. Select DISTINCTIVE fonts — never default to Inter, Roboto, or Arial unless the brand specifically uses them.

### Step 11: Generate canvas-philosophy.md

Create `canvas-philosophy.md` using:
- The selected style's character and principles
- Brand personality from context gathering
- A creative movement name (e.g., "Digital Warmth", "Brutalist Clarity", "Glass Cathedral")
- 4-6 paragraph manifesto describing the visual philosophy
- Web-specific constraints from the style enforcement block

Follow the format from `references/canvas-philosophy-template.md` adapted for web:
- Movement name and description
- Philosophy statement
- Web-specific constraints (padding, word limits, blocks per section)
- Typography rules
- Color strategy
- Layout directives
- Anti-patterns

Save to: `{PROJECT_PATH}/templates/html/{design-system-name}/canvas-philosophy.md`

### Step 12: Generate design-system.md

Create `design-system.md` with:

```markdown
# Design System: {Name}

## Project Context
- **Audience**: {from step 4}
- **Industry**: {from step 4}
- **Goals**: {from step 4}
- **Tone**: {from step 4}
- **Brand Relationship**: {main/sub-identity/independent}

## Identity
- **Style**: {family} → {specific style}
- **Movement**: "{movement name}" — {from canvas-philosophy}

## Design Tokens

### Colors
| Token | Value | Usage |
|-------|-------|-------|
| `--color-primary` | #hex | Primary brand color, CTAs |
| `--color-secondary` | #hex | Secondary elements |
| `--color-accent` | #hex | Highlights, links |
| `--color-bg` | #hex | Page background |
| `--color-bg-alt` | #hex | Alternate section background |
| `--color-text` | #hex | Body text |
| `--color-text-muted` | #hex | Secondary text |

### Typography
| Token | Value | Usage |
|-------|-------|-------|
| `--font-heading` | 'Font', fallback | Headings |
| `--font-body` | 'Font', fallback | Body text |
| Google Fonts URL | full URL | Include in <head> |

### Spacing
| Token | Value |
|-------|-------|
| `--space-xs` | 0.5rem |
| `--space-sm` | 1rem |
| `--space-md` | 2rem |
| `--space-lg` | 4rem |
| `--space-xl` | 6rem |
| `--space-2xl` | 8rem |

### Layout
| Token | Value |
|-------|-------|
| `--max-width` | 1200px |
| `--border-radius` | {style-appropriate}px |
| `--transition` | 0.3s ease |

## Component Catalog

Available component types for this design system:

| Component | Variants | Status |
|-----------|----------|--------|
| Navigation | simple, mega-menu, transparent | Available |
| Hero | centered, split-image, full-background, minimal | Available |
| Feature Grid | 3-col, 4-col, alternating, bento | Available |
| Content Block | text-left, text-right, full-width | Available |
| Testimonials | single-quote, grid, carousel-style | Available |
| CTA | simple, with-image, full-width, floating | Available |
| Stats Bar | 3-metric, 4-metric, with-icons | Available |
| Team Grid | cards, minimal, with-photo | Available |
| FAQ Accordion | simple, categorized | Available |
| Pricing Cards | 2-tier, 3-tier, with-featured | Available |
| Gallery | grid, masonry-like | Available |
| Process Steps | numbered, icon-linked, timeline | Available |
| Contact | form, info-cards, split | Available |
| Footer | simple, multi-column, with-newsletter | Available |
| Logo Bar | scrolling, static-grid | Available |

## Page Category Presets

| Category | Recommended Components |
|----------|----------------------|
| Landing Page | nav, hero, feature-grid, testimonials, CTA, footer |
| About / Company | nav, hero, content-block, team-grid, stats-bar, footer |
| Portfolio | nav, hero, gallery, content-block, testimonials, CTA, footer |
| Event Page | nav, hero, content-block, stats-bar, CTA, footer |
| Pricing Page | nav, hero, pricing-cards, FAQ-accordion, CTA, footer |
| Blog / Article | nav, hero, content-block, CTA, footer |
| Documentation | nav, content-block, process-steps, FAQ-accordion, footer |
| Coming Soon | hero, CTA |
| Contact Page | nav, hero, contact, FAQ-accordion, footer |
| Custom | Select any combination |

## Generated Components

Components will appear here as pages are created:
<!-- (empty until first page is generated) -->
```

Save to: `{PROJECT_PATH}/templates/html/{design-system-name}/design-system.md`

### Step 13: Create Components Directory

Create empty `components/` directory:
```
{PROJECT_PATH}/templates/html/{design-system-name}/components/
```

### Step 14: Confirm and Next Steps

Tell user:
- Design system created at `templates/html/{name}/`
- Files: canvas-philosophy.md, design-system.md, components/ (empty)
- Style: {family} → {style}
- Fonts: {heading font} + {body font}
- Colors: show primary, secondary, accent

Next steps:
- Run `/html-page` to create your first page (this will generate components)
- Run `/html-page-quick` for a faster experience

---

## Output

- Created: `templates/html/{name}/canvas-philosophy.md`
- Created: `templates/html/{name}/design-system.md`
- Created: `templates/html/{name}/components/` (empty directory)
