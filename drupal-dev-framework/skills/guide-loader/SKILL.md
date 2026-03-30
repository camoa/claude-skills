---
name: guide-loader
description: "Use when loading development guide content into context for Drupal, theming, design systems, or dev-practice tasks. Checks local project guides first, then delegates to dev-guides-navigator for online guide discovery with hash-based caching and KG metadata disambiguation. Returns actionable patterns, decision criteria, and code examples from matched guides. Use when user says 'load guide', 'get documentation', 'find best practice', 'how-to guide', or 'reference guide'."
version: 3.0.0
user-invocable: false
---

# Guide Loader

Load development guides into context and extract actionable patterns for the current task.

## Workflow

### 1. Check Local Guides Path

Read `{project_path}/project_state.md` and extract `**Guides Path:** {path}`.

If found and a specific guide is requested by filename:
```
Read {guides_path}/{requested_guide}.md
```
If the file exists, skip to step 3. Otherwise, proceed to step 2.

### 2. Delegate to Navigator

Invoke the `dev-guides-navigator` skill with task keywords. Pass specific terms (e.g., "Drupal forms validation", "SDC component", "config management") rather than broad queries.

The navigator returns raw guide markdown via `curl -s` from raw GitHub URLs — never use WebFetch.

### 3. Extract and Apply

From the guide content, extract and present:

```
Relevant patterns for current task:
- {Decision criteria from guide}
- {Code pattern or API usage to follow}
- {Anti-pattern to avoid}

Recommended approach: {specific recommendation}

Add to architecture/implementation docs? (yes/no)
```

Apply patterns directly to the current implementation — do not merely summarize the guide.

### 4. Cross-Reference Prerequisites

Check the guide's `requires` metadata. If prerequisites exist, load those guides first before applying the current guide's patterns.

## Stop Points

STOP and wait for user:
- If requested guide not found locally or via navigator
- After presenting guide recommendations (ask if user needs more detail)
- If guide conflicts with existing project architecture decisions
