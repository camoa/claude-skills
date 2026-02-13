# Changelog

All notable changes to the design-system-converter plugin.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-02-13

### Added
- **Plugin**: Extracted from brand-content-design v2.2.0 as a standalone converter plugin
- **Router skill** (`design-system-converter`): Routes conversion requests, documents guide ecosystem
- **Analyzer skill** (`html-to-radix-analyzer`): Parses HTML metadata comments, classifies patterns, extracts design tokens, inventories Drupal backend, generates template suggestions
- **Generator skill** (`radix-sdc-generator`): Generates complete Radix 6.0.2 sub-theme with SDC components, template overrides, and Layout Builder config
- **Commands**: `/convert-to-radix` (guided 7-phase wizard) and `/convert-to-radix-quick` (3-question quick mode)
- **Script**: `extract-icons.js` for inline SVG extraction from HTML to Drupal Icon API

### Changed (vs brand-content-design v2.2.0)
- **Scaffold rewritten**: `radix-theme-scaffold.md` now matches real Radix 6.0.2 starterkit (13 gaps fixed)
  - Flat `components/` directory (no atomic subdirs)
  - Library name `style` (not `global`)
  - `_init.scss`: custom variables before Bootstrap functions (matches real starterkit)
  - `_bootstrap.scss`: all modules + helpers + utilities/api
  - `.info.yml`: `ckeditor5-stylesheets`, correct regions, `{THEME_NAME}/style` library
  - `.theme`: auto-loader glob for `includes/*.theme`
  - `webpack.mix.js`: dotenv, component SCSS/JS globs, asset copy, stylelint
  - `package.json`: ~16 devDependencies (biome, drupal-radix-cli, stylelint, etc.)
  - `main.style.scss`: 7 base imports (including drupal-overrides, functions, helpers)
  - Config files: `.env.example`, `.nvmrc`, `.npmrc`, `.browserslistrc`, `biome.json`, `.stylelintrc.json`
  - JS convention: underscore prefix `_name.js` for source files
  - SCSS import: `@import "../../src/scss/init"` (2 levels, not 3)
  - Asset directories: `src/assets/{images,icons,fonts}/` with watched copy
- **Template-matching**: NEW `template-matching-patterns.md` reference
  - Twig template overrides map Drupal entity fields to SDC component props
  - Hybrid pattern: embed `radix:block` → include custom SDC
  - Field access patterns for each Drupal field type
  - Navigation/footer templates (outside Layout Builder)
- **Layout composition instructions**: Replace fragile entity view display YAML with human-readable instructions in the conversion report
  - Section-by-section tables (layout type, styles, block placements)
  - Prerequisites and post-setup checklist
  - Config YAML still generated for block types, fields, views, LB styles
- **External guide ecosystem**: Domain knowledge lives in guides at `https://camoa.github.io/dev-guides/`
  - Eliminated 4 reference files superseded by external guides (design-system-guide, token-to-bootstrap-mapping, radix-base-components, sdc-patterns)
  - Discovery-first protocol: WebFetch llms.txt, then fetch specific pages on demand
- **Analyzer enhanced**: New Part 7 (template suggestions) outputs template paths and field-to-prop mappings
- **Flat component directories**: All SDC components in `components/{name}/`, atomic level in metadata only

### Architecture
- **Metadata-driven**: Parses `<!-- component: -->` / `<!-- prop: -->` / `<!-- slot: -->` comments dynamically
- **Shared analysis + target-specific generators**: Analyzer is target-agnostic, generators produce platform-specific code
- **6px threshold framework**: Design token to Bootstrap SCSS variable mapping
- **Drupal backend inventory**: Scans `config/sync/` for existing entities to maximize reuse
- **Guide-aware**: References external guides via WebFetch rather than embedding domain knowledge
