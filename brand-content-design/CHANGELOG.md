# Changelog

All notable changes to the brand-content-design plugin.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2025-12-08

### Added
- **Brand Analyst Agent Integration**: `/brand-extract` now delegates to `brand-analyst` agent
  - Preserves main conversation context window for heavy asset analysis
  - Agent runs in separate context for images, PDFs, websites
- **Color Theory Analysis**: Agent enhanced with comprehensive color analysis
  - 3-step process: identify colors, analyze relationships, note properties
  - Color harmony identification (monochromatic, analogous, complementary, triadic, tetradic)
  - Temperature, saturation, and emotional association analysis
  - Wikipedia links for color theory reference

### Changed
- `/brand-extract` workflow delegates to agent instead of inline analysis
- Agent references `brand-philosophy-template.md` instead of reproducing format (DRY)

## [1.1.0] - 2025-12-08

### Added
- **Visual Style System**: 13 distinct styles across 4 aesthetic families
  - Japanese Zen: Minimal, Dramatic, Organic, Wabi-Sabi, Shibui, Iki, Ma
  - Scandinavian Nordic: Hygge, Lagom
  - European Modernist: Swiss, Memphis
  - East Asian Harmony: Yeo-baek, Feng Shui
- **Two-step style selection**: Choose aesthetic family first, then specific style
- **Style enforcement blocks**: Hard constraints for whitespace, words, elements per style
- **Color Palette System**: 10 palette types derived from brand colors
  - Harmony-based: Monochromatic, Analogous, Complementary, Split-Complementary, Triadic, Tetradic
  - Tonal variations: Tints, Shades, Tones
  - Custom: AI-generated from mood description
- `/brand-palette` command for generating and saving alternative palettes
- Reference links to Wikipedia/design articles for each style
- Terminal color box display using ANSI codes

### Changed
- Template commands now use two-step style selection (family → style)
- Content commands reference style-constraints.md for enforcement blocks
- Updated presentations-guide.md and carousels-guide.md with all 13 styles

### Fixed
- Template name validation and uniqueness check
- Use Bash `find` command for robust template discovery

## [1.0.0] - 2025-12-07

### Added
- Initial release
- `/brand` - Main entry point
- `/brand-init` - Create brand project structure
- `/brand-extract` - Extract brand philosophy from sources
- `/brand-assets` - Manage brand assets
- `/template-presentation` - Create presentation templates
- `/template-carousel` - Create carousel templates
- `/outline` - Generate content outlines for templates
- `/presentation` and `/presentation-quick` - Create presentations
- `/carousel` and `/carousel-quick` - Create carousels
- `/content-type-new` - Add new content types
- Three-layer philosophy system (brand → content type → template)
- Presentation Zen principles integration
- PPTX safe zone guidance
