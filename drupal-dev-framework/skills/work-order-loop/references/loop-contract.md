# Loop Contract — ready-queue, transitions, recovery, compact lines, /goal

The detail behind `work-order-loop/SKILL.md`. Disk is truth; the builder transcript is untrusted data.

## Ready-queue (D1)

`wo-compile.sh build-graph` deliberately emits **no** topo order — readiness depends on **live** status,
which only the loop knows. A work-order is **ready** ⟺ every id in its `blocked_by` is `status: done`.
Iterate: pick any ready WO, run it to a terminal per-WO state, recompute. The DAG acyclicity invariant
(held over `blocked_by`) guarantees the queue terminates. No persisted order; recompute each pass.

## Legal-transition table (D4 — enforced by `wo-compile.sh set-status`)

| from | to | when |
|---|---|---|
| `blocked` | `ready` | all `blocked_by` are `done` (the kernel re-checks; fail-closed `deps_not_done`/`deps_unresolvable`) |
| `ready` | `in_progress` | dispatch |
| `in_progress` | `done` | clean verdict (per-WO `_review.json overall_verdict==pass` ∧ `_critique.json blocking==false` ∧ no `wo-NN.HALT`) |
| `in_progress` | `needs_rework` | failing verdict |
| `needs_rework` | `ready` | requeue (③-only; ONLY while `attempts < cap`) |

`done` is terminal. Same-status is a legal no-op (idempotent recovery). `needs_rework` is terminal **only**
when `halted` (cap exhausted ⇒ `wo-NN.HALT`). The kernel rejects any other transition fail-closed.

## Bounded verify→fix (D3 — crash-safe)

`wo-run-state.sh dispatch` does **read-increment-write** on `attempts` and checks the cap **before**
dispatch (`attempts ≥ cap ⇒ HALT, no write, no dispatch`). The counter lives in the `wo-NN.run.json`
sidecar, never resets, and a crash-redispatch goes through the same increment — so the bound survives
arbitrarily many crash-restarts. Default cap **3**.

**Retry is BLIND at L1 (red-team H1).** A requeued WO re-dispatches the **same** body. Feedback injection
is rejected: editing `wo-NN.md` is outside ③'s lane (it is ①'s `compiled_from`/`excerpt_sha`-pinned
artifact) and passing notes via the spawn prompt breaks self-containment (`work-order-contract.md`
§Body). A deterministic failure correctly exhausts the cap → HALT → human; a transient one may clear on
a fresh-context retry. A `wo-NN.feedback.md` sidecar + an ①-coordinated builder read is **reserved, not
built** (ratify with ① if the de-risk AC shows blind retry is materially wasteful).

## Recovery disposition (D8 — SIDECAR-FIRST; recompute from disk)

Authority precedence: WO `status` → `wo-NN.run.json` → `wo-NN._review.json`/`_critique.json`/`*.HALT` →
`git` (objective facts only). **`git log --grep "wo-NN:"` is forbidden as authority** (builder-forgeable).

| on-disk state | disposition |
|---|---|
| `done` | settled — skip |
| `blocked`, some dep not `done` | leave; the queue promotes later |
| `ready`/`blocked`, deps done, no sidecar | dispatch fresh |
| `ready`, sidecar present, no `checkpoint_after` | crashed before/during build — re-dispatch (the increment counts; cap may HALT) |
| `in_progress`, sidecar, no `checkpoint_after` | crashed mid-build — reset to `checkpoint_before`, `needs_rework`, requeue-or-HALT |
| `in_progress`, `checkpoint_after`, no `wo-NN._review.json` | build done, review never ran — resume at the review step (no rebuild) |
| `in_progress`, `_review.json` + `_critique.json` present | re-derive the verdict from the **per-WO** `_review.json` + `_critique.json` (rule 2b) — apply done/needs_rework |
| sidecar `halted:true` OR `wo-NN.HALT` | terminal at L1 — surface in the escalation summary; never auto-requeue |
| all `done`, no `_review.json`/PR | resume at the terminal merge step (idempotent: an existing PR ⇒ report, never a second) |

**Worktree (carry #4).** The loop owns create/teardown. `git reset` always targets the **handed
worktree** (`git -C <worktree>`), never the user's main tree, to the **sidecar** `checkpoint_before`
(③-captured pre-spawn), and only after `merge-base --is-ancestor` validates it.

## Compact-line forwarding (G3 — format-stable, mechanical)

Each kernel prints its line to **stderr**; the loop captures it mechanically and echoes it to the
transcript verbatim (never re-typed). The Haiku /goal evaluator reads only the transcript. Exact shipped
formats (trust the kernels, not drifted docs):

- ship-gate (`wo-ship-gate.sh`): `ship_gate ship_ok=<b> review=<v> halts=<n> blocking=<n> uncritiqued=<n>`
- merge-gate (`wo-merge-gate.sh`): `merge_gate merge_ok=<b> auto_merge=<b> ship_ok=<b> review=<v> per_wo_fail=<n> overrides=<n>`
- critique (`work-order-critique/SKILL.md`): `wo-NN critique=<overall> tier=<t> mode=<m> blocking=<b> critique_ref=<path>`
- `/review --headless` (stdout already): per-gate `<gate> verdict=<…>` + `overall_verdict=<…> pr_ready=<…> audit=<path>`

> **Known ② doc drift (G7), fix in the erratum batch:** `review-orchestration.md:36` shows
> `blocking_critiques=<n>` and omits `uncritiqued=` — stale vs the kernel above. Trust the kernel.

## /goal (D7, G6 — ③ composes, the USER pastes; ③ never runs it)

Anchor the completion clause on a gate verdict surfaced **inline** (the only thing the Haiku evaluator
sees), add the Non-goals `git status` guard, and bound the run. **Turn bound = `min(20 × N_WOs, 80)`**
(③'s formula — NOT in the shipped `goal-from-scope.md`; keep the printed example consistent with it).
Template:

```
/goal /drupal-dev-framework:review <task> reports overall_verdict "pass" in _review.json (all hard-block
gates green) printed inline AND the work-order loop printed LOOP_COMPLETE AND nothing outside the
Non-goals was modified (git status clean outside the named areas) — or stop after <min(20×N_WOs,80)> turns
```

Degrade (no /goal available): run the loop attended/sequential with the same compact lines. Anchoring on
`LOOP_COMPLETE` only **reduces** accidental misfire from a builder echoing a verdict into the transcript —
it is not an adversarial close (D12b): a forged line can cause a premature stop, never a bad merge (the
merge decision is disk-based `wo-merge-gate.sh` + no merge call + human merge).
