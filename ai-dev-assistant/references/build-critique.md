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

## Which build the record describes

`build_identity` closes the rung. Three fields, written once when every component is done:

- `head` — `git -C <codePath> rev-parse HEAD`
- `files` — the sorted union of every component's realized file list
- `files_digest` — `printf '%s' "$(printf '%s\n' <those files, sorted>)" | sha256sum | cut -d' ' -f1`

`/review` recomputes that digest from the change set it resolved at step 4 and compares both
halves. A mismatch means the critics reviewed a different build, and the gate fails naming the
files no critic saw.

It exists because the review prompt's `[r]` branch means exit, fix, re-run. Fixing is the point,
so **every remediation produces a build the record predates.** Observed live: three hard-block
gates failed, the operator chose `[r]`, eleven files changed including a deleted branch and a new
fixture shape, and the re-run would have read the same record and passed — the gate that asks
whether the build was challenged answering yes about the build before the fix.

The shas were already here. Each component records its rev range at step 4 below, and that range
sat in the record as prose nothing parsed. The fact was present and no code read it, which is the
shape of nearly everything this gate has had to grow.

After a remediation, re-run the rung over the delta — the same delta-scoping the later rounds
already use — and write the record again. Both halves move together: a new critique and a new
identity.

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
4. **Realize the file list**, scoped to THIS round. Round 1's base is `<component>.before`;
   every later round's base is the **previous round's `.after`**, never the component base.
   `git -C <codePath> diff --name-only <base-for-this-round>..<after> >
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

   **From round 2 on, also hand it every `remedy` from the previous round's blocking findings** —
   the ones the repair under review was answering; a round runs up to three lenses and can raise
   several — and ask it to rule on whether the repair matched them.
   `agents/wo-critic.md` carries what to do with it. Round 1 has no previous remedy and gets
   none. This is the only independent check on `beyond_remedy`, a field the repair's own author
   writes; without the remedy in this dispatch that field is self-report with nothing behind it.

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

## Each round reviews its own delta, not the whole component again

Round 1's range is `<component>.before..<component>.after`. **Every later round's base is the
previous round's `.after`.** A repair round that re-diffs from the component base hands three
critics every line they already reviewed, and they find new things in old code every time, so
findings accumulate instead of converging on what the repair actually changed.

Measured on the run this rule came from: five rounds re-diffed the whole component from base and
none came back clean. The sixth scoped to the delta and was the first non-blocking round of the
six. The build's own orchestrator named it — "five rounds of critics re-reading already-reviewed
code is a large part of why findings never converged."

Keep each round's `.after` sha. It is the next round's base.

**What this gives up, and nothing currently covers it.** A critic seeing only the delta cannot
judge whether the repair fits the component as a whole, and no pass in this framework answers
that: `wo-critic` only ever sees one unit's diff, on both build paths, while the alignment axis
and the deterministic gates judge the whole change without an adversary. Delta-scoping trades a
known cost — findings that never converge because every round re-reads reviewed code — for a
gap that was already there. Do not read the trade as a transfer.

## The finding says what would fix it (v5.36.0+)

Every `critical` and `concern` finding carries a `remedy`: the smallest change that resolves it,
naming every site it must touch. A finding asserting a class of defect backs the claim with an
enumeration, and a search that was not exhaustive says so. `deferred[]` entries carry none, since a
remedy for code that does not exist is the speculative fix the deferral exists to prevent. The
rules live in `agents/wo-critic.md`; the shape is documented in
`skills/work-order-critique/references/critique-envelope.md` as well, and the two move together.

It exists because of what the next section could not do. The repair rules below ask the builder to
keep a repair minimal and to explain growth, and the builder is the only party in that transaction:
it counts its own lines and writes its own reason, and the gate checks that a sentence exists.
Nobody who saw the defect ever stated what fixing it should have cost, so there was nothing for a
repair to be wrong against.

Two live failures fall out of that gap. One repair answered a one-line concern with 277 lines and a
new public interface method, and authored 6 of the 10 criticals raised in the rounds after it. And
round 1 named the correct defect class 71% of the time while binding nobody: where a class statement
claimed uniqueness the claim was false, which excluded the sibling sites by construction, so the
fixer changed one place and the rest surfaced a round later. One sentence, written by the party with
no stake in how long the repair takes, answers both.

`scripts/wo-critique-aggregate.sh` reads only `.severity` off a finding, plus a type check that the
finding is an object at all; it copies the whole object into the envelope, so the added keys ride
through untouched and reach the envelope. Verified by running the kernel on old-shape and new-shape
verdicts at identical severities and comparing the envelopes, rather than by reading the script. The
kernel's own header comment carries the shape too, and moves with the other two sites.

## A finding built on a number states its threshold (v5.36.0+)

When the argument for acting on a finding is a measurement, it carries
`measured {quantity, value, threshold, matters_because}`. Otherwise `measured` is `null`.

Three critique rounds went to an import arrangement justified by a "130x" ratio. The value was
about 90 ms: under the point where a person notices anything, and faster than two of that project's
own dev dependencies. Every one of the three re-measurements improved the accuracy of the number.
None asked whether the number mattered.

That is not a severity problem — 89 concerns across the corpus cost zero rounds, and the concern
gate sorted them correctly. It is a relevance failure, and nothing in this rung asked about
relevance at all. So a ratio, multiple or delta is not admissible on its own; the measured value is
reported in its own units and compared against a threshold sourced from outside the measurement. A
value that does not cross its threshold is not a finding. A threshold that cannot be established
leaves the finding a `concern` carrying `threshold: null`, and never `unresolved` — an undetermined
verdict is blocking at every tier under `--required`, so calling it that would halt the build on the
exact case this rule exists to stop costing anything.

**The rule stops at measurements, deliberately.** "Every finding must justify its worth" applies to
all of them and is satisfied by a sentence, so nothing could fail it. Measurements are where the
rounds were actually spent and the only version that can come back false. A finding that is true,
worthless and unquantified is not covered here, and is not claimed to be.

## Repair the minimum, and defer what cannot be answered yet

Two rules, one cause. The churn was never the critics.

**Growth during repair.** Each round the builder answered a `concern` with new mechanism instead
of the smallest fix, and every new mechanism was fresh attack surface. A method that did not
exist before one round's repair collected 38 of the 58 findings raised in the three rounds after
it; production code grew 72% across the loop while behaviour stopped changing after round 3.
Record `repair_growth: {net_lines, beyond_remedy, reason}` on each repair round, measured against
the previous round's checkpoint. Growth with no reason fails. Growth is allowed; unexamined
growth is not.

**The repair does the remedy (v5.36.0+).** Line count alone was the builder judging the builder:
it produced the number and wrote the sentence, and the gate checked that a sentence existed. With
a `remedy` on the finding there is an independent statement of what the repair should have been,
so work outside it is sorted rather than excused. `beyond_remedy` names the bucket, independent of
`net_lines`, because a repair can exceed its remedy while shrinking a file:

| The extra work is | `beyond_remedy` | What happens |
|---|---|---|
| Nothing; the repair did the remedy | `none` | Proceed |
| Needed to make the remedy work at all | `remedy_insufficient` | Do it, and record what had to be added, so the critic's statement is corrected rather than quietly exceeded |
| A different defect noticed in passing | `new_finding` | Record it in `repair_growth.finding` and leave it. Do not fix it in this repair |
| An improvement the finding did not ask for | no value exists | **Refused.** A record naming one is malformed, not explained |

Anything but `none` needs a `reason`, whatever `net_lines` says. `new_finding` with an empty
`finding` fails the same way a deferral with no `blocked_on` does, and for the same cause: the
bucket exists so a defect noticed during a repair is kept rather than lost.

**The refusal holds in both run modes**, which is what makes it a bound. "Do more and write a
reason" documents scope creep instead of stopping it, and on an unattended run nobody reads the
reason before the code lands. The third bucket is why the refusal is affordable: a builder that
sees a real problem is not told to ignore it, it is told that noticing is a finding and fixing is a
repair, and that the two do not travel together. Without that valve the refusal would push genuine
defects into silence, which is worse than the churn it prevents.

**From round 2 on, hand the critic the previous round's remedy** with the delta and ask it to rule
on the match. A mismatch is a finding like any other. The bucket is still self-reported and a
builder writing `none` untruthfully defeats it, exactly as `rounds` is defeated; what changed is
that doing so requires writing a false record where before it required nothing. Round 1 has no
previous remedy and is unaffected.

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
| `changed[]` disagrees with the baseline on disk | fail | `true` | 1 |

**`changed[]` is re-derived, not read (v5.35.1+).** The gate runs `contract-baseline.sh diff`
itself and compares the result against what the record claims. They must agree. This closes a
gap that only a live record exposed: one asserted `changed: []` and, in the same object, a
`reason` arguing at length that the empty diff was "true and meaningless" -- while the diff on
that same folder returned `status: changed` and named two architecture files a later round had
rewritten. Both the count and the argument built on it were wrong, and the rule directly beneath
(a changed file needs a reason) keys on that count, so it could not fire. The measured set is
also what the reason requirement now keys on, so a record cannot under-report its way past it.
When no baseline exists, or the diff cannot run, the gate records `contract_recheck` as
`unresolved` or `unavailable` and manufactures no agreement in either direction.

**What changed after the last critique pass? (v5.35.3+)** The record carries `closing_fixes`
`{applied, verified_by, reason}`. `applied: 0` passes. `applied > 0` needs a named `verified_by`,
and when that names the fix's own author, or nobody, it needs a reason as well. The match is on the
word anywhere in the string, not the whole string, because the honest answer is usually mixed:
the first real use of this field recorded two fixes read by a fresh context and four resting on
the author's own tests. An exact match let that answer through without a reason, which made the
check unable to fire on the most truthful thing a build can write.

The rung critiques a build, findings come back, and the findings get repaired. On the path where
that repair is the last thing to happen, nothing critiques it: under per-component rounds the
next round sees the repair, but under a single closing pass there is no next round, so the code
that ships is not the code any critic read.

Neither hypothetical nor rare. One live record invented
`rung_resolution.closing_fixes_not_critiqued: true` because the situation existed and this schema
had no field for it, an ad-hoc key that appears nowhere in this plugin and that nothing has ever
read. On the build that produced this rule, six fixes landed after all three lenses returned,
including a critical in the branch deciding whether published content gets unpublished, whose fix
was written by the same agent that wrote the bug. The orchestrator dispatched a fresh-eyes
verifier by hand, correctly, and nothing in the framework asked it to.

The author of a fix is the one person who cannot independently confirm it. Shipping without that
confirmation stays allowed; doing it silently does not.

**Was the component ever run? (v5.35.2+)** Each `components[]` row carries `runtime`:
`executed`, `static_only`, or `not_run`, and the last two need a non-empty `runtime_reason`.

Every gate this rung fires can pass over code that has never been executed. Live, a Drush command
class shipped with phpcs clean, phpstan clean and 58 kernel tests green while its attribute
discovery, option parsing and output were entirely unproven, because installing the module to
exercise the command would also have armed a cron hook that unpublishes site content. Declining
to run it was the right call. The defect is that the decision lived in a chat window and the
record said nothing, so `/review` would have gone green over a component nobody had run.

This is not a demand that everything be executed. Static-only verification is legitimate and
sometimes the only safe option. What is refused is leaving it unsaid.

**Can each criterion be verified by anything shipped? (v5.35.2+)** When the alignment axis runs,
it carries `criteria_unverifiable[]`, each entry `{criterion, reason, what_would_verify}`. An
empty array is required and is an answer: every criterion has something shipped that could prove
it. Absence is fail-closed.

`criteria_not_implemented` says a criterion has no code behind it yet. It was also being used for
a fact it cannot express: a criterion that no test at the level this design chose can verify at
all. Live, a criterion asserting a count of the site's actual content sat against a test strategy
that selected kernel tests, which run on an empty database and cannot observe it at any level of
effort. Nothing surfaced that until a critic was briefed by hand at the end of the build, which
is the most expensive moment to learn it and the furthest from the design decision that caused
it. The two facts have opposite remedies, one being "write the code" and the other "the plan for
proving this is wrong", so they get separate fields. `what_would_verify` is required because
naming a gap without naming the fix leaves it exactly where it was found.

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
| `components[]` | array | One row per component: `component`, `risk_tier`, `lenses[]`, `verdict`, `blocking`, `checkpoint_before`, `checkpoint_after`, `critique_ref`, `findings_count`, and `runtime` (v5.35.2+). |
| `components_declared` | integer or array | How many components the architecture declares. An array of component names is accepted and its length is the count. |
| `components_critiqued` | integer or array | How many actually got a critique. Same two shapes. |
| `uncritiqued[]` | array | `{component, reason}` for every declared component with no critique. **Every entry needs a non-empty `reason`.** |
| `alignment` | object | `{verdict, missing_requirements[], scope_creep[], spec_ref}`, or `{verdict: "skipped", reason}`. |
| `tdd` | object | `{red_observed, passed_first_run, unobserved[], reason}` — the RED-observation half, from loop step 4, aggregated across the whole phase (v5.34.0+, required). See above. |

**`components_declared`, `components_critiqued` and `uncritiqued[]` are all three required,
and a partial run must not be able to read as a complete one.** A rung that critiqued three of seven components and
recorded only its three green rows is a record that cannot say what it did not look at,
which is the failure this framework keeps finding in itself. Any gap is named in
`uncritiqued[]` with a reason.

**A reason per gap, checked (v5.35.1+).** Until v5.35.1 the gate printed "N left uncritiqued
with reasons" and no code read a single one, so the sentence above was a convention rather than
a rule. An entry naming a component and saying nothing about why it was skipped now fails. A
bare string in place of an object fails for the same cause: it can carry no reason. This is the
mechanism that forces a deviation from one-component-per-rung into the record, because a build
that critiques its components together owes a reason for each one it did not critique alone.

**Both count fields accept two shapes (v5.35.1+).** A number, or the list of component names
whose length is that number. A live record wrote the list form and every arithmetic test against
it printed `integer expression expected` to stderr and evaluated FALSE, silently disabling the
check beneath: seven declared, none critiqued, and the gate could not fail on it. A shape that
is neither collapses to the omission failure, which is the honest answer for a field the gate
cannot read.

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
