---
description: "Phase 4 of a task. Run all hard-blocking validation gates before PR creation. Trigger: 'review task', 'pre-PR review', 'gate check'. Aggregates per-gate verdicts into _review.json audit; writes PR_BODY.md on green. Slimmed /complete depends on this — projects with **Review Required:** true require /review before /complete archives. Introduced v4.1.0."
allowed-tools: Read, Write, Edit, Bash, Glob, Skill, Task
argument-hint: <task-name>
---

# Review

Phase 4 of a task — run all hard-blocking validation gates before PR creation. Behavior current as of v4.1.0; full prose / examples / version history in `references/review-phase-walkthrough.md`. **Reading strategy:** gates run **Type B** reads — full source and config files, no grep-first (`https://camoa.github.io/dev-guides/development/reading-strategy/`).

## Usage

```
/ai-dev-assistant:review <task-name>                # default mode (/validate:all)
/ai-dev-assistant:review <task> --team              # use /validate:team (with fallback)
/ai-dev-assistant:review <task> --dry-run           # run, write audit, don't mark Phase 4 [x]
/ai-dev-assistant:review <task> --rerun-failed      # only re-run gates that failed last run
/ai-dev-assistant:review <task> --no-pr-body        # skip writing PR_BODY.md
/ai-dev-assistant:review <task> --skip-<gate> <r>   # skip a gate (reason recorded); --include-<gate> forces a dispatch gate on
/ai-dev-assistant:review <task> --allow-dirty       # skip working-tree warning
/ai-dev-assistant:review <task> --base <branch>     # diff base for change detection (default: main). Pass the PR base for non-main branches — else the merge-base diff against `main` shows the whole branch divergence, not the change.
/ai-dev-assistant:review <task> --headless          # non-interactive: no prompts, fail-closed, exit code + compact verdict
/ai-dev-assistant:review <task> --full-audit        # run all gates whole-tree (no diff scoping; pre-v4.20 behavior)
```

`<gate>` whitelist: `tdd | solid | dry | security | guides | playbook-adherence | skill-review | plugin-validate` (hard-block — `--skip-` bypasses) plus `e2e | visual-regression | visual-parity` (step-6 dispatch gates — `--skip-` = off this run, `--include-` = on this run). Unknown gate names → exit 2. Reasons non-empty, must NOT start with `--` → exit 2. `--headless` is a boolean flag (no value) and composes with all flags above; see the **Headless mode** section below. `--full-audit` is a boolean flag (no value) — when set, all four PHP/JS-centric gates run whole-tree with no diff scoping; see step 5a. Both flags compose freely.

`<task-name>` must match `^[a-z0-9_-]+$`. Path traversal (`..`, `/`) and special chars rejected → exit 2. Missing arg AND no session-context task → exit 2 with usage.

## Runtime Steps

Run in order. Each "gate" step writes audit; non-bypassable unless documented `--skip-*` flag supplied (records `bypass_reason`).

1. **Phase Transition Check.** Read `task.md` Phase Status. If Phase 3 not `[x]`, soft-nudge once. If `## Phase Status` H2 absent entirely, append it with the four standard phase lines (1 Research, 2 Architecture, 3 Implementation, 4 Review). If only Phase 4 line missing, idempotently insert before next `## ` boundary (or EOF if none).

2. **Resolve task + project context.** Validate `<task-name>` charset (above). If absent, try session-context-reader; if also null, exit 2 with usage. Resolve the project folder by running `${CLAUDE_PLUGIN_ROOT}/scripts/project-state-read.sh "<project_folder>"` (Bash) and parsing its JSON.

3. **Working-tree warning.** Run `git diff --name-only`. If non-empty AND `--allow-dirty` not set: print warning ("gates run on staged + working tree state, not committed state. Continue? [y/N]"). Default `[N]`. User declines → exit 0. **Under `--headless`:** do not prompt; proceed regardless of the dirty tree; record `working_tree: "dirty"|"clean"` in the step-10 payload (equivalent to auto-`--allow-dirty`).

4. **Resolve gate plan.** Build `gates_run[]` skeleton. For conditional-gate file detection use **merge-base diff** against the diff base — `git diff $(git merge-base "$BASE" HEAD)..HEAD --name-only`, where `$BASE` is the `--base` value (**default `main`**; the loop passes the PR base). Committed-on-branch changes count, NOT just working tree. **The base matters:** on a branch cut from a non-`main` integration branch, `merge-base main HEAD` resolves to an ancient fork point and the diff balloons to the whole branch divergence (false "change") — always pass the actual base. Detect:
   - `skill-review`: merge-base diff includes `skills/*/SKILL.md`
   - `plugin-validate`: merge-base diff includes any plugin file
   - `validate-playbook-adherence`: file `commands/validate-playbook-adherence.md` exists OR mark `verdict: "skipped-not-shipped"` with `bypass_reason: "sibling adherence_gates not yet shipped"`
   - hardened `validate-guides`: command body contains `<!-- /review:hard-block -->` marker OR fall back to soft mode (note in audit)

5. **Run hard-block gates sequentially.** For each: invoke flow inline (do NOT shell out). Capture per-gate envelope at `<task>/validations/latest/<gate>.json` per `references/validation-gate-result.md` v1.0. Add to `gates_run[]`. Order: tdd → solid → dry → security → guides → validate-playbook-adherence → skill-review (conditional) → plugin-validate (conditional).

   **5.0 Architecture-fit validation against the framework review recipe.** Before the code-quality gates run, validate the change against the documented architecture using the stack's review recipe. Additive — it never replaces or weakens a hard-block gate; it supplies `architecture-validator` the framework-specific BLOCKING checks the generic agent lacks. Follow the shared protocol in `references/recipe-resolution.md` with `phase: review` and the step-2 `<project_folder>`: it invokes `process-recipe-loader`, resolves each framework's review recipe (project_state-first, then source order, else `action:ask-user`), records the source in `project_state.md`, and defines how to follow each result (Read `body_path` — never streamed; follow `verified:true` directly; surface `verified:false` for human review first; `action:ask-user` → ask for a path or to research). Surface loader `warnings[]` (`no_frameworks_defined`, `navigator_unavailable:<framework>`, `recipe_not_published:<framework>`). The COMMAND owns resolution and injects the body; the agent stays generic (no Skill tool).

   - **Inject the body verbatim, or do not dispatch.** For each `available:true` framework, Read its `body_path`, gate by `verified`, then dispatch `architecture-validator` (Task tool) with the recipe body **verbatim** inside the delimited block from `recipe-resolution.md` step 4 (`=== RESOLVED RECIPE (key=…, source=…, verified=…) === <body> === END RECIPE ===`). Dispatching without the body is a bug — the agent would carry no framework checks. The validator keeps its BLOCK posture (a blocking architecture-fit/gate failure is a hard-block result, never softened). Dispatch **only** when a `body_path` resolved: on `no_frameworks_defined`, follow the framework detect-or-ask sub-protocol in `references/recipe-resolution.md` step 6 (under `--headless`, the sub-protocol takes its unattended path — record gap + skip, no prompt); on `action:ask-user` ask and proceed per the answer; a framework that resolved nothing is skipped with a note. This never relaxes the hard-block orchestration below.
   - **Record the resolution (recipe-resolution.md step 7).** After resolving, run `${CLAUDE_PLUGIN_ROOT}/scripts/recipe-declarations-audit.sh --body <body_path> --phase review --framework <fw>` per resolved framework and surface any `absent_recommended` declaration as a one-line advisory (review carries the `recommended:true` `## Change-impact globs` token, so a missing/misspelled one is flagged here rather than silently degrading the change-impact dispatch); then write `<task>/_recipe-load.json` via `${CLAUDE_PLUGIN_ROOT}/scripts/gate-audit-write.sh "<task_folder>" recipe-load "<payload>"` (per `references/gate-audit-schema.md` §5.12), capturing every framework + the lint + any `bypass` (including the `--headless` `no_frameworks_defined` skip). Observability only — never blocks; the hard-block gates below are unaffected.

   **5.0b Adopted agentic-recipe Verifier gate (capability-class, v5.12.0+).** If this task has an `adopted` agentic recipe (per `project_state.md`'s `**Agentic Recipes:**` block / `<task_folder>/_agentic-recipe.json`), run its `## Verifier` as a review gate per `references/agentic-recipe-resolution.md` step 5: Read the recipe body from `<task_folder>/adopted-recipe.md` (the `body_path` recorded in `_agentic-recipe.json` at adoption — a durable task-folder file `/research` persisted, **not** a navigator-served path; if the recorded `body_path` is unreadable, reconstruct it as `<task_folder>/adopted-recipe.md` under the current task folder before failing), run each `## Verifier` check PASS/FAIL — **any check failing exits non-zero ⇒ halt (hard-block)**. The `## Verifier` is typically live-site + `drush`-level (HTTP `<head>` assertions, `/sitemap.xml`, `drush` config checks); **a check that CANNOT run for lack of its dependency (no served site, no `drush`) is unresolved → fail-closed HALT** — apply step 8 rule 2's unresolved-gate posture (an unknown gate result is fail-closed, never absorbed into a pass), never a silent "skipped → pass". Update `<task_folder>/_agentic-recipe.json`'s `verifier` field (`{ran, verdict, failed_checks}`) via `${CLAUDE_PLUGIN_ROOT}/scripts/gate-audit-write.sh "<task_folder>" agentic-recipe "<payload>"` (schema_version `1.5`; `references/gate-audit-schema.md` §5.13). **`gate-audit-write` overwrites the whole file** — first Read the existing `_agentic-recipe.json` and re-supply the **full** §5.13 payload (preserve the recorded `capability`/`recipe_name`/`recipe_sha`/`provenance`/`verified`/`decision`/`reason`/`body_path` fields from `/research`), setting only `verifier`. Do not write a payload that drops the decision half. **Additive** — it never softens or replaces the hard-block gates below; an adopted recipe is not "done" until its own verifier passes. Skip silently when there is no adopted agentic recipe (`no_match`/`used_own`/`deferred`/absent).

   **5a. Change-scoped gate passing (default) and `--full-audit`.** The four PHP/JS-centric gates (`tdd` / `solid` / `dry` / `security`) accept a `--files <list>` parameter (forwarded from their `validate-*` wrappers) which passes to the underlying code-quality `--changed <list>` mode — scoping each gate to the diff rather than the whole project tree.

   **Default (change-scoped) — all modes except `--full-audit`:** From the step-4 merge-base diff (`git diff $(git merge-base "$BASE" HEAD)..HEAD --name-only` with the resolved `--base`, run from the review's cwd), filter to gate-relevant extensions. The extension set is the **union** of a framework-neutral language floor (`.php` `.js` `.mjs` `.cjs` `.ts` `.tsx` `.vue`) **and** the active framework's code-quality extensions, reconstructed from the **same review recipe body already Read at step 5.0** (no second resolution): for each `available:true` framework, take its `## Code-quality extensions` declaration (the `code_quality_extensions` JSON list) and add those to the filter. No recipe (or a framework declaring none) → neutral floor alone (an undeclared framework file type is simply not scoped in — agnostic-floor posture). Write the filtered list to a temp file and pass it via `--files <tmpfile>` to each of the four wrappers (`validate-tdd`, `validate-solid`, `validate-dry`, `validate-security`); clean it up after. An empty filtered list (CSS/config/asset-only change) is skipped internally by the code-quality `--changed` mode — **not** a `--skip-<gate>` bypass (no `bypass_reason`), so by step-8 rule 4 it does **not** prevent `overall_verdict: pass`. **`--full-audit` mode** skips the diff-filter entirely and invokes all four gates with **no** `--files` (whole-tree scan, pre-v4.20 behavior — surfaces whole-codebase debt). `guides` is **not** covered here (own applicability check; CSS/SCSS/design-system changes ARE applicable and cite the guide); `validate-playbook-adherence` / `skill-review` / `plugin-validate` keep their own conditions; an empty diff → empty list → each skips cleanly.

6. **Change-impact dispatch** (v4.11.0+ — replaces v3.13.0's always-soft visual step). Execute `references/visual-review/change-impact-dispatch.md` in full — a RECOMMENDER, not an enforcer. Fast path: no `**Visual Review:**` field in `project_state.md` (or `disabled`) → run zero new gates, print `no visual-review surfaces configured; run /setup-* to opt in`, omit `dispatch_plan` from the payload entirely, skip to step 7. Otherwise: `change-impact-classify.sh <task>` classifies the merge-base diff → recommended gates; the user opts in **per task** via a `## Review Gates` block in `task.md` (written once, never re-asked); opted-in **and** dispatch-ready gates run soft; `visual_parity` auto-runs on design-implementation tasks; unshipped B/C/D gates → `skipped-not-shipped`. `--include-/--skip-<gate>` override the stored opt-in for this run only. Assemble `dispatch_plan` (`gate-audit-schema.md`) for the step-10 payload.

7. **Apply `--skip-<gate> <reason>` flags.** Validate gate name against whitelist + reason non-empty + reason not `--`-prefixed (else exit 2). For each valid flag: don't run the gate; set `gates_run[].verdict: "bypassed"` and `bypass_reason: <reason>`.

8. **Aggregate `overall_verdict`.** A per-gate parse error or missing/unreadable envelope is an **unresolved** result — record it `verdict: "skipped"` with `unresolved: true` in `gates_run[].messages[]`, **distinct** from an explicit `--skip` bypass and from `skipped-not-shipped`. Resolve in this order; **every branch yields a legal `overall_verdict` ∈ {pass, fail, bypassed}**:
   1. `fail` if any hard-block gate has `verdict: fail` — **fail dominates** (a real fail is never masked by another gate's explicit `--skip`).
   2. `fail` if any hard-block gate is **unresolved** (parse-error / missing envelope) — an unknown gate result is **fail-closed, never absorbed into `bypassed`**. (Only the **`overall_verdict`** is written `fail`; the gate's own per-gate `verdict` stays `skipped` + `unresolved: true`, with a `messages[]` note — the schema enum has no `incomplete` value.) **This rule is ranked ABOVE bypass on purpose.**
   3. `bypassed` if any hard-block gate has `bypass_reason` populated (explicit `--skip-<gate>`, or a documented auto-bypass such as an unshipped `validate-playbook-adherence`) — reached only when there is no `fail` and nothing unresolved.
   4. `pass` if **all** hard-block gates `pass`. Benign non-blocking states (`skipped-not-shipped`, a tool-unavailable soft skip) that are **not** unresolved and **not** a hard-block fail do **not** prevent `pass` and do **not** force non-zero on their own.

9. **On `overall_verdict == "fail"` (per step 8, fail dominates any coexisting `--skip` bypass): mandated-wording prompt.** Display verbatim per template `review-gate-fail` (literal text below; mirrors v1.2 template when sibling ships, byte-identical fallback otherwise). Block on `[r]/[s]/[a]` — no default. `[r]` exits 1 (user fixes, re-runs). `[s]` prompts per failed gate for free-text reason, populates `bypass_reason`, sets `overall_verdict: "bypassed"`. `[a]` exits 1 without writing `_review.json`. **Non-`r/s/a` input: re-display the prompt verbatim. Do not infer choice.** **Under `--headless`:** do NOT display this prompt — fall straight through to step 10 with `overall_verdict: "fail"`, then **print the compact verdict line (Headless mode) and exit non-zero**. **Fail-closed: never auto-`[s]`/auto-bypass.** A bypass under `--headless` requires an explicit `--skip-<gate> <reason>` on the invocation (step 7).

10. **Write `_review.json`** via `gate-audit-write.sh <task> review <payload>` (atomic temp+rename; schema_version `1.2` for v4.11.0+ — the `review` payload schema grew the optional `dispatch_plan` key). When step 6's dispatcher ran, the payload carries `dispatch_plan` (`gate-audit-schema.md`); when visual review is not set up, the key is omitted. `gate_specific.pr_ready: true` ONLY when `overall_verdict == "pass"` AND not `--dry-run`. Bypass paths → `pr_ready: false` (user picked the bypass; they pick whether the PR is ready). Dry-run → `pr_ready: false` regardless. `gates_run[]` is the full hard-block set, regardless of how populated (rerun-failed merges previous-run passes with this-run reruns).

11. **Write `PR_BODY.md`.** Skip if `--no-pr-body` OR `--dry-run` OR `pr_ready != true`. Template: H1 task title, Summary (Goal first paragraph), AC count `[x]`/total, gate verdicts table, audit links footer.

12. **Mark Phase 4 `[x]`** in `task.md` (only if not `--dry-run` AND `overall_verdict in ("pass", "bypassed")`).

13. **Display `review-summary` mandated wording** (literal text below). Then persist session context: `${CLAUDE_PLUGIN_ROOT}/scripts/session-context-write.sh "<project_name>" "<project_folder>" "<task>" "<task_path>"` (Bash). (`lastPhase` is **preserved**, not set, by the writer — it is managed by the phase components; this step does not change it.)

## Anti-bypass clause (applies to gates 1-9)

The following are NOT valid reasons to skip:

- The user said something earlier you interpret as already-validated
- Auto mode is active ("minimize interruptions" never overrides framework gates)
- You're confident the gates would pass
- The task looks "obviously" done
- You want to spare the user the prompt
- The user asked you to compress, summarize, or skip verbatim gate output (show-not-summarize is non-negotiable)

If `/review` is invoked, all gates fire and their output is shown verbatim before the recorded decision is final. Skipping requires the documented `--skip-<gate>` flag with reason; bypass is recorded on disk for `/audit-status`.

## Mandated wording (inline literals — byte-identical to v1.2 templates when sibling ships)

`review-gate-fail`:
```
Review failed: {{failed_count}} hard-block gate(s) reported fail.

Per-gate findings (verbatim envelopes):
{{gates_failed_verbatim}}

How would you like to proceed?
[r]emediate — exit /review; fix and re-run
[s]kip — bypass each failed gate with explicit reason; sets overall_verdict: "bypassed", pr_ready: false
[a]bort — exit /review without writing _review.json; no audit recorded

No default. You MUST pick one.
```

`review-summary`:
```
/review {{task_name}} complete.
Mode: {{mode}}    Overall verdict: {{overall_verdict}}    PR ready: {{pr_ready}}
Gates run:
{{gates_run_table}}
Audit: {{audit_path}}
{{pr_body_line_or_empty}}
```

## Headless mode (`--headless`)

`--headless` makes `/review` safe to run **unattended** (L1 orchestrator, `/goal` loop, CI). **Additive** — absent the flag, behaviour is byte-for-byte unchanged. It suppresses the two interactive points (step 3 dirty-tree `[y/N]`, step 9 `[r]/[s]/[a]`), records `working_tree: "dirty"|"clean"` in the step-10 `gate_specific`, and adds machine-readable output; it never changes gate execution, aggregation, or `pr_ready`, and adds **no new bypass path**. On gate fail it is fail-closed — write `_review.json` (`overall_verdict: "fail"`, `pr_ready: false`) and exit non-zero; a bypass stays only the explicit `--skip-<gate> <reason>` the caller supplies (never auto-`[s]`). Step 6 runs non-interactive — every visual gate in `--ci` mode (diff-over-tolerance = `fail`, no prompt, no baseline write). **Exit codes:** `0` only on a clean `pass` (or `bypassed` with zero failing/unresolved hard-block gates); any hard-block `fail` or unresolved gate ⇒ non-zero (`1`); `2` = arg error; not unambiguously clean ⇒ non-zero — **never exit 0 on doubt**. After step 10 print the compact verdict line per gate (`<gate> verdict=<pass|fail|bypassed|skipped>`) plus an overall line for a transcript reader. Full `--headless` contract, `--rerun-failed`/`--team` semantics, and the `claude ultrareview` escalation note: `references/review-phase-walkthrough.md`.

## Pointers

- Walkthrough: `references/review-phase-walkthrough.md` (sibling `plumbing_docs_tests`) · Step 6 dispatcher: `references/visual-review/change-impact-dispatch.md` (v4.11.0+) · schemas: `references/gate-audit-schema.md` v1.2 (`gate_type: "review"`; `dispatch_plan`) + per-gate `references/validation-gate-result.md` v1.0
- Project opt-out: `**Review Required:** false` keeps gates at `/complete` (legacy v4.0.2 posture)
- Related: `/ai-dev-assistant:implement` (Phase 3) · `:complete` (archive; consumes `_review.json`) · `:validate-all` / `:validate-team` (invoked by `/review`) · `:upgrade-project` (set `**Review Required:**`) · `:audit-status` (audit visibility)
