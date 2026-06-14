---
description: "Run all 7 validation gates (tdd, solid, dry, security, guides, visual-regression, visual-parity) sequentially against the current task. Aggregates results, prints summary table, and surfaces complementary code-quality-tools capabilities that aren't wrapped. Soft-nudge; never blocks. Introduced v3.13.0."
allowed-tools: Read, Write, Edit, Bash, Glob, Skill, Task
argument-hint: "[<task-name>]"
---

# Validate: All

Run every validation gate sequentially against the current task. Aggregate the per-gate results into a single summary envelope; print a human-readable table; point at `code-quality-tools` capabilities not wrapped here (for users who want to go deeper).

## Usage

```
/ai-dev-assistant:validate-all              # run all gates against current task
/ai-dev-assistant:validate-all <task-name>  # run against a specific task
```

> **Tip — unattended runs.** `/goal` pairs with `/validate:all` for green-until-done loops — e.g. `/goal every gate in the validation summary reports pass or skipped`. The evaluator judges only what the transcript shows, so the printed summary table (step 7) is what it reads. See `CONVENTIONS.md` "Condition-checked autonomy with `/goal`".

## What this does

1. **Resolve task + project context** — same resolution as other `/validate:*` commands.

2. **Determine which visual gates can run.**
   - `validate-visual-regression` (v4.13.0+, registry-driven) → runs when ALL three hold: (a) `project_state.md` has `**Visual Review:** enabled`, (b) `<codePath>/tests/visual/` exists, and (c) the surface registry has at least one surface with `visual_regression` in `gates[]`. When all three hold, run the gate via `scripts/visual-regression-gate.sh` (step 4). Otherwise → `skipped` with the contextual reason: `"visual review not enabled — run /setup-visual-regression"` / `"tests/visual/ not set up"` / `"registry has no visual_regression surfaces"`.
   - `validate-visual-parity` (v4.14.0+, registry-driven) → ALWAYS `skipped` in the `/validate:all` flow, with the reason `"visual-parity is design-implementation-scoped — run /validate:visual-parity, or let /review auto-run it on design tasks"`. Parity is no longer reference-per-invocation (the rework made it registry-driven), but it is not a *universal* gate the way tdd/solid/security are: it applies only when a task implements a designed surface. `/review`'s change-impact dispatcher auto-runs it (soft) on exactly those tasks; `/validate:all` runs the universal set and leaves parity to the dispatcher + standalone invocation.

   The surface registry (`<codePath>/.visual-review/registry.yml`) is the "visual coverage manifest" — it declares which surfaces `/validate:all` covers. No per-component iteration: the committed `tests/visual/` suite handles the surface × viewport loop.

3. **Run the 5 non-visual gates sequentially**:
   - `/ai-dev-assistant:validate-tdd` → capture envelope
   - `/ai-dev-assistant:validate-solid` → capture
   - `/ai-dev-assistant:validate-dry` → capture
   - `/ai-dev-assistant:validate-security` → capture
   - `/ai-dev-assistant:validate-guides` → capture

   Sequential. Cache locality benefits (each gate may re-use loaded dev-guides, git state, etc.). Parallel is a v2 candidate.

   For each: execute the flow of the target command within this command's execution context (same pattern as `/scope` invocation from `/research` — do NOT shell out to sibling slash commands). Produce the result envelope per `references/validation-gate-result.md`.

4. **Run visual-regression as a single suite invocation** (step 2 gate): when the three conditions hold, invoke `scripts/visual-regression-gate.sh <registry_path> <codePath>` (Library-First — call it via the `Bash` tool, do NOT inline the gate logic). The script runs the whole committed `tests/visual/` suite in one `npx playwright test` invocation and returns the aggregate `surfaces[]` JSON. There is no per-component loop — the suite handles the surface × viewport matrix.

   **Result aggregation:** the gate's per-surface results collapse into a SINGLE entry in the aggregate `gates[]` with `gate: "visual-regression"`. Verdict is the worst across all surfaces (`fail` if any failed > `warning` > `pass`; `skipped` only if all skipped). Per-surface detail goes into `messages[]`:
   > `["home-hero: pass", "article-card: fail (4.2% diff)", "footer: pass"]`

   This keeps the aggregate envelope's `gates[]` closed to the 7 known IDs; per-surface fan-out lives in `messages[]`.

   **Non-interactive (CI) mode:** when `/validate:all` runs without a TTY or with `$CI` set (detect via `[ -t 0 ] || [ -n "$CI" ]`), pass `--ci` to `visual-regression-gate.sh`. In `--ci` mode the suite still runs, but any diff is recorded as `fail` with no classification prompt and no baseline write — defaulting to `intentional` would silently move baselines (dangerous); defaulting to `regression` is the honest CI outcome. This matches v3.13.0's CI posture (interactive classification only happens in an interactive session).

5. **Aggregate into the `_all.json` envelope** (per `references/validation-gate-result.md`):

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
       {"gate": "visual-parity", "verdict": "skipped", "messages": ["design-implementation-scoped — run /validate:visual-parity or let /review auto-run it"]}
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
     visual-parity         skipped    design-scoped — /validate:visual-parity or /review

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
- Does NOT run `/validate:visual-parity`. Parity is registry-driven (v4.14.0+) but design-implementation-scoped, not universal — `/review`'s change-impact dispatcher auto-runs it (soft) on design tasks, and the user can invoke `/validate:visual-parity` standalone. `/validate:all` runs the universal gate set only.

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

- `/ai-dev-assistant:validate-tdd` / `:validate-solid` / `:validate-dry` / `:validate-security` — wrapped gates
- `/ai-dev-assistant:validate-guides` — framework-owned gate
- `/ai-dev-assistant:validate-visual-regression` / `:validate-visual-parity` — visual gates
- `references/validation-gate-result.md` — shared envelope + aggregate envelope schema
- `/code-quality:lint` / `:coverage` / `:review` / `:audit` / `:ultrareview` — complementary `code-quality-tools` capabilities not wrapped here
