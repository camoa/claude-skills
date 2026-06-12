---
description: "Phase 4 of a task. Run all hard-blocking validation gates before PR creation. Trigger: 'review task', 'pre-PR review', 'gate check'. Aggregates per-gate verdicts into _review.json audit; writes PR_BODY.md on green. Slimmed /complete depends on this — projects with **Review Required:** true require /review before /complete archives. Introduced v4.1.0."
allowed-tools: Read, Write, Edit, Bash, Glob, Skill, Task
argument-hint: <task-name>
---

# Review

Phase 4 of a task — run all hard-blocking validation gates before PR creation. Behavior current as of v4.1.0; full prose / examples / version history in `references/review-phase-walkthrough.md`.

> **Reading strategy:** Gates run **Type B** reads — full source and config files, no grep-first. See `https://camoa.github.io/dev-guides/development/reading-strategy/`.

## Usage

```
/drupal-dev-framework:review <task-name>                # default mode (/validate:all)
/drupal-dev-framework:review <task> --team              # use /validate:team (with fallback)
/drupal-dev-framework:review <task> --dry-run           # run, write audit, don't mark Phase 4 [x]
/drupal-dev-framework:review <task> --rerun-failed      # only re-run gates that failed last run
/drupal-dev-framework:review <task> --no-pr-body        # skip writing PR_BODY.md
/drupal-dev-framework:review <task> --skip-<gate> <r>   # skip a gate (reason recorded); --include-<gate> forces a dispatch gate on
/drupal-dev-framework:review <task> --allow-dirty       # skip working-tree warning
/drupal-dev-framework:review <task> --headless          # non-interactive: no prompts, fail-closed, exit code + compact verdict
```

`<gate>` whitelist: `tdd | solid | dry | security | guides | playbook-adherence | skill-review | plugin-validate` (hard-block — `--skip-` bypasses) plus `e2e | visual-regression | visual-parity` (step-6 dispatch gates — `--skip-` = off this run, `--include-` = on this run). Unknown gate names → exit 2. Reasons non-empty, must NOT start with `--` → exit 2. `--headless` is a boolean flag (no value) and composes with all flags above; see the **Headless mode** section below.

`<task-name>` must match `^[a-z0-9_-]+$`. Path traversal (`..`, `/`) and special chars rejected → exit 2. Missing arg AND no session-context task → exit 2 with usage.

## Runtime Steps

Run in order. Each "gate" step writes audit; non-bypassable unless documented `--skip-*` flag supplied (records `bypass_reason`).

1. **Phase Transition Check.** Read `task.md` Phase Status. If Phase 3 not `[x]`, soft-nudge once. If `## Phase Status` H2 absent entirely, append it with the four standard phase lines (1 Research, 2 Architecture, 3 Implementation, 4 Review). If only Phase 4 line missing, idempotently insert before next `## ` boundary (or EOF if none).

2. **Resolve task + project context.** Validate `<task-name>` charset (above). If absent, try session-context-reader; if also null, exit 2 with usage. Resolve the project folder by running `${CLAUDE_PLUGIN_ROOT}/scripts/project-state-read.sh "<project_folder>"` (Bash) and parsing its JSON.

3. **Working-tree warning.** Run `git diff --name-only`. If non-empty AND `--allow-dirty` not set: print warning ("gates run on staged + working tree state, not committed state. Continue? [y/N]"). Default `[N]`. User declines → exit 0. **Under `--headless`:** do not prompt; proceed regardless of the dirty tree; record `working_tree: "dirty"|"clean"` in the step-10 payload (equivalent to auto-`--allow-dirty`).

4. **Resolve gate plan.** Build `gates_run[]` skeleton. For conditional-gate file detection use **merge-base diff** (`git diff $(git merge-base main HEAD)..HEAD --name-only`) — committed-on-branch changes count, NOT just working tree. Detect:
   - `skill-review`: merge-base diff includes `skills/*/SKILL.md`
   - `plugin-validate`: merge-base diff includes any plugin file
   - `validate-playbook-adherence`: file `commands/validate-playbook-adherence.md` exists OR mark `verdict: "skipped-not-shipped"` with `bypass_reason: "sibling adherence_gates not yet shipped"`
   - hardened `validate-guides`: command body contains `<!-- /review:hard-block -->` marker OR fall back to soft mode (note in audit)

5. **Run hard-block gates sequentially.** For each: invoke flow inline (do NOT shell out). Capture per-gate envelope at `<task>/validations/latest/<gate>.json` per `references/validation-gate-result.md` v1.0. Add to `gates_run[]`. Order: tdd → solid → dry → security → guides → validate-playbook-adherence → skill-review (conditional) → plugin-validate (conditional).

6. **Change-impact dispatch** (v4.11.0+ — replaces v3.13.0's always-soft visual step). Execute `references/visual-review/change-impact-dispatch.md` in full — a RECOMMENDER, not an enforcer. Fast path: no `**Visual Review:**` field in `project_state.md` (or `disabled`) → run zero new gates, print `no visual-review surfaces configured; run /setup-* to opt in`, omit `dispatch_plan` from the payload entirely, skip to step 7. Otherwise: `change-impact-classify.sh <task>` classifies the merge-base diff → recommended gates; the user opts in **per task** via a `## Review Gates` block in `task.md` (written once, never re-asked); opted-in **and** dispatch-ready gates run soft; `visual_parity` auto-runs on design-implementation tasks; unshipped B/C/D gates → `skipped-not-shipped`. `--include-/--skip-<gate>` override the stored opt-in for this run only. Assemble `dispatch_plan` (`gate-audit-schema.md` §5.8) for the step-10 payload.

7. **Apply `--skip-<gate> <reason>` flags.** Validate gate name against whitelist + reason non-empty + reason not `--`-prefixed (else exit 2). For each valid flag: don't run the gate; set `gates_run[].verdict: "bypassed"` and `bypass_reason: <reason>`.

8. **Aggregate `overall_verdict`.** A per-gate parse error or missing/unreadable envelope is an **unresolved** result — record it `verdict: "skipped"` with `unresolved: true` in `gates_run[].messages[]`, **distinct** from an explicit `--skip` bypass and from `skipped-not-shipped`. Resolve in this order; **every branch yields a legal `overall_verdict` ∈ {pass, fail, bypassed}**:
   1. `fail` if any hard-block gate has `verdict: fail` — **fail dominates** (a real fail is never masked by another gate's explicit `--skip`).
   2. `fail` if any hard-block gate is **unresolved** (parse-error / missing envelope) — an unknown gate result is **fail-closed, never absorbed into `bypassed`**. (Only the **`overall_verdict`** is written `fail`; the gate's own per-gate `verdict` stays `skipped` + `unresolved: true`, with a `messages[]` note — the schema enum has no `incomplete` value.) **This rule is ranked ABOVE bypass on purpose.**
   3. `bypassed` if any hard-block gate has `bypass_reason` populated (explicit `--skip-<gate>`, or a documented auto-bypass such as an unshipped `validate-playbook-adherence`) — reached only when there is no `fail` and nothing unresolved.
   4. `pass` if **all** hard-block gates `pass`. Benign non-blocking states (`skipped-not-shipped`, a tool-unavailable soft skip) that are **not** unresolved and **not** a hard-block fail do **not** prevent `pass` and do **not** force non-zero on their own.

9. **On `overall_verdict == "fail"` (per step 8, fail dominates any coexisting `--skip` bypass): mandated-wording prompt.** Display verbatim per template `review-gate-fail` (literal text below; mirrors v1.2 template when sibling ships, byte-identical fallback otherwise). Block on `[r]/[s]/[a]` — no default. `[r]` exits 1 (user fixes, re-runs). `[s]` prompts per failed gate for free-text reason, populates `bypass_reason`, sets `overall_verdict: "bypassed"`. `[a]` exits 1 without writing `_review.json`. **Non-`r/s/a` input: re-display the prompt verbatim. Do not infer choice.** **Under `--headless`:** do NOT display this prompt — fall straight through to step 10 with `overall_verdict: "fail"`, then **print the compact verdict line (Headless mode) and exit non-zero**. **Fail-closed: never auto-`[s]`/auto-bypass.** A bypass under `--headless` requires an explicit `--skip-<gate> <reason>` on the invocation (step 7).

10. **Write `_review.json`** via `gate-audit-write.sh <task> review <payload>` (atomic temp+rename; schema_version `1.2` for v4.11.0+ — the `review` payload schema grew the optional `dispatch_plan` key). When step 6's dispatcher ran, the payload carries `dispatch_plan` (`gate-audit-schema.md` §5.8); when visual review is not set up, the key is omitted. `gate_specific.pr_ready: true` ONLY when `overall_verdict == "pass"` AND not `--dry-run`. Bypass paths → `pr_ready: false` (user picked the bypass; they pick whether the PR is ready). Dry-run → `pr_ready: false` regardless. `gates_run[]` is the full hard-block set, regardless of how populated (rerun-failed merges previous-run passes with this-run reruns).

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

## `--rerun-failed` and `--team` semantics
`--rerun-failed` reads previous `_review.json gate_specific.gates_run[]`, filters `verdict == "fail" AND bypass_reason == null`, runs only those, re-aggregates (overwrite). Preserves passed-gate envelopes; soft gates preserve prior verdicts. Refuses with "no valid prior run" if `_review.json` absent/empty/malformed/missing `gate_specific.gates_run`. **An *unresolved* gate** (per-gate `verdict: "skipped"`, `unresolved: true`) is **not** selected by `--rerun-failed` (which targets `verdict: fail`); the run stays correctly red (step 8 rule 2) — retry the unresolved gate with a full `/review`, not `--rerun-failed`.

`--team` invokes `/validate:team` directly; inner fallback (auto-falls-back to `/validate:all` when `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS != "1"` or `TeamCreate` fails) handles unavailability. `_review.json gate_specific.mode` records actual: `"team"`, `"all"`, `"team-fallback-to-all"`.

## Headless mode (`--headless`)

`--headless` makes `/review` safe to run **unattended** (an L1 orchestrator, a `/goal` loop, CI). It is **additive** — absent the flag, behaviour is byte-for-byte unchanged. It changes only the two interactive points (steps 3 and 9) and adds machine-readable output; it does **not** change gate execution, aggregation, or `pr_ready` logic, and introduces **no new bypass path**.

- **No prompts.** Step 3 (`[y/N]` dirty-tree) and step 9 (`[r]/[s]/[a]` on fail) are suppressed.
- **Step 6 (change-impact dispatch) is non-interactive** under `--headless`, and `/review` **passes the non-interactive signal into the dispatcher** (see `change-impact-dispatch.md` → *Headless mode*): never prompt for per-task visual-gate opt-in; an absent `## Review Gates` block = decline-for-this-run (skip), never a question and never written back; every step-6 visual gate is invoked in **`--ci`** mode — a diff over tolerance is recorded `fail` with **no** classification prompt and **no** baseline write (never auto-rotate a baseline under automation).
- **Other steps stay non-interactive too.** The step-1 phase-transition nudge prints and continues (never a question); a classifier `bad_base_ref`/`no_merge_base` warning (step 6.2 / step 4) forces non-zero — an unresolved diff base means conditional gates may have silently not run.
- **Session context on every exit.** Run step-13's `session-context-write.sh` before exiting on **both** the pass and the fail path, so a `/goal` loop keeps task context across iterations.
- **Fail-closed.** On gate fail, write `_review.json` (`overall_verdict: "fail"` + per-gate envelopes, `pr_ready: false`) and exit non-zero. The run **never auto-bypasses** — a bypass remains only the explicit `--skip-<gate> <reason>` the caller supplies. This is what keeps *"cannot ship below the gate floor"* true under automation.
- **Exit codes (total + fail-closed).** `0` **only** when `overall_verdict` is a clean `pass`, or `bypassed` with **zero** failing AND **zero** unresolved hard-block gates; **non-zero (`1`)** for any hard-block `fail` **or** any hard-block **unresolved** (parse-error / missing envelope) gate, or any otherwise-ambiguous verdict; `2` = arg/validation error. **Benign `skipped-not-shipped` / soft-skipped gates do NOT by themselves force non-zero** (else a fully-green run on an interim project never terminates a `/goal` loop). **Not unambiguously clean ⇒ exit non-zero** — never exit 0 on doubt. (Fail dominates bypass per step 8; unresolved is fail-closed above bypass.)
- **Compact verdict line (stdout).** After step 10, print one line per gate plus an overall line — for a transcript-only reader such as `/goal`:
  ```
  <gate> verdict=<pass|fail|bypassed|skipped>
  overall_verdict=<pass|fail|bypassed> pr_ready=<true|false> audit=<path>
  ```
  The verbatim per-gate envelopes stay on disk in `_review.json` (re-read at merge), not echoed in full — keeps the transcript lean.
- **`working_tree` audit field.** Step 10's `gate_specific` gains `working_tree: "dirty"|"clean"` (additive; `gate-audit-write.sh` passes `gate_specific` through unchanged, so no script change).
- **Composes** with `--dry-run` (CI gate-check that never marks Phase 4), `--skip-<gate>`, `--team`, `--rerun-failed`. The Phase 4 `[x]` rule (step 12) is unchanged.

## When to escalate — `claude ultrareview`
After `/review`'s gates pass, a high-stakes PR (production-adjacent, security-critical, or large) can get a deeper pass: `claude ultrareview <PR>` (or `/ultrareview`) runs a multi-agent reviewer fleet in a cloud sandbox that independently reproduces and verifies each finding. **Explicit user opt-in only** — never run it automatically from `/review`; it bills as usage credits (~$5–20/run beyond a small free-run allotment). The `code-quality-tools:ultrareview` skill wraps the same platform check; either entry point works.
**Tip — long runs.** `/review`, `/research-team`, and `/validate:team` take minutes. Enable `channelsEnabled` in user settings for a push notification on completion. `/goal` pairs with `/review` for unattended green-until-done runs (e.g. `/goal every hard-block gate in <task>/validations/latest reports pass`) — see `CONVENTIONS.md` "Condition-checked autonomy with `/goal`".

## Pointers

- Full walkthrough: `references/review-phase-walkthrough.md` (sibling `plumbing_docs_tests`)
- Step 6 dispatcher: `references/visual-review/change-impact-dispatch.md` (v4.11.0+)
- Audit shape: `references/gate-audit-schema.md` v1.2 (`gate_type: "review"`; `dispatch_plan` key)
- Per-gate envelope: `references/validation-gate-result.md` v1.0
- Project opt-out: `**Review Required:** false` keeps gates at `/complete` (legacy v4.0.2 posture)

## Related

- `/drupal-dev-framework:implement` (Phase 3) · `:complete` (archive; consumes `_review.json`) · `:validate-all` / `:validate-team` (invoked by `/review`) · `:upgrade-project` (set `**Review Required:**`) · `:audit-status` (audit visibility)
