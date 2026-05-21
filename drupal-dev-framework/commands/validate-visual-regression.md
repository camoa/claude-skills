---
description: "Run the committed tests/visual/ suite against the surface registry, diff each surface at every viewport, and classify regressions. Registry-driven multi-viewport batch on @lullabot/playwright-drupal; a11y baseline pairing; mask regions. Emits the standard envelope + _visual_regression.json audit. gate_type: visual_regression. Part of the /review dispatcher chain. Soft-nudge. Reworked v4.13.0."
allowed-tools: Read, Write, Edit, Bash, Glob, Skill
argument-hint: "[<task>] [--bootstrap] [--update-baselines \"<reason>\"] [--show-diffs] [--add-surface <url>] [--ci]"
---

# /validate:visual-regression

<!-- visual-review:dispatch-ready -->

Runs the project's committed `tests/visual/` visual-regression suite — every
surface registered with `gates: [visual_regression]`, at every viewport — in a
single Playwright invocation. Diffs against committed baselines; on a diff,
prompts the user to classify regression vs intentional. Emits
`validations/latest/visual-regression.json` (standard envelope) +
`_visual_regression.json` (gate audit). The `<!-- visual-review:dispatch-ready -->`
marker makes `/review`'s change-impact dispatcher call this gate.

Soft-nudge — `fail` signals but never blocks. Full walkthrough:
`references/visual-regression-walkthrough.md`.

## Arguments

- `<task>` — task name (positional); scopes the audit + envelope output
- `--bootstrap` — capture first baselines for surfaces that have none (delegates
  to `baseline-manager.sh`, user-confirmed)
- `--update-baselines "<reason>"` — regenerate baselines for the affected
  surfaces; `<reason>` is required (see the trigger catalog in
  `tests/visual/README.md`)
- `--show-diffs` — open the Playwright HTML report after the run
- `--add-surface <url>` — defer to the `/setup-visual-regression --add-surface`
  fast path (append one surface + offer baseline capture)
- `--ci` — non-interactive: no classification prompts; any diff → `fail`

## Step 1: Resolve task + project context

Resolve the task and project the same way other `/validate:*` commands do.
Resolve `codePath` from `project_state.md` via the `project-state-reader`
skill. If `codePath` is null, prompt the user to run `/set-code-path` and stop.
Invoke the `session-context-writer` skill with the resolved project + task.

## Step 2: Read the Visual Review pointer

Read `project_state.md` via `project-state-reader`; inspect `visualReview`.

- `visualReview: null` (field absent) or `visualReview.enabled: false` → visual
  review is not set up. Print: `"visual review is not set up — run /setup-visual-regression first."` and stop.
- Otherwise continue. The surface registry lives at
  `<codePath>/.visual-review/registry.yml` (shared with `/setup-atk`). The
  `**Visual Review:**` pointer's path is codePath-relative — resolve the
  registry against `codePath`.

## Step 3: Check the suite exists

If `<codePath>/tests/visual/` does not exist → print:
`"No tests/visual/ suite found. Run /setup-visual-regression first."` and stop.
Never auto-scaffold here — setup is `/setup-visual-regression`'s job.

## Step 4: --add-surface fast path

If `--add-surface <url>` is present: this is the `/setup-visual-regression`
add-surface flow. Execute the **`--add-surface` fast path** documented in
`commands/setup-visual-regression.md` (append the surface to the registry,
generate its spec, offer a confirmed baseline capture), then stop.

## Step 5: Load the registry; select VR surfaces

Read `<codePath>/.visual-review/registry.yml` (Claude parses the YAML — no
shell script parses the registry). Collect every surface whose `gates` list
contains `visual_regression`. Note each surface's `id`, `url`, `viewports`
(default to the registry's top-level `viewports` matrix when absent), and
`masks`.

If no surface has `visual_regression` in `gates` → emit `verdict: skipped`,
message `"registry has no visual_regression surfaces"`, persist, and stop.

## Step 6: Check baselines exist (loud failure on missing)

For each (surface × viewport), the expected baseline is
`<codePath>/tests/visual/<id>.spec.ts-snapshots/<id>-1-visual-chromium-<viewport>-linux.png`.
Use the `screenshot-store-reader` skill (`screenshot-store-read.sh <codePath>`)
to enumerate what exists.

If any (surface × viewport) has **no baseline** and neither `--bootstrap` nor
`--update-baselines` was passed → emit `verdict: fail` with the remediation
message:

> No baseline found for `<surface-id>/<viewport>`. Run
> `/validate:visual-regression --bootstrap` to capture first baselines.

Persist the envelope and stop. **Never silently auto-create a baseline.**

## Step 7: --bootstrap / --update-baselines (delegate to baseline-manager.sh)

If `--bootstrap` or `--update-baselines "<reason>"` is present, delegate to
`scripts/baseline-manager.sh` using its **two-stage confirm model**:

1. **Plan stage** — invoke without `--confirmed`:
   - bootstrap: `baseline-manager.sh --bootstrap --registry <reg> --codepath <codePath>`
   - update: `baseline-manager.sh --update-baselines "<reason>" --registry <reg> --codepath <codePath> --grep "<surface-id-pattern>"`
     (`--grep` scopes to the affected surfaces — never blanket unless the user
     explicitly asks for all).
2. Show the user the plan's `surfaces_planned` + `viewports`. If `blanket: true`,
   warn: *"This will update ALL visual baselines for N surfaces. Are you sure? [y]es / [n]o"*; otherwise prompt `[y]es / [n]o`.
3. On `[n]` → stop without writing.
4. On `[y]` → re-invoke `baseline-manager.sh` with the **same arguments + `--confirmed`**.
   This is the only path that runs `npx playwright test --update-snapshots`
   (host-side) and appends `baseline-history.jsonl`.
5. After the confirmed run completes, re-run from Step 6.

In `--ci` mode, baseline writes are not performed — print
`"--ci: baseline (re)generation needs interactive confirmation; run interactively"`
and treat missing baselines as `fail`.

## Step 8: Run the suite

Invoke `scripts/visual-regression-gate.sh <registry_path> <codePath>` (add
`--ci` when this command was called with `--ci`). The script discovers the
`visual-chromium-*` projects from `playwright.config.ts`, runs
`npx playwright test` host-side, and emits a per-surface JSON fragment
(`surfaces[]` + `summary`). Playwright reaches the DDEV site over HTTP via
`DDEV_PRIMARY_URL` / `PLAYWRIGHT_BASE_URL`.

Verify the script's stdout is valid JSON (`jq empty`). If not, surface stderr
verbatim and stop.

## Step 9: Classify each failed surface

For every surface in the gate output with `verdict: fail`:

- **`--ci` mode** — no prompt; record `classification: "regression"`,
  `baseline_updated: false`.
- **Interactive** — show the surface id, failed viewport(s), `diff_percent`,
  and the diff-image location (Playwright writes it under `test-results/`).
  Emit the `visual-regression-gate-fail` prompt from
  `references/gate-hardening-prompts.md` substituting `{{surface_id}}`,
  `{{viewport}}`, `{{diff_percent}}`, `{{diff_pixels}}`, `{{diff_path}}`.
  Classify **one surface before moving to the next** (no batched prompts):
  - `[r]` Regression → `verdict: fail`, `classification: "regression"`,
    `baseline_updated: false`.
  - `[i]` Intentional → run `baseline-manager.sh --update-baselines
    "intentional-ui-change" --registry <reg> --codepath <codePath> --grep
    "<surface-id>" --triggered-by validate-visual-regression:classify` in the
    two-stage model (the `[i]` choice IS the confirmation — go straight to a
    final `[y]/[n]` "about to write" check, then `--confirmed`). After the
    confirmed update, for each updated baseline PNG invoke
    `screenshot-store-write.sh write-baseline-codepath <codePath> <surface-id>
    <png-filename> <viewport> lullabot-playwright <task>` to write the
    provenance sidecar. Set `verdict: pass`, `classification: "intentional"`,
    `baseline_updated: true`.
  - `[c]` Cancel → `verdict: skipped`, `classification: "cancelled"`.

## Step 10: Aggregate + emit the envelope

Aggregate to the worst verdict across all surfaces (`fail` > `warning` >
`pass`; `skipped` only if all skipped). Write the standard envelope per
`references/validation-gate-result.md` to
`<task>/validations/latest/visual-regression.json` and append
`<task>/validations/history.jsonl`. The `details` block:

```json
"details": {
  "source": "framework:visual-regression",
  "runtime": "lullabot-playwright",
  "registry_path": "<abs path to registry.yml>",
  "surfaces": [
    {"id": "home-hero", "url": "/", "viewports": ["desktop","tablet","phone"],
     "verdict": "pass", "classification": null, "baseline_updated": false,
     "a11y_diff_path": null}
  ],
  "diff_tolerance": 0.005,
  "capture_context": "host-side"
}
```

`gate` is `"visual-regression"` (hyphen form — matches the command name).

## Step 11: Write the gate audit

Assemble `_visual_regression.json` with `jq -n --arg`/`--argjson` (never raw
string interpolation) and write it via
`scripts/gate-audit-write.sh <task_folder> visual_regression '<json>'`:

```json
{
  "schema_version": "1.2",
  "gate_type": "visual_regression",
  "fired_at": "<ISO timestamp>",
  "task_folder": "<abs task folder>",
  "user_choice": null,
  "bypass_reason": null,
  "gate_specific": {
    "verdict": "pass | warning | fail | skipped",
    "envelope_path": "<task>/validations/latest/visual-regression.json",
    "surfaces_run": 3,
    "surfaces_passed": 2,
    "surfaces_failed": 1,
    "surfaces_skipped": 0,
    "viewports_tested": ["desktop","tablet","phone"],
    "baselines_updated": ["home-hero/desktop"],
    "a11y_diffs_found": 0,
    "playwright_project_pattern": "visual-chromium-*"
  }
}
```

## Step 12: --show-diffs

If `--show-diffs` was passed, run `npx playwright show-report` host-side from
`codePath` (default port 9323; if busy, Playwright picks the next free port).
Print the report URL.

## Step 13: Print the summary

```
/validate:visual-regression complete.
Verdict: <pass|warning|fail|skipped>
Surfaces: <passed>/<run> passed, <failed> failed, <skipped> skipped
Viewports: <list>
Baselines updated: <list or none>
Audit: <task_folder>/_visual_regression.json
```

## Soft-nudge posture

- A diff `fail` does NOT block — the user investigates at their pace.
- Intentional-change approval is inline and always user-confirmed; nothing
  rotates without an explicit `[y]`.
- Missing baselines fail loudly with a remediation message — never a silent
  auto-create.
- a11y diffs are warning-only in v1 (the `.txt` snapshot surfaces in the
  Playwright report); a future per-surface `a11y_block: true` registry flag can
  make them hard-block.

## Related

- `/drupal-dev-framework:setup-visual-regression` — installs the suite + drives surface discovery
- `/drupal-dev-framework:validate-visual-parity` — sibling gate; compares against a design comp
- `/drupal-dev-framework:validate-all` — orchestrator
- `scripts/visual-regression-gate.sh` · `scripts/baseline-manager.sh` · `scripts/screenshot-store-write.sh`
- `references/screenshot-store-schema.md` · `references/validation-gate-result.md`
