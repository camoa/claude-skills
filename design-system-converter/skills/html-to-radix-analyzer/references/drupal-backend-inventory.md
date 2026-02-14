# Drupal Backend Inventory

Rules for scanning the config sync directory to build an inventory of existing Drupal backend entities and matching HTML components to them.

## Inputs

- `CONFIG_SYNC_DIR` -- absolute path to the config sync directory. Discovered by the command from `settings.php` (`$settings['config_sync_directory']`) or by checking common locations: `config/sync/`, `sites/default/sync/`, `../config/sync/`. Do NOT hardcode `config/sync/`.

## Contents

- Config Scan Rules
  - Content Types
  - Views
  - Block Types
  - Menus
  - Taxonomies
  - Enabled Modules
  - Image Styles
  - Responsive Image Styles
- Existing Theme Inventory
- Matching Algorithm
  - Step 1: Direct Name Match
  - Step 2: Field Structure Match
  - Step 3: View Match
  - Step 4: No Match
- Field Type Mapping
- Inventory Output Format
- Green-Field Mode

## Config Scan Rules

Scan `{CONFIG_SYNC_DIR}` for these YAML file patterns.

### Content Types

**Files:** `node.type.*.yml`

Extract:
- Machine name (id field)
- Label (name field)
- Description

**Related field discovery:**
- `field.storage.node.*.yml` -- field storage definitions (type, cardinality, settings)
- `field.field.node.{type}.*.yml` -- field instance on this content type (label, required, settings)

Build field list per content type: field name, field type, cardinality, required flag.

### Views

**Files:** `views.view.*.yml`

Extract:
- View ID
- Base table (usually `node_field_data`)
- Label
- Display plugins: page, block, attachment, feed
- For each display: path, pager type, items_per_page, sorts, filters, fields/formatters
- Content type filter (if filtered to a specific node type)

### Block Types

**Files:** `block_content.type.*.yml`

Extract:
- Machine name (id field)
- Label (name field)
- Description

**Related field discovery:**
- `field.storage.block_content.*.yml`
- `field.field.block_content.{type}.*.yml`

Build field list per block type, same structure as content types.

### Menus

**Files:** `system.menu.*.yml`

Extract:
- Menu ID (id field)
- Label
- Note which are Drupal defaults (main, footer, account, admin, tools) vs custom

### Taxonomies

**Files:** `taxonomy.vocabulary.*.yml`

Extract:
- Vocabulary machine name
- Label
- Related fields via `field.field.taxonomy_term.{vocab}.*.yml`
- Which content types reference this vocabulary (scan entity_reference fields)

### Enabled Modules

**File:** `core.extension.yml`

Extract the `module:` key to get the full enabled module list.

**Key module checks:**
| Module | Significance |
|---|---|
| `layout_builder` | Layout Builder available for page composition |
| `layout_builder_styles` | Section/block styling in LB |
| `views` | Views available (almost always enabled) |
| `media` / `media_library` | Media handling for images, videos |
| `webform` | Form building available |
| `ui_icons` | Drupal Core Icon API available |
| `paragraphs` | Paragraphs module for structured content |
| `field_group` | Field groups for compound fields |
| `metatag` | SEO metadata |
| `pathauto` | URL alias patterns |
| `focal_point` | Image focal point cropping |

### Image Styles

**Files:** `image.style.*.yml`

Extract available image styles with their effects:
- Machine name (id field)
- Label
- Effects list: each effect has `plugin: image_scale_and_crop` (or `image_scale`, `image_resize`), `width`, `height`
- Compute the aspect ratio from width/height for comparison with design needs

Build a map of existing styles by aspect ratio and size:
```yaml
image_styles:
  - { name: thumbnail, width: 100, height: 100, ratio: "1:1", effect: scale_and_crop }
  - { name: medium, width: 220, height: 220, ratio: "1:1", effect: scale_and_crop }
  - { name: large, width: 480, height: null, ratio: null, effect: scale }
  - { name: hero_wide, width: 1440, height: 500, ratio: "2.88:1", effect: scale_and_crop }
```

### Responsive Image Styles

**Files:** `responsive_image.styles.*.yml`

Extract responsive image style sets:
- Machine name (id field)
- Breakpoint group (e.g., `responsive_image`)
- Mapping of breakpoints to image style(s) and sizes attributes

```yaml
responsive_image_styles:
  - name: hero_responsive
    breakpoint_group: responsive_image
    mappings:
      - { breakpoint: xs, style: hero_sm, multiplier: "1x" }
      - { breakpoint: md, style: hero_md, multiplier: "1x" }
      - { breakpoint: xl, style: hero_xl, multiplier: "1x" }
```

### Image Style Comparison

When the analyzer produces `imageContexts` with `suggestedStyles`, compare each suggested style against existing image styles:
- **Matching ratio and similar size** (within 50px): reuse existing style, record `{ action: "reuse", existingStyle: "..." }`
- **Matching ratio but different size**: suggest a new style, record `{ action: "create_new" }`
- **No matching ratio**: suggest a new style, record `{ action: "create_new" }`
- **Responsive image style exists for this context**: reuse it, otherwise suggest creating one

## Existing Theme Inventory

When an existing Drupal site is detected, inventory the current theme before making any decisions.

### Current Theme Settings

Read `{CONFIG_SYNC_DIR}/{current_theme}.settings.yml` for:
- Logo path and settings (use_default, path)
- Favicon path and settings
- Enabled theme features (node_user_picture, comment_user_picture, etc.)

### Existing Templates

List all `.html.twig` files in the current theme directory:
```
{DRUPAL_PATH}/themes/custom/{current_theme}/templates/**/*.html.twig
```

Record each template path and its type (block, node, views, layout, etc.). Components that already have matching templates should be marked `existingTemplate: true` so the generator skips regenerating them.

### Existing Views

Get enabled views from `drush views:list --status=enabled` output or scan `{CONFIG_SYNC_DIR}/views.view.*.yml`. Record:
- View ID, label, base table, content type filter, display types
- Do NOT regenerate view templates for views that already exist

### Enabled Modules

Get from `drush pm:list --status=enabled --type=module` output or scan `{CONFIG_SYNC_DIR}/core.extension.yml`. Check module availability before generating config that depends on specific modules (e.g., `layout_builder_styles`, `webform`, `media_library`).

### Inventory Output

Include in the analysis output:

```yaml
existingTheme:
  name: {current_theme}
  templates:
    - templates/block/block--system-menu-block--main.html.twig
    - templates/node/node--article--teaser.html.twig
  settings:
    logo_path: themes/custom/{theme}/logo.svg
    favicon_path: null
    features: [logo, name, slogan, node_user_picture]
  views:
    - { id: frontpage, label: Frontpage, content_type: article }
    - { id: blog, label: Blog listing, content_type: blog_post }
  modules: [layout_builder, layout_builder_styles, views, media_library, webform]
```

## Matching Algorithm

For each HTML component classified in the pattern classification step, try to match it to an existing backend entity.

### Step 1: Direct Name Match

Check if `component.type` (or a normalized version) matches any existing entity:
- `hero` matches `block_content.type.hero`
- `blog` or `article` matches `node.type.article`
- Normalize: strip hyphens, underscores; compare lowercased

If direct match found: `{ action: "reuse", confidence: 1.0 }`

### Step 2: Field Structure Match

Compare the component's props to each candidate entity's fields:

```
function compareFields(componentProps, entityFields):
  matchCount = 0
  for prop in componentProps:
    bestFieldMatch = findClosestField(prop, entityFields)
    if bestFieldMatch.similarity >= 0.7:
      matchCount += 1

  return matchCount / max(len(componentProps), len(entityFields))
```

Field similarity considers:
- Name similarity (fuzzy string match on field name vs prop name)
- Type compatibility (prop type maps to an acceptable Drupal field type)
- Cardinality match (multi-value prop matches unlimited cardinality field)

If field match >= 0.8: `{ action: "reuse", confidence: fieldMatch }`
If field match 0.5-0.79: `{ action: "extend", fieldsToAdd: [...], confidence: fieldMatch }`
If field match < 0.5: no match, proceed to Step 3.

### Step 3: View Match

If a component was classified as `repeating_content` and matched a content type in Step 2:
- Check if any View already displays that content type
- If yes: `{ action: "reuse_view", view: view.id }`
- If no: `{ action: "create_view", base_content_type: matched.id }`

### Step 4: No Match

```
{ action: "create_new", recommendations: generateRecommendations(component) }
```

Recommendations include:
- Suggested machine name
- Suggested fields with types
- Whether to use block_content or node (based on pattern classification)
- Related View config if repeating content

## Field Type Mapping

Map HTML prop types to Drupal field types:

| HTML Prop Type | Drupal Field Type | Notes |
|---|---|---|
| `string` (short, < 255 chars) | `string` | Plain text, single line |
| `string` (long, paragraphs) | `text_long` | Formatted long text |
| `string` (rich text with HTML) | `text_with_summary` | For body-like fields |
| `string` (URL pattern) | `link` | External or internal link |
| `string` (icon name) | `string` | With icon widget if `ui_icons` enabled |
| `string` (email pattern) | `email` | Email field |
| `string` (phone pattern) | `telephone` | Telephone field |
| `boolean` | `boolean` | On/off toggle |
| `string` (image path + alt) | `image` | Image with alt text |
| `string` (image path, media) | `entity_reference` (media) | If `media_library` enabled |
| `slot` (repeated items) | Entity reference or multi-value field | Depends on pattern |
| `string` (date pattern) | `datetime` | Date/time field |
| `string` (number pattern) | `integer` or `decimal` | Numeric field |

## Inventory Output Format

Return the full inventory in this structure:

```yaml
inventory:
  content_types:
    - name: article
      label: Article
      fields:
        - { name: field_tags, type: entity_reference, target: tags, cardinality: -1 }
        - { name: field_image, type: image, cardinality: 1 }
        - { name: body, type: text_with_summary, cardinality: 1 }
      has_view: true
      view_id: frontpage
  block_types:
    - name: hero
      label: Hero
      fields:
        - { name: field_headline, type: string, cardinality: 1 }
        - { name: field_body, type: text_long, cardinality: 1 }
        - { name: field_link, type: link, cardinality: 1 }
  menus:
    - { id: main, label: Main navigation, custom: false }
    - { id: footer, label: Footer, custom: false }
  modules: [layout_builder, views, media_library, webform, ui_icons]
  views:
    - id: frontpage
      label: Frontpage
      base_table: node_field_data
      content_type: article
      displays: [page_1, feed_1]
  taxonomies:
    - name: tags
      label: Tags
      used_by: [article]
  image_styles:
    - { name: thumbnail, width: 100, height: 100, ratio: "1:1", effect: scale_and_crop }
    - { name: medium, width: 220, height: 220, ratio: "1:1", effect: scale_and_crop }
    - { name: large, width: 480, height: null, ratio: null, effect: scale }
    - { name: wide, width: 1090, height: 0, ratio: null, effect: scale }
  responsive_image_styles: []

matches:
  - component: hero
    action: reuse
    entity_type: block_content
    entity_name: hero
    confidence: 1.0
    field_mapping:
      heading: field_headline
      body: field_body
      cta_url: field_link
  - component: blog
    action: reuse
    entity_type: node
    entity_name: article
    confidence: 0.85
    view_id: frontpage
    fields_to_add: []
  - component: pricing
    action: create_new
    recommendations:
      entity_type: block_content
      machine_name: pricing
      fields:
        - { name: field_tier_name, type: string }
        - { name: field_price, type: string }
        - { name: field_features, type: text_long, cardinality: -1 }
        - { name: field_cta_link, type: link }
```

## Green-Field Mode

When no `DRUPAL_PATH` is provided or `CONFIG_SYNC_DIR` does not exist:

- Skip the entire inventory scan
- Set `greenField: true` in the output
- All components get `action: "create_new"`
- Generate complete config recommendations for every component
- Recommend a full module list based on detected patterns:
  - Forms detected --> recommend `webform`
  - Icons detected --> recommend `ui_icons`
  - Images detected --> recommend `media_library`
  - Repeating content --> recommend `views` (usually already core)
  - Layout sections --> recommend `layout_builder`, `layout_builder_styles`
- Include a warning: "Green-field analysis -- all config generated from scratch, no existing backend to reuse"
