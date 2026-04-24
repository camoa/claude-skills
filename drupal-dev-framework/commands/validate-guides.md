---
description: "Verify that the task's phase artifacts cite dev-guides-navigator guides appropriate to the domain. Framework-owned gate — not a wrapper. Reads research.md + architecture.md for guide citations, surfaces gaps. Soft-nudge posture; never blocks. Introduced v3.13.0."
allowed-tools: Read, Write, Edit, Bash, Glob, Skill, Task
argument-hint: [<task-name>]
---

# Validate: Guides

Verify that this task's phase artifacts reference Drupal development guides loaded via the `dev-guides-navigator` plugin. The premise: decisions made without consulting authoritative guides drift from community consensus. Catching "no guide citations in research.md or architecture.md" early prevents downstream architectural debt.

This is a **framework-owned** gate — it does NOT wrap a `code-quality-tools` skill. Implementation lives here in drupal-dev-framework.

## Usage

```
/drupal-dev-framework:validate-guides              # run against current task
/drupal-dev-framework:validate-guides <task-name>  # run against a specific task
```

## What this does

1. **Resolve task context** — same resolution as other `/validate:*` commands:
   (a) read `session_context.json` if present
   (b) walk up from `$PWD` until you find `implementation_process/`
   (c) abort with "no project context" if neither resolves

   Locate the task folder under `<project>/implementation_process/in_progress/**/<task-name>/`.

2. **Inspect phase artifacts** — read any of these that exist in the task folder:
   - `research.md` (Phase 1 artifact)
   - `architecture.md` (Phase 2 artifact)
   - `implementation.md` (Phase 3 artifact)

3. **Extract guide citations** — scan for guide references in each artifact. Accept:
   - URLs matching `camoa.github.io/dev-guides/[a-z0-9/-]+` (the published dev-guides site)
   - Inline mentions of guide slugs in the form `drupal/<category>/<topic>`, `design-systems/<topic>`, `nextjs/<topic>`, or similar kebab-case paths
   - Markdown reference links `[...](https://camoa.github.io/dev-guides/...)`
   - Explicit "Loaded guide: <slug>" annotations if the `dev-guides-navigator` skill wrote them

4. **Judge adequacy** — apply verdict rules:
   - `pass` → ≥1 guide citation found in research.md AND ≥1 in architecture.md (if architecture.md exists)
   - `warning` → ≥1 citation found overall but phase coverage uneven (e.g., research cites guides but architecture doesn't)
   - `fail` → no guide citations found in any phase artifact AND at least one artifact exists with ≥200 lines of content (substantive work without guide consultation)
   - `skipped` → no phase artifacts exist yet (task hasn't progressed past creation)

   The 200-line substance threshold prevents false-positives on near-empty stub artifacts.

5. **Emit the shared envelope** (per `references/validation-gate-result.md`) with gate-specific details:

   ```json
   "details": {
     "source": "framework:guides",
     "checked_artifacts": ["<abs path to each artifact examined>"],
     "guides_cited": ["<slug>", "<slug>"],
     "guides_expected_min": 1
   }
   ```

   - `guides_cited` — unique slugs found across all artifacts, deduplicated
   - `guides_expected_min` — v1 hard-coded to 1 per substantive artifact; v2 candidate for per-task configuration

6. **Persist** — write envelope to:
   - `<task_folder>/validations/latest/guides.json` (overwrite)
   - `<task_folder>/validations/history.jsonl` (append)

7. **Print CLI summary** — show verdict, citations found, and per-artifact gaps. On `fail`, suggest running `/dev-guides-navigator` with domain keywords. Non-zero exit (1) only when invoked non-interactively.

## Verdict messages

Examples of what `messages[]` contains:

- `pass`: `["3 guide citations found across research.md and architecture.md"]`
- `warning`: `["2 citations in research.md but 0 in architecture.md — architecture may be under-grounded"]`
- `fail`: `["No guide citations found in any phase artifact", "Suggest: /dev-guides-navigator with keywords from task.md Goal"]`
- `skipped`: `["No phase artifacts exist yet; run /research to begin"]`

## Why this gate exists

The `dev-guides-navigator` plugin exists precisely because AI-generated Drupal work drifts from community consensus when it doesn't load authoritative guides. This gate surfaces the "we didn't check" case and recommends action — it's NOT a block, just a visible signal during `/validate:all`.

Applicability (in the informal sense): relevant whenever a task writes substantive `research.md` or `architecture.md`. Not relevant for trivial config changes, test-only tasks, or documentation-only work. v1 has no auto-skip; user decides when to invoke.

## Error cases

| Scenario | Behavior |
|---|---|
| No session context AND no `<task-name>` arg | Print "no task context" + exit 2 |
| `<task-name>` doesn't resolve to a folder | Print candidate suggestions + exit 2 |
| Task folder has no phase artifacts | Emit `verdict: skipped` with helpful message |
| Persistence write fails | Print CLI summary; mention failure in messages; exit 1 |

## Soft-nudge posture

- Manual invocation always runs
- `fail` verdict signals under-grounded work but never blocks downstream phases
- The recommendation ("run `/dev-guides-navigator`") is a suggestion; user decides if it's worth the time

## v2 candidates

- Per-task configurable `guides_expected_min` (e.g., "this complex task should cite ≥3")
- Detecting STALE citations (guide was updated since task cited it)
- Detecting domain mismatch (task is about forms, cited guides are about entities)

See `implementation_process/in_progress/<this-task>/v2-candidates.md` for the full deferred-features inventory.

## Related

- `/drupal-dev-framework:validate-tdd` / `:validate-solid` / `:validate-dry` / `:validate-security` — sibling gate commands; wrappers
- `/drupal-dev-framework:validate-visual-parity` / `:validate-visual-regression` — visual gates
- `/drupal-dev-framework:validate-all` — sequential orchestrator
- `references/validation-gate-result.md` — the shared envelope contract
- `dev-guides-navigator` plugin — the guide discovery tool whose usage this gate verifies
