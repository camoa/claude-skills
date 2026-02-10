# HTML Design Guide

Design system philosophy for branded HTML pages. This is the content type guide for the HTML generation system.

---

## Why Design System (Not Template)

Presentations and carousels use **templates** — a fixed slide/card sequence filled with content. This works because their output structure is predictable (N slides, N cards).

HTML pages are fundamentally different:
- **Variable structure** — a landing page has different sections than a pricing page
- **Component reuse** — a navigation bar designed for one page works on all pages
- **Growing library** — each new page may add components to the design system
- **Unlimited types** — the same design system produces landing pages, about pages, portfolios, blogs

A **design system** solves this: it defines visual identity (tokens) + a catalog of composable components. Pages are composed by selecting and arranging components.

---

## Three-Layer Application

The HTML design system follows the same three-layer philosophy as other content types, adapted for web:

### Layer 1: Brand Philosophy (or Sub-Identity)

`brand-philosophy.md` provides:
- Visual DNA: colors, typography, imagery style
- Verbal DNA: voice, tone, vocabulary
- Core principles: always/never rules

**Brand relationship models:**

| Model | Description | Token Source |
|-------|-------------|-------------|
| **Use main brand** | Inherits all brand-philosophy.md values | Direct mapping |
| **Sub-identity** | Based on main brand with overrides | Main + overrides |
| **Independent** | Fresh identity for this design system | User-provided or generated |

### Layer 2: Content Type Guide (This File)

Design system philosophy for web — component thinking, token-based design, responsive-first.

### Layer 3: Design System (Per Project)

`canvas-philosophy.md` + `design-system.md` in the project define:
- Visual philosophy and aesthetic movement
- Design tokens (CSS custom properties)
- Component catalog with available types and variants
- Page category presets
- Style constraints adapted for web

---

## Project Context

Before creating a design system, gather context that shapes design decisions:

### Questions to Answer

1. **Target audience** — Demographics, technical level, expectations, devices
2. **Industry/sector** — Tech, creative, healthcare, education, finance, etc.
3. **Project goals** — Convert visitors, inform, showcase work, sell products
4. **Tone/personality** — Professional, playful, bold, understated, luxurious, approachable
5. **Constraints** — Must work on mobile? Accessibility requirements? Performance budget?

### How Context Influences Design

| Context | Design Impact |
|---------|--------------|
| Tech audience | Dark mode, code-style fonts, clean grid |
| Creative industry | Bold typography, asymmetry, animation |
| Healthcare | Calming colors, generous spacing, clear hierarchy |
| E-commerce | Product-focused, clear CTAs, trust signals |
| Enterprise | Professional, grid-based, data-friendly |
| Portfolio | Full-bleed images, minimal text, dramatic transitions |

---

## Zen Principles Adapted for Web

The Presentation Zen foundation adapts for scrollable, responsive, interactive web:

### Restraint (Kanso) → Section Focus

Each section has ONE purpose, ONE primary message. Don't overload sections with multiple CTAs or competing messages.

### Simplicity → Component Clarity

Each component does one thing well. A hero is a hero, not a hero + features + CTA crammed together.

### Naturalness → Organic Scrolling

The page flow should feel natural — purpose → evidence → action. Sections build on each other like a conversation.

### Signal-to-Noise → Per-Section Word Limits

Style constraints enforce word limits per section, not per page. This prevents text walls while allowing pages of any length.

---

## Component-First Thinking

### Component Independence

Every component is designed to:
1. **Work standalone** — viewable in isolation with design token fallbacks
2. **Compose flexibly** — work adjacent to any other component
3. **Scale responsively** — adapt from 375px to 1200px+
4. **Carry identity** — express the design system's personality even in isolation

### Component Growth

The component library grows organically:
1. **Design system created** → defines tokens + component types (no HTML yet)
2. **First page** → generates hero, nav, features, footer → saves to `components/`
3. **Second page** → reuses nav + footer, generates new pricing + FAQ
4. **Library grows** → over time, most pages compose from existing components

### When to Reuse vs. Generate New

- **Reuse** when the existing component matches the needed type and variant
- **Generate new** when a different variant is needed (e.g., hero-split vs. hero-centered)
- **Never modify** existing components — create a new variant instead

---

## Design Tokens

Design tokens are the single source of truth for visual identity. They map from brand philosophy to CSS custom properties.

### Token Categories

| Category | Examples | CSS Property Pattern |
|----------|----------|---------------------|
| **Colors** | Primary, secondary, accent, backgrounds, text | `--color-*` |
| **Typography** | Font families, sizes, weights, line-heights | `--font-*`, `--font-size-*` |
| **Spacing** | Padding, margin, gap scales | `--space-*` |
| **Layout** | Max width, border radius, breakpoints | `--max-width`, `--border-radius` |
| **Effects** | Shadows, transitions, opacity | `--shadow-*`, `--transition` |

### Token Mapping Example

```
Brand Philosophy           →  Design Token          →  CSS Custom Property
Primary color: #2563EB     →  color-primary          →  --color-primary: #2563EB
Heading font: Space Grotesk →  font-heading          →  --font-heading: 'Space Grotesk', sans-serif
```

---

## Page Composition Principles

### Visual Rhythm

Alternate between:
- **Dense sections** (feature grids, testimonials) and **breathing sections** (CTAs, stats bars)
- **Light backgrounds** and **dark/colored backgrounds**
- **Text-heavy** and **visual-heavy** sections

### Hierarchy Through Scroll

The page scroll creates natural hierarchy:
1. **Above the fold** — hero (identity + primary message)
2. **Evidence zone** — features, benefits, social proof
3. **Decision zone** — pricing, comparison, FAQ
4. **Action zone** — CTA, contact, footer

### Section Spacing

Consistent vertical rhythm between sections:
- Desktop: `80-120px` padding per section
- Tablet: `60-80px`
- Mobile: `48-64px`

---

## Page Category Presets

Quick-start component combinations for common page types:

| Category | Components | Character |
|----------|-----------|-----------|
| **Landing Page** | nav, hero, feature-grid, testimonials, CTA, footer | Conversion-focused |
| **About / Company** | nav, hero, content-block, team-grid, stats-bar, footer | Story-driven |
| **Portfolio / Case Study** | nav, hero, gallery, content-block, testimonials, CTA, footer | Visual showcase |
| **Event Page** | nav, hero, content-block, stats-bar, CTA, footer | Date/action focused |
| **Pricing Page** | nav, hero, pricing-cards, FAQ-accordion, CTA, footer | Comparison-driven |
| **Blog / Article** | nav, hero, content-block, CTA, footer | Content-focused |
| **Documentation** | nav, content-block, process-steps, FAQ-accordion, footer | Reference-oriented |
| **Coming Soon** | hero, CTA | Minimal teaser |
| **Contact Page** | nav, hero, contact, FAQ-accordion, footer | Approachable |
| **Custom** | User selects any combination | Flexible |

These presets are suggestions, not constraints. Users can add, remove, or reorder components freely.
