# The Autonomous Recipe — verdict-only reporting contract (v5.18.0+)

**Introduced:** ai-dev-assistant (`autonomous_workflow_path`, epic `orchestrator_context_hygiene`, design spec §4③ / §5 / §6 rows 2-3-5 / §7)
**Owner:** the inline `work-order-loop` / `work-order-loop-parallel` skills (the loop conductors); `commands/run-work-orders.md` (the routing entry that threads `run_mode`)
**Consumers:** the Haiku `/goal` evaluator (reads only the transcript); an outer autonomous driver (reads the single Exit block)

This is the plugin-scoped contract for what an **autonomous** `/run-work-orders` run surfaces and what it
deliberately holds out of the main context. It **formalizes a capability AIDA already has** — it adds no new
engine. ~90% is pre-wired: the loop already sheds its residue by discipline, and the two shipped siblings
(`irreversible_gate`, `spine_memory`) already supply the autonomous teeth.

## 1. The §5 containment — what the "autonomous workflow" IS

The design spec §4③ borrows Claude Code's "spawn a Workflow" framing; **§5 reverses it.** In AIDA the
autonomous "workflow" is **AIDA's own inline `work-order-loop` (or `work-order-loop-parallel`), mode-gated
on** — **NOT** the Claude Code dynamic-workflows runtime (`references/dynamic-workflows.md`, a v2.1.154+
research preview AIDA deliberately declines). Two independent facts force this reading:

1. `dynamic-workflows.md` explicitly declines the runtime ("the framework does not put a gate or a phase on
   a preview primitive").
2. The **flat-call-tree** kernel constraint forbids dispatching the loop into a subagent/fork/Workflow —
   that would push the build atom to **depth-2** (unsupported). The loop MUST run **inline at depth-0**, the
   build atom the sole depth-1 spawn.

So the autonomous path adopts the *property* the CC runtime offers (intermediate results held out of the
orchestrator's context) via the mechanism AIDA already ships (the loop's discipline), with **no runtime
dependency**. This reaffirms the flat-tree decision; it does not re-open it.

## 2. Milestones — what surfaces (byte-stable compact lines)

The only per-WO residue that enters the transcript is the loop's byte-stable compact stderr lines, forwarded
mechanically so the Haiku `/goal` evaluator (which reads only the transcript) sees stable verdicts:

- per-WO: `wo-NN critique=<overall> tier=<tier> mode=<mode> blocking=<bool> critique_ref=<path>`
- the gate lines: `mode_gate allowed=<bool> mode=<mode> reason=<reason>` and `merge_gate …`

Everything else — the verbose per-WO build / review / critique tool output — is **disposable** once that WO's
observability record is written.

## 3. How intermediate state stays out (verdict-only reads)

The mechanism pre-exists in both loops — this contract **cites** it, it does not restate it:

- **Scalar `jq -r` verdict reads**, never a whole-file Read into context (`work-order-loop/SKILL.md` verdict
  step: `jq -r '.gate_specific.overall_verdict'`, `jq -r '.blocking'`).
- **`.HALT` as a file-existence test**, not a file read.
- **Per-WO transcripts are disposable** once the obs record is written — carry forward only the compact lines
  + the reconcile table, never the verbose per-WO transcripts (the loop's transcript-hygiene discipline).

A work-order's result therefore enters the main context **as a few bytes**.

## 4. The final synthesized result — the three terminal outcomes

An autonomous run has **exactly one** clean terminal outcome plus the one failure terminal (a third,
`LOOP_COMPLETE`-with-an-opened-PR, is structurally impossible under autonomous — see the struck row):

| Outcome | When | Meaning |
|---|---|---|
| **`BRANCH_ASSEMBLED_AWAITING_HUMAN`** | every WO GREEN (build + task-level `/review` passed); `wo-pr-open.sh` → `wo-mode-gate.sh` **REFUSES** (`autonomous_irreversible`, exit 1, `gh` never called) | the autonomous **happy-path** terminal. Build is GREEN and the branch is assembled on base; the PR is **correctly withheld** pending a human. Not a failure. Emit the `/goal` for the human to resume attended and open the PR. |
| **`ESCALATION`** | any WO TERMINAL (`wo-NN.HALT` / sidecar `halted:true`) or permanently `blocked` | the **failure** terminal — names the dead branches + HALT reasons and STOPs. |
| ~~`LOOP_COMPLETE`-with-an-opened-PR~~ | — | **structurally impossible** under autonomous — `wo-mode-gate.sh` refuses PR-open **every time**, so no autonomous run ever opens a PR. |

`BRANCH_ASSEMBLED_AWAITING_HUMAN` is what makes the mode-gate's refusal **legible**: the current bare
non-green `merge_gate` line reads like a failure (or worse, implies a PR was opened). It is neither — it is a
clean escalation of a GREEN build. `run_mode` is threaded to the loop's Exit branch **advisory-only**, to
select this *message*; the refusal itself is unchanged and owned by the kernel reading disk fail-closed (§6).

## 5. HALT-composition — how autonomy stays safe

Two choke points make the autonomous path safe, and **both read the same disk fact** (`run_mode` on disk,
set by `spine_memory`, re-read fail-closed by each kernel — the composition of `run_mode` + the irreversible
gate):

1. **PR-refusal (irreversible gate).** The loop opens a PR **only** through `wo-pr-open.sh`, which calls
   `wo-mode-gate.sh` before any `gh`. For `autonomous` the gate **REFUSES** with
   `halt_reason=autonomous_irreversible`, exit 1 — the confirm artifact is never consulted. So the instant an
   autonomous loop reaches PR-open, HALT-on-irreversible holds **transitively** in both loops, with no new
   code. This is `distill_and_drop`'s "Phase-3 `wo-mode-gate.sh` kernel's domain" — the irreversible /
   out-of-band decision (PR / merge / infra) that the advisory layer never touches.
2. **Forced fan-out critique.** `run_mode=autonomous → unattended=true → forced` fan-out critique
   (`work-order-critique` step 2), fail-closed via `wo-critique-aggregate.sh` → the `.blocking` scalar. The
   adversarial verdict returns as a scalar; the critic transcripts never enter context. Same disk fact,
   second choke point.

The autonomous route does nothing special to *make* either gate fire — it fires because the route sets
`run_mode=autonomous` on disk and every kernel re-reads that fact fail-closed. The route's only obligations
are to **not bypass** `wo-pr-open.sh` (it structurally can't — the loop owns PR-open) and to **not loosen**
the disk mode.

## 6. Honest boundary

The gate is only as strong as the **disk fact** it reads. A same-uid process can rewrite `run_mode` on disk —
not closeable in bash. Genuinely-unattended runs rest on the **OS-sandbox precondition** (design §8), not on
bash. The threaded `run_mode` input is **advisory** (message selection only); if the command mis-passed it,
the kernel would **still** refuse (disk is truth) — only the outcome *message* would be less specific. No
security decision rests on the passed input.

## 7. Optional — terminal-transcript distill (kept optional)

The loop is **inline**, so the milestone lines are already in the main transcript and already feed the Haiku
`/goal` evaluator. The **contract** is the milestone-line stream + the single Exit block. An outer autonomous
driver **MAY** compose with the `distill_and_drop` sibling to reduce the terminal stream to one synthesized
line — but **no distill step is mandated here**.

## What this recipe deliberately does NOT add (§5)

No Claude Code dynamic-workflows runtime; no dispatching the loop into a subagent/fork/Workflow (flat
call tree preserved); no new skill, kernel, gate, or `gate_type`; no `--autonomous` CLI flag (mode is
disk-scoped, `.runMode`, read at Step 1); no re-platforming of the interactive path (attended /
`--parallel` / `--in-place` behavior is byte-unchanged). The refusal (`wo-mode-gate.sh`) and the forced
critique (`wo-critique-aggregate.sh`) already ship — this recipe adds **reporting + docs**, not enforcement.
