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
| `ready` | `in_progress` | dispatch — written by the **build atom** (`work-order-builder` step 2), after its re-gate and before it commits; the loop never writes `in_progress` |
| `in_progress` | `done` | clean verdict (per-WO `_review.json` `.gate_specific.overall_verdict==pass` ∧ `_critique.json blocking==false` ∧ no `wo-NN.HALT`) |
| `in_progress` | `needs_rework` | retryable review fail (no blocking critique, no `wo-NN.HALT`) |
| `needs_rework` | `ready` | requeue (③-only; **UNCONDITIONAL** — the cap is enforced solely at `dispatch`, never by withholding the requeue) |

`done` is terminal. Same-status is a legal no-op (idempotent recovery). **TERMINAL is keyed off the
`wo-NN.HALT` marker / sidecar `halted:true`, on ANY status** — at the cap the WO is left `ready` WITH a
HALT (`ready→needs_rework` is ILLEGAL, so it is never set), and a blocking-critique WO is left
`in_progress` WITH a HALT; both are terminal-by-marker and only escalate. The kernel rejects any other
transition fail-closed.

**`build_mode == in-place` (operator-gated infra/state runs):** the `in_progress → needs_rework` retryable
transition does **not** fire and **no `git reset --hard` occurs**. A reset rolls back tracked files but not
DB/module-enable/`vendor/` state, so it would leave a split-brain; instead a review fail (and a mid-build
crash) is made **TERMINAL** — write `wo-NN.HALT` (`in_place_review_fail` / `in_place_crash_manual_recovery`)
and escalate for human reconciliation of the accumulated canonical state. No requeue, no blind re-dispatch.
The `done`/`blocked→ready`/`ready→in_progress` transitions are unchanged.

## Bounded verify→fix (D3 — crash-safe)

`wo-run-state.sh dispatch` does **read-increment-write** on `attempts` and checks the cap **before**
dispatch (`attempts ≥ cap ⇒ HALT, no write, no dispatch`). The counter lives in the `wo-NN.run.json`
sidecar, never resets, and a crash-redispatch goes through the same increment — so the bound survives
arbitrarily many crash-restarts. Default cap **3** ⇒ exactly **3** builds, HALT (`retry_cap_exhausted`)
on the 4th `dispatch`.

`dispatch` is the **sole cap chokepoint.** The `needs_rework→ready` requeue is **unconditional** (③ never
withholds it) — so a failing WO always re-enters the queue and reaches `dispatch`, which is what makes the
cap fire and a `wo-NN.HALT` get written (severing the requeue at `attempts<cap` was the C2 fail-open:
the WO stalled in `needs_rework`, `dispatch` was never called the capping time, no HALT was written, and
the run mis-exited as complete). `dispatch` can also HALT `run_state_corrupt` (a present-but-unreadable
sidecar) or `invalid_cap` — both escalate (write `wo-NN.HALT` with the kernel `.reason`, mark the sidecar
`halted`), never mislabelled as a cap exhaustion.

**Retry is BLIND at L1 (red-team H1).** A requeued WO re-dispatches the **same** body. Feedback injection
is rejected: editing `wo-NN.md` is outside ③'s lane (it is ①'s `compiled_from`/`excerpt_sha`-pinned
artifact) and passing notes via the spawn prompt breaks self-containment (`work-order-contract.md`
Body section). A deterministic failure correctly exhausts the cap → HALT → human; a transient one may clear on
a fresh-context retry. A `wo-NN.feedback.md` sidecar + an ①-coordinated builder read is **reserved, not
built** (ratify with ① if the de-risk AC shows blind retry is materially wasteful).

## Recovery disposition (D8 — SIDECAR-FIRST; recompute from disk)

Authority precedence: WO `status` → `wo-NN.run.json` → `wo-NN._review.json`/`_critique.json`/`*.HALT` →
`git` (objective facts only). **`git log --grep "wo-NN:"` is forbidden as authority** (builder-forgeable).

**Bind `$cp` first.** On every resume row that can reach the retryable-fail reset (`in_progress` rows
below), bind `cp := <sidecar checkpoint_before>` from `wo-NN.run.json` BEFORE the disposition runs — the
loop binds `$cp` only at dispatch (step 5), which resume skips, so an unbound `$cp` would `reset --hard`
a missing ref.

| on-disk state | disposition |
|---|---|
| sidecar `halted:true` OR `wo-NN.HALT` | **TERMINAL at L1 — checked FIRST, before status** — surface in the escalation summary; never auto-requeue |
| `done` | settled — skip |
| `blocked`, some dep not `done` | leave; the queue promotes later |
| `ready`/`blocked`, deps done, no sidecar | dispatch fresh |
| `ready`, sidecar present, no `checkpoint_after` | crashed after `dispatch`, before the builder's flip — the build **never committed** (`ready` ⇒ `HEAD==checkpoint_before` by construction). Re-dispatch (the increment counts; cap may HALT). **No reset.** (`ready`+`checkpoint_after` is impossible — `checkpoint_after` lands only at step 7, after the builder flipped to `in_progress`.) |
| `in_progress`, sidecar, no `checkpoint_after` | crashed mid-build (builder had flipped). **`worktree` mode:** `reset --hard "$cp"`, `needs_rework`, requeue-or-HALT — rolls back a committed-but-uncollected build. **`build_mode==in-place`: NO `reset --hard`** (it can't undo the DB/module/`vendor` state a crashed mid-build applied → split-brain) → write `wo-NN.HALT` `in_place_crash_manual_recovery`, **TERMINAL**, escalate for human reconciliation. |
| `in_progress`, `checkpoint_after`, no `wo-NN._review.json` | build done, review never ran — resume at the review step (no rebuild, no re-dispatch) |
| `in_progress`, `checkpoint_after`, `_review.json` present, `_critique.json` ABSENT | crashed between review and critique — resume at the **critique** step (no rebuild, no re-dispatch) |
| `in_progress`, `_review.json` + `_critique.json` present | re-derive the verdict from the **per-WO** `_review.json` + `_critique.json` (rule 2b) — apply done/needs_rework |
| all `done`, no `_review.json`/PR | resume at the terminal merge step (idempotent: an existing PR ⇒ report, never a second) |

**Flip ownership (crash-safety hinge).** The `ready→in_progress` flip is performed by the **build atom**
(`work-order-builder` step 2), immediately after its re-gate and BEFORE it commits — NOT by the loop after
the build. This guarantees a committed build is never under `status: ready`, which is what makes the
`ready`+sidecar row safe (re-dispatch, no reset) and routes every post-commit crash to the `in_progress`
reset row.

**Worktree (carry #4).** The loop owns create/teardown. `git reset` always targets the **handed
worktree** (`git -C <worktree>`), never the user's main tree, to the **sidecar** `checkpoint_before`
(③-captured pre-spawn), and only after `merge-base --is-ancestor` validates it. **In `build_mode ==
in-place` the loop owns NO worktree lifecycle (the handed path IS the canonical `codePath`) and issues NO
`git reset` at all** — the reset rows convert to HALT (above), so this carry's reset never runs in-place;
this is also why in-place is sequential-only and refuses `--parallel`.

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
/goal /ai-dev-assistant:review <task> reports overall_verdict "pass" in _review.json (all hard-block
gates green) printed inline AND the work-order loop printed LOOP_COMPLETE AND nothing outside the
Non-goals was modified (git status clean outside the named areas) — or stop after <min(20×N_WOs,80)> turns
```

Degrade (no /goal available): run the loop attended/sequential with the same compact lines. Anchoring on
`LOOP_COMPLETE` only **reduces** accidental misfire from a builder echoing a verdict into the transcript —
it is not an adversarial close (D12b): a forged line can cause a premature stop, never a bad merge (the
merge decision is disk-based `wo-merge-gate.sh` + no merge call + human merge).
