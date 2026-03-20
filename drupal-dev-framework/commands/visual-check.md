---
description: "Compare rendered Drupal page against Figma design comp. Use when user says 'visual check', 'does it match the design', 'compare with figma', 'check against comp', 'visual parity', 'design match'. Requires Chrome (--chrome) for rendered page inspection. Optionally uses Figma MCP for automated design spec extraction."
allowed-tools: Read, Glob, Grep, Bash, AskUserQuestion
effort: high
---

# Visual Check

Compare a rendered Drupal page against its Figma design comp to find visual discrepancies.

## Usage

```
/drupal-dev-framework:visual-check [page-path]
```

## What This Does

1. Opens the rendered Drupal page in Chrome (DDEV site)
2. Extracts design specs from Figma (via MCP) or from a reference screenshot
3. Compares: layout, spacing, colors, typography, responsive behavior
4. Reports discrepancies with specific CSS-level fixes

## Prerequisites

**Required:**
- Chrome available (`--chrome` or `/chrome`) — needed to inspect rendered page
- DDEV site running with the page accessible

**Optional but recommended:**
- Figma MCP configured — enables automated design spec extraction
- Figma file URL or frame ID for the target page

**Without Chrome:** This command cannot run. Suggest: "Start Claude Code with `--chrome` to enable visual checking."

## Instructions

### Step 1: Detect Available Tools

Check what's available:

1. **Chrome:** Check for `claude-in-chrome` MCP tools. If not available → HALT with message: "Visual check requires Chrome. Start Claude Code with `--chrome` or run `/chrome` to connect."

2. **Figma MCP:** Check for `figma` MCP tools (from figma-intelligence plugin or standalone Figma MCP).
   - If available: automated comparison mode (extract specs from Figma)
   - If not available: manual reference mode (user provides screenshot or describes expected design)

3. **DDEV:** Check if DDEV is running:
   ```bash
   ddev describe 2>/dev/null | head -5
   ```
   Extract the site URL (e.g., `https://mysite.ddev.site`). If DDEV not running → ask user for the site URL.

### Step 2: Identify What to Check

**If `$ARGUMENTS` provided:** Use as the page path (e.g., `/node/1`, `/admin/config`, `/about`).

**If no arguments:**
AskUserQuestion: "Which page should I check?"
- Provide the page path (e.g., `/homepage`, `/about`, `/node/1`)
- Or paste the full URL

### Step 3: Get Design Reference

**If Figma MCP available:**
AskUserQuestion: "Where's the Figma comp for this page?"
- Paste a Figma file URL (e.g., `https://figma.com/design/...`)
- Or specify a frame name within the connected Figma file
- Or "no figma — I'll compare manually"

If Figma URL/frame provided:
1. Use Figma MCP to extract the frame/component
2. Extract design specs:
   - Colors (hex values for backgrounds, text, borders, CTAs)
   - Typography (font family, size, weight, line-height for headings, body, labels)
   - Spacing (padding, margins, gaps between sections/components)
   - Layout (grid columns, max-width, alignment)
   - Border radius, shadows, opacity values
   - Component dimensions (hero height, card widths, image aspect ratios)

**If no Figma MCP or user declines:**
AskUserQuestion: "Provide a reference for comparison:"
- Paste a screenshot path (I'll Read it for visual comparison)
- Describe the expected design ("Hero should be full-width with centered text, blue gradient background...")
- Or "just check for obvious issues" (generic visual inspection without reference)

### Step 4: Inspect Rendered Page

Open the DDEV page in Chrome:

1. Navigate to the page URL
2. **Desktop check (1280px):**
   - Screenshot the full page
   - Read computed CSS for key elements: hero, navigation, content sections, footer
   - Extract: colors, font properties, padding/margins, border-radius, shadows
3. **Tablet check (768px):**
   - Resize viewport
   - Screenshot — check responsive breakpoint behavior
4. **Mobile check (375px):**
   - Resize viewport
   - Screenshot — check mobile layout, navigation collapse, content reflow

### Step 5: Compare

**If Figma specs available (automated comparison):**

For each design token, compare Figma spec vs rendered CSS:

| Element | Property | Figma Spec | Rendered | Match? | Delta |
|---------|----------|------------|----------|--------|-------|
| Hero bg | color | #1E40AF | #1E40AF | ✓ | — |
| Hero h1 | font-size | 48px | 42px | ✗ | -6px |
| Hero h1 | font-weight | 700 | 600 | ✗ | -100 |
| Section padding | top | 64px | 48px | ✗ | -16px |
| CTA button | border-radius | 8px | 4px | ✗ | -4px |

Flag discrepancies with severity:
- **Critical:** Wrong colors, missing elements, broken layout
- **Major:** Wrong sizes (>4px delta), wrong weights, wrong spacing (>8px delta)
- **Minor:** Small spacing differences (≤8px), slight opacity/shadow differences

**If manual reference (screenshot or description):**
Compare visually — describe what matches and what doesn't. Be specific about what's off and where.

**If generic inspection (no reference):**
Check for obvious issues:
- Broken layouts (overlapping elements, content overflow)
- Missing images or icons
- WCAG contrast failures (text on background)
- Inconsistent spacing rhythm
- Mobile navigation issues
- Unreadable text (too small, wrong color)

### Step 6: Report

```
## Visual Check Report — [Page Path]

**Site:** [DDEV URL]
**Reference:** [Figma frame / Screenshot / Generic inspection]
**Date:** [today]

### Summary
- Discrepancies found: [N] (Critical: [N], Major: [N], Minor: [N])
- Breakpoints checked: Desktop (1280px), Tablet (768px), Mobile (375px)

### Discrepancies

#### Critical
| # | Element | Issue | Expected | Actual | Fix |
|---|---------|-------|----------|--------|-----|

#### Major
| # | Element | Issue | Expected | Actual | Fix |
|---|---------|-------|----------|--------|-----|

#### Minor
| # | Element | Issue | Expected | Actual | Fix |
|---|---------|-------|----------|--------|-----|

### Responsive Issues
[Any breakpoint-specific problems]

### Passed Checks
[What matches correctly — brief list]
```

### Step 7: User Action

AskUserQuestion: "What would you like to do?"
- **Fix the issues** — I'll update the CSS/Twig to address discrepancies
- **Save report** — Save to the task's implementation notes
- **Re-check after fixes** — Run again after I make manual changes
- **Looks good** — No action needed

If **Fix the issues:** For each discrepancy, identify the CSS file (or Twig template) and apply the fix. Then offer to re-check.

If **Save report:** Append to `implementation_process/in_progress/{task}/implementation.md` under a `## Visual Check` section.

## Integration with /complete

When `/complete` runs quality gates, it can optionally invoke this command as Gate 6:

> "Would you like to run a visual check against the design comp before completing? (Requires Chrome)"

This is NOT mandatory — many tasks (services, APIs, CLI commands) have no visual component. Only offer for tasks that modify templates, themes, or front-end code.

## Context Budget

- Figma spec extraction: ~200-400 tokens
- Chrome screenshots (3 breakpoints): ~600-1200 tokens
- Comparison table: ~200 tokens
- Total: ~1,000-1,800 tokens — lightweight

## Limitations

- Chrome is beta — only Chrome/Edge, not WSL
- Figma MCP requires authentication with Figma API token
- Cannot detect animation/transition issues (Chrome shows static state)
- Color comparison is RGB-based — may miss perceptual differences (use WCAG deltaE for precision)
- DDEV must be running with the page accessible
