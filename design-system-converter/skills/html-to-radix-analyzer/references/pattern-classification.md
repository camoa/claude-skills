# Pattern Classification Decision Tree

Use this decision tree to map each HTML component to its Drupal implementation pattern. The converter is metadata-driven -- it reads `<!-- component: {type} variant: {variant} -->` comments, not hardcoded component names. Apply these rules based on HTML structure and slot/prop analysis.

## Contents

- Navigation Detection
- Footer Detection
- Form Detection
- Repeating Content Detection
- Curated Content Detection
- Single Promotional Section
- Accordion / FAQ Detection
- Statistics / Metrics
- Ambiguity Resolution
- Quick-Mode Auto-Resolution Rules
- Classification Output Format

## 1. Navigation Detection

**Signals:**
- `<nav>` element present
- `role="navigation"` attribute
- `<header>` containing anchor links or menu-like lists
- Component type hints: navbar, navigation, header, main-menu

**Drupal mapping:**
- Use Menu system (`main_menu`, `footer_menu`, or custom menu)
- NEVER create a custom block for navigation
- Rendered in theme region (outside Layout Builder)
- SDC: Navbar organism wrapping Drupal menu render array

**Config output:**
- Menu entity if custom menu needed
- Menu link content entities for items
- Block placement in theme region

## 2. Footer Detection

**Signals:**
- `<footer>` element present
- `role="contentinfo"` attribute
- Component at bottom of page with copyright, social links, secondary nav

**Drupal mapping:**
- Footer region with blocks (outside Layout Builder)
- SDC: Footer organism
- May contain sub-components: footer menu, social links block, copyright block

**Config output:**
- Block placements in footer region
- Footer menu if separate from main menu

## 3. Form Detection

**Signals:**
- `<form>` element present
- `<input>`, `<textarea>`, `<select>` elements
- Component type hints: contact, form, subscribe, newsletter, signup

**Drupal mapping:**
- Webform module block placed in Layout Builder section
- SDC: Form styling component (wraps Webform output)
- Do NOT recreate form logic in SDC -- Webform handles submission

**Config output:**
- `webform.webform.{name}.yml` with field definitions
- Block placement in LB section
- Webform handler config (email, submission storage)

## 4. Repeating Content Detection

**Signals:**
- Slot (`<!-- slot: {name} -->`) containing 4+ items
- All items share identical prop structures (same prop names and types)
- Content likely to grow over time: articles, blog posts, team members (5+), portfolio items, events, products

**Drupal mapping:**
- Content type with fields derived from item props
- View with responsive display (block or page display)
- SDC: Card molecule (teaser view mode) + Grid organism (View wrapper)

**Config output:**
- `node.type.{name}.yml`
- `field.storage.node.field_*.yml` + `field.field.node.{type}.field_*.yml` for each prop
- `views.view.{name}.yml` with appropriate display, pager, sort
- View mode config for teaser display

## 5. Curated Content Detection

**Signals:**
- Slot with 2-3 items sharing the same prop structure
- Content unlikely to grow: feature highlights, pricing tiers, key benefits
- Small fixed collection, editorially curated

**Drupal mapping:**
- Custom block type with multi-value fields (one field per prop, cardinality unlimited)
- Placed in Layout Builder section
- SDC: Block organism with embedded molecules

**Config output:**
- `block_content.type.{name}.yml`
- `field.storage.block_content.field_*.yml` + `field.field.block_content.{type}.field_*.yml`
- Multi-value field cardinality set to unlimited

## 6. Single Promotional Section

**Signals:**
- Section with heading prop, body text prop, CTA (link prop or slot)
- No repeating items
- One-off promotional or informational section: hero, CTA banner, about section

**Drupal mapping:**
- Custom block type in Layout Builder section
- SDC: Section organism

**Config output:**
- `block_content.type.{name}.yml`
- Fields for heading, body, link/CTA
- LB section with `layout_builder_styles` for section styling

## 7. Accordion / FAQ Detection

**Signals:**
- `<details>` / `<summary>` elements in HTML
- Slot with Q&A-structured items (question prop + answer prop)
- Component type hints: accordion, faq, expandable

**Drupal mapping:**
- Custom block type with multi-value compound field (question + answer pairs)
- SDC: Accordion organism (extend Radix accordion if available)

**Config output:**
- `block_content.type.{name}.yml`
- Multi-value field group with question (string) + answer (text_long) sub-fields
- OR: Paragraphs type if paragraphs module is enabled

## 8. Statistics / Metrics

**Signals:**
- Short text values combined with numeric-looking props
- Prop names like: stat-value, stat-label, metric, number, count
- Typically 3-4 items in a row

**Drupal mapping:**
- Custom block type with multi-value stat field (value + label pairs)
- SDC: Stats molecule for individual stat, Stats grid organism for the collection

**Config output:**
- `block_content.type.{name}.yml`
- Multi-value field group: stat_value (string) + stat_label (string)

---

## Ambiguity Resolution

Flag a component as `ambiguous: true` when the pattern classification is uncertain:

- **Testimonials with 3-4 items** -- could be curated block or content type + view
- **Team members with 4-6 items** -- borderline between curated and dynamic
- **Content that might grow** but currently has a small item count
- **Mixed grids** combining what looks like curated and dynamic content
- **Items with 3 slots** where structure partially overlaps with existing content types

When `ambiguous: true`, include both possible classifications in the output so the generator can prompt the user.

## Quick-Mode Auto-Resolution Rules

When running in quick mode (no user prompts for ambiguous cases), resolve automatically:

| Condition | Resolution |
|---|---|
| 1-3 items in slot | `block_type` (curated content) |
| 4+ items in slot | `content_type` + `view` (repeating content) |
| Testimonials (any count) | `block_type` (usually curated, rarely grows fast) |
| Team members 1-4 | `block_type` |
| Team members 5+ | `content_type` + `view` |
| Pricing tiers (any count) | `block_type` (always curated) |
| Blog/article items | `content_type` + `view` (always dynamic) |

## Classification Output Format

Return each classification in this structure:

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
    reasoning: "3 feature items with icon, title, description -- curated block"
  - component: blog
    variant: cards
    pattern: repeating_content
    drupal_type: content_type_with_view
    ambiguous: false
    reasoning: "6 articles with identical structure, likely to grow -- content type + view"
  - component: testimonials
    variant: slider
    pattern: curated_content
    drupal_type: block_type
    ambiguous: true
    alt_pattern: repeating_content
    alt_drupal_type: content_type_with_view
    reasoning: "4 testimonials -- borderline count, flagged for user decision"
```
