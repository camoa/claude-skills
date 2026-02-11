---
name: html-to-radix-analyzer
description: Use when analyzing HTML pages for conversion to Drupal. Parses HTML metadata comments, classifies patterns, extracts design tokens, inventories Drupal backend, and produces target-agnostic analysis output.
version: 2.2.0
model: sonnet
user-invocable: false
---

# HTML-to-Radix Analyzer

Analyze HTML pages produced by the brand-content-design workflow and produce a structured, target-agnostic analysis. This analysis feeds into target-specific generators (Radix, Canvas, etc.) that handle the actual Drupal implementation.

## Inputs

- `HTML_FILE` -- Path to the HTML file to analyze (required)
- `DRUPAL_PATH` -- Path to an existing Drupal codebase (optional; enables backend inventory)
- `QUICK_MODE` -- When true, auto-resolve ambiguous classifications without prompting (default: false)

## Part 1: HTML Metadata Parsing

Read the HTML file at `HTML_FILE`.

### Extract Components

Find all component blocks delimited by metadata comments:

```html
<!-- component: {type} variant: {variant} -->
  ...component HTML...
<!-- /component: {type} -->
```

For each component, extract:

1. **Type and variant** from the opening comment
2. **Props** -- all `<!-- prop: {name} type: {type} -->` entries within the component
3. **Slots** -- all `<!-- slot: {name} -->` / `<!-- /slot: {name} -->` blocks, including:
   - Nested props within each slot item
   - Count of items in the slot (number of repeated structures)
   - Whether items share identical prop structures (same names and types)
4. **CSS classes** -- collect all `class="..."` values from the component's HTML elements
5. **Raw HTML** -- the HTML between the component open/close comments (trimmed)
6. **HTML semantic elements** -- note presence of `<nav>`, `<footer>`, `<form>`, `<details>`, `<summary>`, `<header>`, `<main>`, `<section>`, `<article>`

### Extract Design Token Block

Find the `<style>` block containing `:root { ... }` CSS custom property declarations. Store the raw CSS text for Part 2.

### Extract Google Fonts

Find any `<link>` tags with `href` containing `fonts.googleapis.com`. Extract the font family names and weights.

### Component List Output

Build a structured list:

```yaml
components:
  - type: hero
    variant: centered
    props:
      - { name: heading, type: string }
      - { name: subheadline, type: string }
      - { name: cta-text, type: string }
      - { name: cta-url, type: string }
    slots: []
    cssClasses: [hero, hero--centered, container, text-center]
    semanticElements: [section]
    html: "<section class=\"hero hero--centered\">..."
  - type: features
    variant: grid
    props:
      - { name: heading, type: string }
    slots:
      - name: items
        count: 3
        uniformStructure: true
        itemProps:
          - { name: icon, type: string }
          - { name: title, type: string }
          - { name: description, type: string }
    cssClasses: [features, features--grid, container, row]
    semanticElements: [section]
    html: "<section class=\"features features--grid\">..."
```

## Part 2: Design Token Extraction

Parse the `:root { }` CSS custom property declarations extracted in Part 1.

### Categorize Each Token

Group tokens by their prefix and purpose:

**Color tokens** -- `--color-*`:
- Primary, secondary, accent colors
- Background colors (`--color-bg-*`)
- Text colors (`--color-text-*`)
- Semantic colors (`--color-error`, `--color-success`, `--color-warning`, `--color-info`)
- Border colors

**Typography tokens** -- `--font-*`, `--font-size-*`, `--line-height-*`, `--letter-spacing-*`:
- Font families (`--font-heading`, `--font-body`)
- Font sizes per level
- Line heights
- Letter spacing
- Font weights (`--font-weight-*`)

**Spacing tokens** -- `--space-*`:
- Spacing scale values
- Section padding
- Component gaps

**Layout tokens** -- structural measurements:
- `--max-width` (container width)
- `--border-radius` variants
- `--min-tap-target` (accessibility)

**Interaction tokens** -- animation/transition:
- `--timing-*` (durations)
- `--easing-*` (curves)

**Form tokens** -- form-specific:
- `--color-error`, `--color-success`
- Input-related tokens

### Bootstrap Variable Mapping

For each token, determine the closest Bootstrap SCSS variable using the 6px threshold:
- If a token value is within 6px of a Bootstrap default, map to that Bootstrap variable
- If outside 6px, flag as a custom override
- Record both the token name and its Bootstrap equivalent (or "custom")

### Google Fonts

Include the extracted Google Fonts information:
- Font family names
- Weights requested
- The full Google Fonts URL for inclusion

### Design Token Output

```yaml
designTokens:
  colors:
    - { token: "--color-primary", value: "#2563eb", bootstrapVar: "$primary", action: "override" }
    - { token: "--color-bg-dark", value: "#1e293b", bootstrapVar: "$gray-900", action: "map" }
    - { token: "--color-error", value: "#dc2626", bootstrapVar: "$danger", action: "override" }
  typography:
    - { token: "--font-heading", value: "Inter", bootstrapVar: "$headings-font-family", action: "override" }
    - { token: "--font-body", value: "Inter", bootstrapVar: "$font-family-base", action: "override" }
    - { token: "--font-size-xl", value: "3rem", bootstrapVar: "$h1-font-size", action: "map", within6px: true }
  spacing:
    - { token: "--space-lg", value: "2rem", bootstrapVar: "$spacer-4", action: "map" }
  layout:
    - { token: "--max-width", value: "1280px", bootstrapVar: "$container-max-widths(xxl)", action: "override" }
    - { token: "--border-radius", value: "0.5rem", bootstrapVar: "$border-radius", action: "override" }
  interaction:
    - { token: "--timing-normal", value: "200ms", bootstrapVar: null, action: "custom" }
  googleFonts:
    families: [{ name: "Inter", weights: [400, 500, 600, 700] }]
    url: "https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap"
```

## Part 3: Pattern Classification

For each component from Part 1, apply the decision tree in `references/pattern-classification.md`.

### Classification Steps

1. **Check semantic elements first:**
   - `<nav>` or `<header>` with nav links --> `navigation` pattern
   - `<footer>` --> `footer` pattern
   - `<form>` --> `form` pattern
   - `<details>`/`<summary>` --> `accordion` pattern

2. **Check slot structure:**
   - Slots with 4+ uniform items --> `repeating_content` (content type + view)
   - Slots with 2-3 uniform items --> `curated_content` (block type with multi-value fields)
   - No slots or non-uniform slots --> continue to step 3

3. **Check prop patterns:**
   - Numeric/stat-like props (stat-value, stat-label, number) --> `statistics`
   - Heading + body + CTA combination --> `single_promotional`

4. **Flag ambiguous cases:**
   - Set `ambiguous: true` when item count is borderline (3-4 testimonials, 4-6 team members)
   - Include both possible classifications (`pattern` and `alt_pattern`)
   - If `QUICK_MODE` is true, auto-resolve using the quick-mode rules in the reference file

5. **Attach reasoning** for each classification explaining why this pattern was chosen.

### Classification Output

```yaml
classifications:
  - component: hero
    variant: centered
    pattern: single_promotional
    drupal_type: block_type
    ambiguous: false
    reasoning: "Single section with heading, subheadline, CTA -- promotional block"
  - component: features
    variant: grid
    pattern: curated_content
    drupal_type: block_type
    ambiguous: false
    reasoning: "3 feature items, small curated set -- block type with multi-value fields"
  - component: testimonials
    variant: slider
    pattern: curated_content
    drupal_type: block_type
    ambiguous: true
    alt_pattern: repeating_content
    alt_drupal_type: content_type_with_view
    reasoning: "4 testimonials -- borderline, could be curated or dynamic"
```

## Part 4: Drupal Backend Inventory

Only run Part 4 if `DRUPAL_PATH` is provided and `{DRUPAL_PATH}/config/sync/` exists.

### If Config Exists: Run Inventory Scan

Follow the scan rules in `references/drupal-backend-inventory.md`:

1. **Scan config files** in `{DRUPAL_PATH}/config/sync/`:
   - `node.type.*.yml` --> content types
   - `block_content.type.*.yml` --> block types
   - `views.view.*.yml` --> views
   - `system.menu.*.yml` --> menus
   - `taxonomy.vocabulary.*.yml` --> taxonomies
   - `core.extension.yml` --> enabled modules
   - `field.storage.*.*.yml` + `field.field.*.*.*.yml` --> field definitions
   - `image.style.*.yml` --> image styles
   - `responsive_image.styles.*.yml` --> responsive image styles

2. **Build inventory** of all discovered entities with their fields, types, and relationships.

3. **Match each classified component** to existing backend:
   - Step 1: Direct name match (component type == entity machine name)
   - Step 2: Field structure match (80%+ prop-to-field similarity)
   - Step 3: View match (if repeating content, check for existing view)
   - Step 4: No match --> generate create_new recommendation

4. **Record match details**: action (reuse/extend/create_new), confidence, field mapping, fields to add.

### If No Config: Green-Field Mode

Return:

```yaml
inventory:
  greenField: true
  content_types: []
  block_types: []
  menus: []
  modules: []
  views: []
  taxonomies: []
  recommended_modules:
    - layout_builder
    - layout_builder_styles
    # Add based on detected patterns:
    # webform (if forms detected)
    # ui_icons (if icons detected)
    # media_library (if images detected)

matches: []

warnings:
  - "Green-field analysis -- all config generated from scratch, no existing backend to reuse"
```

## Part 5: Icon Extraction

Find all icon comments and their paired SVG elements in the HTML.

### Extraction Steps

1. Find all `<!-- icon: {name} -->` comments
2. For each, extract the immediately following `<svg>` element (the complete SVG markup)
3. Deduplicate by icon name (if same icon appears multiple times, keep one copy)
4. Record which components use each icon

### Icon Output

```yaml
icons:
  - name: rocket
    svg: '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4.5 16.5c-1.5 1.26-2 5-2 5s3.74-.5 5-2c.71-.84.7-2.13-.09-2.91a2.18 2.18 0 0 0-2.91-.09z"/></svg>'
    usedBy: [features, hero]
  - name: check
    svg: '<svg>...</svg>'
    usedBy: [pricing]
```

## Part 6: Atomic Classification

For each component, determine its atomic design level and Radix reuse status.

### Classification Steps

1. Apply the heuristics from `references/atomic-classification.md`:
   - Props only, <= 3 props --> atom
   - Props only or simple slots, 2-6 props --> molecule
   - Slots with repeated items or section-level structure --> organism

2. Check each component against the Radix base component reuse table:
   - If Radix has a matching component --> `action: "extend"`
   - If no Radix match --> `action: "create_new"`
   - Record what changes are needed to extend the Radix base

3. Determine SDC directory placement based on atomic level:
   - `components/atoms/{name}/`
   - `components/molecules/{name}/`
   - `components/organisms/{name}/`

### Atomic Classification Output

```yaml
atomicLevels:
  - component: hero
    level: organism
    directory: components/organisms/hero
    reasoning: "Page section with heading slot, CTA, background -- section-level structure"
  - component: card
    level: molecule
    directory: components/molecules/card
    reasoning: "Combines image, heading, text into self-contained unit"
  - component: button
    level: atom
    directory: components/atoms/button
    reasoning: "Single element, label + url props, no slots"

radixReuse:
  - component: navbar
    radixBase: navbar
    action: extend
    changes: "Add brand colors, custom mobile breakpoint, dropdown styling"
  - component: card
    radixBase: card
    action: extend
    changes: "Add image-top variant, custom hover effect"
  - component: hero
    radixBase: null
    action: create_new
    changes: "No Radix equivalent -- create custom organism with full-width background"
  - component: accordion
    radixBase: accordion
    action: extend
    changes: "Style summary with brand typography, add expand/collapse icons"
```

---

## Analysis Output Format

Return the combined analysis as a single structured result. See `references/analysis-output-schema.md` for the complete YAML schema with all fields documented.

The top-level keys are: `components[]`, `designTokens{}`, `classifications[]`, `inventory{}`, `matches[]`, `icons[]`, `atomicLevels[]`, `radixReuse[]`, `warnings[]`.

---

## Examples

### Example 1: Landing Page (Green-Field)

**Input:** A brand HTML page with hero, feature-grid (3 items), testimonials (4 items), and CTA sections. No Drupal codebase.

**Analysis result:**
- 4 components extracted with props/slots from metadata comments
- 12 design tokens (5 colors, 3 typography, 3 spacing, 1 layout)
- Classifications: hero = `single_promotional`, feature-grid = `curated_content`, testimonials = `ambiguous` (4 items, borderline), CTA = `single_promotional`
- Green-field mode: all components get `create_new` action
- 3 icons extracted (rocket, shield, star)
- Atomic: hero = organism, feature-card = molecule, CTA = organism

### Example 2: Blog Redesign (Existing Codebase)

**Input:** HTML page with nav, hero, article-grid (6 items), and footer. Drupal codebase at `/var/www/html` with existing article content type and frontpage view.

**Analysis result:**
- 4 components extracted
- Inventory: article content type (5 fields), frontpage view, main menu, footer menu
- Matches: article-grid reuses existing article + frontpage view (85% field match), nav reuses main menu
- Classifications: nav = `navigation`, hero = `single_promotional` (create_new), article-grid = `repeating_content` (reuse), footer = `footer`
- 0 icons

---

## Troubleshooting

| Error | Cause | Solution |
|-------|-------|----------|
| No components found | HTML file lacks `<!-- component: -->` metadata comments | Generate the page with `/html-page` which adds metadata automatically |
| No design tokens extracted | Missing `:root { }` CSS block in the HTML | Ensure the HTML was generated from a design system with tokens |
| config/sync/ not found | Drupal path incorrect or config not exported | Run `drush config:export` in the Drupal codebase first |
| Field match below 80% | Existing content type has different field structure | Analyzer flags as create_new; user can override to reuse if appropriate |
| All components flagged ambiguous | Borderline item counts (3-4 items in most slots) | Use quick mode for auto-resolution, or guided mode to decide each one |

## References

- `references/pattern-classification.md` -- Decision tree for HTML pattern to Drupal implementation mapping
- `references/atomic-classification.md` -- Atom/molecule/organism heuristics and Radix reuse table
- `references/drupal-backend-inventory.md` -- Config scan rules and backend matching algorithm
- `references/analysis-output-schema.md` -- Complete YAML output schema with field documentation
