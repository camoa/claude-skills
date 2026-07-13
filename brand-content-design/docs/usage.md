# Using Brand Content Design

The [README](../README.md) is the shop window. This is the how: what the plugin does, when to reach for it, what it needs, how you know it is working, and where it fits with the rest of the marketplace.

## What it does

The plugin runs a three-layer flow: **Brand Guidelines → Templates / Design Systems → Content**. `/brand-extract` reads your sources (screenshots, PDFs, a website URL, or a plain description) and writes `brand-philosophy.md`: colors, typography, imagery style, voice, core always/never rules, and a Brand Depth section (Aaker personality scores, color and emotional profile, spatial rhythm, brand maturity). Every template you build after that, and every piece of content generated from it, reads back from this one file, so the palette and the voice do not have to be re-explained per piece.

A **template** (`/template-presentation`, `/template-carousel`, `/template-infographic`) fixes a structure: slide or card sequence, one of 26 visual styles across 6 aesthetic families, a color palette, and a `canvas-philosophy.md` that states the visual design intent in enforceable terms. A **design system** (`/design-html`) is the same idea for the web: tokens plus a growing catalog of the 15 component types (navigation, hero, feature grid, and so on), composed into pages rather than filled into a fixed sequence. You build a template or design system once and reuse it for as many pieces of content as you need.

Content generation (`/presentation`, `/carousel`, `/infographic`, `/html-page`, and their `*-quick` counterparts) then takes that template plus your content and produces the output: PDF and PPTX for presentations, multi-page PDF for carousels, PNG or SVG for infographics (114 templates across sequence, list, hierarchy, compare, quadrant, relation, and chart categories), a single standalone HTML file for pages. Every output is checked before you see it: WCAG AA contrast (4.5:1 minimum, auto-fixed with safe colors where possible), no element overlap, safe-zone margins, and per-style word limits. That check is deterministic (bounding boxes and contrast ratios are computed, not eyeballed), so it either passes or it flags a specific violation, not a vague "looks fine."

## When to reach for it

- You are producing more than one piece of branded content and want them visually and verbally consistent without re-describing the brand each time: a deck this week, a carousel next week, a landing page after that, all reading from the same `brand-philosophy.md`.
- You want a fast, paste-and-go path (`*-quick` commands) as often as a considered, guided one (the wizard commands); both draw on the same brand and template files, so neither drifts from the other.
- You are extending an existing brand into a new content type: run `/content-type-new`, or just start the relevant `/template-*` command; the brand extraction step is done once and reused.
- The **effort-adaptive router**: when you ask for content without naming a variant ("make a presentation"), the plugin picks `*-quick` at low effort and the guided wizard at medium and above, so the same request scales with how much attention you want to give it.

It is not the right tool for a single ungoverned piece of content where brand consistency does not matter, or for hand-editing HTML/CSS outside the design-system flow (the generated HTML is convertibility-ready for a future SDC or React pass, but this plugin's job stops at generating it).

## Prerequisites

- A **brand project folder**, created by `/brand-init`, containing `brand-philosophy.md` plus the `templates/`, `input/`, and output subfolders. Most commands look for this file in the current or parent directory and stop with instructions if it is missing.
- **At least one template** before creating content: `/template-presentation`, `/template-carousel`, or `/template-infographic` for template-driven content; `/design-html` for HTML pages.
- **Logo files as PNG or JPG.** SVG logos are auto-converted during `/brand-extract`; other vector-only formats are not.
- **Bundled skills, no separate install:** `visual-content` (presentations and carousels from canvas philosophy), `infographic-generator` (114 @antv/infographic templates), and `html-generator` (design-system-driven HTML). These ship with the plugin.
- **Built-in Claude.ai skills** for two output formats: `pptx` (PDF to editable PowerPoint) and `pdf` (multi-page PDF assembly), available on Claude.ai Pro, Max, Team, and Enterprise. Without them, presentation and carousel commands cannot produce their PPTX/PDF outputs.
- Optional but recommended: `${CLAUDE_EFFORT}` set to a meaningful level if you want the effort-adaptive router to pick quick versus guided variants deliberately rather than by default.

## It's working if

- `/brand` prints your current project (or offers to create or switch one) and reflects what is actually on disk.
- `brand-philosophy.md` exists and has real values in its Visual DNA, Verbal DNA, and Core Principles sections, not the `/brand-init` placeholder text.
- Each template folder (`templates/{carousels,presentations,infographics}/{name}/`) contains `template.md`, `canvas-philosophy.md`, and a sample PDF or PNG you can visually check against your brand.
- A content command writes its output to the dated folder it promises (`carousels/{date}-{name}/`, `presentations/{date}-{name}/`, and so on), and the file is openable and matches the template's dimensions.
- Generated content passes the accessibility check silently; if it does not, the command reports which check failed (contrast, overlap, safe zone, or word limit) rather than producing an output that quietly violates it.

If `/brand` cannot find a project, run `/brand-init`. If a content command stops asking for a template, run the matching `/template-*` or `/design-html` command first, this is enforced, not optional: templates and design systems exist so content is never freehand.

## Where it fits

This plugin is not part of the `ai-dev-assistant` coding lifecycle and does not depend on it: there is no scope contract, no research/design/implement/review phases, and no code review gate here. It is a sibling plugin in the same marketplace, applying the marketplace's shared principle (deterministic checks where a check can be deterministic, like contrast ratios and bounding boxes, rather than an assertion) to brand and content work instead of code. See [../../PHILOSOPHY.md](../../PHILOSOPHY.md) for that shared reasoning.

Where the two do meet: if a task in `ai-dev-assistant` needs the visual identity or the actual markup this plugin produces, such as building a real Next.js or Drupal site from an HTML page this plugin generated, that HTML is a content input to the coding task, not something `ai-dev-assistant` invokes this plugin to build for it. The two stay decoupled; you run brand-content-design to produce the asset, then hand it to whatever build process consumes it.

Two of this plugin's generation paths lean on Anthropic's own skills rather than reimplementing them: `pptx` for editable PowerPoint output and the `canvas-design` approach (via the built-in `pdf` skill) for high-fidelity PDF generation. Both are acknowledged in the marketplace [README](../../README.md#acknowledgments).
