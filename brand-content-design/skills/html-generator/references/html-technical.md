# HTML Technical Specs

Technical reference for HTML page generation: boilerplate, file format, responsive breakpoints, font loading, image handling, JS patterns, accessibility, and convertibility metadata.

---

## HTML Boilerplate

Every generated page starts with:

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title><!-- prop: page-title --></title>
  <meta name="description" content="<!-- prop: page-description -->">

  <!-- Google Fonts -->
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=HEADING_FONT:wght@WEIGHTS&family=BODY_FONT:wght@WEIGHTS&display=swap" rel="stylesheet">

  <style>
    /* === CSS Reset === */
    *, *::before, *::after { box-sizing: border-box; }
    * { margin: 0; padding: 0; }
    html { scroll-behavior: smooth; }
    body { min-height: 100vh; line-height: 1.6; -webkit-font-smoothing: antialiased; }
    img, picture, video, canvas, svg { display: block; max-width: 100%; }
    input, button, textarea, select { font: inherit; }
    p, h1, h2, h3, h4, h5, h6 { overflow-wrap: break-word; }

    /* === Design Tokens (from design-system.md) === */
    :root {
      /* All values below come from the project's design-system.md.
         Do not hardcode — read token values from that file. */

      /* Colors: --color-primary, --color-secondary, --color-accent,
         --color-bg, --color-bg-alt, --color-text, --color-text-muted */
      /* Typography: --font-heading, --font-body, --font-size-* scale */
      /* Spacing: --space-xs through --space-2xl */
      /* Layout: --max-width, --border-radius, --min-tap-target */
      /* Interaction: --timing-fast, --timing-base, --timing-slow, --easing-default */
      /* Forms (if needed): --color-error, --color-success */
    }

    /* === Base Typography === */
    body {
      font-family: var(--font-body);
      font-size: var(--font-size-base);
      color: var(--color-text);
      background: var(--color-bg);
    }
    h1, h2, h3, h4 { font-family: var(--font-heading); line-height: 1.2; }
    a { color: var(--color-primary); text-decoration: none; }
    a:hover { text-decoration: underline; }

    /* === Utilities === */
    .container { max-width: var(--max-width); margin: 0 auto; padding: 0 var(--space-md); }
    .sr-only { position: absolute; width: 1px; height: 1px; padding: 0; margin: -1px; overflow: hidden; clip: rect(0,0,0,0); white-space: nowrap; border-width: 0; }
    .skip-link { position: absolute; top: -100%; left: 50%; transform: translateX(-50%); background: var(--color-primary); color: #fff; padding: var(--space-xs) var(--space-sm); border-radius: var(--border-radius); z-index: 999; }
    .skip-link:focus { top: var(--space-xs); }
    .btn { display: inline-block; padding: var(--space-xs) var(--space-md); min-height: var(--min-tap-target, 48px); border-radius: var(--border-radius); font-weight: 600; text-decoration: none; transition: transform var(--timing-fast, 150ms) var(--easing-default, ease), box-shadow var(--timing-fast, 150ms) var(--easing-default, ease); cursor: pointer; border: none; }
    .btn:hover { transform: translateY(-2px); text-decoration: none; }
    .btn:focus-visible { outline: 2px solid var(--color-accent, var(--color-primary)); outline-offset: 2px; }
    .btn--primary { background: var(--color-primary); color: #fff; }
    .btn--secondary { background: transparent; border: 2px solid var(--color-primary); color: var(--color-primary); }

    /* === Reduced Motion === */
    @media (prefers-reduced-motion: reduce) {
      *, *::before, *::after { animation-duration: 0.01ms; animation-iteration-count: 1; transition-duration: 0.01ms; scroll-behavior: auto; }
    }

    /* === Component Styles === */
    /* Each component's CSS goes here, deduplicated */
  </style>
</head>
<body>
  <a href="#main" class="skip-link">Skip to main content</a>

  <!-- Navigation component -->

  <main id="main">
    <!-- Content components in order -->
  </main>

  <!-- Footer component -->

  <script>
    /* Minimal JS if needed by style (scroll triggers, parallax) */
    /* Progressive enhancement — page works without JS */
  </script>
</body>
</html>
```

---

## Responsive Breakpoints

Three breakpoints, mobile-first:

| Breakpoint | Width | Target |
|-----------|-------|--------|
| **Mobile** | Default (375px+) | Phones |
| **Tablet** | `min-width: 768px` | Tablets, small laptops |
| **Desktop** | `min-width: 1200px` | Desktops, large screens |

```css
/* Mobile-first: base styles for mobile */
.component { /* mobile defaults */ }

/* Tablet */
@media (min-width: 768px) { .component { /* tablet overrides */ } }

/* Desktop */
@media (min-width: 1200px) { .component { /* desktop overrides */ } }
```

### Typography Scaling

Use `clamp()` for fluid typography:
```css
h1 { font-size: clamp(2rem, 5vw, 4rem); }
h2 { font-size: clamp(1.5rem, 3vw, 2.5rem); }
h3 { font-size: clamp(1.25rem, 2.5vw, 1.75rem); }
```

---

## Font Loading Strategy

### Google Fonts via `<link>`

```html
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Font+Name:wght@300;400;500;600;700&display=swap" rel="stylesheet">
```

### System Font Fallback Stack

Always provide fallbacks:
```css
--font-heading: 'Chosen Font', Georgia, 'Times New Roman', serif;
--font-body: 'Chosen Font', system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif;
--font-mono: 'Chosen Mono', 'Fira Code', 'Cascadia Code', monospace;
```

### Font Selection Guidelines

- Match font personality to design system's canvas philosophy
- Load only needed weights (max 4-5 per font to minimize load)
- Use `font-display: swap` (included in Google Fonts URL) for fast rendering
- Pair contrasting families (serif heading + sans body, or vice versa)

---

## Image Placeholder Approach

Since Claude cannot generate actual images, create visual placeholders:

### CSS Gradient Placeholders

```css
.image-placeholder {
  background: linear-gradient(135deg, var(--color-primary) 0%, var(--color-accent) 100%);
  border-radius: var(--border-radius);
  display: flex;
  align-items: center;
  justify-content: center;
  color: rgba(255,255,255,0.5);
  font-size: var(--font-size-sm);
}
/* Comment: Replace with <img src="your-image.jpg" alt="Description"> */
```

### Placeholder Variations

| Use Case | Placeholder Pattern |
|----------|-------------------|
| Hero images | Full-gradient with aspect-ratio: 16/9 |
| Team photos | Circular gradient with initials |
| Gallery items | Varied gradients per item |
| Logo placeholders | Small rounded rectangle with text |
| Background images | Subtle multi-stop gradient |

### Always Include

```html
<!-- IMAGE: Replace this placeholder with your actual image -->
<!-- Recommended: 1200x630px for hero, 400x400px for team, 800x600px for gallery -->
<div class="image-placeholder" style="aspect-ratio: 16/9;" role="img" aria-label="Description of intended image">
  <span>Image Placeholder</span>
</div>
```

---

## Icon Integration

Lucide icons are available as inline SVG via a CLI script. Use Bash to fetch icons during generation.

### Fetching Icons

```bash
# Get SVG for specific icons
node "$BRAND_CONTENT_DESIGN_DIR/scripts/html-icons.js" get rocket shield lightbulb

# Search by keyword
node "$BRAND_CONTENT_DESIGN_DIR/scripts/html-icons.js" search chart

# List icons in a category
node "$BRAND_CONTENT_DESIGN_DIR/scripts/html-icons.js" category business

# List all categories
node "$BRAND_CONTENT_DESIGN_DIR/scripts/html-icons.js" categories
```

### Inline SVG Embedding

Paste the SVG output directly into the HTML. Icons use `currentColor` for stroke, so they inherit color from CSS:

```html
<div class="feature-grid__icon" aria-hidden="true">
  <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"
    fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
    <!-- SVG paths from script output -->
  </svg>
</div>
```

### Icon Container CSS

Control size and color through the parent element:

```css
.feature-grid__icon {
  width: 48px;
  height: 48px;
  color: var(--color-primary);
}
.feature-grid__icon svg {
  width: 100%;
  height: 100%;
}
```

### Accessibility

| Context | Attribute |
|---------|-----------|
| Decorative (next to text label) | `aria-hidden="true"` on `<svg>` |
| Meaningful (conveys info alone) | `role="img" aria-label="Description"` on `<svg>` |

### Available Categories

Categories are defined in `skills/infographic-generator/lib/icons.js` — `ICON_CATEGORIES` object. Run `categories` command to list them. Common ones: business, growth, technology, security, actions, misc.

---

## Vanilla JS Patterns

Use only when CSS cannot achieve the desired effect. Always progressive enhancement.

### Intersection Observer (Scroll Reveals)

```javascript
// Reveal elements on scroll
const revealObserver = new IntersectionObserver((entries) => {
  entries.forEach(entry => {
    if (entry.isIntersecting) {
      entry.target.classList.add('revealed');
      revealObserver.unobserve(entry.target);
    }
  });
}, { threshold: 0.1, rootMargin: '0px 0px -50px 0px' });

document.querySelectorAll('[data-reveal]').forEach(el => revealObserver.observe(el));
```

### Mobile Navigation Toggle

```javascript
// Hamburger menu toggle
const navToggle = document.querySelector('.nav__toggle');
const navLinks = document.querySelector('.nav__links');
if (navToggle && navLinks) {
  navToggle.addEventListener('click', () => {
    const expanded = navToggle.getAttribute('aria-expanded') === 'true';
    navToggle.setAttribute('aria-expanded', !expanded);
    navLinks.classList.toggle('nav__links--open');
  });
}
```

### Parallax (Light)

```javascript
// Simple parallax on scroll (respects reduced motion)
if (!window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
  window.addEventListener('scroll', () => {
    document.querySelectorAll('[data-parallax]').forEach(el => {
      const speed = parseFloat(el.dataset.parallax) || 0.5;
      const offset = window.scrollY * speed;
      el.style.transform = `translateY(${offset}px)`;
    });
  }, { passive: true });
}
```

### Rules

- Vanilla JS only — no frameworks, no build tools
- Wrap all JS in a `DOMContentLoaded` listener or place at end of `<body>`
- Check `prefers-reduced-motion` before animations
- Use `passive: true` on scroll listeners for performance
- Under 50 lines total when possible

---

## Accessibility Checklist

Every generated page MUST include:

| Requirement | Implementation |
|-------------|---------------|
| Language | `<html lang="en">` |
| Viewport | `<meta name="viewport" content="width=device-width, initial-scale=1">` |
| Skip link | `<a href="#main" class="skip-link">Skip to main content</a>` |
| Main landmark | `<main id="main">` |
| Header landmark | `<header role="banner">` |
| Nav landmark | `<nav role="navigation" aria-label="Main navigation">` |
| Footer landmark | `<footer role="contentinfo">` |
| Heading hierarchy | h1 → h2 → h3, no skipping |
| One h1 | Exactly one `<h1>` per page |
| Link text | Descriptive (not "click here") |
| Button labels | `aria-label` on icon-only buttons |
| Image alt | Descriptive alt or `role="img" aria-label="..."` for placeholders |
| Contrast | WCAG AA: 4.5:1 normal text, 3:1 large text |
| Focus visible | `:focus-visible` outline on interactive elements |
| Reduced motion | `@media (prefers-reduced-motion: reduce)` |
| Form labels | Every input has a visible `<label>` |

---

## Component File Format

Standalone component files in `components/` directory:

```html
<!-- component: hero variant: centered -->
<!-- Design System: {design-system-name} -->
<!-- Tokens: Uses CSS custom properties from design-system.md -->

<style>
  /* Fallback tokens for standalone viewing */
  :root {
    --color-primary: #2563EB;
    --color-text: #1a1a1a;
    --font-heading: Georgia, serif;
    /* ... other fallbacks from design system */
  }

  .hero { /* component styles */ }
  .hero__title { /* ... */ }
</style>

<section class="hero">
  <!-- prop: headline type: string -->
  <h1 class="hero__title">Headline</h1>
  <!-- prop: subheadline type: string -->
  <p class="hero__subtitle">Subheadline</p>
  <!-- slot: cta -->
  <div class="hero__cta">
    <!-- prop: cta-text type: string -->
    <a href="#" class="btn btn--primary">Call to Action</a>
  </div>
  <!-- /slot: cta -->
</section>

<!-- /component: hero -->
```

---

## Page Composition Format

Full page assembles components with shared CSS root:

1. **HTML boilerplate** (see above)
2. **Shared `:root` tokens** — single source, no fallbacks needed
3. **Shared base styles** — reset, typography, utilities
4. **Component styles** — each component's CSS, deduplicated
5. **HTML body** — skip link → nav → `<main>` → components → footer
6. **Script** — minimal JS at end of body (if style requires)

---

## Convertibility Metadata Format

HTML comments that map to other framework concepts:

| Metadata | HTML Comment | Maps To |
|----------|-------------|---------|
| Component type | `<!-- component: hero variant: centered -->` | Twig template name, React component name |
| Prop (string) | `<!-- prop: headline type: string -->` | Twig variable, React prop, SDC prop |
| Prop (boolean) | `<!-- prop: featured type: boolean -->` | Conditional rendering |
| Slot | `<!-- slot: content -->` ... `<!-- /slot: content -->` | Twig block, React children |
| Component end | `<!-- /component: hero -->` | Template boundary |

CSS custom properties map to:
- **SCSS**: `$color-primary`
- **CSS Modules**: `var(--color-primary)` (same)
- **Styled Components**: `${theme.colorPrimary}`
- **Tailwind config**: `colors.primary`

---

## File Naming Conventions

### Design System Files
```
templates/html/{design-system-name}/
├── canvas-philosophy.md
├── design-system.md
└── components/
    └── {type}-{variant}.html
```

### Output Pages
```
html-pages/
└── {YYYY-MM-DD}-{page-name}/
    └── {page-name}.html
```

### Naming Rules
- All lowercase
- Hyphens for word separation
- Design system names: descriptive (e.g., `acme-corp`, `product-launch`, `developer-portal`)
- Page names: descriptive (e.g., `landing-page`, `about-us`, `pricing`)
- Component files: `{type}-{variant}.html` (e.g., `hero-centered.html`, `nav-simple.html`)
- Date format: ISO 8601 (`YYYY-MM-DD`)
