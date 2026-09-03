# The build-critique rung — challenging a build while it can still change

Phase 3 contract for the two questions a builder cannot answer about its own work:
**is this sound** (adversarial) and **is this what was asked for** (alignment).

## Why this exists

Both agents already existed. Neither could reach an in-session build.

`wo-critic` — fresh context, hostile-diff posture, three lenses — fires only inside
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

After a remediation, re-run the rung over the delta: the remediation's own range, never the
component base. Write the record again. Both halves move together: a new critique and a new
identity.

**This is the one exception to one critic round per component, and it is not a loophole in it.**
The rule binds inside the build: no critic is dispatched again to judge a repair it asked for, so
a finding cannot buy a second opinion on its own fix. A `/review` remediation is a different
thing. The phase closed, a later gate found something the rung did not, and the fix answers that
gate rather than a critic. It opens a new `build_identity`, so the component's round count starts
from zero on a record that is honestly a different record. A remediation is not a repair round,
and counting it as one would mean the rule forbids fixing what review finds.

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
4. **Realize the file list.** The base is `<component>.before` and there is no other base: a
   component gets one critic round. `git -C <codePath> diff --name-only
   <component>.before..<after> > <task_folder>/build-critique/<component>.files.txt`. The
   classifier takes a file list, not a rev range.
5. **Tier.** `wo-risk-classify.sh --files-from <that file> --gate-floor
   "tdd,solid,dry,security,guides"`. **`--gate-floor` is required here.** It normally comes
   from a work-order's frontmatter; a component has none, and the classifier tiers everything
   `high` when both the work-order file and the flag are missing. The value is the
   `base_gate_floor` from `references/risk-tiering-rules.json`, so a component is tiered on
   what it changed rather than on a missing input. Read `.risk_tier` from its JSON.
6. **Lenses** from that file's `tier_lenses`: `low` → `correctness`; `medium` → `security`,
   `correctness`; `high` → `security`, `correctness`, `meets-ac`. A security lens is
   guaranteed at `medium` and above, so executable code always gets one.
7. **For each lens, dispatch ONE `ai-dev-assistant:wo-critic`** via the Task tool — fresh and
   independent, never a fork, or the critique inherits the reasoning it exists to challenge.
   Hand it what the existing contract specifies: `<worktree>` (the project's `codePath`), the
   `<before>..<after>` range, the component's acceptance criteria as injected content, its
   lens, the methodology block, and its output path
   `<task_folder>/build-critique/<component>.critics/<component>.critic-<lens>.json`.

   **The methodology block goes to all three lenses**, `meets-ac` included, unlike the resolved
   recipe, which `security` and `correctness` receive and `meets-ac` does not. It carries the
   test-first material the build was held to, so a critic can tell a repair that met the standard
   from a change that moved it — a builder can answer a finding by rewriting what a test asserts,
   `repair-accept-check.sh` demands a reason for that and never forbids it, and judging which one
   happened needs the rules for what a sound test is. `/implement` loads those into the build and,
   until this block, into nothing that judged the build. It is one named section of
   `references/tdd-workflow.md` plus any already-loaded `development/tdd-spec-driven/*` guide,
   **never** the whole file — the rest of it is build-time procedure a critic cannot act on — and
   **never** the task folder, which is the one place the builder's own account of its tests could
   reach a critic. The full rule, for
   both dispatch paths, is in
   `skills/work-order-critique/references/critic-prompt-contract.md`.
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

- `blocking: true` → the component stops. `[a]ddress` (fix, then record the accept verdict,
  which is where the component ends) or `[o]verride (reason)`, recorded in `bypass_reason`. The
  build does not move to the next component.
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
test is wrong (`passed_first_run`) — passed because the code it describes already existed
(`ratified`, v5.46.0+) — or nobody ran it (`unobserved`, legal only with a reason).
`references/tdd-workflow.md`'s "Who runs the tests, and what has to be recorded" is the source
of these four values and of the rule that `unobserved` is a real, writable value rather than
something silence implies.

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
`{red_observed, passed_first_run, ratified, unobserved[], reason}`, counted and named across
every criterion built the whole phase. `gate-audit-write.sh` lists `tdd` in `build-critique`'s
REQUIRED_KEYS, the same non-blocking check it runs against `phase`, `verdict`,
`components_declared`, and the rest — absence gets a warning on stderr and the file is
written anyway. The enforcement that actually stops a review is downstream, in
`scripts/build-critique-assert.sh`, run by `/review` step 5.0f:

| Payload state | Verdict | `unresolved` | exit |
|---|---|---|---|
| `tdd` key absent | fail | `true` | 1 |
| `red_observed` / `passed_first_run` / `ratified` / `unobserved` — any missing | fail | `true` | 1 |
| `passed_first_run > 0`, no `reason` | fail | `true` | 1 |
| `passed_first_run > 0` with a `reason` | pass | `false` | 0 |
| `unobserved` non-empty, `reason` empty or absent | fail | `true` | 1 |
| `unobserved` non-empty, `reason` populated | pass | — | 0 |
| `ratified > 0`, any value | pass, count surfaced in `messages[]` | — | 0 |
| all present, `unobserved` empty | pass | — | 0 |

**Two different things pass on a first run, and only one is a defect.** A test written
test-first that passes immediately is `tdd-companion`'s named violation: it asserts nothing
about the behavior it claims to test, and lands in `passed_first_run` with a `reason`. A
characterization or regression test written deliberately against code that already exists
passes on its first run by design, and is worth having — locking in behavior, or reproducing a
defect a critic just found. As of v5.46.0 that second kind lands in `ratified`, which owes no
reason and never blocks. Until then both shared `passed_first_run` and the `reason` said which,
so the count that says how much of a suite could not have found anything was folded into the
count that says the suite is broken.

v5.34.0 failed both with no reason path at all. A live build hit it immediately: several tests
added during repair rounds were written against existing code and passed first time, and the
rule would have made the honest record a violation. A gate that punishes the true answer
teaches a builder to write a different one. As everywhere else in this rung, the gate checks
that the question was answered, not that the answer is true. **Applies to the in-session build
path only** — see below.

## What a repaired component records

A component gets at most one critic round, so there is no `rounds` count and no `rounds[]`
history. Three fields on the component row carry what a reader of the record needs.

**`checkpoint_repaired`** is the sha `build-checkpoint.sh capture --label <component>.repaired`
returned at the end of `[a]ddress`. It is captured there and nowhere else, so a non-null value IS
the fact that the repair path ran for that component, and it is what `build-critique-assert.sh`
reads to decide who owes an accept verdict. A row that omits it on a repaired component is a
repair the gate cannot see. A value that is neither a sha string nor null is a repair state
written down and unreadable, reported as unresolved rather than folded into the clean set.

**`deferred[]`** carries `{finding, blocked_on, why_now_is_wrong}` for each finding only a later
component can answer. The check reads it off the component rows, and an absent key yields an empty
list, which passes silently, so a build that defers a finding and writes none has recorded that
deferral nowhere any gate can see it.

**`accept {action, suite, decided_by, reason}`** is owed by every component carrying a
`checkpoint_repaired`. One with no `accept` is `unresolved` at `/review`, and any action other
than `accepted` needs the decision to ship it in the record's top-level `escalation.reason`.

The checkpoint is not merely the signal that survived the round count; it is the stronger one. On
the last record built while the count still decided this, `rounds > 1` named 2 of 14 components
while 13 of 14 carried a repaired checkpoint. Eleven repairs owed an accept verdict under the
contract and none under the check.

## The accept verdict is the closing condition

Every `[a]ddress` ends with one, and the component ends there. `scripts/repair-accept-check.sh`
runs over the repaired tree and its verdict goes on the component row as
`accept {action, suite, decided_by, reason}`. No critic is dispatched again once it is recorded.

A round count was a proxy for a closing condition and never the condition itself. So is a ceiling
on that count: both answer "how many times did we go round" when the question is whether the
repair answered what was found. What closes a component is the accept verdict plus the two set
comparisons `scripts/repair-scope-check.sh` makes over the repair diff: `unnamed`, files the
repair touched that no finding named, and `unaddressed`, sites a finding named that the repair
never touched. One critic round per component is what that buys: the two questions a second critic
was there to answer are now asked on every repair, by something that cannot be talked out of its
answer.

What the trade costs is stated in `agents/wo-critic.md` and is not re-argued here. A set
comparison sees paths, never intent: it cannot tell a named site the repair deliberately left
alone from one it forgot, and it cannot see a repair that edited the right file and fixed
nothing.

**The kernel runs nothing.** It compares two facts the caller hands it: the suite result over the
repaired tree, and the test motion the repair made as `git diff --name-status` over the repair's own
range, which is the sha the component's `.after` checkpoint captured to the post-repair head, and
not the range of the build being critiqued. Both ends are shas: a checkpoint label is not a revision, so
`git diff` handed one exits 128 with the redirect's file already created and empty.

`accepted` means the suite was green and the motion raised nothing unanswered. `not_accepted` means
the suite was red, or a test file was modified with no `--modification-reason`; the tripwire demands
a reason for a modified test, it never forbids the change. `cannot_judge` has three causes: the
motion file was zero bytes, no suite was run over the repaired tree, or the caller could not
establish what a test path is here. The first exists because an empty diff carries no claim. A
caller who knows there are no test paths says `--test-globs '[]'`, and one who cannot tell says
`--test-globs-source undetermined`, so a file with nothing in it means either the diff failed or the
repair changed nothing, and neither is a repair that moved no test.

**`cannot_judge` is not a pass.** It is the answer for nobody looked, and folding that into a clean
result is the defect this framework has now found at five layers. Nothing halts on it: `blocks` is
always false and the repair goes ahead. The demand lands on the record instead. A
component that ends on anything other than `accepted` needs the decision to ship it in the
record's top-level `escalation.reason`, and a repaired component carrying no `accept` verdict at
all is `unresolved` at `/review`.

**One recorded decision clears every unaccepted component in the record.** The gate reads the
decision once from the whole payload, as the top-level `escalation.reason`, trimmed before it is
judged blank so that a decision of one space is no decision. Ten components ending `not_accepted`
are satisfied by one sentence written about one of them, and the message then prints that one
reason beside the count of ten. The gate does not check that the decision it found is about the
component it cleared, and nothing downstream does either.

There is no per-component slot left for that decision. The per-component form was a `resolution`
on the `rounds[]` entry that settled the component, and no `rounds[]` is written; `accept.reason`
says what drove the kernel's action, not who decided to ship a component the kernel did not
accept. `scripts/accept-verdict.sh` still falls back to the last `rounds[].resolution` when the
top-level reason is blank, and finds nothing on any record written since. **That fallback stays
on purpose and is not dead code:** `/review` reads records it did not write, and a task built
under v5.42.0 to v5.46.0 carries the array. Retrofitting those records is a stated non-goal, so
the reader is how they stay readable. So name the component inside the sentence you write into
`escalation.reason`. It is the only place that decision now exists, and giving it a per-component
slot is a mechanism nobody has designed yet rather than a wording problem.

**All four fields are read, not just `action`.** `suite` must be `green`, `red` or `not_run`,
`decided_by` must be `suite_and_motion`, `motion` or `none`, and `reason` must not be blank. Absent
or off-enum is `unresolved`, the same answer a missing verdict gets: a verdict that cannot say what
suite result it weighed, or what settled it, or why, is not a verdict. All three are values
`repair-accept-check.sh` returns on every run, so recording them is transcription, not judgement.

**What it cannot see.** `suite: green` is a value somebody typed, not a suite this kernel ran, and
nothing on disk tells a self-reported green from an observed one. On one live build phpcs, phpstan
and phpunit all passed over a repaired tree that still carried two criticals a later critic found:
the suite is a floor, not a proof, and `accepted` means these two facts raised no objection rather
than that the repair is right. Motion is A / M / D, so a test modified in a way that weakened it, an
assertion loosened or a case cut from inside a file, arrives as an ordinary `M`; the reason string
is the only thing carrying direction and nothing here checks that it is true.

## One range for the critics, and the repair diff for the repair

The critic range is `<component>.before..<component>.after` and there is no other base. Nothing
re-diffs a component for a second read, because there is no second read.

Measured on the run this rule came from: five rounds re-diffed the whole component from base and
none came back clean. The sixth scoped to the delta and was the first non-blocking round of the
six. The build's own orchestrator named it — "five rounds of critics re-reading already-reviewed
code is a large part of why findings never converged." Handing critics code they already reviewed
makes them find new things in old code, so findings accumulate instead of converging on what the
repair changed. That measurement is why the rounds are gone rather than why they are scoped.

Delta-scoping survives where it is still needed, on the repair diff. `<component>.after..$REP` is
the range the accept verdict and both set comparisons are computed over, and it is the repair that
gets scoped now, not a later critic round.

**What this gives up, and nothing currently covers it.** No critic ever reads the repair. A critic
sees one unit's build diff, on both build paths, while the alignment axis and the deterministic
gates judge the whole change without an adversary; the repair itself is read by two set
comparisons over paths and by nothing that reads it as code. `closing_fixes` below is the field
that asks who did, and it is a self-report.

## The finding says what would fix it, and where (v5.36.0+, extended by `finding_contract`)

Every `critical` and `concern` finding carries a `remedy`: the smallest change that resolves it, as
a sentence. The sites it touches live in `where[]`, one `{file, line, symbol}` entry per site —
every site the finding names, not one example standing for the rest. A finding asserting a class of
defect backs the claim with that enumeration, and a search that was not exhaustive says so.
`reachable_by` names who can trigger the finding and what they already hold, required when the
critic file's top-level `lens` is `security`. `id` is the handle a later finding's `extends` points
at, when another critic on the same component names a further site of the same defect and it
should read as one finding rather than two; the kernel appends those sites and marks the
referenced finding `under_enumerated`. `deferred[]` entries carry none of `where[]`, `remedy` or `reachable_by`,
since a remedy for code that does not exist is the speculative fix the deferral exists to prevent.
The rules live in `agents/wo-critic.md`; the shape is documented in
`skills/work-order-critique/references/critique-envelope.md` and
`references/gate-audit-schema.md` as well, and all three move together.

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

**A defect that got through a check is a class, and the remedy enumerates the inputs.** Rule 4 in
the agent body. It is the same rule as the site enumeration above, pointed at inputs rather than
code: a check that let one input past almost never lets only that one past, so the remedy lists
every input that reaches the same hole and the repair closes the list.

This one was measured on the build that added it, which repeated the same exchange three rounds
running. A critic named one record that slipped through a gate; the repair closed that record; the
next critic found a variant still slipping. Three rounds, one defect, three instances. Every repair
was small, stayed inside its remedy, and was still wrong — so bounding the repair does nothing about
it. The remedy named an instance where the defect was a class.

**What this half cannot do.** Nothing checks that an enumeration is complete, and nothing can: a
gate reading a record has no way to know which inputs reach a filter it is not looking at. What the
rule buys is that the fixer is now bound by a list somebody else wrote, which is the same thing the
remedy buys, and each entry in the list becomes a case in a spec that `make test` then holds. It is
prose, and its evidence is three rounds on one build.

`scripts/wo-critique-aggregate.sh` reads `.severity` off a finding, plus, since `finding_contract`,
a shape check against the required fields in `references/gate-audit-schema.md`: `where[]` and
`remedy` on `critical` and `concern` findings, `reachable_by` when the critic file's `lens` is
`security`, `id` on every finding. A finding that fails the check makes the whole critic file `unresolved`, recorded per file
rather than per finding, so a critic cannot pass with its worst finding silently dropped. The check
itself is gated on the critic file's own `schema_version`: absent means pre-contract, and the file
gets the lenient, pre-`finding_contract` reading instead. Whatever the check decides, the kernel
still copies the whole finding object into the envelope untouched, so any key beyond the required
ones rides through unread. Verified by running the kernel on old-shape and new-shape verdicts at
identical severities and comparing the envelopes, rather than by reading the script. The kernel's
own header comment carries the shape too, and moves with the other two sites.

## A finding outside the component's range is moved, not dropped (v5.45.0+, `finding_contract` c5)

A critic reads the component it was handed and sometimes names a defect somewhere else. That
finding is true and it is not this component's repair round: opening one against it makes the
builder change code no critic in this run reviewed, on a slice nobody scoped.
`scripts/wo-critique-aggregate.sh` is handed the component's own file list on
`--component-files-from`, and a `critical` or `concern` finding whose `where[]` sites all fall
outside that list is marked `out_of_range: true`, is left out of the severity that decides
`blocking`, and is copied whole into the envelope's top-level `out_of_range[]`.

**The array is the channel, and this is the reader at the other end of it.**
`scripts/build-critique-assert.sh` walks each `components[].critique_ref`, reads `out_of_range[]`
off every envelope it can resolve, and surfaces the count in `evidence.out_of_range_findings` with
the sites in `evidence.out_of_range_sites` and a message naming both. It surfaces and never blocks,
the same posture as `deferred_findings`: the finding is real, it is about code outside the slice,
and the reviewer decides where it goes. Without that reader the suppression would be the finding
vanishing rather than moving, which is what `references/gate-audit-schema.md` says it must not be.

**Absence is not a clean answer at either end.** The kernel writes
`range_check {status, decided_by, reason}` and stamps `not_run` with a reason whenever no
comparison happened — flag absent, list unreadable, list empty — and suppresses nothing in that
case, so an empty `out_of_range[]` beside `not_run` means nobody looked rather than nothing was
found. The reader holds the same line: a `critique_ref` that does not resolve to a readable JSON
object is counted in `evidence.out_of_range_unreadable_refs` and said out loud as unknown rather
than folded into a count of zero. A readable envelope carrying no `out_of_range` key claims
nothing and adds to neither count, which is every record written before the field existed.

**The verdict drop is bounded.** `agents/wo-critic.md` defines a critic file's own `verdict` as
the max over its findings, so a file whose findings are all out of range carries a verdict that
summarises only suppressed findings, and the kernel drops it. It drops it only when the verdict is
one of `pass`, `concern` or `critical` and ranks no higher than the worst suppressed finding. An
`unresolved` or unrecognised verdict is never dropped: `unresolved` means the critic could not
investigate, which is a separate signal with nowhere else to live, and a verdict ranking above
everything the range check judged is claiming more than the suppressed findings said.

## A finding whose only fix is a different design is moved, not repaired (v5.51.0+)

The sibling of the range check above, with the same routing and a different trigger. A critic
sometimes finds something whose smallest honest fix is not a change to this code but a change to
the mechanism the component's design named. Opening a repair round against that asks the builder
to rewrite the standard it is being judged against, in the same session, with nobody else reading
— and a repair loop whose subject can edit the standard always converges, because the work can
move the goalposts instead of meeting them. `scripts/contract-baseline.sh` catches the edited
design at the close of the phase, after every round it caused has already been spent.

So the critic marks it. A finding carrying `design_change: true` is dropped from the severity that
decides `blocking`, opens no repair round, and is copied whole into the envelope's top-level
`design_change[]` with its `remedy` — the remedy is the trigger, and a reviewer weighing the
finding against the design cannot read the record without it.
`scripts/build-critique-assert.sh` walks the same `components[].critique_ref` list it already
walks for `out_of_range[]` and surfaces the count in `evidence.design_change_findings` with the
sites in `evidence.design_change_sites`. It surfaces and never blocks, the same posture as
`deferred_findings` and `out_of_range_findings`: the finding is real, the disagreement is between
it and the design, and the reviewer is the one who decides which gives way.

**The trigger is the critic's, and it is the remedy.** `agents/wo-critic.md` states it as one
sentence — the flag goes on when the critic's own `remedy` cannot be applied without changing the
mechanism the design names — and rules out the three things it is not: a severity, an opinion of
the design, and a way to raise a departure the design already forbids (that last one's remedy is
"do what the design says", which fits the mechanism perfectly). The kernel cannot compute this.
Whether a remedy fits a mechanism is a reading of the design, so the dispatch hands every lens the
design body, and this route is only as real as that wiring.

**It grants the critic no authority it did not have.** A critic that wanted a component not to
block would write `verdict: "pass"` and file nothing, which is cheaper than marking a finding.
Only the JSON literal `true` suppresses; a string, a number and a null all leave the finding
blocking exactly as before, so every unrecognised value fails toward opening the round.

**Absence is not a clean answer here either, and the kernel does not pretend otherwise.** An empty
`design_change[]` means no critic marked one. It does not mean a critic was given a design to mark
against — the kernel never sees the dispatch, so it claims neither, and
`tests/build-critique-wiring-spec.sh` is what asserts the design reaches the critic on both paths.

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
value that does not cross its threshold is not a finding, and neither is one whose threshold cannot
be established at all: a measurement with no threshold behind it is a number with no argument, which
is the whole of what this rule stops. It is never `unresolved` either — an undetermined verdict is
blocking at every tier under `--required`, so calling it that would halt the build on the exact case
the rule exists to make free.

**The rule stops at measurements, deliberately.** "Every finding must justify its worth" applies to
all of them and is satisfied by a sentence, so nothing could fail it. Measurements are where the
rounds were actually spent and the only version that can come back false. A finding that is true,
worthless and unquantified is not covered here, and is not claimed to be.

## Defer what cannot be answered yet

**Findings that cannot be answered yet.** "This method has no production caller" is true and
unfixable when the caller is three components away. With nowhere to put it, the builder wrote a
specification for the absent caller — and that answer produced the next round's critical, whose
answer produced the round after. Three of the four unanswerable findings in that build were
generated by trying to close the first one. A critic now reports these in its verdict's `deferred[]` as
`{finding, blocked_on, why_now_is_wrong}`, and the builder carries them to the component row's
`deferred[]`, which is the array the gate reads. Deferred findings do not block and are re-checked
when `blocked_on` is built. A deferral short any of the three fields fails: a finding nobody will
return to is a dropped finding wearing a label.

Not machine-checkable as "was this premature". It is checkable as "did you say so", which is the
same standard the rest of this record holds.

(The checks that used to sit here, judging by self-report whether a repair grew or strayed past
what a finding asked for, are gone. `scripts/repair-scope-check.sh` answers the scope question
instead, by comparing the finding's `where[]` against the touched-file set in both directions:
`unnamed`, files the repair touched that no finding named, and `unaddressed`, sites a finding
named that the repair never touched. See the `finding_contract` design, D6.)

**What this cannot do.** Every signal it reads is self-reported. `checkpoint_repaired` is a sha
the builder captured and wrote onto the row, so a repair that captures none is a repair the gate
never asks about, exactly like every other self-reported field here.

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

The rung critiques a build, findings come back, and the findings get repaired. Nothing critiques
the repair. A component gets one critic round, so no critic reads the code a repair produced, and
the code that ships is not the code any critic read. `repair-accept-check.sh` weighs a suite
result and test motion and `repair-scope-check.sh` compares paths; neither reads the repair as
code.

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
| `components[]` | array | One row per component: `component`, `risk_tier`, `lenses[]`, `verdict`, `blocking`, `checkpoint_before`, `checkpoint_after`, `critique_ref`, `findings_count`, and `runtime` (v5.35.2+). A repaired row also carries `checkpoint_repaired` (v5.47.0+) and `accept` (v5.42.0+); `deferred[]` (v5.47.0+) is on the row of the component whose critique deferred a finding. |
| `components_declared` | integer or array | How many components the architecture declares. An array of component names is accepted and its length is the count. |
| `components_critiqued` | integer or array | How many actually got a critique. Same two shapes. |
| `uncritiqued[]` | array | `{component, reason}` for every declared component with no critique. **Every entry needs a non-empty `reason`.** |
| `alignment` | object | `{verdict, missing_requirements[], scope_creep[], spec_ref}`, or `{verdict: "skipped", reason}`. |
| `tdd` | object | `{red_observed, passed_first_run, ratified, unobserved[], reason}` — the RED-observation half, from loop step 4, aggregated across the whole phase (v5.34.0+, required; `ratified` v5.46.0+). See above. |

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
- **The work-order build path owes RED evidence too, per work-order (v5.48.0+).** It did not
  until then, and the paragraph that stood here said so: the `tdd` block lived on
  `_build-critique.json`, only `/implement`'s in-session path wrote that record, and a
  `/run-work-orders` build owed `work-orders/wo-NN._critique.json` instead, which carried nothing
  equivalent. Since the orchestration rules route real builds to delegated agents, following them
  routed every real build around this rung by construction. Measured on a live build: three
  components built, reviewed and merged with no TDD record of any kind, every downstream check
  satisfied, because each one read a record nobody was asked to write.

  Now the unit of the record is the WORK-ORDER. The delegated builder writes
  `work-orders/wo-NN.tdd.json`, the loop collects it into `wo-NN.run.json` via
  `wo-run-state.sh collect --tdd-file`, and `build-critique-assert.sh` judges the `tdd` block on
  that run record with the SAME function the in-session branch uses (`tdd_block_problems` in
  `accept-verdict.sh`), so a record satisfies both paths or neither. A work-order that owes a
  record and has none fails the review, fail-closed and `unresolved`. Which work-orders owe one is
  a union: a run record exists, or a critique exists, or the status is anything but `ready` or
  `blocked`. The full path end to end is in `references/tdd-workflow.md`, "When the build is
  delegated". Evidence keys: `work_orders_owing_tdd`, `work_orders_without_tdd`,
  `work_orders_bad_tdd`.
- **A recorded `observed` is a report of an observation, not proof of one.** Nothing in this
  rung, or in `/review`, captures the test runner's actual exit code. The record is whatever
  Claude typed into the `tdd` block after the fact. A criterion whose test never ran, or whose
  test failed for the wrong reason, or whose result was simply misremembered, still passes as
  long as the block says `observed` and the counts add up. The enforcement above closes the
  gap between "recorded" and "unrecorded"; it does not close the gap between "recorded" and
  "true."
