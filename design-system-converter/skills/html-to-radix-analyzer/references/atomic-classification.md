# Atomic Classification Heuristics

Use these rules to classify each component as atom, molecule, or organism, and to determine Radix base component reuse.

## Contents

- Classification Heuristics
  - Atom -- Single-purpose element
  - Molecule -- Small composed group
  - Organism -- Complex section
- Dynamic Classification Algorithm
  - Edge Cases
- Radix Base Component Reuse Table
  - Reuse Workflow
  - SDC Directory Convention (Flat)
  - Classification Output Format

## Classification Heuristics

### Atom -- Single-purpose element

- Has props only (no slots)
- Renders one visual unit
- Contains no other components
- Typically 1-3 props

**Test:** Does it contain or compose other components? No --> atom.

**Examples:** heading, button, icon, image, badge, link, input, label, separator

### Molecule -- Small composed group

- Combines 2-3 atomic-level elements into a functional unit
- Has props AND/OR simple slots (no repeated items in slots)
- Self-contained: meaningful on its own but not a full page section

**Test:** Is it a self-contained group of atoms that works as a unit? Yes --> molecule.

**Examples:** card, stat-item, form-group, nav-link-with-icon, section-heading (title + subtitle), media-object (image + text), price-tag (amount + period + label)

### Organism -- Complex section

- Has slots containing collections of repeated items
- Wraps multiple molecules or provides page-section-level structure
- Represents a distinct section of the page

**Test:** Does it organize other components into a page section? Yes --> organism.

**Examples:** navbar, hero, feature-grid, testimonials, footer, pricing-table, blog-listing, contact-section, accordion, stats-row

## Dynamic Classification Algorithm

Apply this logic for each component:

```
function classifyComponent(component):
  # No slots, few props --> atom
  if component.slots.length == 0 and component.props.length <= 3:
    return "atom"

  # No slots, moderate props --> molecule
  if component.slots.length == 0 and component.props.length <= 6:
    return "molecule"

  # No slots, many props --> likely molecule (complex but self-contained)
  if component.slots.length == 0 and component.props.length > 6:
    return "molecule"

  # Has slots --> check slot contents
  if component.slots.length > 0:
    # Slots with repeated items --> organism
    if any slot contains repeated items (same-structure children):
      return "organism"

    # Many nested elements --> organism
    if total nested component references > 3:
      return "organism"

    # Simple slots (1-2 children, no repetition) --> molecule
    return "molecule"

  # Fallback
  return "molecule"
```

### Edge Cases

- A component with 0 props and 1 slot containing free HTML: classify as "molecule" (wrapper)
- A component that is purely structural (grid, container): classify as "organism"
- A component with a single slot for a CTA button: classify as "molecule" (the slot holds an atom)

## Radix Base Component Reuse Table

Before creating a new SDC from scratch, check if Radix provides a base component to extend.

| Radix Component | Reuse When | Extend By |
|---|---|---|
| `navbar` | Nav with links + brand logo | Add theme colors, mobile breakpoint, dropdown behavior |
| `button` | CTA buttons, form submits, link buttons | Add brand color variants, size modifiers |
| `card` | Any content card pattern | Add custom card variants, image positions |
| `accordion` | FAQ, expandable sections | Style summary/content, add icons |
| `badge` | Status labels, tags, counters | Brand colors, size variants |
| `breadcrumb` | Breadcrumb navigation | Custom separator, styling |
| `alert` | Notification banners, callouts | Brand styles, dismissible behavior |
| `modal` | Overlay dialogs, popups | Custom modal content layout |
| `carousel` | Sliding content, testimonials | Navigation style, autoplay |
| `tabs` | Tabbed content sections | Tab styling, vertical variant |
| `dropdown` | Menu dropdowns, select-like UI | Custom trigger, menu styling |
| `toast` | Temporary notifications | Position, auto-dismiss timing |

### Reuse Workflow

When Radix has a matching component, extend it instead of creating from scratch:

1. Copy Radix component to sub-theme: `npx drupal-radix-cli component`
2. Modify the copy to match the brand design
3. Keep the same `component.yml` schema structure
4. Override only the Twig template and CSS, not the data model

When no Radix match exists, create a new SDC:

1. Place in `components/{name}/` (flat directory)
2. Follow Radix component.yml conventions for schema
3. Use Bootstrap utility classes as the base styling layer

### SDC Directory Convention (Flat)

Radix uses a flat `components/` directory. All SDC components go in `components/{name}/` -- no atomic subdirectories. Record the atomic level in the `component.yml` description and the conversion report, but do NOT create `atoms/`, `molecules/`, or `organisms/` subdirectories.

```
components/
  heading/
    heading.component.yml
    heading.twig
    heading.scss
  button/
  icon/
  card/
    card.component.yml
    card.twig
    card.scss
  stat-item/
  navbar/
    navbar.component.yml
    navbar.twig
    navbar.scss
  hero/
  feature-grid/
  footer/
```

### Classification Output Format

Return atomic level per component:

```yaml
atomicLevels:
  - component: hero
    level: organism
    directory: components/hero
    reasoning: "Has heading slot, CTA slot, organizes page section"
  - component: card
    level: molecule
    directory: components/card
    reasoning: "Combines image, heading, text -- self-contained group"
  - component: button
    level: atom
    directory: components/button
    reasoning: "Single element, 2 props (label, url), no slots"

radixReuse:
  - component: card
    radixBase: card
    action: extend
    changes: "Add image-top variant, brand color scheme"
  - component: hero
    radixBase: null
    action: create_new
    changes: "No Radix equivalent, create custom organism"
```
