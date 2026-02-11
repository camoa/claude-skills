# Radix 6.0.2 Sub-Theme Scaffold

Complete directory structure and file templates for a Radix sub-theme generated from a brand design system. Replace `{THEME_NAME}` with the machine name (lowercase, underscores) and `{THEME_LABEL}` with the human-readable label.

## Contents

- Theme Directory Structure
- File Templates

## Theme Directory Structure

```
{THEME_NAME}/
├── {THEME_NAME}.info.yml
├── {THEME_NAME}.libraries.yml
├── {THEME_NAME}.icons.yml          # If icon pack generated
├── webpack.mix.js
├── package.json
├── components/
│   ├── atoms/
│   ├── molecules/
│   └── organisms/
├── icons/                           # SVG icon files
├── src/
│   ├── scss/
│   │   ├── main.style.scss          # Entry point
│   │   ├── _init.scss               # Foundation (zero CSS output)
│   │   ├── _bootstrap.scss          # Bootstrap module imports
│   │   └── base/
│   │       ├── _variables.scss      # Bootstrap variable overrides
│   │       ├── _elements.scss       # Global element styles
│   │       └── _typography.scss     # @font-face declarations
│   └── js/
│       └── main.script.js           # Theme JS entry
├── templates/
│   └── layout/                      # Layout Builder section overrides
├── includes/
│   └── {THEME_NAME}.theme           # Preprocess functions
└── build/                           # Compiled output (gitignored)
```

## File Templates

### {THEME_NAME}.info.yml

```yaml
name: '{THEME_LABEL}'
type: theme
description: 'Radix sub-theme generated from brand design system'
core_version_requirement: ^10.3 || ^11
base theme: radix
starterkit: false

regions:
  navbar_top: 'Navbar Top'
  navbar_main: 'Navbar Main'
  header: 'Header'
  highlighted: 'Highlighted'
  help: 'Help'
  content: 'Content'
  sidebar_first: 'Sidebar First'
  sidebar_second: 'Sidebar Second'
  footer: 'Footer'
  page_top: 'Page Top'
  page_bottom: 'Page Bottom'

libraries:
  - {THEME_NAME}/global
```

### {THEME_NAME}.libraries.yml

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
```

### {THEME_NAME}.icons.yml

Generate only when the analysis found icons to extract.

```yaml
{THEME_NAME}_icons:
  label: '{THEME_LABEL} Icons'
  description: 'Brand icons extracted from design system'
  extractor: svg
  enabled: true
  template: '<svg xmlns="http://www.w3.org/2000/svg" width="{{ size }}" height="{{ size }}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">{{ content }}</svg>'
  config:
    sources:
      - icons/
    size: 24
```

### webpack.mix.js

```js
const mix = require('laravel-mix');

// Paths
const proxy = 'https://SITE.ddev.site';
const themePath = 'themes/custom/{THEME_NAME}';

// SCSS compilation
mix.sass(`${themePath}/src/scss/main.style.scss`, `${themePath}/build/css`)
  .options({ processCssUrls: false });

// JS compilation
mix.js(`${themePath}/src/js/main.script.js`, `${themePath}/build/js`);

// BrowserSync for live reload
mix.browserSync({
  proxy,
  files: [
    `${themePath}/**/*.twig`,
    `${themePath}/build/**/*`,
  ],
});
```

### package.json

```json
{
  "name": "{THEME_NAME}",
  "version": "1.0.0",
  "description": "Radix sub-theme generated from brand design system",
  "private": true,
  "scripts": {
    "dev": "npx mix watch",
    "build": "npx mix --production",
    "watch": "npx mix watch"
  },
  "devDependencies": {
    "bootstrap": "^5.3",
    "laravel-mix": "^6.0",
    "sass": "^1.77",
    "sass-loader": "^14.0",
    "resolve-url-loader": "^5.0"
  }
}
```

### src/scss/main.style.scss

```scss
// Foundation -- zero CSS output, provides vars + mixins
@import 'init';

// Bootstrap modules
@import 'bootstrap';

// Base
@import 'base/elements';
@import 'base/typography';
```

### src/scss/_init.scss

```scss
// 1. Bootstrap functions (needed for variable manipulation)
@import '~bootstrap/scss/functions';

// 2. Custom variables -- BEFORE Bootstrap defaults so ours take precedence
@import 'base/variables';

// 3. Bootstrap variables (use !default, so custom overrides win)
@import '~bootstrap/scss/variables';
@import '~bootstrap/scss/variables-dark';

// 4. Bootstrap maps, mixins, utilities
@import '~bootstrap/scss/maps';
@import '~bootstrap/scss/mixins';
@import '~bootstrap/scss/utilities';
```

### src/scss/_bootstrap.scss

```scss
// Bootstrap modules -- import only what the theme needs.
// Comment out unused modules to reduce CSS output.

@import '~bootstrap/scss/root';
@import '~bootstrap/scss/reboot';
@import '~bootstrap/scss/type';
@import '~bootstrap/scss/images';
@import '~bootstrap/scss/containers';
@import '~bootstrap/scss/grid';
@import '~bootstrap/scss/tables';
@import '~bootstrap/scss/forms';
@import '~bootstrap/scss/buttons';
@import '~bootstrap/scss/transitions';
@import '~bootstrap/scss/dropdown';
@import '~bootstrap/scss/button-group';
@import '~bootstrap/scss/nav';
@import '~bootstrap/scss/navbar';
@import '~bootstrap/scss/card';
@import '~bootstrap/scss/accordion';
@import '~bootstrap/scss/breadcrumb';
@import '~bootstrap/scss/pagination';
@import '~bootstrap/scss/badge';
@import '~bootstrap/scss/alert';
@import '~bootstrap/scss/progress';
@import '~bootstrap/scss/list-group';
@import '~bootstrap/scss/close';
@import '~bootstrap/scss/toasts';
@import '~bootstrap/scss/modal';
@import '~bootstrap/scss/tooltip';
@import '~bootstrap/scss/popover';
@import '~bootstrap/scss/carousel';
@import '~bootstrap/scss/spinners';
@import '~bootstrap/scss/offcanvas';
@import '~bootstrap/scss/placeholders';
@import '~bootstrap/scss/helpers';
@import '~bootstrap/scss/utilities/api';
```

### src/scss/base/_variables.scss

```scss
// ==========================================================================
// Bootstrap Variable Overrides
// Generated from brand design tokens via the converter.
// Values placed here override Bootstrap defaults because _init.scss
// imports this file BEFORE Bootstrap's own _variables.scss.
// ==========================================================================

// --------------------------------------------------------------------------
// Colors
// --------------------------------------------------------------------------
// $primary:       #CONVERTER_VALUE;
// $secondary:     #CONVERTER_VALUE;
// $success:       #CONVERTER_VALUE;
// $info:          #CONVERTER_VALUE;
// $warning:       #CONVERTER_VALUE;
// $danger:        #CONVERTER_VALUE;
// $light:         #CONVERTER_VALUE;
// $dark:          #CONVERTER_VALUE;
// $body-bg:       #CONVERTER_VALUE;
// $body-color:    #CONVERTER_VALUE;

// Extend $theme-colors map with custom brand colors:
// $custom-colors: (
//   "accent":  $accent,
//   "bg-alt":  $bg-alt,
// );
// $theme-colors: map-merge($theme-colors, $custom-colors);

// --------------------------------------------------------------------------
// Typography
// --------------------------------------------------------------------------
// $font-family-base:    'CONVERTER_BODY_FONT', sans-serif;
// $font-family-heading: 'CONVERTER_HEADING_FONT', sans-serif;  // Radix convention
// $font-size-base:      1rem;
// $font-size-sm:        $font-size-base * 0.875;
// $font-size-lg:        $font-size-base * 1.25;

// $h1-font-size:        $font-size-base * 2.5;
// $h2-font-size:        $font-size-base * 2;
// $h3-font-size:        $font-size-base * 1.75;
// $h4-font-size:        $font-size-base * 1.5;
// $h5-font-size:        $font-size-base * 1.25;
// $h6-font-size:        $font-size-base;

// $line-height-base:    1.5;
// $headings-font-weight: 700;
// $headings-line-height: 1.2;

// --------------------------------------------------------------------------
// Spacing
// --------------------------------------------------------------------------
// $spacer: 1rem;
// $spacers: map-merge($spacers, (
//   6: $spacer * 4,
//   7: $spacer * 5,
//   8: $spacer * 6,
// ));

// --------------------------------------------------------------------------
// Border Radius
// --------------------------------------------------------------------------
// $border-radius:    0.375rem;
// $border-radius-sm: 0.25rem;
// $border-radius-lg: 0.5rem;
// $border-radius-xl: 1rem;

// --------------------------------------------------------------------------
// Container Widths
// --------------------------------------------------------------------------
// $container-max-widths: (
//   sm:  540px,
//   md:  720px,
//   lg:  960px,
//   xl:  1140px,
//   xxl: 1320px,
// );

// --------------------------------------------------------------------------
// Custom Properties (no Bootstrap equivalent)
// --------------------------------------------------------------------------
// Add brand tokens that don't map to any Bootstrap variable as
// CSS custom properties via the :root rule in _elements.scss.
```

### src/scss/base/_elements.scss

```scss
// ==========================================================================
// Global Element Styles
// Base HTML element overrides beyond Bootstrap's Reboot.
// ==========================================================================

:root {
  // Custom properties for tokens with no Bootstrap equivalent
  // --transition-duration: CONVERTER_VALUE;
  // --transition-easing: CONVERTER_VALUE;
  // --min-tap-target: CONVERTER_VALUE;
}

body {
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
}

a {
  transition: color var(--transition-duration, 0.2s) var(--transition-easing, ease);

  &:hover {
    text-decoration-thickness: 2px;
  }

  &:focus-visible {
    outline: 2px solid $primary;
    outline-offset: 2px;
  }
}

img {
  max-width: 100%;
  height: auto;
}

button,
.btn {
  transition: all var(--transition-duration, 0.2s) var(--transition-easing, ease);
}

section {
  padding-block: $spacer * 4;

  @include media-breakpoint-up(lg) {
    padding-block: $spacer * 6;
  }
}
```

### src/scss/base/_typography.scss

```scss
// ==========================================================================
// Typography -- @font-face declarations and web font imports
// ==========================================================================

// Option A: Google Fonts via @import (simplest)
// @import url('https://fonts.googleapis.com/css2?family=HEADING_FONT:wght@400;700&family=BODY_FONT:wght@400;500;700&display=swap');

// Option B: Self-hosted @font-face (better performance, GDPR-friendly)
// Download fonts and place in {THEME_NAME}/fonts/ directory.
//
// @font-face {
//   font-family: 'HEADING_FONT';
//   src: url('../fonts/heading-font-bold.woff2') format('woff2');
//   font-weight: 700;
//   font-style: normal;
//   font-display: swap;
// }
//
// @font-face {
//   font-family: 'BODY_FONT';
//   src: url('../fonts/body-font-regular.woff2') format('woff2');
//   font-weight: 400;
//   font-style: normal;
//   font-display: swap;
// }

// Heading styles
h1, h2, h3, h4, h5, h6,
.h1, .h2, .h3, .h4, .h5, .h6 {
  font-family: $font-family-heading;
}
```

### src/js/main.script.js

```js
/**
 * @file
 * Theme JS entry point.
 */

(function (Drupal) {
  'use strict';

  /**
   * Scroll reveal observer -- fade in elements as they enter the viewport.
   *
   * Add the attribute `data-reveal` to any element that should animate in.
   * The class `is-revealed` is added once the element is 15% visible.
   */
  Drupal.behaviors.scrollReveal = {
    attach: function (context) {
      const elements = context.querySelectorAll('[data-reveal]:not(.is-revealed)');
      if (!elements.length || !('IntersectionObserver' in window)) {
        return;
      }

      const observer = new IntersectionObserver(
        function (entries) {
          entries.forEach(function (entry) {
            if (entry.isIntersecting) {
              entry.target.classList.add('is-revealed');
              observer.unobserve(entry.target);
            }
          });
        },
        { threshold: 0.15 }
      );

      elements.forEach(function (el) {
        observer.observe(el);
      });
    },
  };

})(Drupal);
```

### templates/layout/layout--onecol.html.twig

```twig
{#
/**
 * @file
 * One-column Layout Builder section override.
 *
 * Nested container pattern:
 *   - Outer div: full viewport width (receives background styles from
 *     layout_builder_styles module).
 *   - Inner .container: constrains content to max-width.
 */
#}
{% set container_classes = ['layout', 'layout--onecol'] %}

<div{{ attributes.addClass(container_classes) }}>
  <div class="container">
    <div{{ content_attributes.addClass('layout__content') }}>
      {{ content.content }}
    </div>
  </div>
</div>
```

### templates/layout/layout--twocol-section.html.twig

```twig
{#
/**
 * @file
 * Two-column Layout Builder section override.
 */
#}
{% set container_classes = ['layout', 'layout--twocol-section'] %}

<div{{ attributes.addClass(container_classes) }}>
  <div class="container">
    <div class="row">
      <div{{ region_attributes.first.addClass('layout__region', 'layout__region--first', 'col-12', 'col-md-6') }}>
        {{ content.first }}
      </div>
      <div{{ region_attributes.second.addClass('layout__region', 'layout__region--second', 'col-12', 'col-md-6') }}>
        {{ content.second }}
      </div>
    </div>
  </div>
</div>
```

### templates/layout/layout--threecol-section.html.twig

```twig
{#
/**
 * @file
 * Three-column Layout Builder section override.
 */
#}
{% set container_classes = ['layout', 'layout--threecol-section'] %}

<div{{ attributes.addClass(container_classes) }}>
  <div class="container">
    <div class="row">
      <div{{ region_attributes.first.addClass('layout__region', 'layout__region--first', 'col-12', 'col-md-4') }}>
        {{ content.first }}
      </div>
      <div{{ region_attributes.second.addClass('layout__region', 'layout__region--second', 'col-12', 'col-md-4') }}>
        {{ content.second }}
      </div>
      <div{{ region_attributes.third.addClass('layout__region', 'layout__region--third', 'col-12', 'col-md-4') }}>
        {{ content.third }}
      </div>
    </div>
  </div>
</div>
```

### includes/{THEME_NAME}.theme

```php
<?php

/**
 * @file
 * Theme preprocess functions for {THEME_LABEL}.
 */

/**
 * Implements hook_preprocess_HOOK() for page templates.
 */
function {THEME_NAME}_preprocess_page(array &$variables): void {
  // Add theme-specific variables to page template.
}

/**
 * Implements hook_preprocess_HOOK() for node templates.
 */
function {THEME_NAME}_preprocess_node(array &$variables): void {
  // Add node-level preprocessing.
}
```

### .gitignore

```
node_modules/
build/
```
