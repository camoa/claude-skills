# Visual Components Reference

Universal visual components available to carousel and presentation templates, constrained by each style's aesthetic rules.

## Overview

Visual components extend the basic text + image capabilities with:
- **Cards** - Rounded containers for content grouping
- **Icons** - Lucide icon library for visual accents
- **Gradients** - Background color transitions

**Important:** Not all styles support all components. Check `style-constraints.md` for style-specific rules.

---

## Cards

Rounded rectangle containers that group related content.

### Card Types

| Type | Description | Use Case |
|------|-------------|----------|
| **Content Card** | Text container with background | Feature descriptions, tips, quotes |
| **Icon Card** | Square with centered icon + label | Process steps, categories |
| **Feature Card** | Icon + title + description | Feature highlights, benefits |
| **Stat Card** | Large number + label | Metrics, statistics |

### Card Properties

| Property | Options | Default |
|----------|---------|---------|
| `corner_radius` | 0, 8, 16, 24 px | 16 |
| `fill_color` | Brand color, transparent | Secondary at 10% |
| `border_color` | Brand color, none | None |
| `border_width` | 1, 2, 3 px | 2 |
| `padding` | 16, 24, 32 px | 24 |
| `shadow` | none, subtle, medium | none |

### Card Style Variations

| Style Family | Card Aesthetic |
|--------------|----------------|
| **Minimal** | Thin border only, no fill |
| **Dramatic** | Bold fill, high contrast |
| **Organic** | Soft fill, warm tones |
| **Hygge** | Warm fill, large radius |
| **Swiss** | Precise borders, grid-aligned |
| **Memphis** | Colorful fills, geometric |

### reportlab Implementation

```python
def draw_content_card(canvas, x, y, width, height,
                      fill_color=None, border_color=None,
                      radius=16, border_width=2):
    """Draw a content card container."""
    canvas.saveState()

    if fill_color:
        canvas.setFillColor(HexColor(fill_color))
    if border_color:
        canvas.setStrokeColor(HexColor(border_color))
        canvas.setLineWidth(border_width)

    canvas.roundRect(x, y, width, height, radius,
                     fill=bool(fill_color),
                     stroke=bool(border_color))

    canvas.restoreState()
```

---

## Icons

Lucide icon library for visual accents. Same library used by infographic-generator.

### Icon Categories

| Category | Icons | Use Case |
|----------|-------|----------|
| **business** | briefcase, building, landmark, store, factory | Corporate, B2B |
| **growth** | trending-up, chart-bar, target, award, trophy | Metrics, success |
| **people** | user, users, user-plus, heart, smile | Community, social |
| **technology** | laptop, smartphone, cloud, database, cpu | Tech, digital |
| **communication** | mail, message-circle, phone, video, megaphone | Contact, social |
| **actions** | check, check-circle, plus, edit, trash-2 | UI, status |
| **navigation** | arrow-right, arrow-left, chevron-right | Direction, flow |
| **time** | clock, calendar, timer, hourglass | Scheduling |
| **documents** | file, file-text, folder, clipboard, book | Content |
| **security** | lock, shield, key, eye | Privacy, safety |
| **money** | dollar-sign, credit-card, wallet, coins | Finance |
| **nature** | sun, moon, leaf, tree, flower | Environment |
| **misc** | star, heart, flag, lightbulb, rocket | General |

### Icon Syntax

Reference icons in outlines using `icon:name` syntax:

```markdown
## Card 2: Feature
- Icon: icon:lightbulb
- Title: Smart Discovery
- Description: AI-powered recommendations
```

### Icon Properties

| Property | Options | Default |
|----------|---------|---------|
| `size` | 24, 32, 48, 64 px | 48 |
| `color` | Brand color, contextual | Primary |
| `style` | outline, filled | outline |

### Icon Placement

| Placement | Description |
|-----------|-------------|
| **in-card** | Centered in icon card or left-aligned in feature card |
| **standalone** | Decorative element outside cards |
| **inline** | Small icon next to text |

### Python Helper Usage

```python
from scripts.icons import get_icon_png, search_icons, ICON_CATEGORIES

# Get icon as PNG for reportlab
icon_path = get_icon_png('lightbulb', color='#3B82F6', size=48)
canvas.drawImage(icon_path, x, y, width=48, height=48, mask='auto')

# Search icons
matches = search_icons('chart')  # ['chart-bar', 'chart-line', 'chart-pie', ...]

# List category
business_icons = ICON_CATEGORIES['business']
```

---

## Gradients

Background color transitions for depth and visual interest.

### Gradient Types

| Type | Description | Use Case |
|------|-------------|----------|
| **Linear** | Two colors transitioning in a direction | Background sweeps |
| **Radial** | Colors radiating from center | Focal emphasis |

### Gradient Directions (Linear)

| Direction | Start → End |
|-----------|-------------|
| `horizontal` | Left → Right |
| `vertical` | Bottom → Top |
| `diagonal` | Bottom-left → Top-right |
| `diagonal-reverse` | Top-left → Bottom-right |

### Gradient Properties

| Property | Options | Default |
|----------|---------|---------|
| `color1` | Brand color | Primary |
| `color2` | Brand color | Secondary |
| `direction` | horizontal, vertical, diagonal | diagonal |
| `opacity` | 0.0 - 1.0 | 1.0 |

### Gradient Style Variations

| Style | Gradient Aesthetic |
|-------|-------------------|
| **Dramatic** | Bold, high contrast angles |
| **Organic** | Warm, subtle transitions |
| **Hygge** | Warm candlelight tones |
| **Memphis** | Vibrant, playful colors |
| **Feng Shui** | Harmonious, balanced |

### reportlab Implementation

```python
from reportlab.lib.colors import linearGradient, HexColor

def draw_gradient_background(canvas, width, height,
                             color1, color2, direction='diagonal'):
    """Draw gradient background on canvas."""
    canvas.saveState()

    # Calculate gradient vector based on direction
    if direction == 'horizontal':
        x1, y1, x2, y2 = 0, height/2, width, height/2
    elif direction == 'vertical':
        x1, y1, x2, y2 = width/2, 0, width/2, height
    elif direction == 'diagonal-reverse':
        x1, y1, x2, y2 = 0, height, width, 0
    else:  # diagonal (default)
        x1, y1, x2, y2 = 0, 0, width, height

    gradient = linearGradient(x1, y1, x2, y2,
                              [HexColor(color1), HexColor(color2)])
    canvas.setFillColor(gradient)
    canvas.rect(0, 0, width, height, fill=True, stroke=False)

    canvas.restoreState()
```

---

## Style Compatibility Matrix

Quick reference for which components each style supports:

| Style | Cards | Icons | Gradients | Notes |
|-------|:-----:|:-----:|:---------:|-------|
| **Minimal** | ◐ | ✗ | ✗ | Cards: thin border only |
| **Dramatic** | ✓ | ✓ | ✓ | Bold, high contrast |
| **Organic** | ✓ | ✓ | ✓ | Warm, soft |
| **Wabi-Sabi** | ◐ | ✗ | ✗ | Cards: textured, imperfect |
| **Shibui** | ◐ | ✗ | ✗ | Cards: hairline borders |
| **Iki** | ✓ | ✓ | ✗ | B&W + pop color |
| **Ma** | ✗ | ✗ | ✗ | Emptiness is primary |
| **Hygge** | ✓ | ✓ | ✓ | Warm, cozy |
| **Lagom** | ✓ | ✓ | ✗ | Functional, balanced |
| **Swiss** | ✓ | ✓ | ✗ | Grid-precise |
| **Memphis** | ✓ | ✓ | ✓ | Colorful, playful |
| **Yeo-baek** | ✗ | ✗ | ✗ | Korean purity |
| **Feng Shui** | ✓ | ✓ | ✓ | Balanced, harmonious |

**Legend:** ✓ = Full support | ◐ = Limited/subtle | ✗ = Not allowed

---

## Usage in Templates

### Canvas Philosophy Section

When visual components are enabled, canvas-philosophy.md includes:

```markdown
## Visual Components

### Card System
- Card style: {none | subtle | bold | warm | playful}
- Corner radius: {0 | 8 | 16 | 24}px
- Fill approach: {transparent | solid | gradient}

### Icon Usage
- Icon style: {none | outline | filled}
- Icon placement: {in-card | standalone | inline}
- Icon color: {primary | accent | contextual}

### Background Treatment
- Background type: {solid | gradient}
- Gradient direction: {horizontal | vertical | diagonal}
- Gradient colors: {primary → secondary | custom}
```

### Outline Format

Reference components in content outlines:

```markdown
## Card 1: Hook
- Type: gradient-background
- Gradient: diagonal, primary → secondary
- Headline: Transform Your Workflow

## Card 2: Feature
- Type: feature-card
- Icon: icon:lightbulb
- Title: Smart Discovery
- Description: AI-powered recommendations that learn from you.
- Card fill: secondary at 15%

## Card 3: Feature
- Type: feature-card
- Icon: icon:zap
- Title: Lightning Fast
- Description: Results in milliseconds, not minutes.
- Card fill: accent at 15%

## Card 4: CTA
- Type: content-card
- Card fill: primary
- Text color: white
- Headline: Get Started Today
- CTA: Learn More →
```

---

## Best Practices

### Cards
- Use cards to group related content, not to fill space
- Maintain consistent card styling within a carousel
- Respect style constraints - minimal styles need subtle cards
- Keep padding consistent (24px default)

### Icons
- Choose icons that clearly represent the concept
- Use consistent icon size throughout
- Match icon color to text or accent color
- Don't overuse - icons should add meaning, not decoration

### Gradients
- Use brand colors for cohesive look
- Ensure text contrast on gradient backgrounds
- Subtle gradients for professional content
- Bold gradients for creative/playful content

### General
- Visual components should enhance, not distract
- When in doubt, use fewer components
- Test readability on mobile (carousel primary use case)
- Maintain style consistency across all cards
