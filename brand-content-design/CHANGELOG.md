# Changelog

All notable changes to the brand-content-design plugin.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **`references/slides-batchupdate-authoring.md`** — LLM-facing authoring guide that teaches how to write a Google Slides API `batchUpdate` `requests[]` list that visually matches a reportlab-rendered PDF. Symmetric counterpart to `visual-content/references/technical-implementation.md`: the reportlab patterns there are the visual ground truth; every recipe in the authoring guide shows the same element authored as a Slides API request. Covers the mental model, the coordinate-translation contract (`PX_TO_PT = 0.375`, y-axis flip), the slide-creation ordering rule, per-element recipes (solid background, pre-rendered-PNG gradient, headline/kicker/paragraph text, hosted-URL logo, card, Iconify-bridge icon), Google-Fonts-first font fallback table for brand fonts unavailable server-side, the anti-patterns table (off-slide, overlap, missing `fields` mask, custom-TTF substitution, SVG URLs, sub-5-char `objectId`, `outline.weight: 0`), the coordinate-fidelity checklist, the `{name}.slides.batchupdate.json` persistence contract (native `{"requests": [...]}` schema), the destructive trash-and-recreate error-recovery loop, and a 1-slide end-to-end worked example with both the reportlab source and the resulting batchUpdate JSON side by side. Validation proof in `scripts/slides/tests/test_authoring_smoke.py` executes the worked example against the real Slides API (auth via `BCD_SLIDES_*`), asserts headline + kicker text + element count read back, and trashes the deck. Out of scope (subtask 4): Drive folder conventions, `.slides.url` pointer files, trash-and-recreate command-md wiring, writing the persisted batchUpdate JSON from `/presentation`.
- **`skills/visual-content/SKILL.md` (3.1.1 → 3.1.2)** — added a short pointer subsection inside Part 8 (Technical Implementation) referencing the new Slides authoring guide. No behavioral change to the existing reportlab-PDF / PPTX path.
- **`references/slides-credentials.md`** — credentials setup reference for the upcoming Google Slides output of `/template-presentation` and `/presentation`. Covers the OAuth-refresh-token vs service-account decision tree, Google Cloud Console + OAuth Playground setup steps, the `BCD_SLIDES_*` env-var contract (service account wins when both set; default scopes `presentations` + `drive.file`), and ready-to-paste Python wire-up snippets for the follow-up `slides_python_runner` subtask. Carries forward the credentials guidance from the rejected PR #179 TypeScript renderer prototype.
- **Drive folder mirroring for Slides output (`slides_drive_mirroring` subtask)** — extends `scripts/slides/` and wires `/presentation` + `/template-presentation` to render a live Google Slides deck in Drive alongside the existing local PDF + PPTX outputs. New `DriveFolderMirror` class in `runner.py` (idempotent find-or-create of the `brand-content/{brand}/{presentations|templates}/{slug}/` chain; soft-delete via `files.update({"trashed":true})` with 404 swallowing; optional root override via `BRAND_CONTENT_DRIVE_ROOT_ID`). New module-level pointer-file helpers `write_slides_url_file` / `read_slides_url_file` (drop `{name}.slides.url` JSON next to local PDF/PPTX, stripping leading `YYYY-MM-DD-` from folder name to derive `{name}`). Five new `cli.py` subcommands: `ensure_render_folder`, `mirror_presentation` (uploads PDF + outline.md), `mirror_template_sample` (deck only — templates flow does NOT mirror source files), `trash_existing_render` (idempotent), `replace_render` (default `trash`-and-recreate; `keep_alongside` writes a `-v2`/`-v3` versioned sibling). Commands updated: `presentation.md` step 11 prompts trash/keep/cancel before rendering Slides, persists `{topic-slug}.slides.batchupdate.json` per the sibling `slides_llm_authoring` subtask's authoring guide (referenced by path — `references/slides-batchupdate-authoring.md`), then `replace_render` mirrors the deck + PDF + outline.md to Drive; `template-presentation.md` step 17 does the same but for `kind=templates` and uploads ONLY the sample.slides deck. Test suite: 22 new mocked unit tests (`test_drive_folder_mirror.py` 17 cases — find-or-create idempotency, full chain ensure, invalid `kind` rejection, 404 trash swallow, default-root fallback; `test_pointer_file.py` 6 cases — date-prefix stripping, write/read roundtrip, overwrite semantics) plus a real-API smoke test (`test_drive_mirror_smoke.py`, env-gated) that ensures the full folder chain, uploads tiny PDF + outline + Slides deck, roundtrips the pointer file, and trashes the render folder in `finally`. PPTX remains in the flow (deprecation transition); is NOT uploaded to Drive.
- **`scripts/slides/`** — thin Python runner that authenticates to Google and executes Slides + Drive API operations. Single responsibility: turn a `batchUpdate` payload (supplied by the caller) into an executed Slides API call. Modules: `auth.py` (env-var routing per `slides-credentials.md` — service-account wins; incomplete OAuth trio raises), `runner.py` (`SlidesRunner` class with `create_deck` / `apply_batch_update` / `move_to_folder` / `deck_url`), `cli.py` (stdin → stdout JSON adapter for command-md integrations to shell out). Pinned deps `google-api-python-client>=2.180,<3` / `google-auth>=2.30,<3` / `google-auth-oauthlib>=1.2,<2`. Test suite: 14 mocked unit tests for auth + runner + a real-API smoke test (`tests/test_e2e_smoke.py`, env-gated) that creates a deck, applies a `batchUpdate`, reads it back, asserts the literal, then trashes the deck. Out of scope (sibling subtasks): LLM authoring of `batchUpdate` requests; Drive folder conventions, trash-and-recreate, `.slides.url` pointer files, command-md wiring.

## [3.4.0] - 2026-05-21

### Added
- **Effort-adaptive variant selection** — the `brand-content-design` router skill (v3.1.0 → v3.2.0) now reads `${CLAUDE_EFFORT}` to pick between the guided and quick command variants when the user doesn't name one: `low` → `*-quick`, `medium`+ → guided. Explicit variant requests still win. Paired with a README note on the built-in **Proactive** output style for the low-effort end of the gradient.

### Changed
- **Conciseness pass on the heavy generator skills** (no behavior change — detail extracted to `references/`, nothing removed):
  - `html-generator` SKILL.md 602 → 189 body lines (v2.9.0 → v2.9.1). All code samples, the metadata-comment format, responsive/JS patterns, the composed-page example, and the convertibility table already lived in `references/html-technical.md` and `references/html-components.md`; SKILL.md now points to them.
  - `visual-content` SKILL.md 480 → 143 body lines (v3.1.0 → v3.1.1). Canvas-philosophy example language, the full 4-gate visual-component decision flow, and the accessibility procedures extracted to the new `references/visual-craft.md`.
  - `infographic-generator` SKILL.md 277 → 200 body lines (v2.9.0 → v2.9.1). Background presets point to `references/backgrounds.md`; config-by-background examples appended to `references/theming.md`; data-structure JSON appended to `references/templates.md`.

### Fixed (pre-existing)
- **`visual-content` dangling reference** — `visual-content/SKILL.md` cited `references/slide-composition-rules.md`, but that file only existed under the sibling `brand-content-design` skill's `references/`. Copied it into `visual-content/references/` so the skill is self-contained (validator flagged it as a missing-reference error).
- **`commands/outline.md` argument-hint** — quoted `argument-hint: "<template-name>"` (was unquoted; validator FM02 angle-bracket nudge).
- **`brand-analyst` agent tool field** — the agent declared its tool list as `allowed-tools`, but the recognized agent frontmatter field is `tools` (`allowed-tools` is the skill/command field — silently ignored on an agent, so the scoping was not actually applied). Renamed `allowed-tools:` → `tools: Read, Glob, WebFetch, Write`; agent version 3.1.2 → 3.1.3. (README agent table corrected — `brand-analyst` is not read-only; it has `Write` to persist analysis results.)

### Hygiene
- Plugin-root `CLAUDE.md` renamed to `CONVENTIONS.md` (validator ST03 — a plugin-root `CLAUDE.md` is not loaded as end-user context).
- `$schema` added to `plugin.json`.
- Both hooks (SessionStart, PreCompact) migrated to exec form (`"args": []`).
- `keywords` trimmed 30 → 25 (validator M15 cap).

## [3.3.1] - 2026-04-27

### Skill visibility hygiene (Tier 2 of multi-plugin command-naming research)

Set `user-invocable: false` on `skills/brand-content-design/SKILL.md` (was explicit `true`). The umbrella skill was substring-matching `/brand` in the typeahead, but the user-facing entry point is the `/brand-content-design:brand` dashboard command (plus 18 specific verb commands like `/carousel`, `/presentation`, `/infographic`). No behavior change — the skill is still autonomously invocable by Claude and loadable via the Skill tool per docs line 290 + 496.

## [3.3.0] - 2026-04-27

### 2026-04-25 doc-refresh deltas

Closes the 2026-04-25 Claude Code doc-refresh deltas affecting this plugin (snapshot pinned at upstream commit `c142d14`). No code or behavior changes — version-only bump aligning with the cross-plugin cycle.

### Note

- **Plugin themes** — Claude Code 2.1.118+ added a first-class plugin themes feature: plugins can ship a `themes/` directory of JSON theme files (`{ name, base, overrides }`) that appear in `/theme` alongside built-in presets. A branded `themes/default.json` for brand-content-design was scoped for this version but **deferred** — shipping a starter theme requires confident brand color tokens for the plugin's own visual identity, which were not authored in this cycle. Will land in a follow-up PR once tokens are decided. The feature itself is documented upstream (Plugins Reference, Terminal Configuration, Claude Directory) and available to users today; this plugin simply has no opinionated theme to ship yet.

## [3.2.0] - 2026-04-08

### Changed
- **PreCompact hook** — No longer dumps brand-philosophy.md content into compaction. Now outputs instructions for Claude to read live project files on demand, reducing compaction bloat.

## [3.1.2] - 2026-03-20

### Fixed
- **brand-analyst agent resume failure** — Agent now writes findings to `brand-analysis-results.md` before returning. If the agent resume fails (concurrency error, API issue), the command reads the file as fallback. Previously, a resume failure lost all analysis data since the agent had no Write access.
- **brand-extract command** — Now reads agent results from `brand-analysis-results.md` file instead of depending solely on the agent's return message. Deletes the intermediate file after successful brand-philosophy.md generation.

### Changed
- `brand-analyst` agent: added `Write` to allowed-tools (was: Read, Glob, WebFetch)

## [3.1.1] - 2026-03-20

### Changed
- CLAUDE.md reviewed against 200-line size guidance — at 33 lines, no changes needed
- Agent frontmatter reviewed for `hooks`/`mcpServers`/`permissionMode` — none present in brand-analyst agent

## [3.1.0] - 2026-03-17

### Added
- **Brand Depth extraction**: `/brand-extract` now captures Aaker personality scores (0-5 with evidence), color profile (harmony/temperature/saturation), emotional profile, spatial & surface profile (spacing/radius/shadows/density), and brand maturity assessment
- **Brand Depth template sections**: `brand-philosophy-template.md` has 5 new sections under `## Brand Depth` — purely additive, existing sections unchanged
- **Pre-populated Aaker reading**: Style recommendation engine reads scores from `## Brand Depth` when available, skips voice-trait derivation (backward compatible fallback)
- **Post-selection personality guidance** (`style-recommendation-engine.md` Section 7): Component selection weighting (7A), canvas philosophy tone modulation (7B), and color intensity weighting (7C) — all keyed by Aaker dimension
- **Personality-informed template creation**: `template-presentation`, `template-carousel`, and `template-infographic` now load Aaker scores and use them for component suggestions, palette guidance, background presets, and canvas philosophy tone
- **Infographic personality integration**: Category recommendations and background presets weighted by primary Aaker dimension
- **Visual-content personality awareness**: Part 2b loads Aaker scores + spatial profile; Part 4 adds personality-informed color intensity; Part 7 Gate 2 factors personality into component decisions

### Changed
- **brand-analyst agent** (v3.1.0): 5 new analysis steps (Aaker scoring, color profile, emotional profile, spatial & surface profile, brand maturity) — output section updated to include Brand Depth
- **brand-extract command**: Agent delegation prompt requests Brand Depth sections; review step highlights Aaker scores for user validation
- **style-recommendation-engine**: Section 1 restructured — checks for pre-populated scores first (Step 1), voice-trait derivation is now Step 2 (fallback)
- **template-presentation**: Steps 7, 8, 12 reference personality guidance from Section 7A/7B/7C
- **template-carousel**: Steps 6, 7, 13 reference personality guidance; new step 4b loads personality
- **template-infographic**: New Phase 1b loads personality; step 4 suggests categories by dimension; step 8 suggests backgrounds by dimension
- **visual-content skill** (v3.1.0): New Part 2b, enhanced Part 4, personality-aware Gate 2

## [3.0.0] - 2026-03-16

### Added
- **Contemporary Professional style family**: 5 new business-focused styles (Tech-Modern, Data-Forward, Corporate-Confident, Pitch-Velocity, Narrative-Clean) — total styles now 18 across 5 families
- **Style recommendation engine** (`references/style-recommendation-engine.md`): Scores all 18 styles based on brand personality (Aaker dimensions), presentation purpose, and target audience — presents top 3 with reasoning
- **Slide composition rules** (`references/slide-composition-rules.md`): Per-slide-type focal point maps, style-aware layout modifiers, component frequency limits, image treatment specs, and composition blueprints for 8 slide types
- **Composition Rules section** in canvas-philosophy-template.md: Structural grounding populated during template creation from composition rules — covers focal points, element positioning, component frequency, image treatment, and density control
- **Component decision gates** in visual-content SKILL.md: 4-gate system (Style Permission → Content Justification → Frequency Budget → Density Check) replaces vague "use components intelligently" guidance
- **Audience question** in template-presentation wizard: New step asking target audience (C-suite, Technical, General, Creative, Investors, Customers)

### Changed
- **Template-presentation wizard**: Reordered steps — purpose and audience now asked BEFORE style selection to enable recommendation engine
- **Style selection**: Now presents scored top-3 recommendations first, with "Browse all 18" fallback to manual family→style selection
- **Presentation command**: Now loads and passes slide-composition-rules.md as fallback for legacy templates without Composition Rules
- **visual-content skill**: Part 3 now requires composition rules check before every slide; Part 7 enforces component decision gates instead of suggestions
- **presentations-guide.md**: Added Contemporary Professional family table with 5 styles
- **visual-components.md**: Added 5 styles to Card Style Variations, Style Compatibility Matrix, and Gradient Style Variations
- **style-constraints.md**: Added Contemporary Professional family section with full enforcement blocks for all 5 styles

## [2.9.0] - 2026-03-16

### Changed
- Remove brand bias from runtime JS fallbacks — Palcera colors (#0D2B5C, #194582, #00f3ff) replaced with neutral grays
- Replace hardcoded hex values in reference docs (theming.md, backgrounds.md) with {brand-*} placeholders
- Remove warm/earth color temperature prescriptions from Organic, Wabi-Sabi, Hygge, Feng Shui styles — styles now define color relationships, not temperature
- Replace Helvetica defaults in technical-implementation.md with brand_fonts.get() pattern
- Fix accent color search bug that caused invisible overlays on light-background brands
- Fix draw_feature_card crash from None font defaults

### Added
- Brand Anchors section in canvas-philosophy-template.md (logo placement, primary color requirement, font mandate)
- bias-prevention.md shared reference with Value Derivation Hierarchy
- No-brand safeguard on infographic, visual-content, and html-generator skills
- Pre-output validation checklists on all generation skills
- Auto-download Google Fonts in brand-extract command
- Brand anchor rule: derived/alternative palettes must include primary brand color

### Fixed
- brand-extract.md font examples used hardcoded "Inter" — now uses {detected heading font}
- template-infographic.md palette display showed Palcera hex — now uses {from brand-philosophy.md}
- style-constraints.md Swiss typography referenced "Helvetica" by name
- web-style-constraints.md Organic/Wabi-Sabi/Hygge enforcement blocks prescribed warm-only colors
- visual-components.md card style table referenced "warm tones"

## [2.8.0] - 2026-03-14

### Fixed
- **WebFetch contradiction**: CLAUDE.md, brand-content-design SKILL.md, and html-generator SKILL.md said "WebFetch the llms.txt index" — replaced with dev-guides-navigator delegation (which enforces curl-only)
- **Version alignment**: All 4 skills and agent now match plugin version (was: SKILL 2.3.0, html-generator 2.6.0, visual-content 1.11.3, infographic 1.11.3)
- **Agent frontmatter**: brand-analyst changed from `tools`/`disallowedTools` to `allowed-tools` (current standard)

### Changed
- Pushy descriptions with trigger phrases on all 19 commands
- Added `allowed-tools` to all 4 skills (explicit tool scoping)
- Added `user-invocable: true` to main brand-content-design skill
- Model upgraded from haiku to sonnet for brand-content-design skill (was already sonnet, confirmed)
- Plugin keywords expanded for better discoverability

## [2.7.1] - 2026-02-17

### Fixed
- **html-page command**: Output path changed from `html-pages/{date}-{page-name}/` to `html-pages/{design-system-name}/{page-name}/` — prevents cross-design-system mixing and duplicate directories on regeneration
- **html-page command**: Added explicit convertibility metadata instruction — generator now mandated to include `<!-- prop: -->` and `<!-- slot: -->` annotations, not just component boundaries
- **html-technical.md**: Updated Output Pages structure to match new design-system-namespaced path, added images directory documentation

## [2.7.0] - 2026-02-17

### Changed
- **html-generator skill**: Enhanced with 6 aesthetic principles inspired by Anthropic's frontend-design skill
  - **"The one memorable thing"** — differentiation test now requires naming the ONE distinctive element per page
  - **Intentionality over intensity** — calibrate design complexity to match the style (restraint for minimal, elaborate for maximalist)
  - **Color dominance** — dominant primary with sharp accent outperforms evenly-distributed palettes
  - **Motion hierarchy** — focus animation budget on one high-impact page load moment, keep the rest subtle
  - **Anti-convergence** — never reuse the same font choices across different page generations
  - **Match complexity to aesthetic** — Swiss precision ≠ Memphis energy; each style demands its own execution approach

## [2.6.0] - 2026-02-16

### Changed
- **Dev-guides integration v2**: Replaced keyword→URL mapping tables (11-entry in html-generator, 6-entry in brand-content-design) with lightweight `llms.txt` discovery + topic hints
- **CLAUDE.md**: Added Online Dev-Guides section with `llms.txt` index URL and topic hints for session-wide awareness

## [2.5.0] - 2026-02-15

### Added
- Online dev-guides integration for design system fundamentals
  - html-generator SKILL.md: 11-entry keyword→URL mapping table for design tokens, component classification, Bootstrap patterns, SCSS, accessibility, progressive enhancement
  - brand-content-design SKILL.md: 6-entry keyword→URL mapping table for design system recognition, analysis methodology, screenshot/Figma analysis
- "See also" pointers in html-components.md, html-technical.md, html-design-guide.md, color-palettes.md linking to online design system guides

---

## [2.4.0] - 2026-02-15

### Fixed
- **html-generator metadata**: Inlined full metadata format (component/prop/slot) in SKILL.md Parts 3, 10, 12 — previously only referenced an unreachable external file, causing generated HTML pages to lack converter-compatible annotations
- **html-page command**: Step 9 now explicitly loads all 4 reference files before invoking html-generator skill
- **html-page-quick command**: Step 5 now explicitly loads all 4 reference files before invoking html-generator skill

### Added
- Framework mapping table in Part 12 showing how HTML metadata maps to Drupal SDC, React, and Twig
- Complete composed page example in Part 10 with all metadata markers
- Explicit anti-pattern: "Do NOT replace metadata with section divider comments"

## [2.3.1] - 2026-02-14

### Fixed
- Removed explicit `hooks` declaration from plugin.json — `hooks/hooks.json` is auto-loaded by Claude Code, duplicate declaration caused plugin load failure

## [2.3.0] - 2026-02-13

### Changed
- **Converter extracted**: HTML-to-Drupal Radix/SDC converter moved to standalone `design-system-converter` plugin
  - Removed `html-to-radix-analyzer` and `radix-sdc-generator` skills
  - Removed `/convert-to-radix` and `/convert-to-radix-quick` commands
  - Removed converter references (radix-theme-scaffold, sdc-patterns, token-to-bootstrap-mapping, layout-builder-config)
  - Removed `scripts/extract-icons.js`
- **SKILL.md**: Removed converter trigger phrases and command routing
- **plugin.json**: Removed Drupal/Radix/SDC/converter keywords, version bump to 2.3.0

## [2.2.0] - 2026-02-11

### Added
- **HTML-to-Drupal Radix/SDC Converter**: Metadata-driven converter that parses HTML component comments to generate Drupal themes
  - `/convert-to-radix` command: Guided 7-phase wizard with 6 AskUserQuestion points for full control
  - `/convert-to-radix-quick` command: Quick mode with 3 questions and auto-resolved ambiguities
  - `html-to-radix-analyzer` skill: Shared analysis layer (HTML metadata parsing, pattern classification, design token extraction, Drupal backend inventory, atomic classification)
  - `radix-sdc-generator` skill: Generates complete Radix 6.0.2 sub-theme with SDC components, Bootstrap SCSS mapping, Layout Builder config, and icon packs
  - `scripts/extract-icons.js`: CLI tool to extract inline SVGs from HTML for Drupal Icon API
  - 7 reference files: pattern-classification, atomic-classification, drupal-backend-inventory, radix-theme-scaffold, token-to-bootstrap-mapping, sdc-patterns, layout-builder-config
- **Architecture**: Shared analysis layer + target-specific generators (Radix first, Canvas and Node.js future)
- **Metadata-driven**: Parses `<!-- component: -->` / `<!-- prop: -->` / `<!-- slot: -->` comments dynamically, not hardcoded to 15 component types
- **6px threshold framework**: Design token to Bootstrap SCSS variable mapping (Accommodate/Extend/Customize/Create)
- **Drupal backend inventory**: Scans `config/sync/` for content types, views, block types, menus to maximize reuse
- **Atomic classification**: Dynamic atom/molecule/organism heuristics with Radix base component reuse detection
- **Per-project config**: `converter/radix-sdc.yml` stores all conversion decisions for reproducibility

### Changed
- **SKILL.md**: Added converter trigger phrases and command routing
- **plugin.json**: Version bump to 2.2.0, added Drupal/Radix/SDC keywords

## [2.1.0] - 2026-02-09

### Added
- **HTML Design System**: New content type for creating branded HTML pages
  - Design-system-based approach (vs template-based for presentations/carousels)
  - Component library grows organically as pages are created
  - 15 reusable component types (nav, hero, feature-grid, testimonials, CTA, pricing, FAQ, etc.)
  - Each component is standalone (viewable independently) + composable into full pages
  - Convertibility-ready structure: prop/slot metadata, semantic HTML, CSS custom properties
- **Digital Native style family**: 8 new web-specific visual styles (21 total)
  - Neobrutalist, Glassmorphism, Dark Mode, Bento Grid, Retro/Y2K, Kinetic, Neumorphism, 3D/Immersive
  - Each with web-adapted enforcement blocks (per-section constraints)
- **`html-generator` skill**: Generates standalone HTML components and composed pages
  - Single-file output with embedded CSS + minimal vanilla JS
  - Mobile-first responsive (375px → 768px → 1200px)
  - CSS-first interactivity (CSS-only accordions, scroll-snap, transitions)
  - WCAG AA accessibility (semantic HTML, skip-nav, contrast, reduced-motion)
  - Image placeholders using CSS gradients with replacement comments
- **`/design-html` command**: Guided wizard for creating HTML design systems
  - Project context gathering (audience, goals, tone)
  - Brand relationship model (main brand, sub-identity, independent)
  - Style selection from 5 families, 21 styles
  - Design token generation (CSS custom properties)
  - Canvas philosophy + design-system.md generation
- **`/html-page` command**: Guided page creation with component selection
  - 10 page category presets (landing, about, portfolio, pricing, etc.)
  - Component reuse from existing library
  - Section-by-section or paste-all content input
- **`/html-page-quick` command**: Quick page creation with minimal questions
- **Web style constraints**: 21 enforcement blocks adapted for web (per-section word limits, padding, layout rules)
- **Component catalog reference**: 15 component types with HTML/CSS patterns and variants
- **Technical specs reference**: Boilerplate, responsive breakpoints, font loading, accessibility checklist

### Changed
- **SKILL.md**: Added HTML trigger phrases and command routing
- **`/brand-init`**: Creates `templates/html/` and `html-pages/` directories
- Style system expanded from 13 → 21 styles (4 → 5 families)

## [2.0.0] - 2026-02-09

### Added
- **Agent memory**: brand-analyst uses `memory: project` for cross-session brand pattern learning
- **Model routing**: opus for visual-content (creative complexity), sonnet for brand-content-design and infographic-generator
- **Tool restrictions**: brand-analyst has `disallowedTools: Edit, Write, Bash` for explicit read-only enforcement
- **Invocation control**: visual-content and infographic-generator set `user-invocable: false` (called by commands only)
- **PreCompact hook**: preserves active brand project context before context compaction
- **CLAUDE.md**: plugin conventions at plugin root
- **Path-scoped rules**: `.claude/rules/` with agent, skill, and command conventions
- **Version fields**: added `version` to all agents and skills

## [1.11.3] - 2025-12-11

### Added
- **Infographic accessibility enforcement**: Mandatory accessibility checks for infographics
  - `generate.js` now validates WCAG AA contrast (4.5:1) before generation
  - Warns about low-contrast text with recommended fixes
  - `getLuminance()`, `getContrastRatio()`, `validateContrast()` functions added
- **Infographic SKILL.md**: New "Accessibility & Readability (MANDATORY)" section
  - Text color rules by background type (dark/light)
  - Spacing & balance requirements
  - Pre-generation checklist
- **Infographic WORKFLOW.md**: Accessibility checklist section with troubleshooting

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
