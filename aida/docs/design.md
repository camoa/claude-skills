# Design

Design decides how the task gets built, and writes that decision down as work orders. There is
no architecture document, no overview file, and no file per component. The work orders, and the
order they run in, are the architecture. Design writes no code and runs no test.

Run `/aida:design <task-id>`, or `/aida:design` with a task already active. With no active
project or task, design stops and names `/aida:next`. Design refuses to start until research
has closed on the task, and names `/aida:research` as the way past that. Every decision below
rests on what research found. Whether a criterion is right was scope's conversation.

## What a work order is

A work order is the unit of work: one build, one review, one commit. It is small enough that
four roles can each act on it without asking what was meant. One writes the tests from it, one
writes the code, one reviews the result against it, and one applies the fixes. Each order is one
structured file in the task folder, with a rendered copy, `design/<id>.md`, beside it to read.

A work order runs three to seven build steps, ten at most. Design splits an order whose steps
mix independent concerns. It merges two orders that each have fewer than three steps and touch
the same component. Too large, and there is no single thing to state a test about. Too small,
and a feature becomes fifty orders that cost more to coordinate than to build.

The merge is a script action, `merge`, not a hand edit. It folds one order into another. Every
list joins the survivor's without duplicates, the folded file is removed, and every dependency
that named it now names the survivor. A test that no longer belongs on an order leaves through
`remove-test`, which refuses the last test an owned machine criterion needs. Both print what moved,
so the change is on record the way every other design write is.

## What a work order declares

| Field | What it says |
|---|---|
| criteria served | The contract criteria this order contributes to. Usually several |
| criteria owned | The criteria whose observable outcome this order produces. Usually none |
| non-goals | The contract boundaries a reviewer needs in view beside this order |
| depends on | The orders that must finish first. This is the build order |
| owned files | The files or directories this order may write. Never a wildcard |
| interface | What this order exposes to the orders that depend on it |
| tests | What each test must observe, before the code exists |
| done when | What must be true for the order to be finished, in your words |
| reasoning | Why this order exists, when a decision is shared with other orders |
| diff budget | How much change the order should take, in plain words |
| proof | `tests`, the default, `gate` for a configuration order, or `record` for a document in the task folder |

Serving and owning are two lists because they answer two questions. One criterion often needs
several orders. A shared thing, such as one base class serving two criteria, is built once
because it serves both. But exactly one order produces the outcome a criterion describes, and
that order owns it. Most orders own nothing: the orders that depend on them reach them. A shared
decision lives in the reasoning of the order that builds the shared thing. The orders that use
it point at it, so nothing else drifts from it. An order whose shape a play decided names that
play in its reasoning too.

The tests are part of the order, not an order of their own. Design says what each test must
observe. It leaves the level, unit or kernel or functional in your framework's words, to the
stage that writes the test. The tests are named here because they must exist before the code
does. A test written from finished code ratifies it; one that failed before the code existed
constrains it. The diff budget is a signal to the reviewer, never a limit that anything enforces.

## What design reads first

Design reads every research finding and the plays research loaded. A finding that says nothing
was found is still an answer. Design then opens the guides and recipes research named without
reading. One recipe covering the work means the decision is made and design follows it. Two, and
design reads both and picks the fit.

Design also reads the process recipe for your framework at this stage. It holds what AIDA cannot
know on its own. What kinds of thing can an order be about here? What is built with configuration
rather than code? What has to exist beside a class for it to work, where does business logic
belong, and what build order does the framework force? No check below can see that an order is
about the wrong kind of thing, so this read has no substitute.

Design judges the recipe's fit once, before the first order. Interactively, design shows a poor
fit with the reason, and you choose: continue with the recipe, without it, or stop. Autonomously,
design continues with the recipe and records the verdict.

No recipe for your framework, a catalog that could not be reached, and a failed network are three
different answers. Design records which one happened. With no recipe, design marks every order as
written without framework input, and it invents no kind of unit and guesses at no convention.
Interactively, it asks whether to write the recipe first.

A stated approach recorded at scope is read as a claim, never as a specification. A required
claim must be followed once design judges it sound, not before. A claim edited after research
grounded it is reported as ungrounded, and it goes back to research when it matters.

Design also names things research had no reason to look for: a particular module, a framework
API, a pattern that only became a decision here. For each such name it asks the catalog which
guides and recipes cover it. It records the answer, a nothing included, as one research finding
of its own, so the same lookup never runs again during the build.

## The reuse decision

Every prior-art candidate research handed over gets an answer: reuse it as it is, extend it, or
supersede it. An unanswered candidate is a proposal nobody acted on, and that is how a project
ends up with a second chat class beside the first. A candidate is not always code; an existing
view or content type is one too, and extending it may produce no code at all.

Design decides by the candidate's distance, same name, same directory, or same layer, and by one
cost model. Build cost is paid once; carry, agent and risk cost are paid forever. Design
records the disposition on the order it lands on: the candidate, the distance, the costs
compared, the verdict and the reason. A fixed table applies. A supersede that cites only build
cost, or a candidate sharing only a layer, comes back as extend. Interactively, a supersede
stands only after you are asked, because it widens the task and owes a migration. A supersede
naming no cost dimension is refused until you say what it compared. Autonomously, a supersede
comes back as extend, with a reason in the order asking you to revisit it on an attended run.

When the order's build or tests will call the candidate, design records where it lives and what
it exposes. That is the class or service, the method the tests call, its arguments, and what it
returns. Design reads the code for this; the test author may not, so the text stands in for it.

## When design finds the scope is wrong

Drafting turns up criteria nobody wrote, and criteria that cannot be built as stated. Neither is
design's to fix alone. Interactively, design says what it found and asks, and any change to the
contract goes through scope. Autonomously, design records what it found in the order's reasoning
and continues. A recorded note reaches you; a silent change does not.

## Owned files and configuration orders

Owned files must not overlap between orders. That is what lets several orders build at once
without colliding. It is also how a reviewer knows a change was out of scope without asking. A
declared list is not a fact, though. Nothing stops a builder touching a file it never declared,
so the check compares declarations only.

An order whose deliverable is exported configuration, such as a view or a content type, writes no
test. TDD is about code, not configuration: a test that reads the exported file back restates
the file and cannot fail for the right reason. Such an order carries `proof: gate`. Its proof is
the configuration gate of your framework's implement recipe, a block of commands the build runs,
every line exiting clean. The behavioural proof lives with the order that consumes the result.

A configuration order is sized around the operation and owns every file that operation rewrites.
Deleting a field owns each display that lists it. An order that owns the field's files alone and
leaves the displays to other orders cannot import on its own, so its gate fails.

An order whose deliverable is a document, a dependency review or a report, writes no test
either. Such an order owns files under the task folder only, in a folder the project commits,
such as `deliverables/`. Never `records/`, which the project ignores. It carries
`proof: record`, and design sets that value itself once every owned file lies under the task
folder, unless you set a proof by hand. Its proof is its done-when rows. The checkpoint judges them, the build reads that
judgement in place of the tests, and the reviewer reads the document whole against them. It
lands no commit in the code repository. Its commits are the project folder's.

An order that changes a page or a screen names it from the project's surface file,
`.visual-review/surfaces.json`. When no
visual or browser test covers that kind of surface, design offers the setup once per task,
interactively only, unless you declined it. Yes runs the setup now. Not this task records
nothing. No is project-wide, and design never asks again.

## Confirming each owner

The check below counts owners. It cannot tell whether the named order will produce what the
criterion describes, or whether its tests observe it. That is judgment, and it needs a person.
Interactively, design shows each criterion beside the one order claiming to own it, and asks
whether that order really produces the outcome. One order to look at, never a list of every
order that mentions the criterion. A no means the work is drafted wrong, and design revises the
orders involved before moving on.

Autonomously, design judges nothing and marks nothing as passed. The run states once, at its end,
that it judged ownership by shape only, and names the criteria that leaves unconfirmed. The
review stage tests those at the end of the task.

## The check against the contract

Design runs one check over every order, against the scope contract, before it can close. The
check counts and matches ids and reads no sentence. A script comparing a criterion's wording to a
test's wording would be matching prose, and a phrase match proves only a phrase.

The check stops first on a work order file with a missing or malformed field, before any content
finding. You fix that file by hand or with an update, then check again. Past that, it finds a
criterion no order serves or owns, or that two orders own, and an order serving no criterion. It
finds an owner of a machine-verified criterion with no test, unless its proof is the gate or the
record. It finds a gate order declaring a test. It finds a record order declaring a test, owning a
file outside the task folder, or missing a done-when row. It finds an order no owner reaches and a dependency cycle. It finds
two orders declaring one file, a wildcard in an owned file, and an id that resolves to nothing.

A clean check says design is finished, subject to your confirmation above. An open item names
the order it is on and its remedy: the missing test, the owner to reconcile, the dependency to
add. A dependency points from the owner to the order it needs, never the other way. An order no
owner needs is dead work unless it owns a criterion of its own. A feature's entry point that is
not a screen belongs in the order that builds the feature, not in an order alone.

No open item can be left with a reason recorded. Each one is an assumption implementation would
build on, and implementation refuses to start on any of them. Leaving one open only moves the
stop to a later and more expensive place.

## The critique

Once the check is clean, three readers who were not in the conversation read the orders, in
parallel, one lens each. The contract lens asks whether each order's text, not only its id list,
serves and produces what the criteria say. It also asks whether anything built falls under a
non-goal. The reuse lens asks whether an order rebuilds something research found. The
buildability lens asks whether a test author and an implementer could work from the order alone.
Of every configuration order, it asks whether the order owns every file its operation rewrites.

Each reader writes one findings file, `records/design-critique-<lens>.md`. A finding is blocking
when implementation would build the wrong thing or could not start, and a concern otherwise.
They never repeat what the check counted, and a clean report names what it compared. A lens whose
file never arrives is dispatched once more. If it fails again, the close leaves it out and says so.

You answer each finding, because a critic that can block trains the builder to write for the
critic. Interactively, design shows the findings grouped by order, and each takes one answer:
change the order, then check again, or leave it with a reason. Design writes the reason into
the order's reasoning so it outlives the conversation. Each change is answered with the changed
lines, and the turn ends; design never asks whether it is ready to close. A finding on the
contract is a scope question. Autonomously, design asks nothing and changes nothing. The
findings stay in their files, and the close records the paths and the count for you to read
later. The close never blocks on the critique, in either mode.

## Running it unattended

Set the task's run mode to autonomous before starting and design asks nothing. One thing runs
unattended that does not run attended. After each reuse disposition, a read-only confirmer reads
the written reasoning and the files it cites, and nothing else. It is refused this
conversation's own account, because a decision checked against its author's narrative is not
checked. It answers agree, disagree or downgrade, with what it compared, and design appends that
answer to the order's reasoning. Interactively, you read the reasoning yourself.

## Closing, and what implementation builds from

The close is the approval, and it is yours to run. Run `/aida:design close <task-id>`, or say in
your own words that the design is right. Design never asks for it. There is no separate approve
step; the close records that a person was present, and that record is the yes.

The close runs the check once more and writes `design-closed.json` only when it is clean. It
commits the task folder at that moment; the order edits before it commit nothing. The record
holds a hash over the contract and every order together, the run mode, and who was present,
`person` or `nobody`. It also holds the recipe verdict and the critique files with their count.

Implementation reads this record on its first run, before it freezes anything, and refuses to
start on a contract or an order that no longer matches the hash. That is what catches an order
edited after design closed. Changing a closed design is supported: edit the order, then close
again, and the new hash replaces the old.

After the close, the distiller, the same reader scope and research dispatch, checks whether the
record stands alone without the conversation that produced it. Does each approach carry its
reason, and is each rejected alternative named? It never blocks. Design shows each gap it
names; acting on one is an edit and a second close.

Interactively, design stops here and names the next command, `/aida:implement <task-id>`.
Autonomously, it starts implementation itself. Each stage refuses to start without the previous
stage's record, so the chain cannot run out of order.
