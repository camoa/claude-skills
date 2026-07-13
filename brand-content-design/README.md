# Brand Content Design

[![Listed on ClaudePluginHub](https://www.claudepluginhub.com/badge/camoa-brand-content-design-brand-content-design)](https://www.claudepluginhub.com/plugins/camoa-brand-content-design-brand-content-design?ref=badge)

Every deck, carousel, and one-pager drifts a little further from the brand. Colors get eyeballed instead of pulled from the palette, the tone shifts slide to slide, and the fifth presentation this quarter looks like it came from a different company than the first. That drift is not carelessness: it is what happens when every piece of content starts from a blank page instead of a shared source of truth.

> **Not using Claude Code?** See the marketplace [PORTABILITY.md](../PORTABILITY.md), skills work in Cursor, Codex CLI, Copilot, Gemini CLI, Cline, and more.

This plugin fixes the starting point. You extract your brand once into `brand-philosophy.md` (colors, type, voice, and an Aaker personality profile), build a template or design system once per content type, and every presentation, carousel, infographic, or HTML page after that is generated from those same files. The palette, the constraints, and the voice do not have to be remembered or re-explained; they are read from disk every time. Twenty-six visual styles, 15 HTML component types, and 114 infographic templates give you range within that constraint, and a built-in accessibility pass (WCAG AA contrast, no text overlap, safe zones) checks every output before you see it.

## See it in action

Four real commands, one brand, one carousel. Output trimmed to what matters.

```text
$ /brand-content-design:brand-init
  Project name? acme-labs
  → acme-labs/ created (brand-philosophy.md placeholder, input/, templates/, output folders)

$ /brand-content-design:brand-extract
  Found in input/: 3 screenshots, 1 logo, 1 PDF of brand guidelines.
  Anything else? (website URL, verbal description, or "use the files")
  → use the files
  → brand-philosophy.md written: colors, type, voice, Aaker personality scores

$ /brand-content-design:template-carousel
  Create new or edit existing? → Create new
  Platform? → LinkedIn (1080x1350)
  Style? → Swiss (strict grid, mathematical precision)
  → templates/carousels/product-launch/ saved (template.md, canvas-philosophy.md, sample.pdf)

$ /brand-content-design:carousel-quick
  Which template? → product-launch
  Paste your outline or content: [pasted 6 bullet points]
  → carousels/2026-07-13-product-launch/product-launch.pdf (6 cards, brand colors, WCAG AA checked)
```

Nothing here invented the brand or the message. The palette and the voice came from `brand-philosophy.md`, the structure and style constraints came from the template you built once, and you supplied the content. What changed is that the fifth carousel looks like the first one.

## When to reach for it

- You are producing more than one piece of branded content (a deck, a set of LinkedIn carousels, a landing page) and want them visually and verbally consistent without re-explaining the brand each time.
- You need a quick one-off (`*-quick` commands) as much as a considered, step-by-step piece (the guided commands): both read from the same brand and template files.
- You are extending into a new content type on an existing brand (an HTML page after presentations, an infographic after carousels): the brand extraction step happens once and every content type after that reuses it.

It is not the right tool for a single ungoverned piece of content where brand consistency does not matter, or for editing raw HTML/CSS by hand outside the design-system flow.

## How it works

```
Brand Guidelines → Templates / Design Systems → Content
```

1. **Brand Guidelines**: extract your visual and verbal identity once (`/brand-extract`) from screenshots, PDFs, a website URL, or a description.
2. **Templates / Design Systems**: build a reusable structure once per content type (`/template-presentation`, `/template-carousel`, `/template-infographic`, `/design-html`).
3. **Content**: generate as many presentations, carousels, infographics, or HTML pages as you need from those templates, guided or quick.

Full workflow, the complete command reference, the 26 visual styles, the HTML component catalog, and the infographic template categories are in [docs/usage.md](docs/usage.md).

## Installation

```bash
/plugin marketplace add https://github.com/camoa/claude-skills
/plugin install brand-content-design@camoa-skills
```

**Bundled (no separate install needed):** the `visual-content`, `infographic-generator`, and `html-generator` skills that do the actual generation.

**Built-in (Claude.ai Pro/Max/Team/Enterprise):** the `pptx` skill (PDF to editable PowerPoint) and `pdf` skill (multi-page PDF creation) that this plugin's outputs depend on.

**Logo format:** PNG or JPG only; SVG logos are auto-converted during `/brand-extract`.

## Commands

| Command | Description |
|---------|-------------|
| `/brand` | Status, switch projects, or start new. |
| `/brand-init` | Create a new brand project folder structure. |
| `/brand-extract` | Extract brand elements from your sources into `brand-philosophy.md`. |
| `/brand-assets` | Add or update logos, icons, fonts after extraction. |
| `/brand-palette` | Generate alternative color palettes (17 types) from your brand colors. |
| `/template-presentation`, `/template-carousel`, `/template-infographic` | Guided wizards for reusable templates. |
| `/design-html` | Create or edit an HTML design system (tokens plus component catalog). |
| `/outline <template>` | Get a fill-in-the-blank outline and an AI prompt for a template. |
| `/presentation`, `/carousel`, `/infographic`, `/html-page` | Guided content generation from a template or design system. |
| `/presentation-quick`, `/carousel-quick`, `/infographic-quick`, `/html-page-quick` | Quick, paste-and-go content generation. |
| `/content-type-new` | Add a new content type. |

The full reference with every field, style, and enforcement rule is in [docs/usage.md](docs/usage.md).

## More

- **Deeper how-to:** [docs/usage.md](docs/usage.md). Prerequisites, "it's working if", and where this plugin fits with the rest of the marketplace.
- **Philosophy:** [../PHILOSOPHY.md](../PHILOSOPHY.md). Why the marketplace's plugins are built this way.
- **Changelog:** [CHANGELOG.md](./CHANGELOG.md).

## License

MIT
