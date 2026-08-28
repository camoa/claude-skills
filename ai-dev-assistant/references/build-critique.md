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

   **And `implementation.md` is not a substitute for that missing record.** Its prose is
   written by the builder, at whatever moment the builder happened to write it, and nothing
   re-checks it afterwards. On a live build it was updated before a repair and never after, so
   by the time the critics read it, it reported 9 tests and 196 assertions for a suite that was
   then 13 and 241, across 269 changed lines including production code — affirmatively wrong
   rather than merely behind. A critic handed `review_ref: null` that then treats that block as
   gate evidence has substituted stale prose for the record whose absence it was just told
   about. `null` means no deterministic gate evidence exists for this unit. Say that in the
   verdict; do not source it from somewhere softer.
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

## The RED-observation half — loop step 4, not this rung

The adversarial critique above answers "is this diff sound." It says nothing about whether
the diff was built test-first, because a critic reading a finished diff cannot tell a test
that failed first from one written after the fact to match working code. That answer has to
come from watching the build happen, and the only point in the loop where it can be watched
is loop step 4 — writing the test and running it before the implementation exists — not the
critique rung at step 8, which fires after the component is already done.

**`observed` means it failed at its own assertion**, not merely that the command exited
non-zero: a test that dies in `setUp` never reached the behaviour it names, and counting that
as a RED credits an observation nobody made. `references/tdd-workflow.md` carries the rule.

**What gets recorded, per acceptance criterion:** whether its test was run and seen to FAIL
before the implementation existed (`observed`), ran and passed on the first try — meaning the
test is wrong (`passed_first_run`) — or nobody ran it (`unobserved`, legal only with a
reason). `references/tdd-workflow.md`'s "Who runs the tests, and what has to be recorded" is
the source of these three values and of the rule that `unobserved` is a real, writable value
rather than something silence implies.

**Who runs the test depends on `run_mode`**, read from `project_state.md` /
`scripts/project-state-read.sh` (task override via `scripts/fm-read.sh`):

| `run_mode` | Who runs it | How RED is observed |
|---|---|---|
| `interactive` (default) | The user, unless they've said otherwise for this project | Claude gives the exact command; the user runs it and reports the result back |
| `autonomous` | The agent, because there is nobody else | The agent runs the command itself and keeps the exit code |

Neither row is a licence to skip the observation — `references/tdd-workflow.md` covers the
edge case (a project that says "I run the tests, not you") explicitly: that instruction is
about unattended whole-suite sweeps, and a single targeted invocation whose only purpose is
to watch one new test fail is the RED step itself, still owed either way.

**Where it lands.** The per-criterion outcomes aggregate once, at Runtime Step 12 part 2 —
not per component — into the `tdd` key of this rung's own record:
`{red_observed, passed_first_run, unobserved[], reason}`, counted and named across every
criterion built the whole phase. `gate-audit-write.sh` lists `tdd` in `build-critique`'s
REQUIRED_KEYS, the same non-blocking check it runs against `phase`, `verdict`,
`components_declared`, and the rest — absence gets a warning on stderr and the file is
written anyway. The enforcement that actually stops a review is downstream, in
`scripts/build-critique-assert.sh`, run by `/review` step 5.0f:

| Payload state | Verdict | `unresolved` | exit |
|---|---|---|---|
| `tdd` key absent | fail | `true` | 1 |
| `red_observed` / `passed_first_run` / `unobserved` — any missing | fail | `true` | 1 |
| `passed_first_run > 0`, no `reason` | fail | `true` | 1 |
| `passed_first_run > 0` with a `reason` | pass | `false` | 0 |
| `unobserved` non-empty, `reason` empty or absent | fail | `true` | 1 |
| `unobserved` non-empty, `reason` populated | pass | — | 0 |
| all present, `unobserved` empty | pass | — | 0 |

**Two different things pass on a first run, and only one is a defect.** A test written
test-first that passes immediately is `tdd-companion`'s named violation: it asserts nothing
about the behavior it claims to test. A characterization or regression test written
deliberately against code that already exists passes on its first run by design, and is worth
having — locking in behavior, or reproducing a defect a critic just found. Both land in
`passed_first_run`, and the `reason` says which.

v5.34.0 failed both with no reason path at all. A live build hit it immediately: several tests
added during repair rounds were written against existing code and passed first time, and the
rule would have made the honest record a violation. A gate that punishes the true answer
teaches a builder to write a different one. As everywhere else in this rung, the gate checks
that the question was answered, not that the answer is true. **Applies to the in-session build
path only** — see below.

## The round budget — two blocking rounds, then somebody decides

`[a]ddress` starts a new round on the component. Nothing counted them, so the loop could run
indefinitely and no artifact said whether it was converging.

Live, one component ran four blocking rounds. Round 1 found a fixture that proved the inverse of
its purpose. Round 2's critical was caused by round 1's repair. Round 3's two criticals were both
caused by round 2's repair. Round 4 then proved the premise behind the round-3 cut was
arithmetically false. Every round was individually correct — the critics found real defects and
the builder fixed them — and the sequence as a whole was not converging. The builder stopped and
asked the operator whether to continue, which was the right instinct arriving from nowhere: no
rule told it to, and an unattended run has nobody to ask.

At the second blocking round on one component, halt.

| `run_mode` | What happens |
|---|---|
| `interactive` | Put it to the person: continue, cut scope, or accept and record a bypass |
| `autonomous` | **HALT.** Never start a fourth round unattended |

Record the outcome either as a top-level `escalation.reason` or as a `resolution` on the
`rounds[]` entry it settled — the per-round form is the one a live build produced, and it is the
better of the two, since a decision belongs with the round that provoked it. Keep a `rounds`
count on each component row, and a `rounds[]` history of what each round found. Past the threshold the gate fails a record with no
`escalation.reason`.

**This caps unsupervised iteration, not quality.** A fourth round is a legitimate choice; an
unrecorded fourth round is not. The reason is the same one the whole rung rests on: a builder that
has been wrong twice running is the least reliable judge of whether the third attempt is
different.

**Why two and not three.** Measured on the run this rule came from: rounds 1 and 2 found real
behavioural defects that no test caught and no amount of reading would have surfaced. Rounds 3, 4
and 5 produced 58 findings between them and not one concerned a defect that pre-existed the
round-1 and round-2 repairs. The value is front-loaded. Past that the loop audits its own repairs.

## Repair the minimum, and defer what cannot be answered yet

Two rules, one cause. The churn was never the critics.

**Growth during repair.** Each round the builder answered a `concern` with new mechanism instead
of the smallest fix, and every new mechanism was fresh attack surface. A method that did not
exist before one round's repair collected 38 of the 58 findings raised in the three rounds after
it; production code grew 72% across the loop while behaviour stopped changing after round 3.
Record `repair_growth: {net_lines, reason}` on each repair round, measured against the previous
round's checkpoint. Growth with no reason fails. Growth is allowed; unexamined growth is not.

**Findings that cannot be answered yet.** "This method has no production caller" is true and
unfixable when the caller is three components away. With nowhere to put it, the builder wrote a
specification for the absent caller — and that answer produced the next round's critical, whose
answer produced the round after. Three of the four unanswerable findings in that build were
generated by trying to close the first one. A critic now reports these in `deferred[]` as
`{finding, blocked_on, why_now_is_wrong}`. Deferred findings do not block and are re-checked when
`blocked_on` is built. A deferral naming no `blocked_on` fails: a finding nobody will return to is
a dropped finding wearing a label.

Neither rule is machine-checkable as "was this minimal" or "was this premature". Both are
checkable as "did you say so", which is the same standard the rest of this record holds.

**What this cannot do.** It counts rounds, not progress — three rounds that each fix something
real trip the same threshold as three that thrash. It reads `rounds` off the record, so a builder
that runs four rounds and writes `1` defeats it, exactly like every other self-reported field
here.

## The contract baseline — Runtime Step 11, before any code exists

Both mechanisms that judge scope, this rung's `meets-ac` lens and the end-of-phase alignment
axis, read `alignment.md` and `architecture/`. The builder can edit those files. Without a
frozen copy the scope question resolves against whatever the design says at critique time,
which may be text the builder wrote to describe the code it is meant to authorise — a build
grading itself against its own homework. Seen live, and caught only because the builder
annotated its own edit: a `meets-ac` critic ruled an addition "blessed only by design-doc text
that self-declares added at Phase 3."

`contract-baseline.sh capture "<task_folder>"` copies `alignment.md`, `architecture.md` and
`architecture/*.md` into `<task_folder>/build-critique/_contract-baseline/` at Runtime Step 11.
`contract-baseline.sh diff` reports `changed[]`, `added[]` and `removed[]` at Step 12, and that
goes into the record's `contract` block.

| Payload state | verdict | `unresolved` | exit |
|---|---|---|---|
| no `contract` key | fail | `true` | 1 |
| `baseline: late`, no `reason` | fail | `true` | 1 |
| `baseline: late` with a `reason` | pass | `false` | 0 |
| `baseline` neither `captured` nor `late` | fail | `true` | 1 |
| `changed[]` non-empty, no `reason` | fail | `true` | 1 |
| `changed[]` non-empty with a `reason` | pass | `false` | 0 |
| `baseline: captured`, nothing changed | pass | `false` | 0 |

**Amending the contract mid-build is legitimate.** A design can be discovered to be
unbuildable, and on the build that produced this rule one was: its recipe for a fixture shape
could not be constructed against the contrib source it depended on. What the gate refuses is an
amendment nobody can see. **Re-capture is refused for the same reason** — a baseline that can be
refreshed mid-phase launders exactly the edit it exists to expose.

**A task already building when this landed cannot produce an honest baseline**, because the
contract has already moved under it. `capture` detects that from the rung's own scaffolding
(`build-critique/*.critics/`, `build-critique/*.files.txt`) and returns `late` rather than
`captured`. Failing `late` forever would punish a task for predating the check; stamping it
`captured` would certify the amendments the baseline exists to expose, which is worse because it
reads as legitimate. So it passes with a reason, and the record says what the baseline is worth.
A fresh phase should never see `late`; if it does, the phase boundary was opened after the code.

**What this cannot do.** It compares files, not intent: rewording a criterion while keeping its
meaning reads as a change, and a `reason` is prose nothing verifies. It cannot see edits made
before Step 11, so a contract rewritten during `/design` is simply the baseline.

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
| `tdd` | object | `{red_observed, passed_first_run, unobserved[], reason}` — the RED-observation half, from loop step 4, aggregated across the whole phase (v5.34.0+, required). See above. |

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
- **The work-order build path carries no RED evidence at all.** The `tdd` block lives on
  `_build-critique.json`, and only `/implement`'s in-session path writes that record. A build
  that went through `/run-work-orders` owes `work-orders/wo-NN._critique.json` instead, and
  nothing in that shape carries `red_observed`, `passed_first_run`, or `unobserved`. The
  RED-observation half is not degraded on that path — it is entirely absent, and
  `build-critique-assert.sh` does not ask it to be present, because the file it would live in
  is never expected to exist there. Documented as not covered, not as covered-and-passing.
- **A recorded `observed` is a report of an observation, not proof of one.** Nothing in this
  rung, or in `/review`, captures the test runner's actual exit code. The record is whatever
  Claude typed into the `tdd` block after the fact. A criterion whose test never ran, or whose
  test failed for the wrong reason, or whose result was simply misremembered, still passes as
  long as the block says `observed` and the counts add up. The enforcement above closes the
  gap between "recorded" and "unrecorded"; it does not close the gap between "recorded" and
  "true."
