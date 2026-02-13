# Drupal Best Practices for Theme Generation

Mandatory rules for generating Radix sub-themes, SDC components, SCSS, JavaScript, and icon packs. These rules prevent common generation errors and ensure Drupal-compatible output.

## Contents

- SCSS Variable Discipline
  - Allowed Variables
  - Forbidden Patterns
  - Custom Values
- SDC Component Schema
  - Required Schema URL
  - Props vs Slots
  - Status Values
  - Component Usage Methods
- JavaScript Patterns
  - Drupal.behaviors Structure
  - once() API
  - Library Dependencies
- Icon API Pack Configuration
  - Pack File Location
  - Extractor Configuration
  - SDC Icon Integration
- Bootstrap SCSS Architecture
  - Import Order in _init.scss
  - Variable Override Strategy
  - Map Extensions
- Radix SDC Conventions
  - Component Replacement (Not Extension)
  - Utility Classes Pattern
  - Bootstrap Classes in Twig

## SCSS Variable Discipline

### Allowed Variables

Every component SCSS file MUST use Bootstrap SCSS variables. Never hardcode values that have a variable equivalent.

**Colors** -- use only these variables:

| Use This | Not This |
|---|---|
| `$primary` | `#0077C0` or any hex color |
| `$secondary` | `#E8634A` |
| `$body-color` | `#2D2926` or `#333` |
| `$body-bg` | `#FBF8F3` or `#fff` |
| `$white` | `white` or `#fff` |
| `$light` | `#f8f9fa` |
| `$dark` | `#212529` |
| `$gray-600` | `#6c757d` |
| `$text-muted` | any muted color literal |

**Typography** -- use only these variables:

| Use This | Not This |
|---|---|
| `$font-family-heading` | `'Fraunces', serif` or any font-family literal |
| `$font-family-base` | `'Epilogue', sans-serif` or any font-family literal |
| `$font-size-base` | `1rem` or `1.125rem` for base text |
| `$font-size-sm` | `0.875rem` |
| `$font-size-lg` | `1.25rem` |
| `$h1-font-size` | `2.5rem` for h1-level text |
| `$h2-font-size` | `2rem` |
| `$h3-font-size` | `1.5rem` |
| `$h4-font-size` | `1.25rem` |
| `$h5-font-size` | `1.125rem` |
| `$h6-font-size` | `1rem` |
| `$font-weight-bold` | `700` |
| `$font-weight-semibold` | `600` |
| `$font-weight-normal` | `400` |
| `$headings-font-weight` | `700` for heading elements |
| `$headings-line-height` | `1.2` for heading elements |
| `$line-height-base` | `1.5` or `1.6` for body text |

**Spacing** -- use only these variables:

| Use This | Not This |
|---|---|
| `$spacer` | `1rem` for the base unit |
| `$spacer * 2` | `2rem` or `32px` |
| `$border-radius` | `0.375rem` or `6px` |
| `$border-radius-lg` | `0.5rem` |
| `$box-shadow-sm` | `0 2px 8px rgba(...)` |
| `$box-shadow` | `0 4px 20px rgba(...)` |

**Transitions** -- use CSS custom properties from `_elements.scss`:

| Use This | Not This |
|---|---|
| `var(--transition-base)` | `0.3s` or `300ms` |
| `var(--transition-fast)` | `0.2s` or `200ms` |
| `var(--easing-default)` | `ease` or `cubic-bezier(...)` |
| `transition: color var(--transition-fast) var(--easing-default)` | `transition: color 0.2s ease` |

### Forbidden Patterns

These patterns MUST NOT appear in generated component SCSS:

1. **Theme-prefixed variables**: `$mytheme-primary`, `$mytheme-font-heading`. These do not exist in Bootstrap or Radix. Always use standard Bootstrap variables.

2. **Hex color literals**: `#0077C0`, `#333`, `#fff`. Always use the Bootstrap variable that holds that color value.

3. **Font-family literals**: `'Fraunces', serif`, `'Inter', sans-serif`. Always use `$font-family-heading` or `$font-family-base`.

4. **Hardcoded font-size**: `font-size: 2.5rem`. Use `$h1-font-size` or the appropriate level variable. For sizes between levels, use `calc()` with variables or define in `_variables.scss`.

5. **Hardcoded font-weight**: `font-weight: 700`. Use `$font-weight-bold` or `$headings-font-weight`.

6. **Hardcoded transition timing**: `transition: all 0.3s ease`. Use CSS custom properties.

### Custom Values

When a component needs a value not covered by Bootstrap variables:

1. Check `_variables.scss` for a brand-specific variable first.
2. Use `calc()` with existing variables: `font-size: calc($font-size-base * 0.9375)`.
3. Use CSS custom properties defined in `_elements.scss`.
4. Only as last resort, use a literal value with a comment explaining why no variable applies.

For line-height, some custom values are acceptable when optimizing for specific content types:
- `line-height: 1.8` for long-form reading content.
- `line-height: 1` for numeric display values.
- Always prefer `$line-height-base` or `$headings-line-height` when the value matches.

## SDC Component Schema

### Required Schema URL

Every `component.yml` file MUST use the Drupal 11 stable schema URL:

```yaml
$schema: https://git.drupalcode.org/project/drupal/-/raw/HEAD/core/assets/schemas/v1/metadata.schema.json
```

Do NOT use the old experimental path (`core/modules/sdc/src/component.schema.json`). That path is from Drupal 10.x when SDC was experimental.

### Props vs Slots

**Props** are for typed, structured data that controls component behavior:
- Configuration values (boolean, enum, number).
- Text strings for display.
- URLs and image paths.
- Validated via JSON Schema.

**Slots** are for unstructured, renderable content:
- Drupal render arrays.
- Nested components.
- HTML markup.
- Accessed via `{% block slot_name %}` in Twig.

SDC does not support preprocessing. All data transformation must happen through props or in the calling context.

### Status Values

Valid values: `experimental`, `stable`, `deprecated`, `obsolete`.

Use `experimental` for newly generated components. Switch to `stable` after testing.

### Component Usage Methods

- **`include()`** -- for props-only usage (most common).
- **`embed` with `block`** -- when populating slots.
- **Render arrays** -- for programmatic usage in PHP.

```twig
{# Props only -- use include #}
{{ include('theme:button', { label: 'Click', variant: 'primary' }, with_context = false) }}

{# With slots -- use embed #}
{% embed 'theme:card' with { title: 'Title' } only %}
  {% block content %}
    <p>Card content</p>
  {% endblock %}
{% endembed %}
```

Do NOT use `{% set %}` to create slot content. Slots are Twig blocks, not variables.

## JavaScript Patterns

### Drupal.behaviors Structure

All theme JavaScript MUST use the `Drupal.behaviors` pattern:

```javascript
(function (Drupal, once) {
  'use strict';

  Drupal.behaviors.themeBehaviorName = {
    attach: function (context) {
      once('unique-id', '.selector', context).forEach(function (element) {
        // Process element
      });
    },
  };

})(Drupal, once);
```

Requirements:
1. Wrap in IIFE with `Drupal` and `once` parameters.
2. Use `'use strict'`.
3. Behavior name should be camelCase, prefixed with theme name.
4. Always use the `context` parameter in DOM queries -- never use global selectors.
5. Always use `once()` to prevent duplicate processing on AJAX page updates.

### once() API

The `once()` function from `core/once` ensures elements are processed only once, even when `Drupal.behaviors.attach` runs multiple times (AJAX, BigPipe, etc.):

```javascript
// Process elements matching selector within context, only once
once('unique-identifier', '.css-selector', context).forEach(function (element) {
  element.addEventListener('click', handler);
});
```

The first argument is a unique string identifier. Use descriptive names: `'scroll-reveal'`, `'mobile-menu'`, etc.

### Library Dependencies

Theme global library MUST declare:

```yaml
global:
  css:
    theme:
      build/css/main.style.css: {}
  js:
    build/js/main.script.js: {}
  dependencies:
    - radix/bootstrap
    - core/drupal
    - core/once
```

`core/once` is required whenever JavaScript uses the `once()` function.

## Icon API Pack Configuration

### Pack File Location

The `.icons.yml` file MUST be at the theme root, at the same level as `.info.yml`:

```
theme_name/
  theme_name.info.yml
  theme_name.icons.yml    <-- here
  icons/                  <-- SVG files
    arrow-right.svg
    heart.svg
```

### Extractor Configuration

For brand icons extracted from HTML designs, use the `svg` extractor:

```yaml
theme_name_icons:
  label: 'Theme Label Icons'
  description: 'Brand icons extracted from design system'
  extractor: svg
  enabled: true
  template: >-
    <svg xmlns="http://www.w3.org/2000/svg"
         width="{{ size }}"
         height="{{ size }}"
         viewBox="0 0 24 24"
         fill="none"
         stroke="currentColor"
         stroke-width="2"
         stroke-linecap="round"
         stroke-linejoin="round">{{ content }}</svg>
  config:
    sources:
      - icons/
    size: 24
```

Key points:
- Use `stroke="currentColor"` so icons inherit text color.
- `{{ content }}` inserts the SVG paths (without the outer `<svg>` wrapper).
- The `sources` array lists directories or glob patterns.

### SDC Icon Integration

Two approaches for icons in SDC components:

**Object prop** (when icon is data-driven):
```yaml
props:
  type: object
  properties:
    icon:
      type: object
      properties:
        pack_id:
          type: string
          default: "theme_name"
        icon_id:
          type: string
```

```twig
{% if icon and icon.icon_id %}
  {{ icon(icon.pack_id|default('theme_name'), icon.icon_id) }}
{% endif %}
```

**Slot** (when icon content is complex or externally provided):
```yaml
slots:
  icon:
    title: Icon Content
```

```twig
{% if icon %}
  <div class="component__icon">{{ icon }}</div>
{% endif %}
```

## Bootstrap SCSS Architecture

### Import Order in _init.scss

This order is critical -- custom variables MUST come before Bootstrap defaults:

```scss
// 1. Bootstrap functions (needed for variable manipulation)
@import '~bootstrap/scss/functions';

// 2. Custom variables -- BEFORE Bootstrap defaults
@import 'base/variables';

// 3. Bootstrap variables (use !default, so custom overrides win)
@import '~bootstrap/scss/variables';
@import '~bootstrap/scss/variables-dark';

// 4. Bootstrap maps, mixins, utilities
@import '~bootstrap/scss/maps';
@import '~bootstrap/scss/mixins';
@import '~bootstrap/scss/utilities';
```

Why this order matters: Bootstrap's `_variables.scss` uses `!default` on every variable. If `_variables` is imported before Bootstrap, our values take precedence. If imported after, Bootstrap's defaults overwrite ours.

### Variable Override Strategy

In `_variables.scss`, override Bootstrap variables directly:

```scss
// Override -- Bootstrap's $primary defaults to #0d6efd, ours replaces it
$primary: #0077C0;

// Extend -- add to existing Bootstrap map
$custom-colors: (
  "primary-dark": $primary-dark,
);
```

Do NOT create variables with theme-specific prefixes. Bootstrap's variable system is the single source of truth for all SCSS values.

### Map Extensions

Extend Bootstrap maps (like `$spacers`, `$theme-colors`) using `map-merge`:

```scss
// In _variables.scss -- define the values
$spacers: (
  6: $spacer * 4,
  7: $spacer * 6,
);

// The actual merge happens after Bootstrap maps are loaded (in _init.scss or a post-map partial)
```

## Radix SDC Conventions

### Component Replacement (Not Extension)

SDC components cannot be extended or inherited. To customize a Radix base component:

1. Copy the entire component directory from Radix to your sub-theme.
2. Place it in the appropriate atomic directory (`atoms/`, `molecules/`, `organisms/`).
3. Modify the template, SCSS, and schema as needed.
4. Drupal's SDC discovery automatically uses the sub-theme version.

For component.yml, the `replaces` directive makes this explicit:
```yaml
replaces: 'radix:card'
```

### Utility Classes Pattern

Every component MUST include a `*_utility_classes` array prop:

```yaml
{component_name}_utility_classes:
  type: array
  items:
    type: string
  default: []
```

Merge into the outermost element's class list:

```twig
{% set classes = [
  'component-name',
  'component-name--' ~ (variant ?? 'default'),
]|merge(component_name_utility_classes ?? [])
|filter(c => c is not empty) %}

<div{{ attributes.addClass(classes) }}>
```

### Bootstrap Classes in Twig

Use Bootstrap utility classes directly in Twig for layout and spacing. Reserve SCSS for brand-specific styling only:

```twig
{# Layout with Bootstrap utilities #}
<div class="d-flex align-items-center gap-3 mb-4">
  <div class="flex-shrink-0">{{ icon }}</div>
  <div class="flex-grow-1">{{ content }}</div>
</div>

{# Grid with Bootstrap #}
<div class="row g-4">
  {% for item in items %}
    <div class="col-12 col-md-4">{{ item }}</div>
  {% endfor %}
</div>
```

Use responsive breakpoint mixins in SCSS when CSS-only responsive changes are needed:

```scss
.component {
  padding: $spacer * 2;

  @include media-breakpoint-up(md) {
    padding: $spacer * 3;
  }
}
```
