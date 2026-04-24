---
description: "Run all 7 validation gates (tdd, solid, dry, security, guides, visual-regression, visual-parity) sequentially against the current task. Aggregates results, prints summary table, and surfaces complementary code-quality-tools capabilities that aren't wrapped. Soft-nudge; never blocks. Introduced v3.13.0."
allowed-tools: Read, Write, Edit, Bash, Glob, Skill, Task
argument-hint: [<task-name>]
---

# Validate: All

Run every validation gate sequentially against the current task. Aggregate the per-gate results into a single summary envelope; print a human-readable table; point at `code-quality-tools` capabilities not wrapped here (for users who want to go deeper).

## Usage

```
/drupal-dev-framework:validate-all              # run all gates against current task
/drupal-dev-framework:validate-all <task-name>  # run against a specific task
```

## What this does

1. **Resolve task + project context** — same resolution as other `/validate:*` commands.

2. **Determine which visual gates can run** — visual-regression and visual-parity require args (`<component>`, `<viewport>`, and for parity a `<reference>`) that this command doesn't take. So:
   - `validate-visual-regression` → runs ONLY if the project's screenshot store already has at least one `<component>/<viewport>` with `role: baseline`. Invokes itself for EACH known component+viewport pair. If the store is empty → skipped with a helpful message.
   - `validate-visual-parity` → v1 ALWAYS skips in the `/validate:all` flow (no way to know the user's intended reference per-invocation). User runs `/validate:visual-parity` manually with explicit args.

   v2 candidate: per-task "visual coverage manifest" declaring which components and references to include in `/validate:all`. For now, user picks.

3. **Run the 5 non-visual gates sequentially**:
   - `/drupal-dev-framework:validate-tdd` → capture envelope
   - `/drupal-dev-framework:validate-solid` → capture
   - `/drupal-dev-framework:validate-dry` → capture
   - `/drupal-dev-framework:validate-security` → capture
   - `/drupal-dev-framework:validate-guides` → capture

   Sequential. Cache locality benefits (each gate may re-use loaded dev-guides, git state, etc.). Parallel is a v2 candidate.

   For each: execute the flow of the target command within this command's execution context (same pattern as `/scope` invocation from `/research` — do NOT shell out to sibling slash commands). Produce the result envelope per `references/validation-gate-result.md`.

4. **Run visual-regression for each stored baseline** (step 2 gate): if the store has components, iterate. For each `<component>/<viewport>` pair, invoke the visual-regression flow with the stored baseline. The user may get a diff-classification prompt per component if any diffs are found — that's expected. Sequence matters: let the user classify each before moving to the next (do NOT batch the prompts).

5. **Aggregate into the `_all.json` envelope** (per `references/validation-gate-result.md` §6):

   ```json
   {
     "schema_version": "1.0",
     "run_at": "<ISO-8601 UTC>",
     "task": "<task_name>",
     "gates": [
       {"gate": "tdd", "verdict": "pass"},
       {"gate": "solid", "verdict": "warning", "messages": ["..."]},
       {"gate": "dry", "verdict": "pass"},
       {"gate": "security", "verdict": "pass"},
       {"gate": "guides", "verdict": "fail", "messages": ["..."]},
       {"gate": "visual-regression", "verdict": "skipped", "messages": ["No baselines in store"]},
       {"gate": "visual-parity", "verdict": "skipped", "messages": ["visual-parity requires explicit reference; run manually"]}
     ],
     "summary": {"pass": 3, "warning": 1, "fail": 1, "skipped": 2, "total": 7},
     "discoverability_hint": "For deeper coverage, see: /code-quality:lint, /code-quality:coverage, /code-quality:review, /code-quality:audit, /code-quality:ultrareview (not wrapped by /validate:*)"
   }
   ```

6. **Persist** — write aggregate to:
   - `<task_folder>/validations/latest/_all.json` (overwrite)
   - `<task_folder>/validations/history.jsonl` (append)

   Note: each individual gate that ran also already persisted its own `latest/<gate>.json`. The `_all.json` is an additional summary, not a replacement.

7. **Print CLI summary** — tabular output:

   ```
   Validation summary for <task_name>:

     Gate                  Verdict    Notes
     tdd                   pass       all checks passed
     solid                 warning    SettingsForm violates SRP
     dry                   pass       no duplication found
     security              pass       no findings
     guides                fail       no guide citations in research.md
     visual-regression     skipped    no baselines in store yet
     visual-parity         skipped    run manually with <reference>

     Totals: 3 pass · 1 warning · 1 fail · 2 skipped

   For deeper coverage, see:
     /code-quality:lint          (coding standards)
     /code-quality:coverage      (test coverage)
     /code-quality:review        (rubric-scored review)
     /code-quality:audit         (full code-quality audit)
     /code-quality:ultrareview   (cloud-hosted deep review)

   Saved:
     summary → <task>/validations/latest/_all.json
     history → <task>/validations/history.jsonl
   ```

8. **Exit behavior** — In interactive mode, the printed summary is the signal. When chained non-interactively (CI), exit with a code reflecting the worst verdict: 0 if all pass/warning/skipped; 1 if any fail.

## Sequential execution

Gates run one at a time. Rationale: simpler error handling, cache locality (git state, guide loads), and the visual gates require user input mid-run which doesn't parallelize well. v2 candidate for non-interactive gates (tdd/solid/dry/security can parallelize; visual gates can't).

## What this does NOT do

- Does NOT wrap `/code-quality:lint`, `:coverage`, `:review`, `:audit`, `:ultrareview`, `:architecture-debate`, `:security-debate`. These stay invokable via their native `/code-quality:*` namespace. `/validate:all` surfaces them as available via the discoverability hint.
- Does NOT auto-skip gates based on AI-inferred applicability. v1 runs every gate (respects each gate's own skip semantics — e.g., `/validate:guides` skips if no phase artifacts exist). AI-driven skipping is a v2 candidate.
- Does NOT enforce `/validate:visual-parity` to run. It requires an explicit reference per invocation; user runs it manually when they have a comp in hand.

## Error cases

| Scenario | Behavior |
|---|---|
| No task context | Abort; exit 2 |
| Individual gate fails to execute (e.g., code-quality-tools missing) | That gate's envelope gets `verdict: skipped` with the failure in messages. Other gates continue. Summary reflects the mix |
| All gates skip | Print summary with all-skipped; exit 0; user sees there's no signal to act on |
| Write to `_all.json` fails | Print summary to stdout anyway; mention write failure in trailer |

## Soft-nudge posture

- Individual gate `fail` never blocks; `/validate:all` aggregates, surfaces, and lets the user decide
- The discoverability hint is a nudge, not noise — shown once at the end, not per-gate
- Visual-regression prompts happen inline per component (can't batch the classification prompts in v1)

## v2 candidates

- Per-task visual coverage manifest (declare which components/viewports/references go into `/validate:all`)
- Parallel execution of non-visual gates
- AI-driven gate skipping based on task context / applicability metadata
- Deferred visual-change approvals via `/complete` batch hook

See `implementation_process/in_progress/<this-task>/v2-candidates.md`.

## Related

- `/drupal-dev-framework:validate-tdd` / `:validate-solid` / `:validate-dry` / `:validate-security` — wrapped gates
- `/drupal-dev-framework:validate-guides` — framework-owned gate
- `/drupal-dev-framework:validate-visual-regression` / `:validate-visual-parity` — visual gates
- `references/validation-gate-result.md` — shared envelope + aggregate envelope schema
- `/code-quality:lint` / `:coverage` / `:review` / `:audit` / `:ultrareview` — complementary `code-quality-tools` capabilities not wrapped here
