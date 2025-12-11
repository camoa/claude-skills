# Brand Content Design Plugin

Create branded presentations, LinkedIn carousels, and infographics with consistent visual identity.

## The Flow

```
Brand Guidelines → Templates → Content
```

1. **Brand Guidelines** - Extract your visual & verbal identity once
2. **Templates** - Create reusable slide/card/infographic structures (create once, use many times)
3. **Content** - Generate presentations/carousels/infographics using your templates

## Installation

```bash
claude plugins:add brand-content-design@camoa-skills
```

## Quick Start

```
/brand                    # Start here - status, switch projects, or create new
```

### First Time Setup (do once per brand)
```
/brand-init               # 1. Create project structure
/brand-extract            # 2. Extract brand colors, fonts, voice
/brand-palette            # 3. (Optional) Generate alternative palettes
/template-presentation    # 4. Create your first presentation template
/template-carousel        # 5. Create your first carousel template
/template-infographic     # 6. Create your first infographic template
```

### Creating Content (repeat as needed)
```
/outline <template-name>  # (Optional) Get outline structure + AI prompt
/presentation             # Create presentation from template
/carousel                 # Create carousel from template
/infographic              # Create infographic from template
```

### Managing Your Brand
```
/brand                    # Check status, switch projects
/brand-assets             # Add/update logos, fonts after setup
/brand-palette            # Generate new color palettes anytime
```

## Workflow (Detailed)

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
│   ├── carousels/        # Reusable carousel templates
│   └── infographics/     # Reusable infographic templates
├── presentations/        # Generated presentations
├── carousels/            # Generated carousels
├── infographics/         # Generated infographics
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
/template-infographic     # Guided wizard for infographic templates
```

Templates define:
- Slide/card/infographic structure and sequence
- Visual style (from 13 styles across 4 aesthetic families for presentations/carousels)
- Color palette (brand colors or saved alternative palette)
- Visual design philosophy (canvas-philosophy.md)
- Sample PPTX/PDF/PNG for reference

**You need at least one template before you can create content.**

### 4. Prepare Content with Outline (Optional)

```
/outline <template-name>  # Get outline template + AI prompt
```

Generates two files for your template:
- **outline-template.md** - Fill-in-the-blank structure matching your slides/cards
- **outline-prompt.txt** - Prompt to use in Claude Projects or any AI chat
  - Includes slide/card type definitions (purpose, content requirements, word limits)
  - External AI will understand exactly what each slide/card type needs

**Workflow:**
1. Run `/outline my-template` to get the prompt
2. Open Claude Projects (or any AI) where you have your content/context
3. Paste the `outline-prompt.txt` content
4. Add your raw content where indicated (`[PASTE YOUR CONTENT HERE]`)
5. AI returns a structured outline matching your template's slide/card sequence
6. Copy the AI's output
7. Run `/presentation` or `/carousel`, select your template
8. Paste the structured outline when asked for content

**Why this works:** The prompt teaches the external AI your template's exact structure and constraints, so its output maps perfectly to `/presentation` or `/carousel`.

### 5. Create Content (using your templates)

**Guided mode** (step-by-step):
```
/presentation             # Select template, provide content
/carousel                 # Select template, provide content
/infographic              # Select template, provide content
```

**Quick mode** (paste and go):
```
/presentation-quick       # Select template, paste content
/carousel-quick           # Select template, paste content
/infographic-quick        # Select template, paste content
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
| `/template-infographic` | Create or edit infographic template |
| `/outline <template>` | Get outline template + AI prompt |
| `/presentation` | Create presentation (guided) |
| `/presentation-quick` | Create presentation (quick) |
| `/carousel` | Create carousel (guided) |
| `/carousel-quick` | Create carousel (quick) |
| `/infographic` | Create infographic (guided) |
| `/infographic-quick` | Create infographic (quick) |
| `/content-type-new` | Add new content type |

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

## Visual Components

Enhance carousels and presentations with **visual components** - available based on your chosen style:

| Component | Description | Supported Styles |
|-----------|-------------|------------------|
| **Cards** | Rounded containers for content grouping | Dramatic, Organic, Hygge, Memphis, Feng Shui, Iki, Lagom, Swiss |
| **Icons** | 1900+ Lucide icons for visual accents | Dramatic, Organic, Hygge, Memphis, Feng Shui, Iki, Lagom, Swiss |
| **Gradients** | Linear/radial backgrounds for depth | Dramatic, Organic, Hygge, Memphis, Feng Shui |

### Component Support by Style

| Style | Cards | Icons | Gradients |
|-------|:-----:|:-----:|:---------:|
| Dramatic | ✓ | ✓ | ✓ |
| Organic | ✓ | ✓ | ✓ |
| Hygge | ✓ | ✓ | ✓ |
| Memphis | ✓ | ✓ | ✓ |
| Feng Shui | ✓ | ✓ | ✓ |
| Iki | ✓ | ✓ | ✗ |
| Lagom | ✓ | ✓ | ✗ |
| Swiss | ✓ | ✓ | ✗ |
| Minimal | ◐ | ✗ | ✗ |
| Wabi-Sabi | ◐ | ✗ | ✗ |
| Shibui | ◐ | ✗ | ✗ |
| Ma | ✗ | ✗ | ✗ |
| Yeo-baek | ✗ | ✗ | ✗ |

**◐** = Subtle/limited support (border-only cards)

When creating templates with `/template-carousel` or `/template-presentation`, you'll be asked which visual components to enable based on your selected style.

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

## Infographic System

Create data visualizations, process diagrams, timelines, and comparisons using **114 built-in templates** powered by @antv/infographic.

### Template Categories

| Category | Templates | Use Cases |
|----------|-----------|-----------|
| **Sequence** | 43 | Timelines, steps, processes, roadmaps, flows |
| **List** | 23 | Tips, features, grids, pyramids, sectors |
| **Hierarchy** | 25 | Org charts, tree structures, taxonomies |
| **Compare** | 17 | VS, before/after, pros/cons, SWOT |
| **Quadrant** | 3 | 2x2 matrices, priority grids |
| **Relation** | 2 | Networks, circular connections |
| **Chart** | 1 | Statistics, metrics, bar charts |

### Template Asset Types

Templates come in three varieties based on visual assets:

| Type | Identifier | Description | Complexity |
|------|------------|-------------|------------|
| **Text-only** | (default) | Labels and descriptions only | Easiest - just provide content |
| **Icon-based** | `icon` in name | Uses icon syntax `icon:rocket` | Medium - choose from icon library |
| **Illustrated** | `-illus` suffix | Requires custom SVG illustrations | Advanced - create SVGs per item |

**Recommendations:**
- Start with **text-only** templates (100+ options)
- Use **icon-based** for visual appeal without custom art (8 templates)
- Use **illustrated** only when you have custom SVG assets (9 templates)

### Text Guidelines (Avoiding Overlap)

Infographic templates have limited space. Follow these guidelines:

| Element | Max Length | Example |
|---------|------------|---------|
| **Labels** | 1-2 words | "Cloud", "Security" |
| **Descriptions** | 2-4 words | "Infrastructure design" |
| **Title** | 3-5 words | "Our Services" |

If content is longer:
1. Use a template with more space (grid vs row)
2. Increase canvas width (1200px+)
3. Use column/done-list templates (more vertical space)

### Background Presets

| Preset | Effect | Best For |
|--------|--------|----------|
| `solid` | Clean solid color | Minimalist |
| `spotlight` | Radial gradient from center | Focus emphasis |
| `spotlight-dots` | Gradient + dot pattern | Modern tech |
| `spotlight-grid` | Gradient + grid overlay | Technical |
| `tech-matrix` | Tech-style gradient + grid | Data/engineering |
| `diagonal-crosshatch` | Diagonal gradient + crosshatch | Creative |

### Infographic Workflow

```
1. /template-infographic    # Choose category → design → style → save template
2. /infographic             # Select template → provide content → generate PNG/SVG
```

Or quick mode:
```
/infographic-quick          # Select template → paste content → get PNG
```

### Output Specifications

- **Dimensions**: Configurable (default 1920x1080 for slides, 1080x1080 for social)
- **Formats**: PNG (recommended), SVG (vector)
- **Location**: `infographics/{date}-{name}/`

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

## Accessibility & Quality Enforcement

All generated content automatically enforces:

| Check | Standard | Action |
|-------|----------|--------|
| **Contrast ratio** | WCAG AA (4.5:1 minimum) | Auto-fixes with safe colors |
| **No text overlap** | Elements never collide | Validates bounding boxes |
| **Safe zones** | 50px presentations, 5% carousels | Enforces margins |
| **Gradient text** | Readable at both ends | Validates contrast range |
| **Word limits** | Per style constraints | Prevents text walls |

**Logo format**: PNG or JPG only (SVG auto-converted during `/brand-extract`)

## Dependencies

This plugin uses these skills for visual output:

| Skill | Purpose | Status |
|-------|---------|--------|
| **visual-content** | Generate presentations/carousels from canvas philosophy | Bundled (no install needed) |
| **infographic-generator** | Generate infographics from @antv/infographic | Bundled (no install needed) |
| **pptx** | Convert PDF to editable PowerPoint | Built-in (Claude.ai Pro/Max/Team/Enterprise) |
| **pdf** | Create multi-page PDFs | Built-in (Claude.ai Pro/Max/Team/Enterprise) |

The `visual-content` skill is bundled with this plugin - it uses artistic philosophy language to create museum-quality visual output following your brand and template constraints.

The `infographic-generator` skill provides 114 data visualization templates with brand theming and custom backgrounds.

## Tips

- **Start with `/brand`** - it adapts to your context
- **Templates are required** - create at least one before making content
- **One template, many outputs** - create a template once, use it for dozens of presentations/carousels
- **Use `/outline`** - helps structure your content to match the template
- **Quick mode** for rapid iteration, **guided mode** for important pieces
- **Brand philosophy evolves** - re-run `/brand-extract` as your brand matures
