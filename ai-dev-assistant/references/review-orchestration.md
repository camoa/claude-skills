# Per-Work-Order Review Orchestration (Mechanism A) — the contract the loop follows

Mechanism A of `gate_integration` (sibling ②). **No skill (AR-A):** the `/review --headless` *run* is
the orchestrator main context's job (③'s loop / a `/goal` loop / a human) — `/review` is
model-executed command-prose, not a callable. ② ships the **deterministic disk side**: two kernels
(`wo-review-snapshot.sh`, `wo-ship-gate.sh`) + this contract. The "zero model context" claim holds for
the **kernels**, not the `/review` run.

## What the loop does, per work-order (in ready-queue order, after the build atom returns its handle)

1. **Cost-gate (read `risk_tier`).** A **trivial/docs** WO (`wo-risk-classify.sh` → `low`, no security
   signal) MAY skip the per-WO checkpoint review to save the whole-tree gate cost; a `medium`/`high` WO
   gets one. The authoritative PR-gate review (step 4) always runs once regardless.
2. **Per-WO checkpoint review.** The loop runs **`/review --headless --dry-run <task>`** (`--dry-run` so
   it never marks Phase 4 / writes `PR_BODY` / sets `pr_ready` — X8). This is a **cumulative tree-state
   checkpoint** ("the tree as of WO-NN's commit"), **honestly NOT a WO-isolated review** — the universal
   gates are whole-tree (X1). It exists for ③'s **fail-fast** (stop building on a red tree).
3. **Snapshot to `review_ref`.** Run **`wo-review-snapshot.sh <task> wo-NN`** → copies the produced
   `<task>/_review.json` to `<task>/work-orders/wo-NN._review.json` (the `review_ref`), snapshots the
   per-gate envelopes to `<task>/validations/wo-NN/`, and rewrites the copied `envelope_path` pointers so
   the next per-WO run cannot clobber them (X11). **Fail-closed:** a missing `_review.json` exits
   non-zero and writes no `review_ref`. WO-level *attribution* is the **critique's** job (it scopes to
   the WO diff), not the whole-tree gates.
4. **PR-gate review (authoritative).** After all WOs build, the loop runs **`/review --headless <task>`**
   (no `--dry-run`) over the full branch — the shipped, whole-tree, authoritative verdict that catches
   cross-WO integration. This writes the task-level `<task>/_review.json`.
5. **Ship verdict (②-owned, fail-closed).** Run **`wo-ship-gate.sh <task>`** →
   `ship_ok = (task `_review.json` `overall_verdict==pass`) AND (no `wo-NN.HALT`) AND (every
   `wo-NN._critique.json` `blocking==false`)`. Non-zero exit + a non-green compact line when not
   shippable. **This is the in-lane tooth** ③ (or a human / `/goal`) consults — **② never edits
   `_review.json`** (AR-B).

## Compact lines (progress only; truth is on disk, re-read at merge)
```
wo-NN review=<overall_verdict> review_ref=<path>          # after step 3
ship_gate ship_ok=<bool> review=<verdict> halts=<n> blocking=<n> uncritiqued=<n>   # after step 5 (stderr); erratum G7: matches wo-ship-gate.sh:81 exactly (was blocking_critiques=, missing uncritiqued=)
```

## Boundaries
- ② owns: the cost-gate rule, `wo-review-snapshot.sh`, `wo-ship-gate.sh`, and this contract.
- ③ owns: running `/review` (main context), the loop, the PR-open, and the **merge decision** (it reads
  `ship_ok` + the per-WO `review_ref` + `_critique.json` + handle `override_used` from disk). **No
  interim automated merge-enforcement exists until ③ ships** — before then `ship_ok` is advisory.
- **No `/review` change** (AR-A): `--base` does not scope the whole-tree gates; dropped. The only
  `/review` flags used are the shipped `--headless` + `--dry-run`.
