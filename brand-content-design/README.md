# Brand Content Design Plugin

Create branded presentations and LinkedIn carousels with consistent visual identity.

## The Flow

```
Brand Guidelines → Templates → Content
```

1. **Brand Guidelines** - Extract your visual & verbal identity once
2. **Templates** - Create reusable slide/card structures (create once, use many times)
3. **Content** - Generate presentations/carousels using your templates

## Installation

```bash
claude plugins:add brand-content-design@camoa-skills
```

## Quick Start

```
/brand                    # Start here - status, switch projects, or create new
```

## Workflow

### 1. Initialize a Project

```
/brand-init
```

Creates a project folder with this structure:
```
{brand-name}/
├── brand-philosophy.md   # Your brand's visual & verbal DNA
├── assets/               # Processed assets ready for use
├── templates/
│   ├── presentations/    # Reusable presentation templates
│   └── carousels/        # Reusable carousel templates
├── presentations/        # Generated presentations
├── carousels/            # Generated carousels
└── input/                # Source files
    ├── logos/            # Logo files (SVG, PNG, AI, EPS)
    ├── icons/            # Icon sets, favicons
    ├── images/           # Brand photography, illustrations
    ├── fonts/            # Custom font files
    ├── screenshots/      # For brand analysis
    └── documents/        # For brand analysis
```

### 2. Extract Brand Philosophy

```
/brand-extract
```

Analyzes your brand from multiple sources:
- **Files** in `input/` folder (screenshots, PDFs, logos)
- **Website URL** - paste your site to analyze
- **Verbal description** - describe your brand in chat
- **Existing guidelines** - paste brand docs directly

Generates `brand-philosophy.md` with your visual identity, voice, and core principles.

### 3. Create Templates (Required before creating content)

```
/template-presentation    # Guided wizard for presentation templates
/template-carousel        # Guided wizard for carousel templates
```

Templates define:
- Slide/card structure and sequence
- Visual style (from 13 styles across 4 aesthetic families)
- Color palette (brand colors or saved alternative palette)
- Visual design philosophy (canvas-philosophy.md)
- Sample PPTX/PDF for reference

**You need at least one template before you can create presentations or carousels.**

### 4. Prepare Content with Outline (Optional)

```
/outline <template-name>  # Get outline template + AI prompt
```

Generates two files for your template:
- **outline-template.md** - Fill-in-the-blank structure matching your slides/cards
- **outline-prompt.txt** - Prompt to use in Claude Projects or any AI chat

**Workflow:**
1. Work on your content in Claude Projects (with your context)
2. Run `/outline my-template` to get the prompt
3. Paste the prompt + your raw content into Claude Projects
4. Get back a structured outline that maps to your template
5. Use that outline with `/presentation` or `/carousel`

### 5. Create Content (using your templates)

**Guided mode** (step-by-step):
```
/presentation             # Select template, provide content
/carousel                 # Select template, provide content
```

**Quick mode** (paste and go):
```
/presentation-quick       # Select template, paste content
/carousel-quick           # Select template, paste content
```

## Commands Reference

| Command | Description |
|---------|-------------|
| `/brand` | Main entry - status, switch projects, or init |
| `/brand-init` | Create new brand project |
| `/brand-extract` | Generate brand philosophy from sources |
| `/brand-assets` | Manage assets (add logos, icons, fonts after extraction) |
| `/brand-palette` | Generate alternative color palettes from brand colors |
| `/template-presentation` | Create or edit presentation template |
| `/template-carousel` | Create or edit carousel template |
| `/outline <template>` | Get outline template + AI prompt (presentations or carousels) |
| `/presentation` | Create presentation (guided) |
| `/presentation-quick` | Create presentation (quick) |
| `/carousel` | Create carousel (guided) |
| `/carousel-quick` | Create carousel (quick) |
| `/content-type-new` | Add new content type (infographic, etc.) |

## Visual Style System

Choose from **13 distinct visual styles** across 4 aesthetic families when creating templates:

### Japanese Zen (7 styles)
| Style | Character | Best For |
|-------|-----------|----------|
| **Minimal** | Max whitespace, single focal point | Executive, data presentations |
| **Dramatic** | Asymmetrical, bold contrast | Pitch decks, launches |
| **Organic** | Natural flow, subtle depth | Storytelling, tips |
| **Wabi-Sabi** | Imperfect beauty, texture | Artisan, craft brands |
| **Shibui** | Quiet elegance, ultra-refined | Luxury, professional |
| **Iki** | B&W + pop color, editorial | Fashion, editorial |
| **Ma** | 70%+ whitespace, floating elements | Meditation, luxury |

### Scandinavian Nordic (2 styles)
| Style | Character | Best For |
|-------|-----------|----------|
| **Hygge** | Warm, cozy, inviting | Wellness, community |
| **Lagom** | Balanced "just enough" | Corporate, balance |

### European Modernist (2 styles)
| Style | Character | Best For |
|-------|-----------|----------|
| **Swiss** | Strict grid, mathematical precision | Tech, corporate |
| **Memphis** | Bold colors, playful chaos | Creative, youth brands |

### East Asian Harmony (2 styles)
| Style | Character | Best For |
|-------|-----------|----------|
| **Yeo-baek** | Extreme emptiness, Korean purity | Premium, meditation |
| **Feng Shui** | Yin-Yang balance, energy flow | Wellness, harmony |

Each style has enforced constraints (whitespace %, word limits, element counts) to ensure authentic visual output.

## Color Palette System

Generate alternative color palettes from your brand colors:

```
/brand-palette
```

Choose between two approaches:

### Derived Palettes (Color Theory)

Mathematical derivations from your brand colors. Select which source colors to use:
- **Primary only** - Generate from main brand color
- **All brand colors** - Generate from each color, combine results
- **Pick specific** - Choose which colors to use

#### Harmony-Based (Color Wheel)
| Type | Description | Use Case |
|------|-------------|----------|
| **Monochromatic** | Single hue, varying lightness | Safe, cohesive |
| **Analogous** | Adjacent colors | Harmonious, comfortable |
| **Complementary** | Opposite colors | High contrast, CTAs |
| **Split-Complementary** | Base + two adjacent to complement | Contrast with less tension |
| **Triadic** | Three equally spaced | Balanced, vibrant |
| **Tetradic** | Four colors (rectangle) | Rich, complex |

#### Tonal Variations
| Type | Description | Use Case |
|------|-------------|----------|
| **Tints** | Source + white | Soft backgrounds |
| **Shades** | Source + black | Bold emphasis |
| **Tones** | Source + gray | Sophisticated, subtle |
| **Interpolation** | Gradients between source colors | Data viz, smooth transitions |

### Alternative Palettes (Mood-Based)

Completely different colors that maintain your brand's feeling. Transforms your **entire palette**:

| Type | Description | Use Case |
|------|-------------|----------|
| **Pastel** | Lighten + desaturate | Gentle campaigns |
| **Bold** | High saturation, strong contrast | Impact, announcements |
| **Earthy** | Natural equivalents | Sustainable, authentic |
| **Vibrant** | Bright, saturated | Youth, energy |
| **Muted** | Desaturated, refined | Luxury, sophistication |
| **Monochrome** | Grayscale + one accent | Editorial, dramatic |
| **Custom** | Describe a mood | Seasonal campaigns |

**17 palette types total** (10 derived + 7 alternative). Generated palettes are saved to `brand-philosophy.md` for use in content creation.

## Three-Layer Philosophy System

```
Layer 1: BRAND PHILOSOPHY (brand-philosophy.md)
├── Visual DNA: colors, typography, imagery style
├── Verbal DNA: voice, tone, vocabulary
└── Core Principles: always/never rules

Layer 2: CONTENT TYPE GUIDES (plugin references)
├── Presentation Zen principles
├── Carousel best practices
├── 13 visual styles with constraints
└── Automatically updated with plugin

Layer 3: TEMPLATE + CANVAS PHILOSOPHY (per template)
├── template.md: structure, slide sequence
├── canvas-philosophy.md: visual design philosophy + style constraints
└── sample.pdf: visual reference
```

## Output Specifications

### Presentations
- Dimensions: 1920x1080 (16:9)
- Format: PDF + PPTX
- Location: `presentations/{date}-{name}/`

### LinkedIn Carousels
- Dimensions: 1080x1350 (4:5 portrait)
- Format: Multi-page PDF
- Location: `carousels/{date}-{name}/`

### Instagram Carousels
- Dimensions: 1080x1080 (1:1 square)
- Format: PDF or PNG sequence

## Tips

- **Start with `/brand`** - it adapts to your context
- **Templates are required** - create at least one before making content
- **One template, many outputs** - create a template once, use it for dozens of presentations/carousels
- **Use `/outline`** - helps structure your content to match the template
- **Quick mode** for rapid iteration, **guided mode** for important pieces
- **Brand philosophy evolves** - re-run `/brand-extract` as your brand matures
