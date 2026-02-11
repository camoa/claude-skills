---
description: Create a branded HTML page by selecting components from a design system
allowed-tools: Bash, Read, Write, Glob, Grep, AskUserQuestion, Skill
---

# HTML Page Command

Create a branded HTML page by selecting components from an existing design system. Generates standalone components + a composed single-file HTML page.

## Prerequisites

- A brand project with `brand-philosophy.md`
- At least one HTML design system (run `/design-html` first)

---

## Workflow

### Step 1: Find Project

Search for `brand-philosophy.md` using this order:

1. Current directory — check `./brand-philosophy.md`
2. Parent directory — check `../brand-philosophy.md`
3. Subdirectories — `find . -maxdepth 2 -name "brand-philosophy.md"`
4. If multiple found — ask user which project
5. If none found — tell user to run `/brand-init` first

Set `PROJECT_PATH` to the directory containing `brand-philosophy.md`.

### Step 2: List Design Systems

Search for existing HTML design systems:
```
find {PROJECT_PATH}/templates/html -maxdepth 2 -name "design-system.md" 2>/dev/null
```

If none found — tell user to run `/design-html` first.
If one found — auto-select it.
If multiple found — ask user which one to use.

### Step 3: Load Design System

Read these files:
- `{PROJECT_PATH}/templates/html/{name}/design-system.md`
- `{PROJECT_PATH}/templates/html/{name}/canvas-philosophy.md`
- `{PROJECT_PATH}/brand-philosophy.md` (or sub-identity if specified in design system)

Extract design tokens, style constraints, and component catalog.

### Step 4: Check Existing Components

List existing components in the design system:
```
find {PROJECT_PATH}/templates/html/{name}/components -name "*.html" 2>/dev/null
```

Store the list of available reusable components.

### Step 5: Page Category

**AskUserQuestion**: "What type of page are you creating?"
- **Landing Page** — Conversion-focused (nav, hero, features, testimonials, CTA, footer)
- **About / Company** — Story-driven (nav, hero, content, team, stats, footer)
- **Portfolio / Case Study** — Visual showcase (nav, hero, gallery, content, CTA, footer)
- **Pricing Page** — Comparison (nav, hero, pricing, FAQ, CTA, footer)

Follow up with remaining categories if none selected:
- **Event Page** — Date/action focused
- **Blog / Article** — Content-focused
- **Contact Page** — Approachable
- **Custom** — Select any combination

### Step 6: Component Selection

Show the recommended components for the selected category. For each component, indicate if it already exists in `components/`:

**AskUserQuestion**: "Here are the recommended components for a {category}. Confirm or modify:"

Display as a table:
```
| # | Component | Variant | Status |
|---|-----------|---------|--------|
| 1 | Navigation | simple | ✓ Reuse existing |
| 2 | Hero | centered | NEW — will generate |
| 3 | Feature Grid | 3-col | NEW — will generate |
| 4 | Testimonials | grid | NEW — will generate |
| 5 | CTA | simple | ✓ Reuse existing |
| 6 | Footer | multi-column | ✓ Reuse existing |
```

- **Looks good** — Proceed with these components
- **Add components** — Add more sections
- **Remove components** — Remove sections from the list

If adding: show available component types not yet selected (with variants).
If removing: ask which to remove.

Allow the user to also change the variant for any component (e.g., hero-centered → hero-split-image).

### Step 7: Page Title and Meta

**AskUserQuestion**: "What's the page title?"

Also ask for a short meta description (1-2 sentences for SEO).

### Step 8: Gather Content

**AskUserQuestion**: "How would you like to provide content?"
- **Paste all at once** — Paste everything, I'll map it to components
- **Section by section** — I'll ask for each component's content separately

If **paste all at once**: ask user to paste their content. Parse and map to selected components.

If **section by section**: for each selected component, ask for the specific content fields:
- Hero: headline, subheadline, CTA text
- Features: section title, 3-4 feature titles + descriptions
- Testimonials: 2-3 quotes with author/role
- CTA: heading, description, button text
- etc.

### Step 9: Generate

Invoke the `html-generator` skill via Skill tool with:
- Design system files (canvas-philosophy.md + design-system.md)
- Brand philosophy (or sub-identity)
- Selected components (type + variant for each)
- Existing components to reuse (read their HTML from components/)
- Content mapped to each component
- Style constraints from `references/web-style-constraints.md`

The html-generator skill will:
1. Generate any NEW components as standalone HTML
2. Compose all components into a single page

### Step 10: Save Components

For each newly generated component:
- Save standalone HTML to: `{PROJECT_PATH}/templates/html/{name}/components/{type}-{variant}.html`
- Update `design-system.md` Generated Components section with the new component

### Step 11: Save Page

Create output directory and save the composed page:
```
{PROJECT_PATH}/html-pages/{YYYY-MM-DD}-{page-name}/{page-name}.html
```

### Step 12: Confirm

Tell user:
- Page saved to: `html-pages/{date}-{page-name}/{page-name}.html`
- New components generated: list any new components saved to the library
- Total components in library: count
- Open the HTML file in a browser to preview

Suggest:
- "Create another page with `/html-page`"
- "Quick mode: `/html-page-quick`"

---

## Output

- Created: `html-pages/{YYYY-MM-DD}-{page-name}/{page-name}.html`
- Created (if new): `templates/html/{name}/components/{type}-{variant}.html` for each new component
- Updated: `templates/html/{name}/design-system.md` (Generated Components section)
