---
description: "Verify that the task's phase artifacts cite dev-guides-navigator guides appropriate to the domain. Framework-owned gate — not a wrapper. Reads research.md + architecture.md for guide citations, surfaces gaps. Soft-nudge posture; never blocks. Introduced v3.13.0."
allowed-tools: Read, Write, Bash, Glob, Skill
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

2. **Applicability check (v3.14.2+)** — before inspecting artifacts, determine whether dev-guides apply to this task at all. The dev-guides catalog covers Drupal, Next.js, design systems (Bootstrap/Radix/Tailwind/DaisyUI), CSS, and cross-cutting methodology. For tasks whose codePath contains none of those domain markers (e.g., a Claude Code plugin marketplace, a pure docs project, a shell-script tools repo), guide citations are not expected and `fail` would be a false positive.

   Read `project_state.md` for `codePath` and `codePathState`. Then:

   - If `codePathState == "docs-only"` OR `codePathState == "unset"` → emit `verdict: "skipped"` with reason `"task has no code path declared (state: <state>); guide citation rule does not apply"`. Skip Steps 3-5.
   - If `codePathState == "set"` → quick-scan codePath for domain markers:
     - **Drupal:** any `*.info.yml`, `*.module`, `composer.json` containing `"drupal/core"`, or directory ending in `.theme`
     - **Next.js:** `package.json` containing `"next"` as a dep, or `next.config.{js,ts,mjs}`
     - **Frontend/CSS:** `*.scss`, `*.css`, `tailwind.config.*`, or `package.json` containing `"react"`/`"vue"`/`"svelte"`
   - If at least one marker matches → applicable; continue.
   - If NO markers match → emit `verdict: "skipped"` with reason `"codePath at <path> contains no Drupal/Next.js/frontend code; guide citation rule does not apply to this task type"`. Skip Steps 3-5.

   The applicability check is intentionally generous (any marker → applicable). False positives are cheaper than false negatives — if a task even smells Drupal-or-frontend, run the citation check.

   Detection is shallow (top-level + 1-deep) to keep the check fast. Implement via `Glob` + `Bash` `grep`. Cache result on `details.applicability` so consumers can see what fired.

3. **Inspect phase artifacts** — read any of these that exist in the task folder:
   - `research.md` (Phase 1 artifact)
   - `architecture.md` (Phase 2 artifact)
   - `implementation.md` (Phase 3 artifact)

4. **Extract guide citations** — scan for guide references in each artifact. Accept:
   - URLs matching `camoa.github.io/dev-guides/[a-z0-9/-]+` (the published dev-guides site)
   - Inline mentions of guide slugs in the form `drupal/<category>/<topic>`, `design-systems/<topic>`, `nextjs/<topic>`, or similar kebab-case paths
   - Markdown reference links `[...](https://camoa.github.io/dev-guides/...)`
   - Explicit "Loaded guide: <slug>" annotations if the `dev-guides-navigator` skill wrote them

5. **Judge adequacy** — apply verdict rules:
   - `pass` → ≥1 guide citation found in research.md AND ≥1 in architecture.md (if architecture.md exists)
   - `warning` → ≥1 citation found overall but phase coverage uneven (e.g., research cites guides but architecture doesn't)
   - `fail` → no guide citations found in any phase artifact AND at least one artifact exists with ≥200 lines of content (substantive work without guide consultation)
   - `skipped` → no phase artifacts exist yet (task hasn't progressed past creation)

   The 200-line substance threshold prevents false-positives on near-empty stub artifacts.

6. **Emit the shared envelope** (per `references/validation-gate-result.md`) with gate-specific details:

   ```json
   "details": {
     "source": "framework:guides",
     "applicability": {
       "decision": "applicable | skipped",
       "reason": "<one-line explanation>",
       "markers_found": ["drupal", "frontend"]
     },
     "checked_artifacts": ["<abs path to each artifact examined>"],
     "guides_cited": ["<slug>", "<slug>"],
     "guides_expected_min": 1
   }
   ```

   - `applicability` — populated by Step 2; for `skipped` runs, `checked_artifacts` and `guides_cited` may be omitted
   - `guides_cited` — unique slugs found across all artifacts, deduplicated
   - `guides_expected_min` — v1 hard-coded to 1 per substantive artifact; v2 candidate for per-task configuration

7. **Persist** — write envelope to:
   - `<task_folder>/validations/latest/guides.json` (overwrite)
   - `<task_folder>/validations/history.jsonl` (append)

8. **Print CLI summary** — show verdict, citations found, and per-artifact gaps. On `fail`, suggest running `/dev-guides-navigator` with domain keywords. On `skipped` due to applicability, print the applicability reason. Non-zero exit (1) only when invoked non-interactively.

## Verdict messages

Examples of what `messages[]` contains:

- `pass`: `["3 guide citations found across research.md and architecture.md"]`
- `warning`: `["2 citations in research.md but 0 in architecture.md — architecture may be under-grounded"]`
- `skipped (applicability)`: `["codePath at /abs/path contains no Drupal/Next.js/frontend code; guide citation rule does not apply to this task type"]` or `["task has no code path declared (state: docs-only); guide citation rule does not apply"]`
- `fail`: `["No guide citations found in any phase artifact", "Suggest: /dev-guides-navigator with keywords from task.md Goal"]`
- `skipped`: `["No phase artifacts exist yet; run /research to begin"]`

## Why this gate exists

The `dev-guides-navigator` plugin exists precisely because AI-generated Drupal work drifts from community consensus when it doesn't load authoritative guides. This gate surfaces the "we didn't check" case and recommends action — it's NOT a block, just a visible signal during `/validate:all`.

**Applicability auto-skip (v3.14.2+):** the gate now skips with reason when codePath has no Drupal/Next.js/frontend markers, OR when codePathState is `docs-only` / `unset`. This makes the gate safe to include in `/validate:all` and `/validate:team` runs against non-Drupal tasks (Claude Code plugin work, shell-tool repos, pure-docs projects) without producing spurious `fail` verdicts. v1 had no auto-skip and relied on user judgment about when to invoke; v3.14.2 makes that judgment explicit and machine-checkable.

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
