# Recipe-adoption sweep (`/upgrade-project` Step 4b)

The eager on-ramp that complements the lazy point-of-need recipe trigger: after the project-state pass, once `**Frameworks:**` is known, `/upgrade-project` resolves + **records** process recipes for ALL applicable lifecycle phases in one pass so the coverage map is visible up front, instead of being discovered one phase at a time mid-work.

**It records source decisions and reports coverage; it does NOT pre-cache or follow recipe bodies, and it does NOT approve unverified recipes** — bodies are still Read and followed lazily per-phase at use-time, and `verified:false` recipes still get human review then. This is a recording + visibility pass, not an execution commitment. Runs after Step 4, part of the project-level work (so it runs even with `--skip-tasks`); skipped only when frameworks are empty.

- **Guard.** Re-run `bash scripts/project-state-read.sh <project>` to read the now-current `.frameworks` and `.processRecipes`. If `.frameworks == []` (no codePath, undetectable stack, or user declined the Frameworks gap in Step 4), SKIP the sweep with a one-line note ("recipe-adoption sweep skipped: no **Frameworks:** set"). Never fail.
- **Snapshot for idempotency.** Capture the set of already-recorded keys from `.processRecipes` (each entry's `key`) BEFORE driving the loader. A key resolved during the sweep that is in this snapshot is reported "already"; one not in it is "newly recorded". The loader's `write_source_record` is itself idempotent (an unchanged line is a no-op — rc 3 — so re-running the sweep produces no churn); this snapshot only labels the report.
- **Drive the loader once per phase.** For each phase in the declared list in `references/recipe-resolution.md` ("Phases that resolve a framework recipe") — `research`, `design`, `implement`, `review`, `e2e-setup`, `visual-regression` — invoke the `process-recipe-loader` skill (Skill tool) with `phase: <phase>` and `project_folder: <project_folder>`. The loader resolves every framework for that phase, records each resolved `source=` line into `project_state.md` (idempotently), and returns its per-result JSON `{available, source, verified, recorded, action, body_path, notes[]}` + `warnings[]`. Resolution mechanics (source order, trust model, the `project_state` short-circuit, the source-record write) live in `references/recipe-resolution.md` and the loader — do not re-describe them here. **The sweep never Reads `body_path` and never follows a body** (no pre-caching; execution stays lazy).
- **Non-blocking on every miss.** The sweep is informational and MUST NOT prompt. Treat each no-body outcome as "no recipe yet" in the coverage map — do NOT enter the loader's `action:ask-user` interactive protocol, do NOT ask the user for a path, do NOT research or fabricate. Specifically: `available:false` + `action:ask-user`, a `recipe_not_published:<fw>` warning, a `navigator_unavailable:<fw>` warning, and `results:[]` with `no_frameworks_defined` all map to "no recipe yet" for that (phase, framework). Render `navigator_unavailable` as a transient "no recipe yet (navigator unavailable — re-run)" distinct from the benign "not published yet".
- **Coverage report.** After all six phases, print the map (per phase, per framework):
  ```
  ## Process-recipe adoption — coverage map (<project>)

  Frameworks: <fw1>, <fw2>
  Swept phases: research, design, implement, review, e2e-setup, visual-regression

  | phase             | <fw1>                          | <fw2>            |
  |-------------------|--------------------------------|------------------|
  | research          | ✓ source=dev-guides (recorded) | — no recipe yet  |
  | design            | ✓ source=local (already)       | — no recipe yet  |
  | implement         | — no recipe yet                | — no recipe yet  |
  | review            | ✓ source=dev-guides (recorded) | — no recipe yet  |
  | e2e-setup         | — no recipe yet                | — no recipe yet  |
  | visual-regression | — no recipe yet (navigator unavailable — re-run) | — no recipe yet |

  Recorded: {newly} newly, {already} already (idempotent). Gaps (no recipe yet): {G} of {phases×frameworks}.
  Bodies are NOT pre-cached — each is Read + followed lazily at its phase; verified:false recipes still get human review at use-time.
  ```
  Per cell: `✓ source=<src> (recorded|already)` when `available:true` (`recorded` = key absent from the pre-sweep snapshot, written this run; `already` = key in the snapshot, no churn); otherwise `— no recipe yet` (append the transient reason for `navigator_unavailable`). Make the gaps visible — the gap count is the headline.
- **`--dry-run`:** do NOT invoke the loader (it writes). Report "would sweep phases [research, design, implement, review, e2e-setup, visual-regression] across frameworks [<list>] and record resolved `source=` lines into project_state.md — no writes". Use the frameworks Step 4 would have set (the `detect-frameworks.sh` result) when `**Frameworks:**` is not yet on disk. Exit 0.
- **Unattended-safe.** The sweep auto-runs with no prompt; in a `--headless`/auto run it records what resolves and reports the gaps identically (no interactive arm is ever entered). It never blocks the upgrade.
