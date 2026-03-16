# Bias Prevention Guidelines

Rules for preventing brand-specific values from leaking into generated output.
Adapted from design-intelligence's bias-prevention-guidelines.md for brand-content-design output types.

## Core Principle

**Reference files are DECISION FRAMEWORKS, not LOOKUP TABLES.**

Every generated output must derive its visual values from the project's brand-philosophy.md,
not from defaults, examples, or fallback values in reference files or code.

## Value Derivation Hierarchy

When generating any branded output, derive ALL visual values from these sources in priority order:

1. **Brand philosophy** — colors, fonts, and personality from `brand-philosophy.md`
2. **Design system tokens** — if a `design-system.md` exists, use its CSS custom properties
3. **Canvas philosophy** — aesthetic direction from `canvas-philosophy.md`
4. **WCAG constraint floors** — contrast ≥ 4.5:1, text sizes ≥ 14px
5. **Deliberately bland neutrals** — only if no brand is available (#1a1a1a, #666, #f5f5f5)

### Per Output Type

| Output Type | Color Source | Font Source | Spacing Source |
|-------------|-------------|-------------|----------------|
| **Infographic (JSON)** | Derived hex from brand palette | Brand heading/body fonts | Template defaults |
| **HTML page** | CSS custom properties from design-system.md | Google Fonts `<link>` from brand | Design tokens |
| **Presentation (PDF)** | `parse_brand_colors()` from brand-philosophy.md | `load_brand_fonts()` from assets | Style constraints |
| **Carousel (PDF)** | `parse_brand_colors()` from brand-philosophy.md | `load_brand_fonts()` from assets | Style constraints |
| **PPTX** | Converted from PDF brand colors | Embedded from assets/fonts | From PDF layout |

## Known Biased Defaults

These values are former hardcoded defaults that should NEVER appear in generated output:

### Colors
| Hex | Origin | Neutral Replacement |
|-----|--------|-------------------|
| `#0D2B5C` | Former Palcera navy | `#333333` |
| `#194582` | Former Palcera blue | `#444444` |
| `#00f3ff` | Former Palcera cyan | `#888888` |
| `#061120` | Former Palcera dark | `#1a1a1a` |
| `#60A5FA` | Former example blue | `#666666` |

### Fonts
| Font | Context | Replacement |
|------|---------|-------------|
| `Inter` | Former default heading/body | Brand's heading/body font |
| `Helvetica-Bold` | PDF code example default | `brand_fonts.get('heading', 'Helvetica-Bold')` |
| `Helvetica` | PDF code example default | `brand_fonts.get('body', 'Helvetica')` |

## Pre-Output Validation Checklist

Run before finalizing ANY generated content:

```
□ colorBg / background derived from brand-philosophy.md, not a default
□ colorPrimary / accent derived from brand-philosophy.md, not a default
□ Colors traced to brand-philosophy.md (not copied from reference docs or runtime fallbacks)
□ font-family from brand, not "Inter" or "Helvetica" (unless brand actually uses these)
□ Text colors WCAG-validated against actual background
□ Palette colors used for shapes/fills only, not text
□ If dark background: text is white/near-white
□ If light background: text is near-black/dark gray
```

## Marking Illustrative Values

When reference files must show example values for educational purposes:

- Prefix with comment: `/* Illustrative — derive from brand-philosophy.md */`
- Use `{brand-*}` placeholder syntax: `{brand-primary}`, `{brand-bg}`, `{brand-heading-font}`
- Add note: "The values shown are placeholders. Actual values come from your project's brand-philosophy.md."

## No-Brand Safeguard

If `brand-philosophy.md` is not found in the project:

1. **STOP generation** — inform user: "No brand-philosophy.md found. Run `/brand-extract` first to analyze your brand."
2. **If user insists on proceeding without brand**: Use deliberately bland neutrals that cannot be mistaken for any specific brand:
   - Background: `#f5f5f5` (light) or `#1a1a1a` (dark)
   - Text: `#333333` (on light) or `#e5e5e5` (on dark)
   - Accent: `#666666`
   - Fonts: System font stack (`-apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif`)
3. **Never** fall back to Palcera, example, or any recognizable brand colors.

## What Counts as Bias

### BIASED (must fix)
- Specific hex colors from any particular brand
- Specific font names as defaults (unless they're system fonts)
- Fixed pixel values when a token or range exists
- Example values that get copied verbatim into output

### NOT BIASED (keep)
- `#FFFFFF` / `#000000` (universal black/white)
- WCAG contrast calculation logic
- `rgba(255,255,255,0.85)` for text opacity on dark backgrounds (universal pattern)
- Safe zone margins and spacing constants
- Template structure and layout dimensions
