# Cost model — what a reuse / extend / supersede verdict is comparing

Loaded at step 4, once there is an actual candidate to judge. A verdict is a cost comparison, not a
code-quality score. Costs are paid on different schedules, and grouping them by *when they're paid*
is what makes a candidate and the task's own plan comparable at all.

## The four classes

**`build`** — paid once. Implementation effort to reach working, plus what each new dependency costs
going forward: an upgrade treadmill, a license, an abandonment risk. This is the cost everyone
estimates first and the smallest one in most decisions.

**`carry`** — paid on every change. Change amplification (one requirement change touching N places —
duplication multiplies this directly and permanently), test cost, blast radius, comprehension time.

**`agent`** — paid on every session. Token economy (how much must be read to change this safely — a
capability spread over two implementations costs double the read before a line is written), the
ambiguity tax (a human learns which implementation is canonical once; an agent rediscovers that from
scratch every session and pays the tax forever), wrong-target risk (a patch lands on the wrong copy
and the bug survives, now in two shapes).

**`risk`** — paid on incident. Security surface (attack surface multiplies with implementations), the
performance ceiling the design forecloses, reversibility, operational weight (a daemon, a service, a
thing that pages someone).

Duplication is strictly more expensive in an agent-driven codebase than in a human one — an agent
pays the ambiguity tax on every task, not once. That is the strongest argument for running this search
at all.

## Naming a dimension: `{class, name, kind, value}`

Each dimension you cite in a hit's `dimensions[]` needs a `class` (one of the four above), a short
`name`, a `kind` (`measurable` or `judgment`), and — when `kind` is `measurable` — a `value`.

| Measurable | Judgment |
|---|---|
| context size / tokens to load the implementation | coupling |
| test coverage and testability | comprehension effort |
| call-site count a change would touch | reversibility |
| dependency count and advisory status | performance ceiling |
| benchmark on a representative operation | security posture beyond known findings |

Whether the cited number is the *right* number stays judgment — that's fine, and the record should
say so. What isn't optional is naming what was compared. "The new approach is better" with nothing
behind it isn't a verdict, it's an assertion borrowing authority it hasn't earned. The repo's standing
lesson applies here directly: a check that cannot fail cannot inform, and neither can a verdict that
cites nothing.

## Why the default leans reuse

`build` is paid once. `carry`, `agent`, and `risk` are paid forever. A candidate has to beat the
task's own plan on a **recurring** dimension, not the one-time one — "I would have written it
differently" is a build-cost preference and isn't sufficient on its own.

**What the kernel actually enforces, which is coarser than this model.**
`scripts/prior-art-disposition.sh` sees only dimension *classes*, not whether a dimension is
measurable or judgment: its grammar is `--dimensions "class:name,..."` plus `--measured` and
`--absorbs`. So it catches a supersede argued only on `build`, and it catches one with nothing in
`--measured` at all. It cannot detect an all-judgment set as such. That gap is closed by *your*
honesty, not by the kernel: when nothing was measured, `--measured` must be left empty, and the
kernel then rejects. Do not report a measured value you did not measure. See the citation-floor
section of `references/internal-prior-art.md` for the authoritative description.
or only `judgment` dimensions gets downgraded to `extend`, no matter how the case is argued in prose.

## The supersede trap

A supersede whose migration gets deferred creates exactly the duplication this search exists to
prevent: judge the new implementation better, put off migrating the old one, and the codebase now
holds two. The verdict caused the bug it was meant to catch.

So a supersede carries a build constraint, not only a recording obligation:

> **The new implementation must be able to absorb the superseded use case.** It's judged as the
> replacement target. If its design can't serve the old caller, it isn't a better replacement — it's
> a second implementation with better opinions, and the verdict is **extend**, not supersede.

State this as `absorbs_superseded_use_case` in the hit. `false` forces the effective verdict to
`extend` — the caller's disposition kernel enforces it, but the judgment call is made here, honestly,
at the point where the evidence is actually in front of you.

A settled supersede is never silently applied. It's either an explicit in-task decision to refactor,
or a linked follow-up task for the migration — that's the caller's job once disposition has run, not
this skill's, but the verdict you hand back is what makes that downstream step possible or not.
