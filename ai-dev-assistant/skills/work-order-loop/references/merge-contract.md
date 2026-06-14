# Merge Contract — the honest no-auto-merge guarantee

The detail behind the loop's terminal merge step (`wo-merge-gate.sh` K3 + `wo-pr-open.sh` K4).

## What the gate guarantees (HONEST wording — R-4)

> **The loop cannot ship below the floor *silently*** — every bypass leaves a disk record and withholds
> `pr_ready`/auto-merge. **It is NOT "non-bypassable."**

`wo-pr-open.sh` is the **one supported road to a PR**, and it mechanically includes the floor check: it
re-runs `wo-merge-gate.sh` and calls `gh pr create` **only** on a clean verdict (exit 0). `wo-merge-gate.sh`
itself **re-runs** `wo-ship-gate.sh` from disk (never a cached verdict — TOCTOU-safe) and adds the per-WO
`review_ref` + `override_used` checks ship-gate does not cover.

**Honest limits (accepted residuals, backstopped by the human merge):**
- Re-running ship-gate protects against **newly-added** blockers, **not removed** ones. A builder whose
  tool reach includes the memory repo can delete a `wo-NN.HALT` (D12a/H5). Off-road `gh pr create` outside
  the loop also remains possible (prose-layer residual). Both are backstopped by branch protection + the
  human merge, and the audit trail exposes them.
- The merge decision is **disk-based**; a builder echoing `ship_ok=true` into the transcript can cause a
  premature LOOP-STOP but **never a bad merge** (D12b).

## No-auto-merge-on-bypass (AC4)

- `blocking`/CRITICAL/HALT ⇒ ship-gate `ship_ok=false` ⇒ `merge_ok=false` ⇒ **`wo-pr-open.sh` refuses to
  open**. No PR.
- A recorded **grounding override** (`override_used` in a `wo-NN.run.json`, or a non-null WO
  `coverage_override`) ⇒ `merge_ok` may be true but **`auto_merge_allowed=false`** ⇒ the PR is opened
  **flagged** (body appends `⚠ grounding override recorded — DO NOT auto-merge`; `needs-grounding-review`
  label best-effort). The human merges with eyes open.
- **No merge call is ever built.** `wo-pr-open.sh` contains `gh pr create` and **never** `gh pr merge` —
  the absence of a merge call is the primary control; branch protection is defense-in-depth.
- Fail-closed: a **deleted or malformed** `wo-NN.run.json` for a dispatched WO (status ∈
  {in_progress,done,needs_rework}) ⇒ `missing_run_state` ⇒ `merge_ok=false`. A missing `PR_BODY.md` ⇒
  `wo-pr-open.sh` refuses (`pr_body_absent`).

## VR and oracle-integrity (terminal escalation — never silent)

Under automation the loop **runs** VR (compares current output to the baseline) but **NEVER regenerates
the baseline** — consistent with `/review --headless` passing `--ci` to VR tooling (no baseline-write
path in CI mode). This is load-bearing: an auto-rebaseline would silently pass a visual regression,
defeating the gate.

- A **VR diff** (baseline exists, current output diverges) is **terminal escalation** — the human
  decides whether the change is a regression to fix or an intended change requiring a deliberate
  I-rebaseline. The loop never resolves this silently.
- An **`oracle_tamper` HALT** (a WO diff touched an un-exempted oracle artifact — VR baseline / test
  deletion / `phpstan-baseline.*`) joins the set of terminal-HALT reasons the loop already escalates
  on (alongside `verified_false`, `unpinned_ref`, etc.). Neither is auto-merged; both require human
  decision before the PR can proceed.
- The `oracle_update` WO field is the **sole exemption path**: when present and the tamper signal's
  `oracle_class ∈ oracle_update.classes`, the signal is downgraded HALT→flag (PR opens flagged, not
  blocked). Absent or mismatched ⇒ `oracle_tamper` HALT (terminal).

## PR-open posture + token (D6, R-2, H2)

- v1 PR body source = `<task>/PR_BODY.md`, written by the task-level `/review --headless` on green
  (`overall_verdict==pass`, not `--dry-run`, not `--no-pr-body`).
- Token precedence: `GH_TOKEN="${WO_MERGE_GH_TOKEN:-$GH_TOKEN}" gh pr create …`. Supply a **fine-grained
  single-repo PAT** via `WO_MERGE_GH_TOKEN` for unattended runs.
- **Honest scope (H2):** the PAT seam **reduces the blast radius to one repo** (vs the ambient
  `repo`-scope token readable across *all* the user's repos). It does **NOT** prevent exfiltration — a
  builder Task subagent inherits the session env, so any token reachable by `wo-pr-open.sh` is reachable
  by the builder. **Exfiltration prevention requires unsetting the token on the *builder process* —
  process-level builder env isolation (scrubbed HOME / unset `GH_TOKEN` on the spawn) is ④'s scope.** The
  fine-grained PAT is the **precondition for a genuinely unattended run**, not a v2 nicety.
- Side-effect residual class (a hostile builder's no-diff local action — reading credentials, writing
  persistence outside both repos) is **structurally invisible to the human merge** (no diff). Named here
  and in the `injection-boundary.md` erratum; full mitigation = ④.
