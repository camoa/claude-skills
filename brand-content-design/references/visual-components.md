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

## Intelligent Usage Guidelines

Visual components are **opt-in** (user enables during template creation) but should be used **intelligently** based on content. Don't use components on every slide/card just because they're enabled.

---

### When to Use Cards

**USE cards when:**
| Content Type | Why Cards Help |
|--------------|----------------|
| Multiple related points | Groups information, reduces cognitive load |
| Feature comparisons | Visual containment shows items are comparable |
| Tips/steps in a list | Each tip gets its own scannable container |
| Quotes or callouts | Elevates content, signals "this is important" |
| Stats with context | Number + label contained together |

**DON'T use cards when:**
| Situation | Why Not |
|-----------|---------|
| Single focal point | Cards compete with the main message |
| Hero/hook slides | Let the headline breathe - cards add clutter |
| Image-dominant slides | Cards fight with photography |
| Only 1-2 words of content | Cards need substance to justify containment |
| CTA slides | Direct action, don't wrap in containers |

**Card quantity guidelines:**
- **2-4 cards per slide** = optimal scanability
- **1 card** = use only if it's a featured callout
- **5+ cards** = too dense, split across slides

---

### When to Use Icons

**USE icons when:**
| Content Type | Why Icons Help |
|--------------|----------------|
| Process steps | Visual anchors help track progress (1→2→3) |
| Feature lists | Icon + text = 20% faster comprehension than text alone |
| Categories/topics | Icons create visual distinction between items |
| Abstract concepts | Concrete visual for intangible ideas (e.g., "security" → shield) |
| Inside cards | Reinforces card purpose, adds visual interest |

**DON'T use icons when:**
| Situation | Why Not |
|-----------|---------|
| No clear visual metaphor | Forced icons confuse more than help |
| Emotional/story content | Icons feel clinical, break narrative flow |
| Data/statistics | Numbers are the visual - icons compete |
| Quote slides | Let the words speak |
| Already image-heavy | Icons add visual noise |

**Icon placement rules:**
- **In cards**: Center or top-left, 32-48px size
- **With text**: Left of text, vertically centered, 24-32px
- **Standalone decorative**: Corners only, subtle, 20-24px

**Icon selection criteria:**
1. Is there an obvious icon for this concept? (lightbulb=idea, rocket=launch)
2. Would someone understand the icon WITHOUT the label?
3. If no clear match exists, **don't force it** - skip the icon

---

### When to Use Gradients

**USE gradients when:**
| Content Type | Why Gradients Help |
|--------------|-------------------|
| Opening/hook slides | Creates visual impact, thumb-stopping |
| Section transitions | Signals "new chapter" in the carousel |
| CTA slides | Draws attention to the action |
| Brand moments | Reinforces brand colors dramatically |
| Low-text slides | Gradient fills visual space meaningfully |

**DON'T use gradients when:**
| Situation | Why Not |
|-----------|---------|
| Text-heavy slides | Reduces readability, gradient competes with content |
| Content slides with cards | Cards + gradient = too much visual complexity |
| Every slide | Loses impact - gradients should be special |
| Data/chart slides | Gradient distracts from the numbers |
| Middle of carousel | Reserve for opening, transitions, closing |

**Gradient frequency:**
- **Max 2-3 gradient slides** per carousel (opening, transition, CTA)
- Rest should be solid backgrounds for readability

**Text contrast on gradients:**
- Always use high-contrast text (white on dark gradient, dark on light)
- Test at BOTH ends of the gradient - text must be readable throughout
- Keep text in the gradient's lighter OR darker zone, not spanning both

---

### Decision Framework

When generating content, ask these questions IN ORDER:

**Step 1: Does this slide/card have enough content?**
- < 10 words → Probably no cards needed
- 10-30 words → Consider cards if grouping helps
- > 30 words → Definitely use cards to chunk content

**Step 2: Is there a clear visual metaphor?**
- Yes, obvious icon exists → Use icon
- Maybe, could work → Use icon only if inside a card
- No clear match → Skip icon entirely

**Step 3: What's the slide's purpose?**
- Hook/CTA/Transition → Consider gradient background
- Content/Data/Quote → Solid background, focus on content

**Step 4: What's the visual density so far?**
- Already has image → No gradient, minimal cards
- Already has 3+ cards → No icons outside cards
- Already has gradient → No cards, minimal text

---

### Slide-Type Recommendations

| Slide Type | Cards | Icons | Gradient |
|------------|:-----:|:-----:|:--------:|
| **Hook/Opening** | ✗ | ✗ | ✓ |
| **Problem** | ◐ | ◐ | ✗ |
| **Solution Overview** | ✗ | ✗ | ✗ |
| **Features (list)** | ✓ | ✓ | ✗ |
| **Process/Steps** | ✓ | ✓ | ✗ |
| **Data/Stats** | ◐ | ✗ | ✗ |
| **Quote/Testimonial** | ◐ | ✗ | ✗ |
| **Story/Narrative** | ✗ | ✗ | ✗ |
| **Comparison** | ✓ | ◐ | ✗ |
| **Transition** | ✗ | ✗ | ✓ |
| **CTA/Closing** | ✗ | ✗ | ✓ |

**Legend:** ✓ = Recommended | ◐ = If content warrants | ✗ = Avoid

---

### Common Mistakes to Avoid

1. **Card everything** - Cards lose meaning when overused
2. **Icon every point** - Forces bad metaphors, looks cluttered
3. **Gradient every slide** - Becomes exhausting, loses impact
4. **Components without content** - Visual elements need substance
5. **Mixing all three** - Card + icon + gradient = visual chaos
6. **Ignoring mobile** - Components must work at small sizes

---

### Quality Checklist

Before finalizing, verify:

- [ ] Cards only where content benefits from grouping
- [ ] Icons only where clear visual metaphor exists
- [ ] Gradients only on 2-3 slides max (hook, transition, CTA)
- [ ] No slide has cards + icons + gradient together
- [ ] Text readable on all backgrounds (4.5:1 contrast minimum)
- [ ] Components consistent in style throughout
- [ ] Mobile preview shows components at readable size
