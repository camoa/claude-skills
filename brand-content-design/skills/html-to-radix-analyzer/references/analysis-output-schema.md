# Analysis Output Schema

## Contents

- Complete output structure
- Metadata fields
- Components array
- Design tokens map
- Classifications array
- Inventory and matches
- Icons array
- Atomic levels and Radix reuse
- Warnings array

## Complete Output Structure

Combine all parts into a single structured analysis result. This is the complete output schema that the analyzer returns to calling commands and the generator skill consumes.

```yaml
analysis:
  # Metadata
  sourceFile: "{HTML_FILE}"
  analyzedAt: "{timestamp}"
  quickMode: false
  greenField: false

  # Part 1: Parsed components
  components:
    - type: hero
      variant: centered
      props:
        - { name: heading, type: string }
        - { name: subheadline, type: string }
        - { name: cta-text, type: string }
        - { name: cta-url, type: string }
      slots: []
      cssClasses: [hero, hero--centered, container]
      semanticElements: [section]
      html: "<section class=\"hero\">..."
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
      cssClasses: [features, features--grid, row]
      semanticElements: [section]
      html: "<section class=\"features\">..."

  # Part 2: Design tokens
  designTokens:
    colors:
      - { token: "--color-primary", value: "#2563eb", bootstrapVar: "$primary", action: "override" }
    typography:
      - { token: "--font-heading", value: "Inter", bootstrapVar: "$headings-font-family", action: "override" }
    spacing:
      - { token: "--space-lg", value: "2rem", bootstrapVar: "$spacer-4", action: "map" }
    layout:
      - { token: "--max-width", value: "1280px", bootstrapVar: "$container-max-widths(xxl)", action: "override" }
    interaction:
      - { token: "--timing-normal", value: "200ms", bootstrapVar: null, action: "custom" }
    googleFonts:
      families: [{ name: "Inter", weights: [400, 500, 600, 700] }]
      url: "https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap"

  # Part 3: Pattern classifications
  classifications:
    - component: hero
      variant: centered
      pattern: single_promotional
      drupal_type: block_type
      ambiguous: false
      reasoning: "Single section with heading, subheadline, CTA"
    - component: features
      variant: grid
      pattern: curated_content
      drupal_type: block_type
      ambiguous: false
      reasoning: "3 uniform items -- curated block with multi-value fields"

  # Part 4: Backend inventory and matches
  inventory:
    greenField: false
    content_types:
      - name: article
        label: Article
        fields: [{ name: body, type: text_with_summary }, { name: field_image, type: image }]
        has_view: true
        view_id: content_recent
    block_types:
      - name: hero
        label: Hero
        fields: [{ name: field_headline, type: string }, { name: field_link, type: link }]
    menus: [{ id: main, label: "Main navigation" }, { id: footer, label: "Footer" }]
    modules: [layout_builder, views, media_library]
    views:
      - { id: content_recent, base_table: node_field_data, content_type: article }
    taxonomies:
      - { name: tags, label: Tags, used_by: [article] }

  matches:
    - component: hero
      action: reuse
      entity_type: block_content
      entity_name: hero
      confidence: 1.0
      field_mapping: { heading: field_headline, cta-url: field_link }
    - component: blog
      action: create_new
      recommendations:
        entity_type: node
        machine_name: blog_post
        fields:
          - { name: field_summary, type: text_long }
          - { name: field_featured_image, type: image }

  # Part 5: Icons
  icons:
    - name: rocket
      svg: "<svg>...</svg>"
      usedBy: [features]
    - name: check
      svg: "<svg>...</svg>"
      usedBy: [pricing]

  # Part 6: Atomic levels and Radix reuse
  atomicLevels:
    - { component: hero, level: organism, directory: "components/organisms/hero" }
    - { component: card, level: molecule, directory: "components/molecules/card" }
    - { component: button, level: atom, directory: "components/atoms/button" }

  radixReuse:
    - { component: card, radixBase: card, action: extend, changes: "Add brand variants" }
    - { component: hero, radixBase: null, action: create_new, changes: "Custom full-width organism" }

  # Warnings and notes
  warnings:
    - "Testimonials section flagged as ambiguous (4 items, borderline count)"
    - "No webform module detected -- form component will need webform installed"
```

## Field Details

### Component Props

| Field | Type | Description |
|---|---|---|
| `name` | string | Prop name from `<!-- prop: {name} -->` |
| `type` | string | Prop type from `<!-- prop: ... type: {type} -->` |

### Slot Fields

| Field | Type | Description |
|---|---|---|
| `name` | string | Slot name from `<!-- slot: {name} -->` |
| `count` | integer | Number of items found in the slot |
| `uniformStructure` | boolean | Whether all items share identical prop names/types |
| `itemProps` | array | Props common to each item in the slot |

### Classification Actions

| Action | Meaning |
|---|---|
| `reuse` | Existing backend entity matches, reuse it |
| `extend` | Existing entity partially matches, add missing fields |
| `create_new` | No match found, generate new config |

### Token Mapping Actions

| Action | Meaning |
|---|---|
| `accommodate` | Within 6px of Bootstrap default, use as-is |
| `map` | Close to a Bootstrap variable, map directly |
| `override` | Override Bootstrap variable with custom value |
| `custom` | No Bootstrap equivalent, create custom variable |
