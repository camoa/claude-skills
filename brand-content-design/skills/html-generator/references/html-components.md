# HTML Components Catalog

15 reusable component types for HTML page composition. Each component is standalone, responsive, and uses design tokens via CSS custom properties.

> **Online Dev-Guides:** For component classification methodology (atomic design) and Bootstrap component mapping patterns, see https://camoa.github.io/dev-guides/design-systems/recognition/component-classification-framework/ and https://camoa.github.io/dev-guides/design-systems/bootstrap/.

---

## Component Conventions

### Naming
- File name: `{type}-{variant}.html` (e.g., `hero-centered.html`, `nav-simple.html`)
- CSS class root: `.{type}` (e.g., `.hero`, `.nav`, `.feature-grid`)
- BEM for children: `.{type}__{element}` and `.{type}__{element}--{modifier}`

### Standalone Structure
Each component file is a valid HTML fragment:
```html
<!-- component: {type} variant: {variant} -->
<style>
  /* Component-scoped CSS using design tokens */
  .{type} { ... }
</style>
<section class="{type}">
  <!-- content with prop/slot metadata -->
</section>
<!-- /component: {type} -->
```

### Shared Tokens
All components reference the same CSS custom property names from the design system. When standalone, include fallback values:
```css
.hero {
  color: var(--color-text, #1a1a1a);
  font-family: var(--font-heading, 'Georgia', serif);
}
```

---

## 1. Navigation

Site header with logo and links.

### Variants
| Variant | Description | Mobile Behavior |
|---------|-------------|----------------|
| **simple** | Logo left, links right, solid background | Hamburger menu |
| **mega-menu** | Multi-column dropdowns on hover | Accordion menu |
| **transparent** | Overlays hero, transparent → solid on scroll | Hamburger menu |

### Content Fields
```
<!-- prop: logo-text type: string -->
<!-- prop: logo-image type: string (optional) -->
<!-- slot: nav-links -->
  <!-- prop: link-text type: string -->
  <!-- prop: link-href type: string -->
<!-- /slot: nav-links -->
<!-- prop: cta-text type: string (optional) -->
<!-- prop: cta-href type: string (optional) -->
```

### HTML Skeleton (simple)
```html
<header class="nav" role="banner">
  <div class="nav__container">
    <a href="/" class="nav__logo" aria-label="Home">Logo</a>
    <nav class="nav__links" role="navigation" aria-label="Main navigation">
      <a href="#" class="nav__link">Link</a>
      <!-- ... -->
    </nav>
    <a href="#" class="nav__cta btn">CTA</a>
    <button class="nav__toggle" aria-label="Toggle menu" aria-expanded="false">
      <span class="nav__toggle-bar"></span>
      <span class="nav__toggle-bar"></span>
      <span class="nav__toggle-bar"></span>
    </button>
  </div>
</header>
```

### CSS Pattern
```css
.nav { position: sticky; top: 0; z-index: 100; background: var(--color-bg); }
.nav__container { max-width: var(--max-width); margin: 0 auto; display: flex; align-items: center; justify-content: space-between; padding: var(--space-sm) var(--space-md); }
.nav__links { display: flex; gap: var(--space-md); }
.nav__toggle { display: none; }
@media (max-width: 767px) {
  .nav__links { display: none; position: absolute; /* mobile dropdown */ }
  .nav__toggle { display: block; }
}
```

### Responsive
- Mobile: hamburger toggle, vertical link list
- Desktop: horizontal links, visible CTA button

---

## 2. Hero

Page opening section — first impression, primary message.

### Variants
| Variant | Description | Layout |
|---------|-------------|--------|
| **centered** | Text centered, optional background gradient | Single column center |
| **split-image** | Text left, image/placeholder right | Two columns 50/50 |
| **full-background** | Full-width gradient/image with overlay text | Overlay on background |
| **minimal** | Small text, massive whitespace | Minimal centered |

### Content Fields
```
<!-- prop: headline type: string -->
<!-- prop: subheadline type: string -->
<!-- slot: cta -->
  <!-- prop: cta-text type: string -->
  <!-- prop: cta-href type: string -->
  <!-- prop: cta-secondary-text type: string (optional) -->
<!-- /slot: cta -->
```

### HTML Skeleton (centered)
```html
<section class="hero">
  <div class="hero__container">
    <h1 class="hero__headline">Headline</h1>
    <p class="hero__subheadline">Subheadline text</p>
    <div class="hero__cta">
      <a href="#" class="btn btn--primary">Primary CTA</a>
      <a href="#" class="btn btn--secondary">Secondary CTA</a>
    </div>
  </div>
</section>
```

### CSS Pattern
```css
.hero { padding: var(--space-2xl) var(--space-md); text-align: center; min-height: 80vh; display: flex; align-items: center; }
.hero__container { max-width: 800px; margin: 0 auto; }
.hero__headline { font-family: var(--font-heading); font-size: clamp(2.5rem, 6vw, 4.5rem); line-height: 1.1; margin-bottom: var(--space-md); }
.hero__subheadline { font-size: var(--font-size-lg); color: var(--color-text-muted); margin-bottom: var(--space-lg); }
```

### Responsive
- Mobile: stacked, smaller typography, full-width CTAs
- Desktop: larger type, side-by-side CTAs

---

## 3. Feature Grid

Feature or benefit showcase in a grid layout.

### Variants
| Variant | Description | Columns |
|---------|-------------|---------|
| **3-col** | Equal three columns | 1 → 2 → 3 |
| **4-col** | Equal four columns | 1 → 2 → 4 |
| **alternating** | Image/text alternating rows | 1 → 2 cols |
| **bento** | Mixed-size cards in CSS grid | Varied spans |

### Content Fields
```
<!-- prop: section-title type: string -->
<!-- prop: section-subtitle type: string (optional) -->
<!-- slot: features -->
  <!-- prop: feature-icon type: string (Lucide icon name, e.g. "rocket") -->
  <!-- prop: feature-title type: string -->
  <!-- prop: feature-description type: string -->
<!-- /slot: features -->
```

### HTML Skeleton (3-col)
```html
<section class="feature-grid">
  <div class="feature-grid__container">
    <h2 class="feature-grid__title">Section Title</h2>
    <p class="feature-grid__subtitle">Section subtitle</p>
    <div class="feature-grid__grid">
      <div class="feature-grid__item">
        <div class="feature-grid__icon" aria-hidden="true">
          <!-- inline SVG from html-icons.js -->
        </div>
        <h3 class="feature-grid__item-title">Feature</h3>
        <p class="feature-grid__item-desc">Description</p>
      </div>
      <!-- repeat -->
    </div>
  </div>
</section>
```

### CSS Pattern
```css
.feature-grid__grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: var(--space-lg); }
@media (max-width: 767px) { .feature-grid__grid { grid-template-columns: 1fr; } }
@media (min-width: 768px) and (max-width: 1199px) { .feature-grid__grid { grid-template-columns: repeat(2, 1fr); } }
```

---

## 4. Content Block

Rich text section with optional image. Versatile general-purpose component.

### Variants
| Variant | Description |
|---------|-------------|
| **text-left** | Image right, text left |
| **text-right** | Image left, text right |
| **full-width** | Full-width text, no image |

### Content Fields
```
<!-- prop: heading type: string -->
<!-- prop: body type: string (supports multiple paragraphs) -->
<!-- prop: image-alt type: string (optional) -->
<!-- slot: image (optional) -->
```

### CSS Pattern
```css
.content-block { display: grid; grid-template-columns: 1fr 1fr; gap: var(--space-xl); align-items: center; }
.content-block--full-width { grid-template-columns: 1fr; max-width: 800px; margin: 0 auto; }
@media (max-width: 767px) { .content-block { grid-template-columns: 1fr; } }
```

---

## 5. Testimonials

Social proof through quotes or reviews.

### Variants
| Variant | Description |
|---------|-------------|
| **single-quote** | Large featured quote, centered |
| **grid** | Multiple testimonials in a card grid |
| **carousel-style** | Horizontal scroll with CSS scroll-snap |

### Content Fields
```
<!-- slot: testimonials -->
  <!-- prop: quote type: string -->
  <!-- prop: author type: string -->
  <!-- prop: role type: string (optional) -->
  <!-- prop: company type: string (optional) -->
<!-- /slot: testimonials -->
```

### CSS Pattern (grid)
```css
.testimonials__grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: var(--space-md); }
.testimonials__card { background: var(--color-bg-alt); padding: var(--space-lg); border-radius: var(--border-radius); }
.testimonials__quote { font-style: italic; font-size: var(--font-size-lg); margin-bottom: var(--space-md); }
```

---

## 6. CTA (Call to Action)

Conversion-focused section driving user action.

### Variants
| Variant | Description |
|---------|-------------|
| **simple** | Heading + button, centered |
| **with-image** | CTA alongside image/illustration |
| **full-width** | Full-bleed colored background |
| **floating** | Sticky/floating bar at page bottom |

### Content Fields
```
<!-- prop: heading type: string -->
<!-- prop: description type: string (optional) -->
<!-- prop: cta-text type: string -->
<!-- prop: cta-href type: string -->
<!-- prop: cta-secondary-text type: string (optional) -->
```

### CSS Pattern (simple)
```css
.cta { background: var(--color-primary); color: #fff; text-align: center; padding: var(--space-xl) var(--space-md); border-radius: var(--border-radius); }
.cta__heading { font-family: var(--font-heading); font-size: var(--font-size-3xl); margin-bottom: var(--space-sm); }
```

---

## 7. Stats Bar

Key numbers or metrics displayed prominently.

### Variants
| Variant | Description |
|---------|-------------|
| **3-metric** | Three statistics in a row |
| **4-metric** | Four statistics in a row |
| **with-icons** | Stats paired with icons/emoji |

### Content Fields
```
<!-- slot: stats -->
  <!-- prop: stat-value type: string -->
  <!-- prop: stat-label type: string -->
  <!-- prop: stat-icon type: string (optional, Lucide icon name) -->
<!-- /slot: stats -->
```

### CSS Pattern
```css
.stats-bar { display: flex; justify-content: center; gap: var(--space-xl); text-align: center; }
.stats-bar__value { font-family: var(--font-heading); font-size: var(--font-size-4xl); font-weight: 700; }
.stats-bar__label { font-size: var(--font-size-sm); color: var(--color-text-muted); text-transform: uppercase; letter-spacing: 0.05em; }
@media (max-width: 767px) { .stats-bar { flex-direction: column; gap: var(--space-md); } }
```

---

## 8. Team Grid

Team member showcase with optional photos.

### Variants
| Variant | Description |
|---------|-------------|
| **cards** | Photo + name + role + bio in card |
| **minimal** | Name + role only, no photos |
| **with-photo** | Large circular photos, name + role |

### Content Fields
```
<!-- prop: section-title type: string -->
<!-- slot: members -->
  <!-- prop: name type: string -->
  <!-- prop: role type: string -->
  <!-- prop: bio type: string (optional) -->
  <!-- prop: photo-alt type: string -->
<!-- /slot: members -->
```

### CSS Pattern
```css
.team-grid__grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: var(--space-lg); }
.team-grid__photo { width: 120px; height: 120px; border-radius: 50%; background: linear-gradient(135deg, var(--color-primary), var(--color-accent)); }
@media (max-width: 767px) { .team-grid__grid { grid-template-columns: repeat(2, 1fr); } }
```

---

## 9. FAQ Accordion

Questions and answers using CSS-only `<details>` elements.

### Variants
| Variant | Description |
|---------|-------------|
| **simple** | Flat list of Q&A |
| **categorized** | Grouped by topic with section headers |

### Content Fields
```
<!-- prop: section-title type: string -->
<!-- slot: questions -->
  <!-- prop: question type: string -->
  <!-- prop: answer type: string -->
  <!-- prop: category type: string (optional, for categorized variant) -->
<!-- /slot: questions -->
```

### HTML Skeleton
```html
<section class="faq">
  <h2 class="faq__title">Frequently Asked Questions</h2>
  <div class="faq__list">
    <details class="faq__item">
      <summary class="faq__question">Question?</summary>
      <div class="faq__answer"><p>Answer text.</p></div>
    </details>
  </div>
</section>
```

### CSS Pattern
```css
.faq__item { border-bottom: 1px solid var(--color-bg-alt); }
.faq__question { padding: var(--space-md) 0; cursor: pointer; font-weight: 600; list-style: none; }
.faq__question::marker { display: none; }
.faq__question::after { content: '+'; float: right; transition: transform var(--transition); }
.faq__item[open] .faq__question::after { transform: rotate(45deg); }
.faq__answer { padding: 0 0 var(--space-md); color: var(--color-text-muted); }
```

---

## 10. Pricing Cards

Pricing tier comparison with feature lists.

### Variants
| Variant | Description |
|---------|-------------|
| **2-tier** | Two plans side-by-side |
| **3-tier** | Three plans, middle featured |
| **with-featured** | One plan highlighted/elevated |

### Content Fields
```
<!-- prop: section-title type: string -->
<!-- slot: plans -->
  <!-- prop: plan-name type: string -->
  <!-- prop: plan-price type: string -->
  <!-- prop: plan-period type: string -->
  <!-- prop: plan-description type: string -->
  <!-- prop: plan-featured type: boolean -->
  <!-- slot: plan-features -->
    <!-- prop: feature-text type: string -->
    <!-- prop: feature-included type: boolean -->
  <!-- /slot: plan-features -->
  <!-- prop: plan-cta-text type: string -->
<!-- /slot: plans -->
```

### CSS Pattern
```css
.pricing__grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: var(--space-md); align-items: start; }
.pricing__card { background: var(--color-bg-alt); border-radius: var(--border-radius); padding: var(--space-lg); }
.pricing__card--featured { transform: scale(1.05); box-shadow: 0 8px 40px rgba(0,0,0,0.12); border: 2px solid var(--color-primary); }
.pricing__price { font-family: var(--font-heading); font-size: var(--font-size-4xl); }
@media (max-width: 767px) { .pricing__grid { grid-template-columns: 1fr; } .pricing__card--featured { transform: none; } }
```

---

## 11. Gallery

Image or work showcase in a grid layout.

### Variants
| Variant | Description |
|---------|-------------|
| **grid** | Equal-size grid of images/cards |
| **masonry-like** | Varied heights using CSS columns |

### Content Fields
```
<!-- prop: section-title type: string -->
<!-- slot: items -->
  <!-- prop: item-title type: string -->
  <!-- prop: item-description type: string (optional) -->
  <!-- prop: item-image-alt type: string -->
  <!-- prop: item-category type: string (optional) -->
<!-- /slot: items -->
```

### CSS Pattern (masonry-like)
```css
.gallery__grid { columns: 3; column-gap: var(--space-md); }
.gallery__item { break-inside: avoid; margin-bottom: var(--space-md); border-radius: var(--border-radius); overflow: hidden; }
@media (max-width: 767px) { .gallery__grid { columns: 1; } }
@media (min-width: 768px) and (max-width: 1199px) { .gallery__grid { columns: 2; } }
```

---

## 12. Process Steps

Step-by-step flow showing a process, timeline, or journey.

### Variants
| Variant | Description |
|---------|-------------|
| **numbered** | Sequential numbered steps |
| **icon-linked** | Steps with icons and connecting lines |
| **timeline** | Vertical timeline with alternating sides |

### Content Fields
```
<!-- prop: section-title type: string -->
<!-- slot: steps -->
  <!-- prop: step-number type: string -->
  <!-- prop: step-title type: string -->
  <!-- prop: step-description type: string -->
  <!-- prop: step-icon type: string (optional, Lucide icon name) -->
<!-- /slot: steps -->
```

### CSS Pattern (numbered)
```css
.process__steps { display: flex; gap: var(--space-lg); }
.process__step { flex: 1; text-align: center; position: relative; }
.process__number { width: 48px; height: 48px; border-radius: 50%; background: var(--color-primary); color: #fff; display: flex; align-items: center; justify-content: center; margin: 0 auto var(--space-sm); font-weight: 700; }
@media (max-width: 767px) { .process__steps { flex-direction: column; } }
```

---

## 13. Contact

Contact information, form layout, or combined display.

### Variants
| Variant | Description |
|---------|-------------|
| **form** | Contact form with fields |
| **info-cards** | Contact methods in cards (email, phone, address) |
| **split** | Form on one side, info on other |

### Content Fields
```
<!-- prop: section-title type: string -->
<!-- prop: section-description type: string (optional) -->
<!-- slot: contact-methods (for info-cards) -->
  <!-- prop: method-type type: string -->
  <!-- prop: method-value type: string -->
  <!-- prop: method-label type: string -->
<!-- /slot: contact-methods -->
<!-- slot: form-fields (for form) -->
  <!-- prop: field-label type: string -->
  <!-- prop: field-type type: string (text/email/textarea) -->
  <!-- prop: field-required type: boolean -->
<!-- /slot: form-fields -->
```

### Note on Forms
Generated forms are visual-only (no backend). Include `action="#"` and `method="POST"` as placeholders. Add a comment:
```html
<!-- Form action: Replace "#" with your form endpoint (Netlify Forms, Formspree, etc.) -->
```

---

## 14. Footer

Page footer with links, copyright, and optional newsletter signup.

### Variants
| Variant | Description |
|---------|-------------|
| **simple** | Logo + copyright + social links |
| **multi-column** | Multiple link columns + copyright |
| **with-newsletter** | Newsletter signup + links + copyright |

### Content Fields
```
<!-- prop: logo-text type: string -->
<!-- prop: copyright type: string -->
<!-- slot: footer-columns (for multi-column) -->
  <!-- prop: column-title type: string -->
  <!-- slot: column-links -->
    <!-- prop: link-text type: string -->
    <!-- prop: link-href type: string -->
  <!-- /slot: column-links -->
<!-- /slot: footer-columns -->
<!-- slot: social-links -->
  <!-- prop: platform type: string -->
  <!-- prop: url type: string -->
<!-- /slot: social-links -->
```

### CSS Pattern
```css
.footer { background: var(--color-bg-alt, #1a1a1a); color: var(--color-text-muted, #999); padding: var(--space-xl) var(--space-md); }
.footer__grid { display: grid; grid-template-columns: 2fr repeat(3, 1fr); gap: var(--space-lg); max-width: var(--max-width); margin: 0 auto; }
.footer__bottom { border-top: 1px solid rgba(255,255,255,0.1); padding-top: var(--space-md); margin-top: var(--space-lg); text-align: center; font-size: var(--font-size-sm); }
@media (max-width: 767px) { .footer__grid { grid-template-columns: 1fr; } }
```

---

## 15. Logo Bar

Partner, client, or integration logos display.

### Variants
| Variant | Description |
|---------|-------------|
| **scrolling** | Auto-scrolling horizontal strip (CSS animation) |
| **static-grid** | Static grid of logos |

### Content Fields
```
<!-- prop: section-title type: string (optional, e.g., "Trusted by") -->
<!-- slot: logos -->
  <!-- prop: logo-name type: string -->
  <!-- prop: logo-image-alt type: string -->
<!-- /slot: logos -->
```

### CSS Pattern (scrolling)
```css
.logo-bar__track { display: flex; gap: var(--space-xl); animation: scroll 30s linear infinite; overflow: hidden; }
@keyframes scroll { 0% { transform: translateX(0); } 100% { transform: translateX(-50%); } }
.logo-bar__item { flex-shrink: 0; height: 40px; opacity: 0.6; filter: grayscale(100%); transition: opacity var(--transition), filter var(--transition); }
.logo-bar__item:hover { opacity: 1; filter: none; }
@media (prefers-reduced-motion: reduce) { .logo-bar__track { animation: none; flex-wrap: wrap; justify-content: center; } }
```

---

## Composition Rules

### Section Order Guidelines

Pages typically follow this flow (not mandatory, but recommended):

1. **Navigation** — always first
2. **Hero** — primary message, below nav
3. **Social proof** (logo bar, stats) — early trust signals
4. **Features/benefits** — what you offer
5. **Content blocks** — deeper explanation
6. **Testimonials** — social proof reinforcement
7. **Pricing/comparison** — decision support
8. **FAQ** — objection handling
9. **CTA** — final conversion push
10. **Contact** — alternative action
11. **Footer** — always last

### Section Spacing

Between sections: use consistent padding defined by the style's enforcement block. Use alternating background colors (light/dark/accent) for visual rhythm.

### Adjacent Component Rules

- **Never stack** two CTAs adjacent to each other
- **Never follow** hero immediately with footer (add at least one content section)
- **Stats bar** works well between hero and features (trust signal)
- **Testimonials** pair well after features or before CTA
- **FAQ** naturally precedes final CTA (handles objections)
