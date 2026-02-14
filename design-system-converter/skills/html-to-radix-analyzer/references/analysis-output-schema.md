# Analysis Output Schema

## Contents

- Complete output structure
- Metadata fields
- Components array
- Design tokens map
- Page layouts (section structure)
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

  # Part 4b: Existing theme inventory (only when existing site detected)
  existingTheme:
    name: adrupalcouple_theme
    templates:
      - templates/block/block--system-menu-block--main.html.twig
      - templates/node/node--article--teaser.html.twig
      - templates/views/views-view--blog.html.twig
    settings:
      logo_path: themes/custom/adrupalcouple_theme/logo.svg
      favicon_path: null
      features: [logo, name, slogan, node_user_picture]
    views:
      - { id: frontpage, label: Frontpage, content_type: article }
      - { id: blog, label: Blog listing, content_type: blog_post }
    modules: [layout_builder, layout_builder_styles, views, media_library, webform]

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

  # Part 1b: Page layouts (section structure per page)
  pageLayouts:
    - page: home
      sourceFile: "home.html"
      sections:
        - id: section-1
          order: 1
          layout: onecol          # onecol | twocol | threecol | grid
          proportions: [100]      # percentage per column
          containerType: container # container | container-fluid | none
          classes: [bg-primary, py-5]
          backgroundStyle: "var(--color-primary)"
          paddingStyle: "py-5"
          components: [hero]      # component names inside this section
          regions:
            - { position: 1, components: [hero] }
        - id: section-2
          order: 2
          layout: twocol
          proportions: [67, 33]
          containerType: container
          classes: [bg-white, py-4]
          components: [blog-listing, sidebar-cta]
          regions:
            - { position: 1, components: [blog-listing] }
            - { position: 2, components: [sidebar-cta] }
        - id: section-3
          order: 3
          layout: grid
          proportions: [33, 33, 33]  # equal thirds
          gridTemplate: "repeat(3, 1fr)"
          containerType: container
          classes: [bg-light, py-4]
          components: [card, card, card]  # repeated component type
          regions:
            - { position: 1, components: [card] }

  # Part 5: Icons
  icons:
    - name: rocket
      svg: "<svg>...</svg>"
      usedBy: [features]
    - name: check
      svg: "<svg>...</svg>"
      usedBy: [pricing]

  # Part 5b: Image contexts (for image style generation)
  imageContexts:
    - component: hero
      field: field_image
      context: hero
      aspectRatio: "21:9"
      containerWidth: 1440
      breakpoints:
        - { breakpoint: xs, width: 576, height: 247 }
        - { breakpoint: md, width: 992, height: 425 }
        - { breakpoint: xl, width: 1440, height: 617 }
      suggestedStyles:
        - { name: hero_xl, effect: scale_and_crop, width: 1440, height: 617 }
        - { name: hero_md, effect: scale_and_crop, width: 992, height: 425 }
        - { name: hero_sm, effect: scale_and_crop, width: 576, height: 247 }
    - component: card
      field: field_image
      context: card_thumbnail
      aspectRatio: "4:3"
      containerWidth: 400
      breakpoints:
        - { breakpoint: xs, width: 576, height: 432 }
        - { breakpoint: md, width: 400, height: 300 }
      suggestedStyles:
        - { name: card_md, effect: scale_and_crop, width: 400, height: 300 }
        - { name: card_sm, effect: scale_and_crop, width: 576, height: 432 }
    - component: team
      field: field_photo
      context: avatar
      aspectRatio: "1:1"
      containerWidth: 200
      breakpoints:
        - { breakpoint: xs, width: 200, height: 200 }
      suggestedStyles:
        - { name: avatar, effect: scale_and_crop, width: 200, height: 200 }

  # Part 6: Atomic levels and Radix reuse
  atomicLevels:
    - { component: hero, level: organism, directory: "components/hero" }
    - { component: card, level: molecule, directory: "components/card" }
    - { component: button, level: atom, directory: "components/button" }

  radixReuse:
    - { component: card, radixBase: card, action: extend, changes: "Add brand variants" }
    - { component: hero, radixBase: null, action: create_new, changes: "Custom full-width organism" }

  # Part 7: Template suggestions with existing template tracking
  templateSuggestions:
    - component: hero
      template: templates/block/block--block-content--type--hero.html.twig
      existingTemplate: false
      fieldMapping: { heading: field_heading, body: field_body, image: field_image }
    - component: navbar
      template: templates/block/block--system-menu-block--main.html.twig
      existingTemplate: true
      existingTemplatePath: templates/block/block--system-menu-block--main.html.twig

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

### Page Layout Fields

| Field | Type | Description |
|---|---|---|
| `page` | string | Page identifier (e.g., `home`, `about`) |
| `sourceFile` | string | HTML source filename |
| `sections` | array | Ordered list of page sections |

### Section Fields

| Field | Type | Description |
|---|---|---|
| `id` | string | Unique section identifier (e.g., `section-1`) |
| `order` | integer | Top-to-bottom position on the page |
| `layout` | string | Layout type: `onecol`, `twocol`, `threecol`, `grid` |
| `proportions` | array | Percentage per column (e.g., `[67, 33]`) |
| `containerType` | string | `container`, `container-fluid`, or `none` |
| `classes` | array | CSS classes on the section (background, padding, etc.) |
| `backgroundStyle` | string | Background color/style value |
| `paddingStyle` | string | Padding class (e.g., `py-5`) |
| `gridTemplate` | string | CSS grid-template-columns value (only for `grid` layout) |
| `components` | array | Component names inside this section |
| `regions` | array | Column regions with position and component assignments |

### Classification Actions

| Action | Meaning |
|---|---|
| `reuse` | Existing backend entity matches, reuse it |
| `extend` | Existing entity partially matches, add missing fields |
| `create_new` | No match found, generate new config |

### Image Context Fields

| Field | Type | Description |
|---|---|---|
| `component` | string | Component that uses this image |
| `field` | string | Drupal field name for the image |
| `context` | string | Usage context: `hero`, `card_thumbnail`, `avatar`, `gallery`, `inline`, `banner` |
| `aspectRatio` | string | Detected aspect ratio (e.g., `"16:9"`, `"4:3"`, `"1:1"`, `"21:9"`) |
| `containerWidth` | integer | Maximum container width in pixels at the largest breakpoint |
| `breakpoints` | array | Sizes per responsive breakpoint `{ breakpoint, width, height }` |
| `suggestedStyles` | array | Suggested Drupal image styles `{ name, effect, width, height }` |

### Template Suggestion Fields

| Field | Type | Description |
|---|---|---|
| `component` | string | Component name this template serves |
| `template` | string | Template path to generate |
| `existingTemplate` | boolean | Whether this template already exists in the current theme |
| `existingTemplatePath` | string | Path to the existing template (only when `existingTemplate: true`) |
| `fieldMapping` | object | Map of component prop name to Drupal field name |

### Token Mapping Actions

| Action | Meaning |
|---|---|
| `accommodate` | Within 6px of Bootstrap default, use as-is |
| `map` | Close to a Bootstrap variable, map directly |
| `override` | Override Bootstrap variable with custom value |
| `custom` | No Bootstrap equivalent, create custom variable |
