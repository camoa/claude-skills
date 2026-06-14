# /review Phase Walkthrough

> Companion to `commands/review.md`. Loaded only on explicit user read (token-efficiency split per v4.0.2 pattern).

**Introduced:** ai-dev-assistant v4.1.0
**Driver:** [feedback memo `feedback_framework_phase_gates.md`](https://github.com/camoa/claude-skills/issues) (2026-04-24, 2026-04-25) — gates exist but Claude treats them as a menu rather than mandatory. The 5-mechanism v4.0.0 hardening pattern works where applied; `/review` extends it to pre-PR validation.

## Overview

`/review` is **Phase 4** in the framework lifecycle (Research → Architecture → Implementation → **Review** → /complete archive). It runs all hard-blocking validation gates between `/implement` and PR creation, with the v4.0.0 5-mechanism pattern: anti-bypass clause, mandated wording, audit JSON, show-not-summarize, always-evaluated.

Before `/review` shipped (v4.0.2 and earlier), validation lived in `/complete`'s Step 3-5. Two problems:
1. **Late firing** — `/complete` runs after PR merge in our actual workflow; the reviewer never saw gate-checked code
2. **Soft posture** — 5/7 gates were soft-nudge (bypassable by default) and the 2 hardened gates only fired conditionally

`/review` solves both: explicit phase between `/implement` and PR; hard-blocks on `fail` with mandated-wording prompt requiring `--skip-<gate> <reason>` to bypass (audit-recorded).

## Per-step deep-dive

### Step 1 — Phase Transition Check + idempotent Phase 4 line insert

Reads `task.md` Phase Status. If Phase 3 not `[x]`, prints one-line soft-nudge ("Phase 3 not complete — running `/review` early"). Never blocks.

If `## Phase Status` H2 absent entirely, appends the 4-line block. If only `Phase 4: Review` line missing, idempotent insert before next `## ` boundary (or EOF). The Phase 4 line in fresh-scaffold tasks has been present since v4.1.0 (PR #138 added to `scripts/fm-helpers.sh write_stub_task_md` + `references/research-walkthrough.md` template prose). Pre-v4.1.0 tasks may lack it; `/review` retrofits on first invocation.

### Step 2 — Resolve task + project context

Same pattern as `/validate:*`: prefer `session_context.json` (`projectPath` + `task`); fall back to walking up from `$PWD` until finding `implementation_process/`. If both fail, exit 2 with usage. The session-context-reader is the same primitive used by `/scope`, `/research`, `/complete`.

### Step 3 — Working-tree warning

Runs `git diff --name-only`. If non-empty AND `--allow-dirty` not set, prompts `[y/N]` (default `[N]`) — gates run on staged + working tree state, not committed state. Surfacing the gap is honest; refusing entirely is annoying for devs who want to see if WIP passes before committing.

### Step 4 — Resolve gate plan

Builds `gates_run[]` skeleton. Determines conditional gates via **merge-base diff** (`git diff $(git merge-base main HEAD)..HEAD --name-only`):
- `skill-review` — fires if any `skills/*/SKILL.md` changed
- `plugin-validate` — fires if any plugin file changed
- `validate-playbook-adherence` — fires if file exists OR marks `verdict: "skipped-not-shipped"` (graceful fallback for pre-PR-#139 state)
- hardened `validate-guides` — detects `<!-- /review:hard-block -->` capability marker; if absent, falls back to soft mode

The merge-base diff is a v4.1.0 fix (paper-test caught: working-tree-only diff misses already-committed changes on the branch).

### Step 5 — Run hard-block gates sequentially

For each gate: invoke its flow inline (DO NOT shell out — same pattern `/scope` uses from `/research`). Capture per-gate envelope at `<task>/validations/latest/<gate>.json` per `references/validation-gate-result.md` v1.0. Order: tdd → solid → dry → security → guides → validate-playbook-adherence → skill-review (conditional) → plugin-validate (conditional).

### Step 6 — Run soft gates

`visual-regression` and `visual-parity` per `commands/validate-all.md` semantics — interactive classification, never auto-block. These remain soft even under `/review` (per architecture decision: diff classification has no sensible non-interactive default).

### Step 7 — Apply `--skip-<gate> <reason>` flags

Validates gate name against whitelist (`tdd|solid|dry|security|guides|playbook-adherence|skill-review|plugin-validate`); reason must be non-empty AND not start with `--`. For each valid flag: don't run the gate; set `gates_run[].verdict: "bypassed"` + `bypass_reason: <reason>`.

### Step 8 — Aggregate `overall_verdict`

Per-gate parse errors don't crash aggregation — surface in `gates_run[].messages[]` and continue. Logic:
- `bypassed` if any hard-block gate has `bypass_reason` populated
- `fail` if any hard-block gate has `verdict: fail` AND no bypass
- `pass` only if all hard-block gates `pass` (warnings/skipped/skipped-not-shipped don't block but don't yield clean `pass` for PR-ready purposes — see Step 10)

### Step 9 — Mandated-wording prompt on `fail`

Display `review-gate-fail` template verbatim (literal text inline in command body — byte-identical to v1.2 template). Block on `[r]/[s]/[a]`:
- `[r]emediate` — exit 1; user fixes + re-runs
- `[s]kip` — prompts per failed gate for free-text reason; populates `bypass_reason`; sets `overall_verdict: "bypassed"`
- `[a]bort` — exit 1 without writing audit (gate didn't complete)

**Non-`r/s/a` input: re-display verbatim. Do not infer choice.** This is the rationalization-resistance contract — Claude trained on English is constrained from paraphrasing English literal templates.

### Step 10 — Write `_review.json`

Via `gate-audit-write.sh <task> review <payload>` (atomic temp+rename; schema_version `1.1`). `gate_specific.pr_ready: true` ONLY when `overall_verdict == "pass"` AND not `--dry-run`. Bypass paths get `pr_ready: false` (the user picked the bypass; they pick whether the PR is ready). Dry-run forces `pr_ready: false` regardless.

### Step 11 — Write `PR_BODY.md`

Skip if `--no-pr-body` OR `--dry-run` OR `pr_ready != true`. Template fills from `_review.json` + `task.md`: H1 task title, Summary (Goal first paragraph), AC count `[x]`/total, gate verdicts table, audit links footer. User invokes `gh pr create --body-file <task>/PR_BODY.md`.

### Step 12 — Mark Phase 4 `[x]`

Only if not `--dry-run` AND `overall_verdict in ("pass", "bypassed")`.

### Step 13 — Display `review-summary` mandated wording

Verbatim. Includes verdict table + audit + PR_BODY paths. Then invokes `session-context-writer` with `lastPhase: "review"`.

## Examples

### Default invocation (all gates pass)

```
$ /ai-dev-assistant:review my_task
[Step 1] Phase 3 ✓; Phase 4 line present
[Step 3] Working tree clean
[Step 4] Gate plan: 8 hard-block (5 standard + playbook-adherence + plugin-validate) + 0 conditional
[Step 5] Running gates sequentially...
  tdd: pass | solid: pass | dry: pass | security: pass | guides: pass
  playbook-adherence: pass (4/4 plays cited)
  plugin-validate: pass
[Step 8] overall_verdict: pass
[Step 10] _review.json written; pr_ready: true
[Step 11] PR_BODY.md written
[Step 12] Phase 4 [x]
[Step 13] /review my_task complete. Mode: all  Verdict: pass  PR ready: true
```

### `--team` mode

```
$ /ai-dev-assistant:review my_task --team
[Step 5] Running gates via /validate:team (4 isolated agent teammates)...
  Fallback chain: CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 → /validate:team active
  Mode recorded as: "team" in _review.json gate_specific.mode
```

If `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS != "1"` OR `TeamCreate` fails, `/validate:team` auto-falls back to `/validate:all`; `_review.json` records `mode: "team-fallback-to-all"`.

### `--rerun-failed`

```
$ /ai-dev-assistant:review my_task --rerun-failed
Reading <task>/_review.json from previous run...
Re-running only: dry, security (verdict: fail in prior run)
  dry: pass | security: pass
Re-aggregating: overall_verdict: pass (was: fail)
Updating _review.json (overwrite)
```

### `--dry-run`

```
$ /ai-dev-assistant:review my_task --dry-run
[All gates run; envelope written]
[Step 10] _review.json gate_specific.dry_run: true; pr_ready: false (forced)
[Step 11] PR_BODY.md skipped
[Step 12] Phase 4 NOT marked [x] (dry-run)
[Step 13] Summary: would have been pass; pr_ready forced false; Phase 4 not marked
```

Exit code: always `0` under `--dry-run` (POSIX-compatible).

### `--skip-<gate>`

```
$ /ai-dev-assistant:review my_task --skip-tdd "no test framework yet"
[Step 7] Skip flag validated: tdd ∈ whitelist; reason non-empty; not --prefix
[Step 5-6] All gates run except tdd
[Step 8] tdd marked verdict: bypassed, bypass_reason: "no test framework yet"
[Step 8] overall_verdict: bypassed (other gates pass)
[Step 10] _review.json written; pr_ready: false (bypassed; user must explicitly decide)
[Step 12] Phase 4 [x] (bypassed counts as resolved)
```

## Edge cases

- **Phase 3 not `[x]`** — soft-nudge, never blocks. User can review pre-implementation if they want.
- **No `_review.json` from prior run + `--rerun-failed`** — refuses with explicit message; suggests running without flag.
- **Concurrent `/review` invocations on same task** — last-writer-wins on `_review.json`; M4 from paper-test report deferred to v2 (concurrency lock).
- **Conditional gate detection on already-merged branch** — merge-base diff handles this; if base branch has moved, the diff still captures branch-local changes correctly.
- **Hard-block marker absent on a gate that should be hardened** — graceful soft-mode fallback; audit notes `kind: "soft"` for that entry.

## `--rerun-failed` and `--team` semantics (detail)

`--rerun-failed` reads the previous `_review.json gate_specific.gates_run[]`, filters `verdict == "fail" AND bypass_reason == null`, runs only those, then re-aggregates (overwrite). Passed-gate envelopes are preserved; soft gates keep their prior verdicts. It refuses with "no valid prior run" if `_review.json` is absent/empty/malformed/missing `gate_specific.gates_run`. An **unresolved** gate (per-gate `verdict: "skipped"`, `unresolved: true`) is **not** selected by `--rerun-failed` (which targets `verdict: fail`); the run stays correctly red (step 8 rule 2) — retry an unresolved gate with a full `/review`, not `--rerun-failed`.

`--team` invokes `/validate:team` directly; the inner fallback (auto-falls back to `/validate:all` when `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS != "1"` or `TeamCreate` fails) handles unavailability. `_review.json gate_specific.mode` records the actual mode: `"team"`, `"all"`, or `"team-fallback-to-all"`.

## Headless mode (`--headless`) — full contract

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

> Both mandated-wording literals (`review-gate-fail`, `review-summary`) stay **inline** in `commands/review.md` and byte-identical to `references/gate-hardening-prompts.md` — pinned there by `tests/gate-prompts-vs-inline.sh`, so they are not relocated here.

## Version history

- **v4.1.0** — initial introduction. 13 runtime steps; v4.0.0 5-mechanism pattern; mandated-wording templates inline in command body (byte-identical to `gate-hardening-prompts.md` v1.2 templates per Decision Log #3 in `plumbing_docs_tests/research.md`).
- **v5.3.1** — `commands/review.md` body trimmed back under the ≤120-line budget (the de-Drupalization recipe-resolution prose had pushed it to 157 lines). The full `--headless` contract, the `--rerun-failed`/`--team` semantics, and the `claude ultrareview` escalation note were relocated here; the command keeps every runtime step, the anti-bypass clause, all flags, and **both** mandated-wording literals (`review-gate-fail`, `review-summary`) inline (the literals are pinned inline by `tests/gate-prompts-vs-inline.sh`). It now carries a compact `--headless` section — retaining the `Exit codes`, compact-verdict-line, `--ci`, and "never exit 0 on doubt" clauses that `tests/headless-review-contract-spec.sh` asserts — plus pointers to the relocated detail. Step 5.0/5a recipe-resolution prose was condensed (full protocol stays in `references/recipe-resolution.md`).

## Related

- `commands/review.md` — runtime body (≤120 lines token-efficient)
- `commands/complete.md` — slimmed in v4.1.0; honors `**Review Required:**` field for legacy posture
- `references/gate-hardening-prompts.md` v1.2 — `review-gate-fail` + `review-summary` templates
- `references/gate-audit-schema.md` v1.1 — `_review.json` shape (`gate_type: "review"`)
- `references/validation-gate-result.md` v1.0 — per-gate envelope shape
- `references/feedback_framework_phase_gates.md` (memo) — driver
