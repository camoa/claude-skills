# Changelog

All notable changes to the brand-content-design plugin.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.4.0] - 2025-12-09

### Added
- **`visual-content` skill**: Bundled skill for generating presentations and carousels
  - Uses artistic philosophy language ("museum-quality execution", "90% visual, 10% text")
  - Specialized for presentations and carousels (not generic visual output)
  - Two-phase process: Generate PDF first (source of truth), then convert to PPTX for editability
  - Enforces style constraints (whitespace %, word limits, element counts)
  - No external dependencies required

### Changed
- All commands now use bundled `visual-content` skill instead of external `canvas-design`
  - `/presentation`, `/presentation-quick`, `/carousel`, `/carousel-quick`
  - `/template-presentation`, `/template-carousel`
- PDF → PPTX workflow: Visual output generated as PDF first, then converted for editability
- SKILL.md updated to document visual-content as bundled skill

### Removed
- External `canvas-design` dependency (replaced by bundled `visual-content` skill)

## [1.3.2] - 2025-12-09

### Fixed
- **`/brand-init` next steps**: Now shows `/brand-palette` and `/template-*` commands after init
- **Alternative palette menu**: Both mood questions now marked "ALWAYS ASK" (sequential, not conditional)
- **Palette confirmation message**: Now correctly mentions `/template-presentation` and `/template-carousel` (not `/presentation`)
- **Template purpose question**: Now shows examples and asks for 2-4 word description instead of limited menu options

## [1.3.1] - 2025-12-09

### Added
- **Palette selection in template creation**: Templates now lock style + palette together
  - Step 6 in `/template-presentation` and `/template-carousel` asks which palette
  - Options: Brand colors (default) or any saved alternative palette
  - Palette colors used in canvas-philosophy.md, template.md, and sample generation

### Changed
- Templates are now more specific: style + palette locked at template level
- Content creation (`/presentation`, `/carousel`) uses template's locked palette
- Step numbers updated in both template commands (now 16 steps each)

### Fixed
- **All palette options now shown**: Removed "More..." gates in `/brand-palette`
  - Derived: 2 harmony questions (4+2) + 1 tonal question (4) - all 10 types visible
  - Alternative: 2 mood questions (4+3) - all 7 types visible including Custom
  - Users no longer need to click "More..." to see all options
- **Outline prompts now include slide/card type definitions**: External AI can now understand what content each type needs (word limits, purpose, content requirements)

## [1.3.0] - 2025-12-09

### Added
- **Expanded Palette System**: 17 palette types (up from 10)
  - **Derived palettes** (color theory): 10 types
    - Harmony: Monochromatic, Analogous, Complementary, Split-Complementary, Triadic, Tetradic
    - Tonal: Tints, Shades, Tones, Interpolation
  - **Alternative palettes** (mood-based): 7 types
    - Pastel, Bold, Earthy, Vibrant, Muted, Monochrome, Custom
- **Source color selection**: Choose which brand colors to derive from
  - Primary only (default, simplest)
  - All brand colors (richest results)
  - Pick specific colors
- **Branching palette selection**: Choose "Derived" or "Alternative" first, then specific options
- **Full palette awareness**: Alternative moods transform entire brand palette, not just primary
- **Interpolation**: Creates gradient colors between selected source colors

### Changed
- `/brand-palette` now uses branching workflow (category → options)
- Derived palettes use "Source" instead of "Primary" - works with any selected colors
- Alternative palettes transform all brand colors to maintain palette structure
- `color-palettes.md` reorganized with Derived vs Alternative sections
- Removed "Extended Harmony" - replaced by source selection feature

## [1.2.1] - 2025-12-09

### Fixed
- **AskUserQuestion option limits**: Split multi-option selections to respect 4-option limit
  - Palette selection: 3 questions (basic harmony, advanced harmony, tonal)
  - Japanese Zen styles: 2 questions (7 styles split into 3+4)
  - All 10 palette types and 13 styles now accessible

### Added
- `/brand-palette` added to `/brand` command quick actions
- `/brand-palette` added to SKILL.md commands table
- Trigger phrases for "color palette" / "generate palette" / "alternative colors"
- `style-constraints.md` and `color-palettes.md` added to SKILL.md references

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
