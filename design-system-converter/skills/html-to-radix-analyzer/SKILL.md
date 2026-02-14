---
name: html-to-radix-analyzer
description: Use when analyzing HTML pages for conversion to Drupal. Parses HTML metadata comments, classifies patterns, extracts design tokens, inventories Drupal backend and existing theme, and produces target-agnostic analysis output.
version: 1.1.0
model: sonnet
user-invocable: false
---

# HTML-to-Radix Analyzer

Analyze HTML pages produced by the brand-content-design workflow and produce a structured, target-agnostic analysis. This analysis feeds into target-specific generators (Radix, Canvas, etc.).

## Inputs

- `HTML_FILE` -- Path to the HTML file to analyze (required)
- `DRUPAL_PATH` -- Path to an existing Drupal codebase (optional; enables backend inventory)
- `CONFIG_SYNC_DIR` -- Absolute path to config sync directory (optional; discovered by command from `settings.php`)
- `QUICK_MODE` -- When true, auto-resolve ambiguous classifications without prompting (default: false)

## External Guide Discovery (MANDATORY)

**MANDATORY first step**: WebFetch `https://camoa.github.io/dev-guides/llms.txt` to discover current guide pages.

1. Fetch `llms.txt` and list the discovered pages before proceeding
2. Validate that at least 3 guide sections were discovered (e.g., `design-systems/`, `drupal/`)
3. If WebFetch fails or validation fails, STOP and warn the user -- do not fall back to local references only
4. Use `design-systems/recognition/` pages for token identification and classification heuristics
5. Use `design-systems/radix-components/` pages for component selection strategy and full API reference

This step is non-negotiable because external guides contain critical classification rules and component API details that local references cannot fully replicate.

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
   - Count of items in the slot
   - Whether items share identical prop structures
4. **CSS classes** -- collect all `class="..."` values from the component's HTML elements
5. **Raw HTML** -- the HTML between the component open/close comments (trimmed)
6. **HTML semantic elements** -- note presence of `<nav>`, `<footer>`, `<form>`, `<details>`, `<summary>`, `<header>`, `<main>`, `<section>`, `<article>`
7. **Image contexts** -- for each image prop, extract:
   - Container dimensions (from CSS classes, inline styles, `width`/`height` attributes)
   - Aspect ratio (from `aspect-ratio` CSS, or computed from container width/height)
   - Usage context: hero (full-width), card thumbnail, avatar/profile, inline content, gallery
   - Whether the image appears at multiple sizes across breakpoints (responsive containers)

### Extract Design Token Block

Find the `<style>` block containing `:root { ... }` CSS custom property declarations. Store the raw CSS text for Part 2.

### Extract Google Fonts

Find any `<link>` tags with `href` containing `fonts.googleapis.com`. Extract the font family names and weights.

## Part 1b: Layout Structure Extraction

For each HTML page, parse the section/row/column hierarchy to capture how components are arranged on the page. This data feeds into Layout Builder section mapping and styleguide layout wireframes.

### Walk the DOM

1. Identify top-level sections: `<section>` elements, or top-level wrappers between `<!-- component: -->` markers
2. Process each section top-to-bottom in document order

### Per-Section Extraction

For each section, extract:

1. **Layout type** -- detect from CSS classes:
   - Bootstrap grid: `row` with single `col-*` child = `onecol`, two `col-*` children = `twocol`, three = `threecol`
   - CSS grid: `grid-template-columns` patterns (e.g., `repeat(3, 1fr)`) = `grid`
   - No grid structure = `onecol` (full-width)

2. **Column proportions** -- parse `col-md-{n}` or `col-lg-{n}` classes into percentages:
   - `col-md-8` + `col-md-4` = `[67, 33]`
   - `col-md-6` + `col-md-6` = `[50, 50]`
   - `col-md-4` × 3 = `[33, 33, 33]`
   - CSS grid `repeat(3, 1fr)` = `[33, 33, 33]`

3. **Visual properties**:
   - Background classes: `bg-*`, inline `background-color`
   - Padding classes: `py-*`, `p-*`, `pt-*`, `pb-*`
   - Container type: `container` vs `container-fluid` vs none

4. **Components inside** -- which `<!-- component: -->` markers fall within this section

5. **Regions** -- map components to column positions:
   - Single column: all components in position 1
   - Multi-column: assign components to their column's position based on DOM nesting

6. **Section order** -- sequential index (1-based) from top of page

### Output

Add `pageLayouts[]` to the analysis result. See `references/analysis-output-schema.md` for the complete schema.

---

## Part 2: Design Token Extraction

Parse the `:root { }` CSS custom property declarations extracted in Part 1.

### Categorize Each Token

Group tokens by prefix and purpose:

- **Color tokens** -- `--color-*`: primary, secondary, accent, background, text, semantic, border
- **Typography tokens** -- `--font-*`, `--font-size-*`, `--line-height-*`, `--letter-spacing-*`, `--font-weight-*`
- **Spacing tokens** -- `--space-*`: spacing scale, section padding, component gaps
- **Layout tokens** -- `--max-width`, `--border-radius` variants
- **Interaction tokens** -- `--timing-*`, `--easing-*`

### Bootstrap Variable Mapping

For each token, determine the closest Bootstrap SCSS variable using the 6px threshold:
- Within 6px of Bootstrap default --> map to that variable
- Outside 6px --> flag as custom override
- Record both the token name and its Bootstrap equivalent (or "custom")

### Google Fonts

Include extracted Google Fonts: family names, weights, full URL.

## Part 3: Pattern Classification

For each component from Part 1, apply the decision tree in `references/pattern-classification.md`.

### Classification Steps

1. **Check semantic elements first**: `<nav>` --> navigation, `<footer>` --> footer, `<form>` --> form, `<details>` --> accordion
2. **Check slot structure**: 4+ uniform items --> repeating_content; 2-3 uniform items --> curated_content
3. **Check prop patterns**: stat-like props --> statistics; heading + body + CTA --> single_promotional
4. **Flag ambiguous cases**: Set `ambiguous: true` with both possible classifications
5. **Attach reasoning** for each classification

## Part 4: Drupal Backend Inventory

Only run if `DRUPAL_PATH` is provided and `CONFIG_SYNC_DIR` exists.

Follow the scan rules in `references/drupal-backend-inventory.md`:
1. Scan `CONFIG_SYNC_DIR` (NOT hardcoded `config/sync/`) for content types, block types, views, menus, taxonomies, modules, image styles
2. Build inventory of all discovered entities with fields
3. Match each classified component to existing backend (direct name, field structure, view match)
4. Record match details: action (reuse/extend/create_new), confidence, field mapping

### Part 4b: Existing Site Inventory

When `DRUPAL_PATH` is provided with an existing theme:

1. Read `{CONFIG_SYNC_DIR}/{current_theme}.settings.yml` for logo, favicon, features
2. List all `.html.twig` template files in the current theme directory
3. Get enabled views from `drush views:list --status=enabled` output or `CONFIG_SYNC_DIR` views configs
4. Get enabled modules from `drush pm:list --status=enabled --type=module` output or `core.extension.yml`
5. Output includes `existingTheme: { name, templates[], settings, views[], modules[] }`

This inventory is critical for overlay mode -- the generator must know what already exists to avoid overwriting it.

If no config exists, return green-field mode with `greenField: true` and recommended modules.

## Part 5: Icon Extraction

Find all icons using two strategies:

**Strategy 1: Metadata comments** (preferred)
Find all `<!-- icon: {name} -->` comments and their paired `<svg>` elements:
1. Extract the immediately following `<svg>` element
2. Deduplicate by icon name
3. Record which components use each icon

**Strategy 2: Context-based SVG detection** (fallback)
When no `<!-- icon: -->` markers exist, parse `<svg>` elements by context:
1. Check `class` attributes on the SVG or its parent for icon-related names (e.g., `icon-*`, `svg-icon`, `bi-*`)
2. Check parent component type -- SVGs inside feature cards, buttons, or navigation are likely icons
3. Check SVG dimensions -- small viewBox (16-32px) suggests icons vs. larger illustrations
4. Derive icon name from class name, `data-icon` attribute, or parent component context
5. Deduplicate and record which components use each icon

## Part 6: Atomic Classification

For each component, determine atomic design level and Radix reuse status.

1. Apply heuristics from `references/atomic-classification.md`:
   - Props only, <= 3 props --> atom
   - Props only or simple slots, 2-6 props --> molecule
   - Slots with repeated items or section-level structure --> organism

2. Check against Radix base component reuse table:
   - Radix match --> `action: "extend"`
   - No match --> `action: "create_new"`

3. Determine SDC directory placement -- **flat `components/{name}/`** (no atomic subdirs):
   - `components/hero/` (not `components/organisms/hero/`)
   - `components/card/` (not `components/molecules/card/`)
   - Atomic level is recorded in metadata, not directory structure

## Part 7: Template Suggestions

For each component, determine the Twig template override path needed:

1. **Block types** --> `templates/block/block--block-content--type--{name}.html.twig`
2. **Content types (view rows)** --> `templates/node/node--{type}--teaser.html.twig`
3. **Navigation** --> `templates/block/block--system-menu-block--main.html.twig`
4. **Footer** --> `templates/block/block--system-menu-block--footer.html.twig`
5. **Views** --> `templates/views/views-view--{view-name}.html.twig`

Record the template path, the SDC component it maps to, and the field-to-prop mapping.

**Existing template handling**: When the existing theme has templates (from Part 4b inventory), check each template suggestion against the existing list. If a matching template already exists, mark the suggestion with `existingTemplate: true` and the existing template path. The generator will skip generating templates that already exist.

---

## Analysis Output Format

Return the combined analysis as a single structured result. See `references/analysis-output-schema.md` for the complete YAML schema.

The top-level keys are: `components[]`, `designTokens{}`, `pageLayouts[]`, `classifications[]`, `inventory{}`, `matches[]`, `icons[]`, `imageContexts[]`, `atomicLevels[]`, `radixReuse[]`, `templateSuggestions[]`, `warnings[]`.

---

## Examples

### Example 1: Landing Page (Green-Field)

**Input:** HTML page with hero, feature-grid (3 items), testimonials (4 items), CTA. No Drupal codebase.

**Result:**
- 4 components with props/slots from metadata
- 12 design tokens mapped to Bootstrap variables
- Classifications: hero = single_promotional, feature-grid = curated_content, testimonials = ambiguous
- Green-field mode: all create_new
- Template suggestions: 3 block templates, 1 navigation template
- 3 icons extracted

### Example 2: Blog Redesign (Existing Codebase)

**Input:** HTML page with nav, hero, article-grid (6 items), footer. Existing article content type.

**Result:**
- article-grid reuses existing article + frontpage view (85% field match)
- Template suggestions include node--article--teaser.html.twig for view rows

---

## Troubleshooting

| Error | Cause | Solution |
|-------|-------|----------|
| No components found | Missing `<!-- component: -->` metadata | Generate page with `/html-page` which adds metadata |
| No design tokens | Missing `:root { }` CSS block | Ensure HTML was generated from a design system |
| config/sync/ not found | Drupal path incorrect or not exported | Run `drush config:export` first |
| All ambiguous | Borderline item counts | Use quick mode or guided mode to decide |

## References

- `references/pattern-classification.md` -- Decision tree for pattern to Drupal mapping
- `references/atomic-classification.md` -- Atom/molecule/organism heuristics and Radix reuse table
- `references/drupal-backend-inventory.md` -- Config scan rules and matching algorithm
- `references/analysis-output-schema.md` -- Complete YAML output schema
