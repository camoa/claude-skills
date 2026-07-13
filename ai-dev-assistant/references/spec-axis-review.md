# Spec-Axis Review (M2)

**Introduced:** ai-dev-assistant v5.20.0 (`/review` step 5.0d). Borrows `mattpocock/skills`' `code-review`
two-axis idea: a review has an explicit **Standards** axis and an explicit **Spec** axis, kept separate on
purpose. This is the canonical spec for the Spec axis; `commands/review.md` cites it and stays thin.

## The two axes

- **Standards** — steps 5.0/5.0b/5.0c plus the hard-block gate battery (`tdd`/`solid`/`dry`/`security`/
  `guides`/…) already in `/review`. Answers *"does the code follow the repo's standards?"* — judged against
  the code as written, with no memory of why it was written.
- **Spec** — this step. Answers the orthogonal question *"does the change faithfully implement what the
  originating task's contract actually asked for?"* — judged against `alignment.md`, the task's own
  contract.

**Never merged.** A change can pass every Standards gate and still fail Spec (over-built, under-built, or
solving the wrong problem) — that must surface as its own signal, never masked by a green Standards row.
Symmetrically, a Spec pass never excuses a Standards fail. `/review`'s report carries a `## Standards` block
and a distinct `## Spec` block (`review-summary` mandated wording); the two verdicts are never blended into
one score.

## What it checks

Reads the task's `alignment.md` **Task-Level `### Success criteria`** (grammar: `references/
alignment-contract.md`) and `architecture.md` if present, then judges the merge-base diff for:

1. **Missing requirements** — a success criterion with no corresponding implementation in the diff. This is
   the **hard** signal — objective (a criterion either has a corresponding hunk or it doesn't) — and alone
   drives the verdict per the rule below.
2. **Scope creep** — a substantive diff hunk not traceable to any criterion or architecture decision. This is
   **advisory** — surfaced as warnings, never a hard fail on its own (see "Verdict rule" below).

This generalizes `agents/wo-critic.md`'s `meets-ac` lens (which checks one work-order's `## Done =`
checklist) to the whole task change against the whole task contract.

## Verdict rule — missing-requirements hard, scope-creep advisory

`verdict` is `fail` **iff `missing_requirements[]` is non-empty**. `scope_creep[]` never drives the verdict
on its own: a scope-creep-only result (empty `missing_requirements[]`, non-empty `scope_creep[]`) is
`verdict: "pass"` with the scope-creep findings still listed as warnings in `/review`'s `## Spec` block. This
is a **deliberate de-risking**: scope creep is an inherently subjective judgment (untraceable-to-what, by
whose reading of `architecture.md`) and hard-failing on it alone was producing false-fails under unattended
(`--headless`) runs. Missing requirements is the objective, hard signal and remains a full hard-block —
it still drives `overall_verdict` via step 8 rule 1 exactly as before.

## Dispatch

`/review` dispatches `agents/spec-axis-reviewer.md` (Task tool, read-only, generic) with the parsed success
criteria + `architecture.md` (if present) + the merge-base diff — the same command-owns-resolution /
agent-stays-generic pattern `/review` step 5.0 already uses for `architecture-validator`. The agent returns
its verdict as its Task response (it does not write files); `/review` captures it into
`<task_folder>/_spec.json` via `gate-audit-write.sh <task> spec <payload>` (`gate-audit-schema.md` §5.15)
and adds `gates_run[]` entry `name: "spec"`, `kind: "hard-block"`.

## Aggregation — distinct, not collapsed

The `spec` entry folds into step 8's `overall_verdict` exactly like any other hard-block `gates_run[]`
entry — a `fail` triggers rule 1 (fail dominates) like any other gate. It stays **independently
attributable**: the fail prompt's `{{gates_failed_verbatim}}` list names it `spec`, never lumped into a
generic "gate(s) failed" count that reads as a Standards failure. A human or `/goal` evaluator reading the
output can always tell *which* axis failed.

## Skip semantics — benign, not fail-closed

**No `alignment.md`** ⇒ no task-level contract to check against ⇒ `verdict: "skipped"` with a `messages[]`
reason (`"no alignment.md — nothing to check the change against"`). **Never fabricate criteria to force a
verdict.** This skip is deliberately shaped like `skipped-not-shipped`, NOT like an `unresolved` gate — it
does not trip step 8 rule 2's fail-closed path, because an absent optional artifact is a documented,
expected state (`/scope` is opt-in per `CONVENTIONS.md`'s Alignment Step), not evidence of a bypassed
check. Contrast with `mechanism-challenge` (`references/mechanism-challenge.md`), whose absent record IS
fail-closed — that gate's precondition (research ran) is mandatory; Spec's precondition (`/scope` ran) is
not.

## `--headless`

No prompt. A Spec `fail` is fail-closed exactly like every other hard-block gate: non-zero exit, and it
appears in the compact per-gate verdict line (`spec verdict=<pass|fail|skipped>`) the same way `tdd` or
`solid` would.

## Out of scope

Re-running Standards checks (style, SOLID, security) — that is the other axis's job, unchanged by this
step. Scoring severity/weighting a partial-credit Spec result — the verdict is binary (`pass`/`fail`) plus
`skipped`; nuance lives in the findings, not a numeric blend with Standards.
