---
description: Create a branded HTML page quickly with minimal questions
allowed-tools: Bash, Read, Write, Glob, Grep, AskUserQuestion, Skill
---

# HTML Page Quick Command

Quick-create a branded HTML page with minimal interaction. Auto-selects component variants, uses default presets, and lets you paste all content at once.

## Prerequisites

- A brand project with `brand-philosophy.md`
- At least one HTML design system (run `/design-html` first)

---

## Workflow

### Step 1: Find Project and Design System

Search for `brand-philosophy.md` using standard project detection order. Set `PROJECT_PATH`.

Search for HTML design systems:
```
find {PROJECT_PATH}/templates/html -maxdepth 2 -name "design-system.md" 2>/dev/null
```

If none — tell user to run `/design-html` first.
If one — auto-select.
If multiple — ask which one.

Load design-system.md + canvas-philosophy.md + brand-philosophy.md.

### Step 2: Page Category

**AskUserQuestion**: "What type of page?"
- **Landing Page** — Hero, features, testimonials, CTA
- **About / Company** — Hero, content, team, stats
- **Portfolio** — Hero, gallery, content, CTA
- **Pricing** — Hero, pricing, FAQ, CTA

(Uses default component sets for the selected category. Auto-adds nav + footer.)

### Step 3: Content

**AskUserQuestion**: "Paste your page content below. Include headings, descriptions, feature lists, testimonials — everything for the page."

Parse the pasted content and automatically:
- Map content to the category's component set
- Select the best variant for each component based on content structure
- Check `components/` for reusable components

### Step 4: Page Name

**AskUserQuestion**: "Page name? (used for file naming)"
- Suggest based on content/category

### Step 5: Generate

Invoke the `html-generator` skill with:
- Design system files
- Brand philosophy
- Auto-selected components + variants
- Existing reusable components from library
- Mapped content
- Style constraints

### Step 6: Save and Confirm

Save new components to `templates/html/{name}/components/`.
Save page to `html-pages/{YYYY-MM-DD}-{page-name}/{page-name}.html`.
Update `design-system.md` Generated Components section.

Tell user:
- Page saved to: path
- Components generated: list
- Open in browser to preview

---

## Output

- Created: `html-pages/{YYYY-MM-DD}-{page-name}/{page-name}.html`
- Created (if new): component files in design system's `components/`
- Updated: `design-system.md` (Generated Components section)
