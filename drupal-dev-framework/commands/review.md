---
description: "Phase 4 of a task. Run all hard-blocking validation gates before PR creation. Trigger: 'review task', 'pre-PR review', 'gate check'. Aggregates per-gate verdicts into _review.json audit; writes PR_BODY.md on green. Slimmed /complete depends on this — projects with **Review Required:** true require /review before /complete archives. Introduced v4.1.0."
allowed-tools: Read, Write, Edit, Bash, Glob, Skill, Task
argument-hint: <task-name>
---

# Review

Phase 4 of a task — run all hard-blocking validation gates before PR creation. Behavior current as of v4.1.0; full prose / examples / version history in `references/review-phase-walkthrough.md`.

## Usage

```
/drupal-dev-framework:review <task-name>                # default mode (/validate:all)
/drupal-dev-framework:review <task> --team              # use /validate:team (with fallback)
/drupal-dev-framework:review <task> --dry-run           # run, write audit, don't mark Phase 4 [x]
/drupal-dev-framework:review <task> --rerun-failed      # only re-run gates that failed last run
/drupal-dev-framework:review <task> --no-pr-body        # skip writing PR_BODY.md
/drupal-dev-framework:review <task> --skip-<gate> <r>   # bypass a gate; reason recorded in audit
/drupal-dev-framework:review <task> --allow-dirty       # skip working-tree warning
```

`<gate>` whitelist: `tdd | solid | dry | security | guides | playbook-adherence | skill-review | plugin-validate`. Unknown gate names → exit 2. Reasons must be non-empty and must NOT start with `--` (would eat the next flag) → exit 2.

`<task-name>` must match `^[a-z0-9_-]+$`. Path traversal (`..`, `/`) and special chars rejected → exit 2. Missing arg AND no session-context task → exit 2 with usage.

## Runtime Steps

Run in order. Each "gate" step writes audit; non-bypassable unless documented `--skip-*` flag supplied (records `bypass_reason`).

1. **Phase Transition Check.** Read `task.md` Phase Status. If Phase 3 not `[x]`, soft-nudge once. If `## Phase Status` H2 absent entirely, append it with the four standard phase lines (1 Research, 2 Architecture, 3 Implementation, 4 Review). If only Phase 4 line missing, idempotently insert before next `## ` boundary (or EOF if none).

2. **Resolve task + project context.** Validate `<task-name>` charset (above). If absent, try session-context-reader; if also null, exit 2 with usage. Resolve project folder via project-state-reader.

3. **Working-tree warning.** Run `git diff --name-only`. If non-empty AND `--allow-dirty` not set: print warning ("gates run on staged + working tree state, not committed state. Continue? [y/N]"). Default `[N]`. User declines → exit 0.

4. **Resolve gate plan.** Build `gates_run[]` skeleton. For conditional-gate file detection use **merge-base diff** (`git diff $(git merge-base main HEAD)..HEAD --name-only`) — committed-on-branch changes count, NOT just working tree. Detect:
   - `skill-review`: merge-base diff includes `skills/*/SKILL.md`
   - `plugin-validate`: merge-base diff includes any plugin file
   - `validate-playbook-adherence`: file `commands/validate-playbook-adherence.md` exists OR mark `verdict: "skipped-not-shipped"` with `bypass_reason: "sibling adherence_gates not yet shipped"`
   - hardened `validate-guides`: command body contains `<!-- /review:hard-block -->` marker OR fall back to soft mode (note in audit)

5. **Run hard-block gates sequentially.** For each: invoke flow inline (do NOT shell out). Capture per-gate envelope at `<task>/validations/latest/<gate>.json` per `references/validation-gate-result.md` v1.0. Add to `gates_run[]`. Order: tdd → solid → dry → security → guides → validate-playbook-adherence → skill-review (conditional) → plugin-validate (conditional).

6. **Run soft gates** (visual-regression, visual-parity per `commands/validate-all.md` semantics — interactive classification, never auto-block).

7. **Apply `--skip-<gate> <reason>` flags.** Validate gate name against whitelist + reason non-empty + reason not `--`-prefixed (else exit 2). For each valid flag: don't run the gate; set `gates_run[].verdict: "bypassed"` and `bypass_reason: <reason>`.

8. **Aggregate `overall_verdict`.** Per-gate parse errors don't crash aggregation — surface in `gates_run[].messages[]` and continue with `verdict: "skipped"` for that gate. Logic:
   - `bypassed` if any hard-block gate has `bypass_reason` populated AND no `fail`
   - `fail` if any hard-block gate has `verdict: fail` AND no bypass
   - `pass` only if all hard-block gates `pass` (warnings/skipped/skipped-not-shipped don't promote to fail; they don't block but also don't yield clean `pass` for PR-ready purposes — see Step 10)

9. **On `fail` (no bypass): mandated-wording prompt.** Display verbatim per template `review-gate-fail` (literal text below; mirrors v1.2 template when sibling ships, byte-identical fallback otherwise). Block on `[r]/[s]/[a]` — no default. `[r]` exits 1 (user fixes, re-runs). `[s]` prompts per failed gate for free-text reason, populates `bypass_reason`, sets `overall_verdict: "bypassed"`. `[a]` exits 1 without writing `_review.json`. **Non-`r/s/a` input: re-display the prompt verbatim. Do not infer choice.**

10. **Write `_review.json`** via `gate-audit-write.sh <task> review <payload>` (atomic temp+rename; schema_version `1.1`). `gate_specific.pr_ready: true` ONLY when `overall_verdict == "pass"` AND not `--dry-run`. Bypass paths → `pr_ready: false` (user picked the bypass; they pick whether the PR is ready). Dry-run → `pr_ready: false` regardless. `gates_run[]` is the full hard-block set, regardless of how populated (rerun-failed merges previous-run passes with this-run reruns).

11. **Write `PR_BODY.md`.** Skip if `--no-pr-body` OR `--dry-run` OR `pr_ready != true`. Template: H1 task title, Summary (Goal first paragraph), AC count `[x]`/total, gate verdicts table, audit links footer.

12. **Mark Phase 4 `[x]`** in `task.md` (only if not `--dry-run` AND `overall_verdict in ("pass", "bypassed")`).

13. **Display `review-summary` mandated wording** (literal text below). Then invoke `session-context-writer` with `lastPhase: "review"`.

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

`--rerun-failed` reads previous `_review.json gate_specific.gates_run[]`, filters `verdict == "fail" AND bypass_reason == null`, runs only those, re-aggregates (overwrite). Preserves passed-gate envelopes; soft gates preserve prior verdicts. Refuses with "no valid prior run" if `_review.json` absent/empty/malformed/missing `gate_specific.gates_run`.

`--team` invokes `/validate:team` directly; inner fallback (auto-falls-back to `/validate:all` when `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS != "1"` or `TeamCreate` fails) handles unavailability. `_review.json gate_specific.mode` records actual: `"team"`, `"all"`, `"team-fallback-to-all"`.

## Pointers

- Full walkthrough: `references/review-phase-walkthrough.md` (sibling `plumbing_docs_tests`)
- Audit shape: `references/gate-audit-schema.md` v1.1 (`gate_type: "review"`)
- Per-gate envelope: `references/validation-gate-result.md` v1.0
- Project opt-out: `**Review Required:** false` keeps gates at `/complete` (legacy v4.0.2 posture)

## Related

- `/drupal-dev-framework:implement` (Phase 3) · `:complete` (archive; consumes `_review.json`) · `:validate-all` / `:validate-team` (invoked by `/review`) · `:upgrade-project` (set `**Review Required:**`) · `:audit-status` (audit visibility)
