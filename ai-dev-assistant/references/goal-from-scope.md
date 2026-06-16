# `/scope` → `/goal` bridge — build a completion condition from the scope contract

> This file documents how to turn a task's scope contract (`alignment.md`) into a
> ready-to-paste `/goal` condition. It does NOT re-document `/goal` itself — that
> lives in `CONVENTIONS.md` under `## Condition-checked autonomy with /goal`. Read
> that section first for the transcript-only evaluator, gate-anchoring, and
> turn-bounding rules.

## The mapping

`alignment.md` is the persistent scope contract, parsed by
`scripts/alignment-read.sh <task_folder>` into per-phase
`{ goal, expected_result, success_criteria[], non_goals[] }` (see the
`alignment-reader` skill and `references/alignment-contract.md`). The bridge reads
the relevant phase (Phase-3 for implementation, else task-level) and maps two of its
fields into a `/goal` condition:

- **Success criteria** (`success_criteria[]`) → the **completion clause**. These must
  already be gate-anchored — a criterion the evaluator can confirm from a verdict in
  the transcript, not loose prose.
  - When a criterion carries a `verification` note (grammar v1.1 — the parsed
    `{text, checked, verification}` item has a non-null `verification`), the bridge
    uses that note as the concrete signal the completion clause anchors that criterion
    to: it tells the evaluator precisely which inline gate output / observable to look
    for. A criterion *without* a verification note (`verification: null`) falls back to
    today's behavior — it must still be gate-anchored from its prose. The verification
    note **refines which signal each criterion maps to; it does NOT replace** the
    non-negotiable requirement (below) that a gate ran and surfaced its verdict inline.
- **Non-goals** (`non_goals[]`) → a **guard clause**: "…and nothing outside the listed
  scope was modified (`git status` clean outside the named areas)."

## The non-negotiable anchoring rule

The `/goal` evaluator is a small fast model (default Haiku) that reads **only the
conversation transcript** — it runs no tools and reads no files. It cannot read
`alignment.md`, and it cannot read `_review.json` on disk. So a condition that
anchors to bare `alignment.md` success-criteria prose would be rubber-stamped.

**Every emitted condition MUST require that a framework gate ran and surfaced its
verdict inline** — i.e. `/ai-dev-assistant:review` (which writes `_review.json`
and prints per-gate verdicts to the transcript) or `/ai-dev-assistant:validate:all`
(which prints a per-gate summary table). Anchor the completion clause to that
surfaced verdict, add the Non-goals guard, and bound the run with a turn clause.

A criterion's `verification` note (v1.1) is the **preferred** anchor when it names a
confirmable inline signal — e.g. "`/review`'s e2e gate prints a passing Playwright
run for the route" — because it makes the anchor explicit rather than leaving the
bridge to infer it from prose. But a `verify:` note that merely restates the
criterion ("verify: the component works") names no inline signal, so it still needs a
real gate verdict to anchor to: never let a verification note become a rubber-stamp.

### Worked example

Given a Phase-3 contract like:

```
Success criteria:
- [ ] /review reports all hard-block gates green for this task
- [ ] The new component renders on its route with no console errors — verify: /review's e2e gate prints a passing Playwright run for the route
Non-goals:
- Do not touch framework core or third-party dependencies under vendor/
- Do not change the theme's style build pipeline
```

the second criterion carries a `verification` note; the first does not. The bridge
emits:

```
/goal /ai-dev-assistant:review <task> reports overall_verdict "pass" in _review.json (all hard-block gates green) printed inline AND /review's e2e gate prints a passing Playwright run for the route AND nothing outside the Non-goals was modified — git status shows no changes under framework core, vendor/, or the style build pipeline — or stop after 20 turns
```

The first criterion has no `verify:` note, so it falls back to its gate-anchored prose
— the inline `/review` `overall_verdict "pass"`. The second criterion's verification
note becomes the specific anchored check ("`/review`'s e2e gate prints a passing
Playwright run for the route") instead of a generic "Success criteria hold". The
condition references the `/review` verdicts that land in the transcript, folds in the
Non-goals as a `git status` guard, and turn-bounds the loop.

## Limits — state these plainly

- **Session-scoped and ephemeral.** `/goal` is active for the current session only;
  `alignment.md` stays the persistent source of truth. The goal is driven *from* the
  contract, it never replaces it.
- **Completion check, not a guardrail.** `/goal` only withholds "done" until the
  condition holds — it will NOT block a scope-creep action mid-turn. Active Non-goal
  enforcement stays with the framework's existing guardrails (`autoMode.hard_deny`,
  the phase gates, `/review`).
- **Does not author or validate the contract.** Authoring + static validation of
  `alignment.md` stays with `/scope` and the `alignment-reader` skill. The bridge only
  *reads* the parsed contract to suggest a condition.
- **Requires workspace trust + hooks + Claude Code v2.1.139+.** `/goal` is part of the
  hooks system, so it is unavailable under `disableAllHooks`, `allowManagedHooksOnly`,
  or in an untrusted workspace. Surfaces that suggest a `/goal` string must **degrade
  gracefully** — if `/goal` is unavailable, omit the suggestion silently.

## Related

- `CONVENTIONS.md` the `Condition-checked autonomy with /goal` section — the `/goal` primitive
  and its evaluator semantics (do not duplicate here).
- `references/alignment-contract.md` — the `alignment.md` grammar the bridge reads.
- `/ai-dev-assistant:implement` — surfaces this suggestion once at the start of
  Phase 3.
