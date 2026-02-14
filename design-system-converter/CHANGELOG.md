# Changelog

All notable changes to the design-system-converter plugin.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-02-14

### Foundation Layer, Styleguide & Layout Analysis
- **Foundation layer**: Image styles (focal point + WebP), breakpoints, icons, LB style groups consolidated into Part 3 — generated BEFORE atoms, since atoms depend on them
- **Styleguide generation**: Master template (`node--styleguide.html.twig`) with accordion-based ToC and sub-template includes for each layer: tokens, foundation, layouts, atoms, molecules, organisms
- **Layout analysis**: Analyzer Part 1b extracts section structure per page — layout type, column proportions, visual properties, component placement. Feeds into Layout Builder mapping and layout wireframes.
- **Image style enhancements**: Focal point support (`focal_point_scale_and_crop` when module available), WebP conversion as last effect in every style chain
- **Layered generation flow**: Tokens → Foundation → Layouts → Components → Templates → Config → Report (was: Tokens → Atoms → Molecules → Organisms)

### Architecture Rework
- **Design-system-first flow**: Components generated in atomic order (tokens → atoms → molecules → organisms) per page, not all at once. Home page first, subsequent pages add only NEW components.
- **Overlay mode**: Existing sites are inventoried first (theme settings, templates, views, content types, modules). Existing theme is the starting point for all decisions (GP-1).
- **Competing agents**: Ambiguous component classifications are debated by a team of specialized agents (custom-block, content-view, taxonomy-view, devils-advocate) before presenting options to the user.

### Bug Fixes (21 bugs from v1.0.0 testing)

**Critical (5)**:
- **BUG-T8**: Use `drush radix:create` for scaffold instead of manual generation from reference file
- **BUG-T9**: Block content templates now use `content['#block_content']` entity access, not `node`
- **BUG-T13**: Generate ALL field storages and instances for ALL block types, not just the first one
- **BUG-T15**: Field storage configs include ALL required keys (`module`, `dependencies`, `locked`, `translatable`, `indexes`, `persist_with_no_fields`, `custom_storage`)
- **BUG-T20**: Converter inventories existing site before making decisions (theme, templates, views, content types)

**High (2)**:
- **BUG-T2**: Removed "hardcoded in template" as a classification option; added "Fields on content type" and "Taxonomy + view"
- **BUG-T15b**: Config exports split into `pass1/` (storages) and `pass2/` (instances) for safe import ordering

**Medium (11)**:
- **BUG-T1**: Config sync directory discovered from `settings.php` instead of hardcoded `config/sync/`
- **BUG-T3**: SVG icon extraction falls back to context-based detection when no `<!-- icon: -->` markers exist
- **BUG-T4**: Ambiguity questions prefixed with source HTML page filename and include content excerpts
- **BUG-T5**: Removed `mix.version()` from webpack.mix.js (breaks Drupal asset paths)
- **BUG-T7**: WebFetch of external guides is now MANDATORY with explicit validation
- **BUG-T10**: ALL block content templates MUST embed `radix:block` wrapper (no exceptions)
- **BUG-T11**: Entity-level field access everywhere — NEVER `content.field_*['#items']`
- **BUG-T14**: Removed Paragraphs as default for multi-value structured content
- **BUG-T16**: Only generate config for field types from enabled modules
- **BUG-T18**: Content images come from Drupal fields, not theme `src/assets/images/`
- **BUG-T19**: Added `$theme-colors: map-merge($theme-colors, $custom-colors)` to `_init.scss` after maps import

**Low (3)**:
- **BUG-T6**: Removed duplicate `@import "~bootstrap/scss/utilities"` and `@import "~bootstrap/scss/root"` from `_bootstrap.scss`
- **BUG-T12**: Custom color keys must not include utility prefix (`"alt"` not `"bg-alt"`)
- **BUG-T17**: Logo copied from existing theme settings config, not theme directory

### Improvements
- **IMP-T1**: Two-pass config import instructions in conversion report
- **IMP-T2**: `composer require` commands included in next steps
- **IMP-T3**: Complete field storage YAML template with module-by-type reference table
- **IMP-T4**: Image style and responsive image style generation — analyzer extracts image aspect ratios and container sizes from HTML, generator produces `image.style.*.yml` and `responsive_image.styles.*.yml` configs with breakpoint-aware responsive groupings. On existing sites, reuses matching styles instead of duplicating.

### Files Changed
- `skills/radix-sdc-generator/SKILL.md` — Radix CLI scaffold, page-by-page generation, entity access, complete field storage, two-pass config, image style generation
- `skills/html-to-radix-analyzer/SKILL.md` — Mandatory WebFetch, CONFIG_SYNC_DIR, SVG context parsing, existing theme inventory, image context extraction
- `commands/convert-to-radix.md` — Config sync discovery, site inventory, competing agents, two-pass import
- `commands/convert-to-radix-quick.md` — Same structural changes adapted for quick mode
- `skills/design-system-converter/SKILL.md` — Updated architecture description, examples, troubleshooting
- 7 reference files updated with bug fixes, image style configs, and new patterns

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
