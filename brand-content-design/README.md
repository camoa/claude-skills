# Brand Content Design Plugin

Create branded presentations and LinkedIn carousels with consistent visual identity using a three-layer philosophy system.

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

### 3. Create Templates (Recommended)

```
/template-presentation    # Guided wizard for presentation templates
/template-carousel        # Guided wizard for carousel templates
```

Templates define:
- Slide/card structure and sequence
- Visual design philosophy (canvas-philosophy.md)
- Sample output for reference

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

### 5. Create Content

**Guided mode** (step-by-step):
```
/presentation             # Full control over each slide
/carousel                 # Full control over each card
```

**Quick mode** (minimal questions):
```
/presentation-quick       # Topic + template, auto-generate
/carousel-quick           # Topic + template, auto-generate
```

## Commands Reference

| Command | Description |
|---------|-------------|
| `/brand` | Main entry - status, switch projects, or init |
| `/brand-init` | Create new brand project |
| `/brand-extract` | Generate brand philosophy from sources |
| `/brand-assets` | Manage assets (add logos, icons, fonts after extraction) |
| `/template-presentation` | Create or edit presentation template |
| `/template-carousel` | Create or edit carousel template |
| `/outline <template>` | Get outline template + AI prompt (presentations or carousels) |
| `/presentation` | Create presentation (guided) |
| `/presentation-quick` | Create presentation (quick) |
| `/carousel` | Create carousel (guided) |
| `/carousel-quick` | Create carousel (quick) |
| `/content-type-new` | Add new content type (infographic, etc.) |

## Three-Layer Philosophy System

```
Layer 1: BRAND PHILOSOPHY (brand-philosophy.md)
├── Visual DNA: colors, typography, imagery style
├── Verbal DNA: voice, tone, vocabulary
└── Core Principles: always/never rules

Layer 2: CONTENT TYPE GUIDES (plugin references)
├── Presentation Zen principles
├── Carousel best practices
└── Automatically updated with plugin

Layer 3: TEMPLATE + CANVAS PHILOSOPHY (per template)
├── template.md: structure, slide sequence
├── canvas-philosophy.md: visual design philosophy
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
- **Create templates first** - they make content creation faster
- **Use quick mode** for rapid iteration, guided mode for important pieces
- **Brand philosophy evolves** - re-run `/brand-extract` as your brand matures
- **Add assets anytime** - use `/brand-assets` to add logos, fonts, etc. without re-extracting
