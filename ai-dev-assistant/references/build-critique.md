# The build-critique rung — challenging a build while it can still change

Phase 3 contract for the two questions a builder cannot answer about its own work:
**is this sound** (adversarial) and **is this what was asked for** (alignment).

## Why this exists

Both agents already existed. Neither could reach an in-session build.

`wo-critic` — fresh context, hostile-diff posture, four lenses — fires only inside
`/run-work-orders` and the work-order loop skills. `spec-axis-reviewer` runs only in
Phase 4. So a task that declined the work-order offer had no adversarial coverage at all
until every line was written, and the work-order offer never said that declining removed
it. The default in-session path had the same hole permanently.

What `/implement` did activate — `tdd-companion`, `code-pattern-checker` — are skills the
builder runs **on itself, in its own context**. That is self-review. A builder holding its
own reasoning cannot be surprised by it, which is the entire value a critic supplies.

Observed on a live Phase 3 round: a builder hand-rolled a test-runner install, rewrote a
component's architecture file mid-build to reverse a finding from the design phase, and
emptied a static-analysis suppression list. Each was a defensible call. None was seen by
anything but the agent that made it.

## The unit is an architecture component

`/design` writes `architecture.md` as a hub plus one `architecture/<component>.md` per
component, each carrying that component's interface, its structure, and **its acceptance
criteria**. Those criteria are the direct analogue of a work-order's `## Done =` checklist,
which is what `wo-critic` already reads. So the component is the unit, and the existing
critique stack is reused rather than duplicated: `scripts/wo-risk-classify.sh` for the
tier, `references/risk-tiering-rules.json` for the lens set, the `wo-critic` agent itself,
and `scripts/wo-critique-aggregate.sh` for the verdict.

A design that genuinely has one component gets one critique. A flat `architecture.md` with
no component files is one unit named `main`.

## The boundary problem, and the checkpoint

The work-order loop hands each critic a `<before>..<after>` git rev range and gets both
shas free, because a work-order is a discrete build atom: `git rev-parse HEAD` before
dispatch, the builder's handle after. **An in-session build has neither.** The code sits in
the working tree, uncommitted, usually untracked, and HEAD does not move between one
component and the next. There is no range.

Committing per component would produce one. It is also not ours to require: how a
repository uses version control belongs to whoever owns it, and a build gate that writes
commits into someone's branch has overstepped.

`scripts/build-checkpoint.sh` resolves it. A checkpoint is a commit **object** with no
branch — a temporary index, `git write-tree`, `git commit-tree` — anchored under
`refs/worktree/aida/build-checkpoints/<label>`, plus a second, shared keep-ref at
`refs/aida/build-checkpoints-keep/<sha>`. It needs both, and the reason is measured rather
than assumed.

**Why two refs.** `refs/worktree/` is the point of that path, not decoration. Every other namespace under
`refs/` is shared by all checkouts of a repository; `refs/worktree/` is per-checkout. Two
agents building different tasks in two worktrees of the same repository is the ordinary
working pattern, and `/implement` step 2 nudges toward a worktree, so a shared namespace is a
collision by default rather than by accident: both write the documented default label `main`,
the second overwrites the first, and whichever finishes first deletes the other's boundary on
its end-of-phase clear. The critic then reads a range belonging to a different task.

Per-checkout refs, though, are **not reachability roots for a `git gc` run from a different
checkout**, so isolation on its own costs the protection the anchor exists to give. Measured
on git 2.43: `gc --prune=now` from a sibling checkout deletes the object and leaves the ref,
after which `list` names a checkpoint whose commit is gone and the critic's rev range is a git
fatal. The shared keep-ref closes that, and naming it by the object's own sha is what makes
sharing safe: two checkouts can only collide on that name by having produced byte-identical
trees, in which case they are the same object. `clear` releases both.

`list` reports each checkpoint's `object` as `resolvable` or `unresolvable` and counts the
latter, because a ref can still outlive its object if someone deletes a ref by hand, and a
range that fails at the critic is the same failure arriving further from its cause. HEAD
does not move, no branch advances, the real index and working tree are untouched, and the
sha behaves as an ordinary commit for `git diff <a>..<b>`. Untracked-not-ignored files are
included deliberately: a new module is entirely untracked until someone stages it, and a
checkpoint that skipped them would hand the critic an empty diff for exactly the component
most worth critiquing. What rode along is reported in `untracked[]` rather than left to be
discovered.

`build-checkpoint.sh clear --repo <codePath>` removes the namespace. `/implement` clears it
when the phase ends.

## Sequence

Per component, at loop step 8 of `/implement`'s Interactive Development Loop. The scripts are
the existing work-order critique kernels, and their flags are not optional: two of them
fail closed into `high` / non-blocking respectively when a required flag is absent.

1. **Before writing the component's code**, `build-checkpoint.sh capture --repo <codePath>
   --label <component>.before`; keep the sha.
2. Build the component.
3. **When its acceptance criteria are built**, capture `--label <component>.after`.
4. **Realize the file list.** `git -C <codePath> diff --name-only <before>..<after> >
   <task_folder>/build-critique/<component>.files.txt`. The classifier takes a file list, not
   a rev range.
5. **Tier.** `wo-risk-classify.sh --files-from <that file> --gate-floor
   "tdd,solid,dry,security,guides"`. **`--gate-floor` is required here.** It normally comes
   from a work-order's frontmatter; a component has none, and the classifier tiers everything
   `high` when both the work-order file and the flag are missing. The value is the
   `base_gate_floor` from `references/risk-tiering-rules.json`, so a component is tiered on
   what it changed rather than on a missing input. Read `.risk_tier` from its JSON.
6. **Lenses** from that file's `tier_lenses`: `low` → `skeptic`; `medium` → `security`,
   `correctness`; `high` → `security`, `correctness`, `meets-ac`. A security lens is
   guaranteed at `medium` and above, so executable code always gets one.
7. **For each lens, dispatch ONE `ai-dev-assistant:wo-critic`** via the Task tool — fresh and
   independent, never a fork, or the critique inherits the reasoning it exists to challenge.
   Hand it what the existing contract specifies: `<worktree>` (the project's `codePath`), the
   `<before>..<after>` range, the component's acceptance criteria as injected content, its
   lens, and its output path
   `<task_folder>/build-critique/<component>.critics/<component>.critic-<lens>.json`.
   There is no per-component `_review.json`, so `<review_ref>` is passed as `null` and the
   critic is told the deterministic gates have not run for this unit — it must not read an
   absent gate record as a clean one.
8. **Aggregate**, redirecting stdout, because the kernel prints its envelope rather than
   writing a file:

   ```
   wo-critique-aggregate.sh --wo "<component>" --tier "<risk_tier>" --mode fanout \
     --expected <lens count> --critics-dir "<...>/<component>.critics" \
     --evaluated true --required [--diff-empty] \
     > <task_folder>/build-critique/<component>.critique.json
   ```

**Do not read a critic's Task return for its verdict.** Read its verdict file. Disk is
truth, and an agent that died mid-response returns text that looks like an answer.

## Posture — blocking, on the component

The kernel **always exits 0 and always emits an envelope**. The verdict is the envelope's
`blocking` field, never the exit code. `blocking` is
`critical | (not_evaluated & required) | (required & unresolved) | (degraded & high)`.

- `blocking: true` → the component stops. `[a]ddress` (fix, then re-run this rung for this
  component) or `[o]verride (reason)`, recorded in `bypass_reason`. The build does not move to
  the next component.
- `overall: "concern"` → surfaced, not blocking.
- `overall: "pass"` → continue.

**`--required` is what makes `unresolved` blocking, and it is passed unconditionally.**
Without it the kernel folds an undetermined critic into a non-blocking `concern` at `low` and
`medium` tier, and a critic that could not determine has cleared nothing. This is a flag, not
a judgment call, and it is not conditioned on any run mode: `/implement` has no `--headless`
flag to condition it on, and an unattended run is exactly where an undetermined verdict must
not pass quietly.

**`--diff-empty` when the component's file list is empty**, which the kernel scores
`critical`. That is correct and deliberate: a component declared done that changed nothing is
a do-nothing build, and catching it is the `meets-ac` lens's whole purpose. It is not the same
thing as the rung-level `skipped` below, which is about the phase having no change at all.

## The alignment axis — once, at the end of the phase

The adversarial axis asks whether the code is sound. It does not ask whether it is the
thing that was asked for, and a component-by-component check cannot: `alignment.md`'s
success criteria are task-level, and judging one component against the whole contract
would report most of them missing every time.

So once, at Runtime Step 12, dispatch `ai-dev-assistant:spec-axis-reviewer` with
`alignment.md`'s Task-Level `### Success criteria`, `architecture.md`, and the file list from
`git -C <codePath> diff --name-only <phase.before>..<phase.after>` — a phase-level checkpoint
pair captured at Runtime Step 11 and at step 12.

**Not `scripts/review-change-set.sh`.** That resolver deliberately excludes untracked files,
and a new module is entirely untracked until someone stages it, which is the exact case this
phase exists to build. Handed a change set with the new code missing, the reviewer finds every
success criterion unimplemented and hard-fails work that is complete. Phase 4 can use it
because by then the work is usually committed; Phase 3 cannot.

Its verdict rule is unchanged from Phase 4: `missing_requirements[]` non-empty is a hard fail;
`scope_creep[]` alone is advisory.

This is the same check Phase 4 runs. Running it here as well is the point rather than a
duplication: at the end of Phase 3 the builder can still act on it, and at the Phase 4 gate
the finding arrives when the work is supposed to be finished. A criterion discovered
unimplemented while the build is open is a task; discovered at the gate it is a reopening.

`/review` runs its own Spec pass afterwards regardless. This one never writes `_spec.json`
— its result belongs to the build record below.

## The record

One `gate-audit-write.sh` envelope, `gate_type: "build-critique"`, schema 1.9, written to
`<task_folder>/_build-critique.json`. Both axes live in one record because they are one
rung, the same way `/review` carries its Standards and Spec axes in one `_review.json`
without merging their verdicts.

`gate_specific`:

| Key | Type | Meaning |
|---|---|---|
| `phase` | string | Always `"implement"`. |
| `verdict` | enum | `pass` \| `concern` \| `critical` \| `unresolved` \| `skipped`. The rung's overall answer. |
| `components[]` | array | One row per component: `component`, `risk_tier`, `lenses[]`, `verdict`, `blocking`, `checkpoint_before`, `checkpoint_after`, `critique_ref`, `findings_count`. |
| `components_declared` | integer | How many components the architecture declares. |
| `components_critiqued` | integer | How many actually got a critique. |
| `uncritiqued[]` | array | `{component, reason}` for every declared component with no critique. |
| `alignment` | object | `{verdict, missing_requirements[], scope_creep[], spec_ref}`, or `{verdict: "skipped", reason}`. |

**`components_declared`, `components_critiqued` and `uncritiqued[]` are all three required,
and a partial run must not be able to read as a complete one.** A rung that critiqued three of seven components and
recorded only its three green rows is a record that cannot say what it did not look at,
which is the failure this framework keeps finding in itself. Any gap is named in
`uncritiqued[]` with a reason.

`verdict: "skipped"` is legitimate in exactly two cases, each carrying its reason: the
phase-level checkpoint range is empty, or no architecture file exists (a task with no design
phase). It is never the answer to "the critics did not run" — that is `unresolved`, with the
components named. It is also not the same as a single component's empty diff, which is
`critical` via `--diff-empty`.

## What this rung cannot do

- **It critiques a diff, not a design.** A component built exactly as specified from a
  wrong specification passes every lens. The alignment axis catches a criterion with no
  implementation; it does not catch a criterion that was wrong to agree to.
- **The lens set is four one-line descriptions.** There is no per-lens prompt, checklist, or
  severity guidance anywhere in the plugin. Two lenses on the same diff can and do overlap.
- **A checkpoint boundary is the builder's word.** It captures whenever the build says a
  component is done. A builder that never declares one done is never critiqued, and the
  `uncritiqued[]` row is what makes that visible rather than silent.
- **An architecture with no acceptance criteria per component** leaves `meets-ac` with
  nothing to check. The critique still runs; the row records the criteria were absent.
