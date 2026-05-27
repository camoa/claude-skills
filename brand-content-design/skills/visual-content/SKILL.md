---
name: visual-content
description: Use when creating branded presentations or carousels. Generates museum-quality visual output from canvas philosophy, enforcing style constraints. Outputs PDF first, then converts to PPTX for editability.
version: 3.1.2
allowed-tools: Read, Write, Glob, Bash
user-invocable: false
---

# Visual Content Skill

Create gallery-quality branded presentations and carousels through artistic design philosophy.

## The Critical Understanding

Visual content creation is an act of **artistic expression**, not template filling. Every slide or card should appear as if crafted by a designer at the absolute top of their field — meticulous, intentional, worthy of display.

- **What you receive**: a canvas philosophy and brand DNA — foundation, not constraint.
- **What you create**: visual artifacts that are 90% design, 10% essential text.
- **The standard**: work that looks like it took countless hours, labored over with painstaking care.

## Part 1: Understanding Canvas Philosophy

A canvas philosophy is not a layout specification — it's an **aesthetic movement**, a manifesto for how ideas become visual form. When you receive a `canvas-philosophy.md`, internalize its spirit:

- **The movement name** tells you the soul: "Chromatic Silence" demands restraint; "Brutalist Joy" permits boldness.
- **The philosophy paragraphs** describe how ideas manifest through form, space, color, composition.
- **The constraints** are sacred boundaries that define the style's character.

Read it as an artist reads a creative brief — absorb the worldview, then express it. For the depth and language a canvas philosophy uses, see the worked examples in `references/visual-craft.md` § Canvas Philosophy — Example Language.

## Part 2: The Subtle Reference

**CRITICAL STEP**: Before creating visuals, identify the conceptual thread from the content.

The topic becomes a **subtle, niche reference embedded within the design itself** — not literal, always sophisticated. Someone familiar with the subject should feel it intuitively, while others simply experience a masterful composition. Think like a jazz musician quoting another song — only those who know will catch it, but everyone appreciates the music.

The canvas philosophy provides the aesthetic language. The content provides the soul — the quiet conceptual DNA woven invisibly into form, color, and composition.

## Part 2b: Brand Personality Loading

Before creating visuals, check `brand-philosophy.md` for `## Brand Depth` > `### Personality (Aaker Framework)`:

**If present and populated**: read the Aaker scores and primary/secondary dimensions. Store in working context — these inform component decisions (Part 7), color intensity (Part 4), and spatial choices throughout.

**If not present**: read voice traits from `## Verbal Identity` > `### Voice Personality` and map to Aaker dimensions by proximity — precise/reliable/expert/professional → **Competence**; warm/friendly/approachable/genuine → **Sincerity**; bold/innovative/daring/creative → **Excitement**; elegant/refined/luxurious/polished → **Sophistication**; rugged/authentic/tough/adventurous → **Ruggedness**.

Also check for `### Spatial & Surface Profile` — if present, use its values (spacing rhythm, border radius, shadow style, layout density) to inform element placement and styling.

## Part 3: Visual Expression

With philosophy internalized and conceptual thread identified, create the visual artifacts.

### Composition Rules Application (MANDATORY)

Before laying out ANY slide:

1. **Identify slide type** — Title, Content, Image, Data/Chart, Quote, CTA, or Transition.
2. **Look up focal point** — from the Composition Rules section of canvas-philosophy.md (or `references/slide-composition-rules.md` if missing).
3. **Place focal element FIRST** — the primary visual anchor goes in position before anything else.
4. **Apply style modifier** — adjust position per the style's layout rules (centered, asymmetric, grid, flowing).
5. **Check component frequency** — before adding cards/icons/gradients, confirm budget across all slides.
6. **Verify density** — max 3 visual layers, no element collisions, 24px minimum spacing.

If canvas-philosophy.md has no Composition Rules section (legacy templates), use the defaults from `references/slide-composition-rules.md` with the style's modifiers applied.

### The Craftsmanship Standard

**CRITICAL**: to achieve human-crafted quality (not AI-generated), create work that looks like it took countless hours — as though someone at the absolute top of their field labored over every detail. Composition, spacing, color, typography — everything must scream expert-level craftsmanship. This is non-negotiable. The mantra: meticulously crafted, the product of deep expertise, painstaking attention to detail, master-level execution, labored over with care.

### Creating Presentations (16:9)

1920×1080 px. PDF first (source of truth) → PPTX (for editability). Each slide = one clear message (3-second test). Text sparse, integrated as a visual element — never paragraphs. Nothing within 50px of edges. **The slide is a canvas, not a document** — information lives in scale, position, color, whitespace.

### Creating Carousels (Mobile-First)

LinkedIn 1080×1350 (4:5), Instagram Square 1080×1080, Instagram Portrait 1080×1350. Multi-page PDF. Each card = 2-second comprehension (thumb-stopping). Text bold, scannable, commanding. **The card is a poster glimpsed while scrolling** — it must arrest attention instantly through visual impact, not dense information.

### Style Enforcement

Each piece must respect its style's **hard constraints** — whitespace % (breathing room), word limit (economy), element count (no visual noise), layout rules (spatial grammar), typography weight (voice). **If content exceeds constraints, reduce. Never violate the style. The constraints ARE the style.**

## Part 4: Execution Principles

**Visual hierarchy** — a single focal point per slide/card; a clear reading order (F- or Z-pattern); contrast guides attention; nothing competes with the message.

**Typography as visual element** — headlines bold, commanding, minimal; body text avoided when possible (whispered if unavoidable); numbers large, prominent, contextualized; labels small, quiet, supportive. Text is always minimal and visual-first; let context set whether that means whisper-quiet labels or bold typographic gestures, but sophistication is non-negotiable.

**Color application** — use the brand palette (or selected alternative) exclusively: Primary ~60% (dominant voice), Secondary ~30% (supporting harmony), Accent ~10% (emphasis only). Never introduce off-brand colors. *Personality-informed intensity (from Part 2b)*: Excitement → vibrant saturation, bolder blocks, higher-contrast accents; Sophistication → muted/desaturated, restrained accents; Sincerity → warm mid-saturation tones; Competence → clean, systematic application with clear hierarchy; Ruggedness → deep earthy values, textured application.

**Spatial communication** — whitespace is active, meaningful silence; placement carries meaning (center = importance, edges = supporting); proportion creates rhythm; margins are sacred — nothing touches edges, nothing overlaps.

## Part 5: Anti-Patterns (Death to These)

Bullet-point lists; walls of text (violate the 3-second rule); clip art or stock clichés; competing focal points; decoration without purpose; violating whitespace minimums; exceeding word limits; generic template feel.

## Part 6: The Final Polish

Before declaring done, assume the user already said: *"It isn't perfect enough. It must be pristine, a masterpiece of craftsmanship, as if about to be displayed in a museum."* To refine, do NOT add more elements — refine what exists and make it extremely crisp. Ask: **"How can I make what's already here more of a piece of art?"** Take a second pass: check every alignment, verify every spacing decision, confirm nothing overlaps, ensure breathing room between all elements, polish until it gleams.

## Part 6b: Accessibility & Safety (MANDATORY)

These checks are NON-NEGOTIABLE before any output is finalized. Run the
pre-render checklist for EVERY slide/card:

```
□ All text passes 4.5:1 contrast check (3:1 for 24px+ text)
□ No elements overlap (text, logos, icons, margins)
□ All elements within the safe zone (50px presentations / 54px carousels)
□ Word count within the style limit
□ Element count within the style limit
□ Gradient text readable at both ends (if applicable)
```

**If ANY check fails, DO NOT render. Fix the issue first.** Full procedures —
contrast validation steps, the absolute no-overlap rule, safe-zone tables, and
gradient text safety — are in `references/visual-craft.md` § Accessibility &
Safety Procedures. `validate_contrast()` code is in
`references/technical-implementation.md`.

## Part 7: Visual Components (Optional)

Some styles support visual components (cards, icons, gradients) that enhance the design. Components are opt-in (enabled during template creation) but must be used **intelligently based on content** — not on every slide just because they are enabled.

Before using ANY component, pass it through the **4 decision gates IN ORDER**: Gate 1 Style Permission → Gate 2 Content + Personality Justification → Gate 3 Frequency Budget (Cards ≤60% of slides, Icons ≤50%, Gradients ≤3 total) → Gate 4 Density Check (≤3 visual layers). A component that fails any gate is skipped in favour of an alternative treatment (bold text, typographic emphasis, solid background).

The full gate detail, the component-availability-by-style table, card/icon/gradient usage code, and the slide-type quick reference are in `references/visual-craft.md` § Visual Components. **When in doubt, use fewer.**

## Part 8: Technical Implementation

PDF generation code patterns are in `references/technical-implementation.md` — asset prep (SVG→PNG, font loading), reportlab patterns for presentations and carousels, color parsing, positioning patterns (Centered for Ma/Minimal, Asymmetric for Dramatic/Iki, Grid for Swiss), and the card/gradient/icon component code.

Key constraints: logos must be **PNG or JPG** (reportlab does not support SVG — `/brand-extract` converts SVG→PNG automatically); custom fonts load from `{PROJECT_PATH}/assets/fonts/`; colors parse from the brand-philosophy.md color table.

**Output process**: generate the PDF (source of truth) with the `pdf` skill, then convert presentations to PPTX with the `pptx` skill for editability.

### Google Slides output (additional, AI-authored per render)

When a presentation render also targets Google Slides, the LLM emits a Slides API `batchUpdate` `requests[]` list that visually matches the PDF, using the reportlab Python source as ground truth. The authoring guide — coordinate translation (px → PT), per-element recipes (text, background, gradient, logo, card, icon), font fallback, anti-patterns, and the `{name}.slides.batchupdate.json` persistence contract — lives in `../../references/slides-batchupdate-authoring.md`. Execution is handled by the Python runner in `scripts/slides/` (see `references/slides-credentials.md` for the env-var contract).

## Part 9: Workflow Integration

Called by `/template-presentation` and `/template-carousel` (generate samples) and by `/presentation`, `/presentation-quick`, `/carousel`, `/carousel-quick` (generate final output).

## Part 10: Input Requirements

When invoking this skill, provide: canvas philosophy content, the style enforcement block, the content outline, brand philosophy (colors, fonts, logo), output format, dimensions, and the optional visual-components config.

**No-brand safeguard** — if `brand-philosophy.md` is not found OR has no `## Color Palette` section: STOP and tell the user "No brand colors found. Run `/brand-extract` first to analyze your brand." If the user insists, use deliberately bland neutrals (#1a1a1a, #666, #f5f5f5, system fonts) — never fall back to any recognizable brand colors.

**Pre-output brand bias check** — before finalizing, verify all colors derive from the brand-philosophy.md color table, all fonts load from project `assets/fonts/` or brand-philosophy.md, no generic font defaults (unless the brand uses them), and text colors are WCAG-validated against the actual background.

## Part 11: The Ultimate Test

Before finalizing, ask: would this work hang in a design museum? Would a creative director approve it for a premium client? Does every pixel serve the message? Does it look like someone labored over it with painstaking care? If yes to all four, the work is ready. If no to any, return to Part 6 and polish until it gleams.
