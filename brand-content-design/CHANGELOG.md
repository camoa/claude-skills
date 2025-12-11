# Changelog

All notable changes to the brand-content-design plugin.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.11.2] - 2025-12-11

### Fixed
- **Logo format enforcement**: Logos must be PNG or JPG - SVG not supported by reportlab
  - `/brand-extract` now converts SVG logos to PNG automatically during brand setup
  - `brand-philosophy-template.md` clearly states PNG/JPG requirement
  - Runtime fallback conversion if SVG encountered at generation time
  - Added format validation with warning for unsupported formats

### Added
- **Mandatory accessibility checks**: New "Accessibility & Safety Checks" section in technical-implementation.md
  - WCAG AA contrast validation (4.5:1 minimum) with auto-fix
  - Text bounding box collision detection to prevent overlap
  - Safe zone enforcement with constants for presentations and carousels
  - Pre-render checklist that must pass before output
  - Gradient text safety validation (contrast at both ends)
- **Part 6b in SKILL.md**: "Accessibility & Safety (MANDATORY)" with enforcement rules
  - No overlap rule (ABSOLUTE) - text must never overlap anything
  - Safe zone enforcement table with usable dimensions
  - Pre-render checklist for every slide/card

### Changed
- **Technical documentation**: Updated asset preparation section with supported formats table

## [1.11.1] - 2025-12-11

### Fixed
- **Gradient rendering bug**: Fixed `AttributeError: 'PDFPathObject' object has no attribute 'closePath'` - reportlab uses `p.close()` not `p.closePath()`
- **Icons fallback paths**: Added fallback plugin directory detection when `BRAND_CONTENT_DESIGN_DIR` env var not set by hook

### Added
- **Intelligent usage guidelines**: Visual components now have decision framework for smart usage
  - When to use/avoid cards, icons, gradients based on content type
  - Slide-type recommendation matrix
  - Quality checklist and common mistakes
- **Outline command**: `/outline` now includes visual components in generated AI prompts

## [1.11.0] - 2025-12-11

### Added
- **Visual Components System**: Universal visual components for carousels and presentations
  - **Cards**: Rounded containers for content grouping (style-dependent support)
  - **Icons**: 1900+ Lucide icons via Python helper (`scripts/icons.py`)
  - **Gradients**: Linear/radial backgrounds for depth
- **Style-specific component rules**: Each of 13 styles has explicit card/icon/gradient support
  - Full support (all three): Dramatic, Organic, Hygge, Memphis, Feng Shui
  - Cards + Icons only: Iki, Lagom, Swiss
  - Cards only (subtle): Minimal, Wabi-Sabi, Shibui
  - No components: Ma, Yeo-baek
- **Visual Components wizard**: Step 6 in `/template-carousel` and `/template-presentation`
  - Multi-select for cards, icons, gradients based on style support
  - Follow-up questions for card style, icon categories, gradient direction
- **SessionStart hook**: Exports `BRAND_CONTENT_DESIGN_DIR` for portable Python imports
- **`references/visual-components.md`**: Universal components documentation

### Changed
- **Template wizards**: Now 17 steps (added Step 6: Visual Components)
- **`visual-content/SKILL.md`**: Added Part 7: Visual Components with usage patterns
- **`technical-implementation.md`**: Added reportlab patterns for cards, gradients, icons
- **`canvas-philosophy-template.md`**: Added Visual Components section template
- **`style-constraints.md`**: Added Visual Components section to all 13 styles

### Technical
- `scripts/icons.py`: Python helper for SVG→PNG conversion (requires `cairosvg`)
- `hooks/setup-env.sh`: Sets `BRAND_CONTENT_DESIGN_DIR=${CLAUDE_PLUGIN_ROOT}`
- Icons sourced from `infographic-generator/node_modules/lucide-static/icons/`

## [1.10.0] - 2025-12-11

### Added
- **Palette contrast validation**: `/brand-palette` now validates all generated palettes for text contrast
  - Calculates luminance and contrast ratio for each color
  - Automatically adds `Text (light bg)` and `Text (dark bg)` colors to every palette
  - Uses WCAG AA standard (≥4.5:1 contrast ratio)
  - Derives text colors from palette when possible, falls back to safe defaults
  - Shows ⚠️ indicator when text colors are derived (not from original palette)
- **Text colors in brand-philosophy-template.md**: New "Text Colors (Contrast-Validated)" section
- **Multi-format illustration support**: Illustrated templates now accept SVG, PNG, and JPG
  - "I have images" option for providing your own files
  - "Find icons for me" with expanded resource list (Lucide, Heroicons, Unsplash, unDraw, Storyset)
  - "Use placeholders" for quick prototyping

### Changed
- **`/template-infographic`**: Now reads `Text (light bg)` and `Text (dark bg)` from selected palette
  - Config generation uses palette text colors for `title.fill`, `desc.fill`, `item` fills
  - Template category table now shows Icons/Illustrated columns
- **`/template-presentation`**: Now extracts and uses palette text colors
  - Canvas philosophy includes text color guidance section
- **`/template-carousel`**: Now extracts and uses palette text colors
  - Canvas philosophy includes text color guidance section
- **Palette storage format**: Alternative palettes now include text colors:
  ```markdown
  ### Pastel (Alternative)
  - Base: #E0E7FF
  - Text (light bg): #1E293B ⚠️
  - Text (dark bg): #F8FAFC
  ```
- **Illustration storage location**: Images now stored with infographic output, not template
  - Each infographic: `infographics/{date}-{name}/illustrations/`
  - Templates only contain config.json and outline-template.md

### Fixed
- Pastel/low-contrast palettes no longer produce unreadable text
- All three content types (infographics, presentations, carousels) now use consistent text contrast rules
- Illustrated templates no longer expect images in template folder

## [1.8.0] - 2025-12-11

### Added
- **Infographic Generator Skill**: Complete system for creating branded infographics
  - Uses @antv/infographic library with 114 templates across 7 categories
  - Three template types: text-only (100+), icon-based (8), illustrated (9)
  - Custom background system with 11 presets (4 layered + 7 simple)
  - Lucide icon integration (1909 icons via lucide-static)
  - Automatic npm dependency installation on first use

### Changed
- **Color contrast system**: Dark backgrounds now use proper light text colors
  - `colorBg` sets the background base color for gradient derivation
  - Explicit `title`, `desc`, `item.label`, `item.desc` fill colors for contrast
  - `darkenColor()` and `isLightColor()` helpers for intelligent color handling
- **Removed dimension config**: Library auto-sizes based on content (width/height removed)

### Fixed
- Background presets now properly applied via `extractSVG` instead of `exportToDataURL`
- Illustrated templates render with placeholder SVGs when files are missing

## [1.7.0] - 2025-12-10

### Added
- **`/template-infographic`**: Create infographic templates with 114 designs
- **`/infographic`**: Generate infographics (guided mode)
- **`/infographic-quick`**: Generate infographics (fast mode)
- **Infographic skill files**: SKILL.md, references for templates, theming, backgrounds, icons, illustrations
- **Node.js generator**: `generate.js` with Puppeteer for PNG export
- **Background presets**: spotlight-dots, spotlight-grid, diagonal-crosshatch, tech-matrix, and 7 simple presets

## [1.5.0] - 2025-12-10

### Added
- Initial infographic generator infrastructure
- Template command with category/design selection workflow
- Outline template and prompt generation for infographic content

## [1.4.1] - 2025-12-09

### Added
- **Command validation script**: `scripts/validate_commands.py` for integrity testing
  - Validates frontmatter, AskUserQuestion compliance, skill references, file references
  - Checks step numbering and required sections
  - Run with `python3 scripts/validate_commands.py`

### Fixed
- **AskUserQuestion compliance in palette selection**: Template commands now show 2+ bold options for dynamic palette lists
- **Step numbering in `/outline`**: Fixed duplicate step 4, now correctly numbered 1-9
- **Template edit mode**: Split into 2-question flow to respect 4-option limit
  - Step 4a: Choose aspect to modify (Structure, Visual style, Regenerate, Start over)
  - Step 4b: If Structure selected, choose action (Add, Remove, Reorder)

## [1.4.0] - 2025-12-09

### Added
- **`visual-content` skill**: Bundled skill for generating presentations and carousels
  - Uses artistic philosophy language ("museum-quality execution", "90% visual, 10% text")
  - Specialized for presentations and carousels (not generic visual output)
  - Two-phase process: Generate PDF first (source of truth), then convert to PPTX for editability
  - Enforces style constraints (whitespace %, word limits, element counts)
  - No external dependencies required
  - **Part 7: Technical Implementation** with reportlab code patterns:
    - SVG to PNG conversion for logo embedding
    - Custom font loading from `assets/fonts/`
    - PDF generation patterns for slides (1920x1080) and cards (1080x1350)
    - Positioning patterns: Centered, Asymmetric, Grid layouts
    - Color parsing from brand-philosophy.md
- **Font support**: Custom brand fonts now flow through the system
  - `/brand-init` creates `assets/fonts/` folder
  - `/brand-extract` scans `input/fonts/` and copies to `assets/fonts/`
  - `/brand-extract` detects fonts from websites and recommends downloads
  - `brand-philosophy-template.md` includes Font Files table
  - `visual-content` loads fonts from project's `assets/fonts/`

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
