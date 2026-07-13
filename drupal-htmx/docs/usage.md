# Using Drupal HTMX

The [README](../README.md) is the shop window. This is the how: what the plugin does, when to reach for it, what it needs, how you know it is working, and where it fits with the rest of the marketplace.

## What it does

Four commands cover the AJAX-to-HTMX lifecycle on a Drupal 11.3+ codebase. `/htmx-analyze <path>` scans a custom module for `#ajax` and `AjaxResponse` usage and returns a migration report ranked simple/medium/complex, so you know where to start. `/htmx-pattern <use-case>` returns the recommended HTMX pattern for something you are about to build (a dependent dropdown, infinite scroll, a multi-step wizard) with a working code example, so new work does not go through AJAX first only to be migrated later. `/htmx-migrate <file> [pattern]` walks one file through the conversion: it shows the current AJAX code, the `Htmx`-class equivalent, and a step checklist (remove `#ajax`, add the Htmx configuration, move callback logic into `buildForm()`, delete the now-unused callback method). `/htmx-validate <path>` then checks the result: critical issues (a missing `onlyMainContent()` returning a full page where a fragment was expected, an invalid selector), accessibility warnings (missing `aria-live` on a dynamic region), and suggestions, plus the checks that passed. `/htmx [path]` is the quick status scan that tells you which of the above to run next.

Three read-only agents (`ajax-analyzer`, `htmx-recommender`, `htmx-validator`; sonnet, `Read`/`Glob`/`Grep` only) do the scanning and pattern-matching behind `/htmx-analyze`, `/htmx-pattern`, and `/htmx-validate`. None of them edit files: `/htmx-migrate` shows you the before and after and you apply the change, and `/htmx-validate` reports on what is there, it does not fix it for you. Everything is scoped to custom modules; core and contrib are not scanned or modified unless you explicitly ask.

## When to reach for it

Reach for it whenever a Drupal 11.3+ task touches dynamic, partial-page interaction: an existing AJAX callback you are converting, or a new dependent dropdown, real-time validation, infinite scroll, or multi-step form you are about to build. Start with `/htmx-analyze` when you are migrating an existing module and need to know what is worth converting and in what order. Start with `/htmx-pattern` when you are building something new and want the right pattern before you write code you would otherwise redo. It is not for legacy-AJAX maintenance with no migration intent (the plugin's reference material covers Drupal 11.3+ HTMX patterns only, not historical AJAX guidance beyond what you need to read the existing code), and it does not reach into core or contrib.

## Prerequisites

- **Drupal 11.3+.** This is where Drupal's native HTMX support landed; the whole plugin is built against it.
- **Claude Code**, with the plugin installed (`/plugin install drupal-htmx@camoa-skills`).
- A custom module to point the commands at. There is no separate project-memory setup: each command takes a path or file argument directly.
- **Recommended, not required:** `dev-guides-navigator`, which the `htmx-development` skill pulls in at `high` effort and above for supplementary Drupal forms, routing, and render-API context.

## It's working if

- `/htmx [path]` prints a current-state summary (AJAX patterns found, HTMX implementations found) and names the next command to run.
- `/htmx-analyze <path>` returns a report with a file count, a pattern count, and migration candidates grouped by complexity (simple/medium/complex), each with a file and line reference.
- `/htmx-pattern <use-case>` returns a named pattern with a runnable code example using the `Htmx` class, not raw `#ajax` properties.
- After `/htmx-migrate <file>`, you can see both the original AJAX code and the HTMX equivalent side by side, plus a numbered checklist of the edits still to apply by hand.
- `/htmx-validate <path>` returns a report split into Critical / Warnings / Suggestions / Passed Checks, not a bare pass/fail. A clean pass shows 0 critical issues and the accessibility checks (aria-live, progressive enhancement, works without JavaScript) in the Passed list.

If a command finds nothing, check the path: all four commands only look inside custom modules, so a path under core or contrib returns no results by design.

## Where it fits

- **[ai-dev-assistant](../../ai-dev-assistant/README.md)**: when a task involving HTMX work runs through the full Research → Architecture → Implementation → Review lifecycle, the process-recipe/guide layer there is where the Drupal-specific method for each phase comes from; this plugin is the specialist tool the AJAX-to-HTMX decision itself reaches for, inside or outside that lifecycle.
- **[dev-guides-navigator](../../dev-guides-navigator/README.md)**: supplies the supplementary Drupal domain guides (forms, routing, render API, JS behaviors) the `htmx-development` skill cross-references at higher effort levels. Not a hard dependency; the plugin's own condensed references (`skills/htmx-development/references/`) cover the HTMX-specific API and migration patterns on their own.
- **[code-quality-tools](../../code-quality-tools/README.md)**: not invoked directly by this plugin, but a natural next step after a migration: run its gates over the changed file the same way you would after any code change.

This plugin does not itself enforce a review gate; it is analysis, recommendation, and guided migration, and the accessibility and correctness checks in `/htmx-validate` are the closest thing to a gate it ships. For the reasoning behind the marketplace's split between gates that enforce and guides that explain the why, see [PHILOSOPHY.md](../../PHILOSOPHY.md).
