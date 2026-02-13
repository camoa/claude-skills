---
name: html-to-radix-analyzer
description: Use when analyzing HTML pages for conversion to Drupal. Parses HTML metadata comments, classifies patterns, extracts design tokens, inventories Drupal backend, and produces target-agnostic analysis output.
version: 1.0.0
model: sonnet
user-invocable: false
---

# HTML-to-Radix Analyzer

Analyze HTML pages produced by the brand-content-design workflow and produce a structured, target-agnostic analysis. This analysis feeds into target-specific generators (Radix, Canvas, etc.).

## Inputs

- `HTML_FILE` -- Path to the HTML file to analyze (required)
- `DRUPAL_PATH` -- Path to an existing Drupal codebase (optional; enables backend inventory)
- `QUICK_MODE` -- When true, auto-resolve ambiguous classifications without prompting (default: false)

## External Guide Discovery

Before starting analysis, WebFetch `https://camoa.github.io/dev-guides/llms.txt` to discover current guide pages. Use `design-systems/recognition/` pages for token identification and classification heuristics. Use `design-systems/radix-components/` pages for component selection strategy and full API reference.

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

### Extract Design Token Block

Find the `<style>` block containing `:root { ... }` CSS custom property declarations. Store the raw CSS text for Part 2.

### Extract Google Fonts

Find any `<link>` tags with `href` containing `fonts.googleapis.com`. Extract the font family names and weights.

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

Only run if `DRUPAL_PATH` is provided and `{DRUPAL_PATH}/config/sync/` exists.

Follow the scan rules in `references/drupal-backend-inventory.md`:
1. Scan config files for content types, block types, views, menus, taxonomies, modules, image styles
2. Build inventory of all discovered entities with fields
3. Match each classified component to existing backend (direct name, field structure, view match)
4. Record match details: action (reuse/extend/create_new), confidence, field mapping

If no config exists, return green-field mode with `greenField: true` and recommended modules.

## Part 5: Icon Extraction

Find all `<!-- icon: {name} -->` comments and their paired `<svg>` elements:
1. Extract the immediately following `<svg>` element
2. Deduplicate by icon name
3. Record which components use each icon

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

---

## Analysis Output Format

Return the combined analysis as a single structured result. See `references/analysis-output-schema.md` for the complete YAML schema.

The top-level keys are: `components[]`, `designTokens{}`, `classifications[]`, `inventory{}`, `matches[]`, `icons[]`, `atomicLevels[]`, `radixReuse[]`, `templateSuggestions[]`, `warnings[]`.

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
