# Radix 6.0.2 Sub-Theme Scaffold

> **Note**: This reference is for understanding the structure. When `DRUPAL_PATH` is available, use `drush --include="themes/contrib/radix" radix:create {THEME_NAME} "{THEME_LABEL}"` instead of generating the scaffold manually. Only overlay customizations (variables, typography, elements) on top of the CLI-generated scaffold.

Complete file templates matching the real Radix 6.0.2 starterkit. Replace `{THEME_NAME}` with the machine name (lowercase, underscores) and `{THEME_LABEL}` with the human-readable label.

## 1. Directory Structure

```
{THEME_NAME}/
├── {THEME_NAME}.info.yml
├── {THEME_NAME}.libraries.yml
├── {THEME_NAME}.icons.yml              # Only when icons found
├── {THEME_NAME}.theme                  # Auto-loader for includes/
├── webpack.mix.js
├── package.json
├── .env.example
├── .nvmrc
├── .npmrc
├── .browserslistrc
├── biome.json
├── .stylelintrc.json
├── .gitignore
├── components/                         # Flat — NO atomic subdirs
│   └── {name}/
│       ├── {name}.twig
│       ├── {name}.yml                  # SDC schema
│       ├── __{name}.scss
│       └── _{name}.js                  # Underscore prefix convention
├── src/
│   ├── scss/
│   │   ├── main.style.scss
│   │   ├── _init.scss
│   │   ├── _bootstrap.scss
│   │   └── base/
│   │       ├── _variables.scss         # Loaded BEFORE Bootstrap functions
│   │       ├── _mixins.scss
│   │       ├── _utilities.scss
│   │       ├── _typography.scss
│   │       ├── _elements.scss
│   │       ├── _drupal-overrides.scss
│   │       ├── _functions.scss
│   │       └── _helpers.scss
│   ├── js/
│   │   └── main.script.js
│   └── assets/
│       ├── images/
│       ├── icons/
│       └── fonts/
├── templates/
│   └── layout/
├── includes/
├── config/
└── build/                              # Gitignored
```

## 2. File Templates

### {THEME_NAME}.info.yml

```yaml
name: '{THEME_LABEL}'
description: '{THEME_LABEL} theme based on Radix 6.x and Bootstrap 5.x'
core_version_requirement: ^10.3 || ^11
type: theme
base theme: radix
regions:
  navbar_branding: Navbar branding
  navbar_left: Navbar left
  navbar_right: Navbar right
  header: Header
  content: Content
  page_bottom: Page bottom
  footer: Footer
libraries:
  - {THEME_NAME}/style
ckeditor5-stylesheets:
  - build/css/main.style.css
```

### {THEME_NAME}.libraries.yml

Library name is `style` (not `global`).

```yaml
style:
  css:
    theme:
      build/css/main.style.css: {}
  js:
    build/js/main.script.js: {}
  dependencies:
    - core/drupal
```

### {THEME_NAME}.icons.yml (conditional)

Generate only when the analysis found icons. Uses Drupal Core Icon API with SVG extractor.

```yaml
{THEME_NAME}_icons:
  label: '{THEME_LABEL} Icons'
  description: 'Brand icons extracted from design system'
  extractor: svg
  enabled: true
  template: '<svg xmlns="http://www.w3.org/2000/svg" width="{{ size }}" height="{{ size }}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">{{ content }}</svg>'
  config:
    sources:
      - src/assets/icons/
    size: 24
```

### {THEME_NAME}.theme

Create always, even when `includes/` is initially empty.

```php
<?php
/**
 * @file
 * Theme functions.
 */
// Include all files from the includes directory.
$includes_path = __DIR__ . '/includes/*.theme';
foreach (glob($includes_path) as $file) {
  require_once __DIR__ . '/includes/' . basename($file);
}
```

### webpack.mix.js

```js
const mix = require('laravel-mix');
const dotenv = require('dotenv');
dotenv.config({ path: '.env.local' });

const proxy = process.env.DRUPAL_BASE_URL || 'https://SITE.ddev.site';

// SCSS compilation.
mix
  .sass('src/scss/main.style.scss', 'build/css', {
    sassOptions: { includePaths: ['node_modules'] },
  })
  .options({
    processCssUrls: false,
    postCss: [require('autoprefixer')],
  });

// JS compilation.
mix.js('src/js/main.script.js', 'build/js');

// Component JS — underscore prefix convention: _name.js → name.js.
const glob = require('glob');
const componentScripts = glob.sync('components/**/_{*.js,*.js}');
componentScripts.forEach((script) => {
  const outputName = script
    .replace(/\/_/, '/')
    .replace('components/', 'build/js/components/');
  mix.js(script, outputName);
});

// Copy watched assets to build/.
mix.copyDirectory('src/assets/images', 'build/assets/images');
mix.copyDirectory('src/assets/icons', 'build/assets/icons');
mix.copyDirectory('src/assets/fonts', 'build/assets/fonts');

// BrowserSync.
mix.browserSync({
  proxy: proxy,
  files: ['templates/**/*.twig', 'components/**/*.twig', 'build/**/*'],
  stream: true,
});

// Note: Do NOT use mix.version() -- it breaks asset paths in Drupal.
// Drupal handles cache busting via ?v= query strings on aggregated CSS/JS.
```

### package.json

```json
{
  "name": "{THEME_NAME}",
  "version": "1.0.0",
  "description": "{THEME_LABEL} theme based on Radix 6.x and Bootstrap 5.x",
  "private": true,
  "scripts": {
    "dev": "npx mix watch",
    "build": "npx mix --production",
    "watch": "npx mix watch",
    "lint": "npx stylelint 'src/scss/**/*.scss' 'components/**/*.scss'",
    "format": "npx @biomejs/biome format --write src/js/ components/"
  },
  "devDependencies": {
    "@biomejs/biome": "^1.9",
    "@popperjs/core": "^2.11",
    "autoprefixer": "^10.4",
    "bootstrap": "^5.3",
    "browser-sync": "^3.0",
    "browser-sync-webpack-plugin": "^2.3",
    "cross-env": "^7.0",
    "dotenv": "^16.4",
    "drupal-radix-cli": "^1.0",
    "glob": "^10.3",
    "laravel-mix": "^6.0",
    "postcss": "^8.4",
    "sass": "^1.77",
    "sass-loader": "^14.0",
    "stylelint": "^16.0",
    "stylelint-config-standard-scss": "^13.0"
  }
}
```

### src/scss/main.style.scss

```scss
@import "init";
@import "bootstrap";
@import "base/drupal-overrides";
@import "base/elements";
@import "base/functions";
@import "base/helpers";
@import "base/typography";
```

### src/scss/_init.scss

Custom variables load BEFORE Bootstrap functions. This is the real Radix 6.0.2 init order.

```scss
// Custom overrides
@import "base/variables";

// 1. Include functions first
@import "~bootstrap/scss/functions";

// 3. Include remainder of required Bootstrap stylesheets
@import "~bootstrap/scss/variables";
@import "~bootstrap/scss/variables-dark";

// 5. Include remainder of required parts
@import "~bootstrap/scss/maps";

// Merge custom colors into $theme-colors AFTER maps are loaded
$theme-colors: map-merge($theme-colors, $custom-colors);

@import "~bootstrap/scss/utilities";
@import "~bootstrap/scss/mixins";
@import "~bootstrap/scss/root";

// Radix specific parts
@import "base/mixins";
@import "base/utilities";

// Optionally include any other parts
@import "~bootstrap/scss/vendor/rfs";
```

### src/scss/_bootstrap.scss

Placeholders commented out (buggy with Drupal). Helpers and utilities/api at end.

Note: Do NOT import `~bootstrap/scss/utilities` or `~bootstrap/scss/root` here -- they are already imported in `_init.scss`. Duplicating them causes compilation errors.

```scss
@import "~bootstrap/scss/reboot";
@import "~bootstrap/scss/type";
@import "~bootstrap/scss/images";
@import "~bootstrap/scss/containers";
@import "~bootstrap/scss/grid";
@import "~bootstrap/scss/tables";
@import "~bootstrap/scss/forms";
@import "~bootstrap/scss/buttons";
@import "~bootstrap/scss/transitions";
@import "~bootstrap/scss/dropdown";
@import "~bootstrap/scss/button-group";
@import "~bootstrap/scss/nav";
@import "~bootstrap/scss/navbar";
@import "~bootstrap/scss/card";
@import "~bootstrap/scss/accordion";
@import "~bootstrap/scss/breadcrumb";
@import "~bootstrap/scss/pagination";
@import "~bootstrap/scss/badge";
@import "~bootstrap/scss/alert";
@import "~bootstrap/scss/progress";
@import "~bootstrap/scss/list-group";
@import "~bootstrap/scss/close";
@import "~bootstrap/scss/toasts";
@import "~bootstrap/scss/modal";
@import "~bootstrap/scss/tooltip";
@import "~bootstrap/scss/popover";
@import "~bootstrap/scss/carousel";
@import "~bootstrap/scss/spinners";
@import "~bootstrap/scss/offcanvas";
// @import "~bootstrap/scss/placeholders"; // Buggy with Drupal
@import "~bootstrap/scss/helpers";
@import "~bootstrap/scss/utilities/api";
```

### src/scss/base/_variables.scss

Populate with actual values from the design tokens. Supported variable groups:

- **Colors**: `$primary`, `$secondary`, `$success`, `$info`, `$warning`, `$danger`, `$light`, `$dark`, `$body-bg`, `$body-color`. Extend with `$custom-colors` map merged into `$theme-colors`.
- **Typography**: `$font-family-base`, `$font-family-heading` (Radix convention), `$font-size-base`, `$h1`-`$h6-font-size`, `$headings-font-weight`, `$headings-line-height`.
- **Spacing**: `$spacer`.
- **Border radius**: `$border-radius`, `$border-radius-sm`, `$border-radius-lg`.
- **Containers**: `$container-max-widths` map.
- **Custom properties**: Tokens with no Bootstrap equivalent go in `:root` in `_elements.scss`.

### src/scss/base/_elements.scss

```scss
// Global Element Styles — overrides beyond Bootstrap Reboot.

:root {
  // Tokens with no Bootstrap equivalent:
  // --transition-base: 300ms;
  // --transition-fast: 150ms;
  // --easing-default: cubic-bezier(0.4, 0, 0.2, 1);
  // --min-tap-target: 44px;
}

body {
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
}

a {
  transition: color var(--transition-base, 300ms) var(--easing-default, ease);
  &:hover { text-decoration-thickness: 2px; }
  &:focus-visible {
    outline: 2px solid $primary;
    outline-offset: 2px;
  }
}

img { max-width: 100%; height: auto; }

button,
.btn {
  transition: all var(--transition-base, 300ms) var(--easing-default, ease);
}

section {
  padding-block: $spacer * 4;
  @include media-breakpoint-up(lg) { padding-block: $spacer * 6; }
}
```

### src/scss/base/_typography.scss

Contains `@font-face` declarations. Use Google Fonts `@import` or self-hosted `@font-face` (place `.woff2` files in `src/assets/fonts/`). Always include heading font-family assignment:

```scss
h1, h2, h3, h4, h5, h6,
.h1, .h2, .h3, .h4, .h5, .h6 {
  font-family: $font-family-heading;
}
```

### Empty base partials

Create each of these files with a single comment line describing its purpose:

| File | Content |
|------|---------|
| `base/_mixins.scss` | `// Custom theme mixins. Available after Radix base mixins in _init.` |
| `base/_utilities.scss` | `// Custom utility classes. Extend Bootstrap $utilities map here.` |
| `base/_drupal-overrides.scss` | `// Drupal admin toolbar, contextual links, Layout Builder fixes.` |
| `base/_functions.scss` | `// Custom SCSS functions.` |
| `base/_helpers.scss` | `// Helper classes specific to this theme.` |

### src/js/main.script.js

```js
/**
 * @file
 * Theme JS entry point.
 */
(function (Drupal, once) {
  'use strict';

  Drupal.behaviors.scrollReveal = {
    attach: function (context) {
      once('scroll-reveal', '[data-reveal]', context).forEach(function (element) {
        if (!('IntersectionObserver' in window)) {
          element.classList.add('is-revealed');
          return;
        }
        var observer = new IntersectionObserver(
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
        observer.observe(element);
      });
    },
  };
})(Drupal, once);
```

### templates/layout/layout--onecol.html.twig

Nested container pattern: outer div is full-width (receives `layout_builder_styles`), inner `.container` constrains content.

```twig
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

### Config files

| File | Content |
|------|---------|
| `.env.example` | `DRUPAL_BASE_URL=https://SITE.ddev.site` |
| `.nvmrc` | `22` |
| `.npmrc` | `package-lock=true` |
| `.browserslistrc` | `defaults` + newline + `not IE 11` |

**biome.json** — Biome formatter with 2-space indent, single quotes, trailing commas, semicolons:
```json
{"$schema":"https://biomejs.dev/schemas/1.9.0/schema.json","organizeImports":{"enabled":true},"formatter":{"indentStyle":"space","indentWidth":2,"lineWidth":100},"javascript":{"formatter":{"quoteStyle":"single","trailingCommas":"all","semicolons":"always"}}}
```

**.stylelintrc.json** — Standard SCSS config with relaxed rules for Drupal:
```json
{"extends":"stylelint-config-standard-scss","rules":{"selector-class-pattern":null,"scss/at-import-partial-extension":null,"scss/dollar-variable-pattern":null,"no-descending-specificity":null}}
```

### .gitignore

```
node_modules/
build/
.env.local
```

## 3. Component Conventions

**SCSS import** — 2 levels up from `components/{name}/`:
```scss
// In components/{name}/__{name}.scss
@import "../../src/scss/init";
.{name} { /* Component styles */ }
```

**JS naming** — underscore prefix stripped during compilation:

| Source | Compiled |
|--------|----------|
| `components/hero/_hero.js` | `build/js/components/hero/hero.js` |
