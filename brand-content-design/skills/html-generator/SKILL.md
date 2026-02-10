---
name: html-generator
description: Use when generating branded HTML pages and components from a design system. Creates standalone HTML components and composes them into full pages with embedded CSS, responsive design, and brand integration.
version: 2.1.0
model: opus
user-invocable: false
---

# HTML Generator Skill

Create distinctive, branded HTML pages and standalone components from a design system.

## The Critical Understanding

HTML page creation is **design-system-driven composition**, not template filling. Each component is a standalone design artifact that works independently AND as part of a composed page. Every section should feel crafted by a senior designer — intentional, distinctive, unforgettable.

**What you receive**: A design system (canvas-philosophy.md + design-system.md) with design tokens, component catalog, and brand identity.
**What you create**: Standalone HTML components + a composed single-file HTML page.
**The standard**: Work that makes the viewer stop scrolling. Bold, distinctive, never generic.

---

## When Called

This skill is invoked by `/html-page` and `/html-page-quick` commands. It receives:

1. **Design system files** — canvas-philosophy.md + design-system.md from the project
2. **Brand philosophy** — brand-philosophy.md (or sub-identity overrides)
3. **Component selections** — which components to include (hero, features, CTA, etc.)
4. **Existing components** — any reusable components from `components/` directory
5. **Content** — text, headings, descriptions for each section
6. **Style constraints** — from `references/web-style-constraints.md`

---

## Two Output Modes

### Mode 1: Component Generation

Generate individual standalone components. Each component:
- Is a complete HTML fragment with embedded `<style>`
- References design tokens via CSS custom properties
- Includes prop/slot metadata comments for future conversion
- Can be viewed independently in a browser (with token fallback values)

### Mode 2: Page Composition

Assemble components into a single `.html` file:
- Shared CSS custom properties (design tokens) in `:root`
- Responsive wrapper with meta viewport
- Components assembled in order with consistent spacing
- Navigation at top, footer at bottom
- Single embedded `<style>` block (deduplicated from components)
- Minimal `<script>` when style requires it (scroll triggers, parallax)

---

## Part 1: Design Thinking Process

Before writing any HTML, internalize the design system:

1. **Read the canvas philosophy** — absorb its aesthetic movement, not just rules
2. **Load design tokens** — colors, fonts, spacing become CSS custom properties
3. **Understand the style** — read enforcement blocks from `references/web-style-constraints.md`
4. **Consider the content** — what is the page's purpose? Who sees it? What should they feel?
5. **Plan differentiation** — what makes THIS page visually memorable vs. generic?

### The Differentiation Test

Before generating, ask: "Could this page belong to any brand?" If yes, push harder. Incorporate:
- The canvas philosophy's unique movement name and spirit
- Unexpected layout choices (asymmetry, overlap, grid-breaking)
- Typography as art (size contrasts, weight mixing, letter-spacing play)
- Atmosphere (gradient meshes, noise textures, patterns, shadows with depth)
- The brand's personality expressed through micro-interactions (hover states, transitions)

---

## Part 2: Brand Integration

### Design Tokens → CSS Custom Properties

Map design-system.md tokens to CSS custom properties:

```css
:root {
  /* Colors */
  --color-primary: #value;
  --color-secondary: #value;
  --color-accent: #value;
  --color-bg: #value;
  --color-bg-alt: #value;
  --color-text: #value;
  --color-text-muted: #value;

  /* Typography */
  --font-heading: 'Font Name', system-fallback;
  --font-body: 'Font Name', system-fallback;
  --font-size-base: 1rem;
  --font-size-sm: 0.875rem;
  --font-size-lg: 1.25rem;
  --font-size-xl: 1.5rem;
  --font-size-2xl: 2rem;
  --font-size-3xl: 3rem;
  --font-size-4xl: 4rem;

  /* Spacing */
  --space-xs: 0.5rem;
  --space-sm: 1rem;
  --space-md: 2rem;
  --space-lg: 4rem;
  --space-xl: 6rem;
  --space-2xl: 8rem;

  /* Layout */
  --max-width: 1200px;
  --border-radius: 8px;
  --transition: 0.3s ease;
}
```

### Font Loading

Use Google Fonts via `<link>` with system font fallback stack:
```html
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=FontName:wght@300;400;500;600;700&display=swap" rel="stylesheet">
```

Choose DISTINCTIVE fonts — never default to Inter, Roboto, or Arial. Every design system deserves fonts that match its personality.

---

## Part 3: Component Generation

### Rules for Every Component

1. **Standalone validity** — each component works as a standalone HTML file
2. **Shared tokens** — all components reference the same CSS custom property names
3. **Consistent naming** — `{type}-{variant}.html` (e.g., `hero-centered.html`)
4. **Prop/slot metadata** — HTML comments marking content insertion points
5. **Responsive** — mobile-first, works at all 3 breakpoints
6. **Accessible** — semantic HTML, ARIA labels where needed, focus management

### Metadata Comments Format

Every component includes conversion-ready metadata:

```html
<!-- component: hero variant: centered -->
<!-- prop: headline type: string -->
<h1>The Headline</h1>
<!-- prop: subheadline type: string -->
<p>The subheadline text</p>
<!-- slot: cta -->
<div class="hero__cta">
  <!-- prop: cta-text type: string -->
  <a href="#" class="btn btn--primary">Get Started</a>
</div>
<!-- /slot: cta -->
<!-- /component: hero -->
```

### Component CSS Pattern

Each component scopes its styles using BEM-like class naming:

```css
.hero { /* component root */ }
.hero__title { /* element */ }
.hero__title--large { /* modifier */ }
```

Components reference design tokens (not hardcoded values):
```css
.hero {
  background: var(--color-bg);
  color: var(--color-text);
  padding: var(--space-xl) var(--space-md);
  font-family: var(--font-body);
}
```

---

## Part 4: Style Enforcement

Read `references/web-style-constraints.md` for the selected style and enforce:

- **Per-section limits** — word counts, element counts per section
- **Spacing values** — padding, margin ranges in CSS units
- **Typography rules** — weights, sizes, letter-spacing
- **Color strategy** — how many colors, contrast requirements
- **Layout directives** — CSS Grid/Flexbox patterns required
- **JS allowance** — which styles allow/require minimal JavaScript
- **Anti-patterns** — what NEVER to do with this style

Read the enforcement block and apply it to every component and composed page.

---

## Part 5: Responsive Design

Mobile-first approach with 3 breakpoints:

```css
/* Mobile: 375px (default) */
.component { /* base mobile styles */ }

/* Tablet: 768px */
@media (min-width: 768px) {
  .component { /* tablet overrides */ }
}

/* Desktop: 1200px */
@media (min-width: 1200px) {
  .component { /* desktop overrides */ }
}
```

### Responsive Patterns

- **Navigation**: Hamburger on mobile → horizontal on desktop
- **Hero**: Stacked on mobile → side-by-side on desktop
- **Grids**: 1 col mobile → 2 col tablet → 3-4 col desktop
- **Typography**: Scale down 15-20% on mobile
- **Spacing**: Reduce section padding 30-40% on mobile
- **Images**: Full-width on mobile, constrained on desktop

---

## Part 6: CSS-First Interactivity

Prefer CSS solutions. Use JS only when CSS cannot achieve the effect.

### CSS-Only Patterns

- **Hover effects**: `transform`, `box-shadow`, `opacity` transitions
- **Accordions**: `<details>` + `<summary>` elements
- **Scroll snap**: `scroll-snap-type` for carousel-like sections
- **Animations**: `@keyframes` for loading, reveals, decorative motion
- **Smooth scroll**: `scroll-behavior: smooth`
- **Focus states**: `:focus-visible` with custom outlines

### Minimal JS (When Required by Style)

Some styles (Kinetic, 3D/Immersive, Parallax effects) need vanilla JS:

```javascript
// Intersection Observer for scroll reveals
const observer = new IntersectionObserver((entries) => {
  entries.forEach(entry => {
    if (entry.isIntersecting) {
      entry.target.classList.add('revealed');
    }
  });
}, { threshold: 0.1 });

document.querySelectorAll('[data-reveal]').forEach(el => observer.observe(el));
```

Rules for JS:
- Vanilla JS only — no frameworks, no jQuery, no build tools
- Progressive enhancement — page works without JS
- Respect `prefers-reduced-motion` — disable animations when set
- Minimal footprint — under 50 lines when possible

---

## Part 7: Typography as Art

Typography is the primary design tool for HTML pages. Make bold choices:

### Font Pairing Strategy

- **Heading + Body**: Contrasting but harmonious (serif heading + sans body, or vice versa)
- **Weight contrast**: Use the full weight range (300-900) for hierarchy
- **Size contrast**: Headlines should be DRAMATICALLY larger than body (3x-6x)
- **Letter-spacing**: Loose for uppercase headings, tight for large display text
- **Line-height**: Generous for body (1.6-1.8), tighter for headlines (1.0-1.2)

### Never Use

- Inter, Roboto, Arial, Helvetica (unless the brand specifically uses them)
- System font stack alone (always include a distinctive Google Font)
- Single weight throughout (exploit the full weight range)
- Uniform sizing (create dramatic scale contrast)

---

## Part 8: Spatial Composition

### Layout Philosophy

- **Asymmetry over symmetry** — perfect symmetry is boring; controlled asymmetry creates energy
- **Overlap and layering** — elements can overlap (images behind text, decorative shapes)
- **Grid-breaking** — establish a grid, then intentionally break it for key moments
- **Generous negative space** — sections breathe with `var(--space-xl)` to `var(--space-2xl)` padding
- **Full-bleed moments** — some sections should break out of the max-width container

### Background & Atmosphere

- **Gradient meshes** — multi-stop gradients for depth (`background: linear-gradient(135deg, ...)`)
- **Noise/grain textures** — subtle SVG noise for tactile quality
- **Geometric patterns** — CSS-generated shapes, clip-paths for visual interest
- **Depth through shadow** — layered `box-shadow` for elevation
- **Color blocking** — alternating section backgrounds for rhythm

---

## Part 9: Accessibility (MANDATORY)

Every generated page MUST pass these checks:

### Requirements

- **Semantic HTML5**: `<header>`, `<nav>`, `<main>`, `<section>`, `<article>`, `<footer>`
- **Heading hierarchy**: h1 → h2 → h3, no skipping levels
- **Skip navigation**: Hidden link to main content
- **WCAG AA contrast**: 4.5:1 for normal text, 3:1 for large text
- **Focus indicators**: Visible `:focus-visible` on all interactive elements
- **Alt text**: Descriptive alt text on images (or placeholder comments)
- **ARIA labels**: On navigation, landmarks, interactive elements
- **Reduced motion**: `@media (prefers-reduced-motion: reduce)` disables animations
- **Language attribute**: `<html lang="en">`
- **Viewport meta**: `<meta name="viewport" content="width=device-width, initial-scale=1">`

### Neumorphism Warning

When using Neumorphism style, DOUBLE-CHECK contrast ratios. Soft shadows on similar backgrounds risk failing WCAG AA. Add explicit borders or increase shadow contrast if needed.

---

## Part 10: Page Composition

When assembling components into a full page:

### Structure

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Page Title</title>
  <meta name="description" content="Page description">
  <!-- Google Fonts -->
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=...&display=swap" rel="stylesheet">
  <style>
    /* Reset + Design Tokens + All Component Styles */
  </style>
</head>
<body>
  <a href="#main" class="skip-link">Skip to main content</a>
  <!-- nav component -->
  <main id="main">
    <!-- content components in order -->
  </main>
  <!-- footer component -->
  <script>
    /* Minimal JS if needed by style */
  </script>
</body>
</html>
```

### CSS Organization in Composed Page

1. **CSS Reset** — minimal reset (box-sizing, margin:0, img max-width)
2. **Design Tokens** — `:root` custom properties
3. **Base Typography** — body, headings, links, paragraphs
4. **Utility classes** — `.container`, `.sr-only`, `.skip-link`
5. **Component styles** — each component's CSS block, deduplicated

### Section Spacing

- Consistent section padding: `var(--space-xl) 0` (desktop), `var(--space-lg) 0` (mobile)
- Alternating backgrounds for visual rhythm
- No visible borders between sections (spacing and color changes create separation)

---

## Part 11: Image Handling

Since Claude cannot generate actual images, use smart placeholders:

### CSS Gradient Placeholders

```css
.hero__image-placeholder {
  background: linear-gradient(135deg, var(--color-primary) 0%, var(--color-accent) 100%);
  aspect-ratio: 16/9;
  border-radius: var(--border-radius);
  /* Replace with actual image:
     background: url('your-image.jpg') center/cover; */
}
```

### Placeholder Strategy

- Use CSS gradients that match the brand palette
- Add `aspect-ratio` to maintain proportions
- Include HTML comments with image replacement instructions
- Use decorative CSS patterns (stripes, dots, shapes) for variety
- For team photos: use initials or icon placeholders

---

## Part 12: Convertibility Structure

Design components for future conversion to other frameworks:

### HTML Comments as Metadata

```html
<!-- component: feature-grid variant: 3-col -->
<!-- prop: section-title type: string -->
<!-- prop: section-subtitle type: string -->
<!-- slot: features -->
  <!-- prop: feature-icon type: string -->
  <!-- prop: feature-title type: string -->
  <!-- prop: feature-description type: string -->
<!-- /slot: features -->
<!-- /component: feature-grid -->
```

### Naming Conventions

- Components use semantic names: `hero`, `feature-grid`, `testimonials`, `cta`
- CSS classes use BEM: `.hero__title`, `.feature-grid__item`
- CSS custom properties for all brand values (map to SCSS variables, CSS modules)
- Data attributes for behavioral hooks: `data-reveal`, `data-parallax`

This structure maps to:
- **Twig**: Props → variables, slots → blocks, HTML → template
- **SDC**: Props → component schema, slots → component slots
- **React**: Props → component props, slots → children/render props
- **Canvas**: Props → component config, HTML → JSX

---

## Anti-Patterns (NEVER)

- **No CSS frameworks** — no Bootstrap, Tailwind, Foundation in output
- **No external JS** — no jQuery, React, Alpine, HTMX in output
- **No broken images** — use CSS placeholders, never `<img src="missing.jpg">`
- **No AI slop** — avoid generic stock photo aesthetics, overused gradients, cliched layouts
- **No wall of text** — respect per-section word limits from style constraints
- **No inline styles** — all CSS in `<style>` block (except CSS custom property overrides)
- **No pixel units for typography** — use rem/em for accessibility
- **No frameworks** in font loading — Google Fonts `<link>` only

---

## References

Load these reference files when generating:

- `references/html-design-guide.md` — Design system philosophy and content type guide
- `references/web-style-constraints.md` — 21 style enforcement blocks for web
- `references/html-components.md` — 15 component types with HTML/CSS patterns
- `references/html-technical.md` — Technical specs, boilerplate, file format
