---
name: html-generator
description: Use when generating branded HTML pages and components from a design system. Creates standalone HTML components and composes them into full pages with embedded CSS, responsive design, and brand integration.
version: 2.9.1
allowed-tools: Read, Write, Glob, Grep, Bash
user-invocable: false
---

# HTML Generator Skill

Create distinctive, branded HTML pages and standalone components from a design system.

## The Critical Understanding

HTML page creation is **design-system-driven composition**, not template filling. Each component is a standalone design artifact that works independently AND as part of a composed page. Every section should feel crafted by a senior designer — intentional, distinctive, unforgettable.

- **What you receive**: a design system (canvas-philosophy.md + design-system.md) with design tokens, component catalog, and brand identity.
- **What you create**: standalone HTML components + a composed single-file HTML page.
- **The standard**: work that makes the viewer stop scrolling. Bold, distinctive, never generic.

## When Called

Invoked by `/html-page` and `/html-page-quick`. Receives: design system files (canvas-philosophy.md + design-system.md), brand philosophy (brand-philosophy.md or sub-identity overrides), component selections, any reusable components from `components/`, content, and style constraints from `references/web-style-constraints.md`.

## Two Output Modes

- **Component generation** — individual standalone components: a complete HTML fragment with embedded `<style>`, design tokens via CSS custom properties, prop/slot metadata comments, viewable independently with token fallbacks.
- **Page composition** — assemble components into one `.html` file: shared `:root` tokens, responsive wrapper with meta viewport, components in order with consistent spacing, nav top + footer bottom, single deduplicated `<style>` block, minimal `<script>` only when the style requires it.

File format, boilerplate, and the full component/page structure are in `references/html-technical.md`.

## Part 1: Design Thinking Process

Before writing any HTML, internalize the design system:

0. **Verify brand exists** — if no `design-system.md` in the project, STOP and suggest `/design-html` first. If no `brand-philosophy.md`, suggest `/brand-extract` first. Never proceed with default/example values.
1. **Read the canvas philosophy** — absorb its aesthetic movement, not just rules.
2. **Load design tokens** — colors, fonts, spacing become CSS custom properties.
3. **Understand the style** — read enforcement blocks from `references/web-style-constraints.md`.
4. **Consider the content** — what is the page's purpose? Who sees it? What should they feel?
5. **Plan differentiation** — what makes THIS page visually memorable vs. generic?

### The Differentiation Test

Before generating, ask: "Could this page belong to any brand?" If yes, push harder. Then ask: **"What is the ONE thing someone will remember about this page?"** — a dramatic type scale, a surprising color moment, an unexpected layout break. If you cannot name it, the design is not distinctive enough.

Incorporate the canvas philosophy's unique movement and spirit, unexpected layout choices (asymmetry, overlap, grid-breaking), typography as art, atmosphere (gradient meshes, noise, patterns, depth shadows), and brand personality through micro-interactions.

### Intentionality Over Intensity

**Match implementation complexity to the aesthetic vision.** Maximalist designs need elaborate code with extensive animation and layered effects; minimalist or refined designs need restraint, precision, and careful spacing/typography. The key is intentionality, not intensity — a Swiss design executed with mathematical precision is as powerful as a Memphis design executed with wild energy. Never apply "bold" uniformly; calibrate to the style.

## Part 2: Brand Integration

### Design Tokens → CSS Custom Properties

Read the project's `design-system.md` and map ALL token sections to `:root` custom properties — colors (`--color-primary`, `--color-accent`, `--color-bg`, `--color-text`, …), typography (`--font-heading`, `--font-body`, `--font-size-*`), spacing (`--space-xs`…`--space-2xl`), layout (`--max-width`, `--border-radius`, `--min-tap-target`), interaction timing/easing, and form tokens when the page has forms. The design-system.md is the single source of truth — never hardcode values.

### Brand Bias Prevention (verify before generating any HTML)

```
□ All colors use CSS custom properties from design-system.md (--color-primary, etc.)
□ No hardcoded hex values except #FFFFFF/#000000 for universal black/white
□ font-family from design-system.md, never "Inter", "Roboto", or "Arial" as defaults
□ If no design-system.md exists: STOP, suggest /design-html first
□ Background, accent, and text colors all traced to design tokens
```

**Never copy hex codes or font names from reference-file examples into generated HTML.** All visual values flow: design-system.md → CSS custom properties → component styles.

### Color Dominance Principle

Dominant colors with sharp accents outperform timid, evenly-distributed palettes. Use `--color-primary` as the dominant voice (headings, CTAs, active nav), `--color-accent` as sharp punctuation (links, hover, highlights), and let `--color-bg`/`--color-text` do the quiet structural work. If the palette feels "even", push primary harder or pull secondary back.

### Font Loading

Load DISTINCTIVE Google Fonts via `<link>` with a system fallback stack — never default to Inter, Roboto, or Arial. Exact `<link>` markup and the fallback stack are in `references/html-technical.md` § Font Loading Strategy.

## Part 3: Component Generation

### Rules for Every Component

1. **Standalone validity** — each component works as a standalone HTML file.
2. **Shared tokens** — all components reference the same CSS custom property names.
3. **Consistent naming** — `{type}-{variant}.html` (e.g., `hero-centered.html`).
4. **Prop/slot metadata** — HTML comments marking content insertion points.
5. **Responsive** — mobile-first, works at all 3 breakpoints.
6. **Accessible** — semantic HTML, ARIA labels where needed, focus management.
7. **Interactive states** — every clickable element defines hover, focus, and active styles using interaction tokens.
8. **Touch-ready** — interactive elements meet `--min-tap-target` size with adequate spacing.

### Metadata Comments (MANDATORY)

Every component MUST carry conversion-ready metadata comments — without them the design-system-converter cannot identify components, props, or slots:

- `<!-- component: type variant: name -->` … `<!-- /component: type -->` wrap the whole component
- `<!-- prop: name type: string|boolean -->` immediately before the element it annotates
- `<!-- slot: name -->` … `<!-- /slot: name -->` around repeating/insertable content
- `<!-- icon: name -->` before an SVG

Supported prop types: `string`, `boolean`. These comments MUST appear in both standalone components AND composed pages. Full format with examples: `references/html-technical.md` § Convertibility Metadata Format.

### Component CSS

Scope styles with BEM-like naming (`.hero`, `.hero__title`, `.hero__title--large`) and reference design tokens, never hardcoded values. Per-component HTML skeletons and CSS patterns for all 15 component types are in `references/html-components.md`.

## Part 3.5: Icon Integration

Lucide icons (1,500+) are available as inline SVG via `node "$BRAND_CONTENT_DESIGN_DIR/scripts/html-icons.js" get|search|category|categories`. Icons use `currentColor` for stroke and inherit size from the container. Use icons only when a clear visual metaphor exists; pair them with text labels; mark decorative icons `aria-hidden="true"` and meaningful icons `role="img" aria-label="…"`. Fetch commands, embedding pattern, and container CSS: `references/html-technical.md` § Icon Integration.

## Part 4: Style Enforcement

Read `references/web-style-constraints.md` for the selected style and enforce its per-section limits (word/element counts), spacing values, typography rules, color strategy, layout directives, JS allowance, and anti-patterns. Apply the enforcement block to every component and composed page.

## Part 5: Responsive Design

Mobile-first with 3 breakpoints: 375px base, `@media (min-width: 768px)` tablet, `@media (min-width: 1200px)` desktop. Standard adaptations — hamburger→horizontal nav, stacked→side-by-side hero, 1→2→3-4 col grids, type scaled down 15-20% on mobile, section padding reduced 30-40% on mobile. Breakpoint code and typography scaling: `references/html-technical.md` § Responsive Breakpoints.

## Part 6: CSS-First Interactivity

Prefer CSS; use JS only when CSS cannot achieve the effect.

**Motion hierarchy** — focus the motion budget on **one high-impact moment** per page. One well-orchestrated page load with staggered reveals beats scattered micro-interactions. Decide: hero entrance, stats counting up, or card grid cascade — pick one, make it great, keep the rest subtle.

CSS-only patterns: hover transitions (`transform`, `box-shadow`, `opacity`), `<details>`/`<summary>` accordions, `scroll-snap`, `@keyframes`, `scroll-behavior: smooth`, `:focus-visible`. When a style (Kinetic, 3D/Immersive, parallax) needs JS: vanilla only, progressive enhancement, respect `prefers-reduced-motion`, keep it under ~50 lines. JS pattern code (Intersection Observer, mobile nav toggle, light parallax): `references/html-technical.md` § Vanilla JS Patterns.

## Part 7: Typography as Art

Typography is the primary design tool for HTML pages. Make bold choices:

- **Heading + body pairing** — contrasting but harmonious (serif heading + sans body, or vice versa).
- **Weight contrast** — exploit the full 300-900 range for hierarchy.
- **Size contrast** — headlines DRAMATICALLY larger than body (3x-6x).
- **Letter-spacing** — loose for uppercase headings, tight for large display text.
- **Line-height** — generous body (1.6-1.8), tight headlines (1.0-1.2).

**Never use** Inter/Roboto/Arial/Helvetica (unless the brand or the style's Visual DNA specifies them), a system stack alone, a single weight throughout, or uniform sizing.

**Anti-convergence** — never converge on the same font choices across generations. If 10 generated pages were lined up, they should look like 10 different designers' work. Vary display fonts, body fonts, weight distributions, and size scales between projects.

## Part 8: Spatial Composition

- **Asymmetry over symmetry** — perfect symmetry is boring; controlled asymmetry creates energy.
- **Overlap and layering** — elements can overlap (images behind text, decorative shapes).
- **Grid-breaking** — establish a grid, then intentionally break it for key moments.
- **Generous negative space** — sections breathe with `var(--space-xl)`–`var(--space-2xl)` padding.
- **Full-bleed moments** — some sections break out of the max-width container.
- **Atmosphere** — gradient meshes, subtle SVG noise/grain, CSS-generated geometric patterns, layered `box-shadow` depth, alternating section backgrounds for rhythm.

## Part 9: Accessibility (MANDATORY)

Every generated page MUST pass: semantic HTML5 landmarks; h1→h2→h3 hierarchy with no skipped levels; a skip-navigation link; WCAG AA contrast (4.5:1 normal text, 3:1 large); visible `:focus-visible` indicators; descriptive alt text (or placeholder comments); ARIA labels on nav/landmarks/interactive elements; `@media (prefers-reduced-motion: reduce)` disabling animation; `<html lang="en">`; and the viewport meta tag.

**Neumorphism warning** — soft shadows on similar backgrounds risk failing WCAG AA. Double-check contrast; add explicit borders or increase shadow contrast if needed. Full checklist: `references/html-technical.md` § Accessibility Checklist.

## Part 10: Page Composition

When assembling components into a full page, **every component section MUST retain its metadata comments** — this is the most critical requirement for framework convertibility.

- Place `<!-- component: type variant: variant -->` before the outermost element, `<!-- /component: type -->` after the closing tag.
- Place `<!-- prop: name type: type -->` immediately before the element it annotates; wrap slot areas in `<!-- slot: name -->` … `<!-- /slot: name -->`.
- Do NOT strip, summarize, or simplify metadata, and do NOT replace it with section-divider comments (`<!-- Navigation -->`, `<!-- ===== HERO ===== -->`).

CSS in a composed page is ordered: reset → `:root` tokens → base typography → utilities (`.container`, `.sr-only`, `.skip-link`) → component styles (deduplicated). Use consistent section padding (`var(--space-xl) 0` desktop, `var(--space-lg) 0` mobile) with alternating backgrounds for rhythm and no visible borders between sections. Full composed-page example and HTML boilerplate: `references/html-technical.md` § Page Composition Format.

## Part 11: Image Handling

Claude cannot generate images — use smart placeholders: CSS gradients that match the brand palette, `aspect-ratio` to hold proportions, HTML comments with image-replacement instructions, decorative CSS patterns for variety, and initials/icon placeholders for team photos. Placeholder CSS: `references/html-technical.md` § Image Placeholder Approach.

## Part 12: Convertibility Structure

Design components for future conversion to Drupal SDC, React, Canvas, and other frameworks — the metadata comments from Parts 3 and 10 are what make conversion possible. Use semantic component names (`hero`, `feature-grid`, `cta`), BEM CSS classes, CSS custom properties for all brand values, and data attributes for behavioral hooks (`data-reveal`, `data-parallax`). The full HTML-metadata → SDC/React/Twig mapping table is in `references/html-technical.md` § Convertibility Metadata Format.

## Anti-Patterns (NEVER)

- **No CSS frameworks** in output — no Bootstrap, Tailwind, Foundation.
- **No external JS** in output — no jQuery, React, Alpine, HTMX.
- **No broken images** — use CSS placeholders, never `<img src="missing.jpg">`.
- **No AI slop** — avoid generic stock-photo aesthetics, overused gradients, cliched layouts.
- **No wall of text** — respect per-section word limits from style constraints.
- **No inline styles** — all CSS in the `<style>` block (except CSS custom property overrides).
- **No pixel units for typography** — use rem/em for accessibility.
- **No framework font loading** — Google Fonts `<link>` only.

## References

### Bundled (Plugin-Specific)

- `references/html-design-guide.md` — design system philosophy and content type guide
- `references/web-style-constraints.md` — 21 style enforcement blocks for web
- `references/html-components.md` — 15 component types with HTML/CSS patterns
- `references/html-technical.md` — boilerplate, metadata format, responsive, fonts, icons, JS, accessibility, page composition, convertibility

### Online Dev-Guides (Design Systems)

For design system fundamentals beyond this plugin's visual styles, invoke `/dev-guides-navigator` with keywords like "design system recognition", "Bootstrap mapping", "Radix SDC", or "component classification". The navigator handles caching and disambiguation — never fetch dev-guides URLs directly.
