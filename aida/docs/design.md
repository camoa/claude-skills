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
that named it now names the survivor. The folded order's interface and reasoning are appended
to the survivor's, under a line naming the folded order. The title stays the survivor's, and the
output says what was carried and what was not. A test that no longer belongs on an order leaves
through `remove-test`, which refuses the last test an owned machine criterion needs. A done-when
row leaves through `remove-done-when` and an owned file through `remove-owned-file`. A file
moved to another order then leaves no rows behind. All print what moved, so the change is
on record the way every other design write is.

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
| proof | `tests` for code a test can pin. `gate` for tools run that change state, such as configuration. `record` for a document. `observe` for what a page shows. `confirm` for code on a task with no automated tests |
| verify | The order's own proof, from the recipe or the research that covers it: commands a script runs and checks a model judges, each citing its source |

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

## Where an order's proof comes from

The knowledge that covers an order says how to verify it, and design carries that onto the
order as its `verify` list. When an agentic recipe covers the order, design copies the recipe's
`## Verifier`. Each entry of its `verifier:` block becomes a command, with what passing means:
exit 0, empty standard output, or standard output holding a text. Each numbered item of its
prose becomes a check, word for word. Design never turns a sentence into a command. Today's
recipes hold prose only, so they give checks.

When no recipe covers the order, research's findings on how reputable sources verify the work
give the entries. Each one cites its source and is marked as not binding, because this project
never accepted that source. A command from research never runs unless you approve it at the
close. Unapproved, the reviewer judges it as a check instead. The design check names every order holding such an entry. Before
you close the design, you see those entries with their sources.

A command runs through the same runner as the configuration gate: arguments, never a shell. On
a `gate` order the commands run first and the configuration gate after them, and the worse
answer stands. On every other order they run inside the order's first
check, after its own answer, and the check is met only when both are. The reviewer judges each
check. On an `observe` order the look also judges each check that needs a served site.

Design records each guide body as it opens it: the path, a hash of the body, the date, and the
name research gave it. The record is `design-guides-read.json` in the task folder, one entry per
body. A design run resumed in a new session compares each entry to the body on disk. It reads
only what changed, and what research named that no entry records. Without the record, a second
run either read every body again or trusted a conversation it never had.

Design also reads the process recipe for your framework at this stage. It holds what AIDA cannot
know on its own. What kinds of thing can an order be about here? What is built with configuration
rather than code? What has to exist beside a class for it to work, where does business logic
belong, and what build order does the framework force? No check below can see that an order is
about the wrong kind of thing, so this read has no substitute.

Design judges the recipe's fit once, before the first order. Interactively, design shows a poor
fit with the reason, and you choose: continue with the recipe, without it, write the recipe
first, or stop. Autonomously, design continues with the recipe and records the verdict.

No recipe for your framework, a catalog that could not be reached, and a failed network are three
different answers. Design records which one happened. With no recipe, design marks every order as
written without framework input, and it invents no kind of unit and guesses at no convention.
Interactively, it asks whether to write the recipe first. After a poor fit that question was
already put, and design does not ask it again.

A stated approach recorded at scope is read as a claim, never as a specification. A required
claim must be followed once design judges it sound, not before. A claim edited after research
grounded it is reported as ungrounded, and it goes back to research when it matters.

Design also names things research had no reason to look for: a particular module, a framework
API, a pattern that only became a decision here. For each such name it asks the catalog which
guides and recipes cover it. It records the answer, a nothing included, as one research finding
of its own, so the same lookup never runs again during the build.

## The reuse decision

Every prior-art candidate research handed over gets an answer: reuse it as it is, extend it,
supersede it, or decline it. An unanswered candidate is a proposal nobody acted on, and that is
how a project ends up with a second chat class beside the first. A candidate design finds itself,
an exported configuration entity of the same kind as the unit, say, gets an answer too. A decline
records that the candidate was weighed and set aside, with the reason, so it is told apart later
from one nobody weighed. A candidate is not always code; an existing view or content type is one
too, and extending it may produce no code at all.

Design decides by the candidate's distance, same name, same directory, or same layer, and by one
cost model. Build cost is paid once; carry, agent and risk cost are paid forever. Design
records the disposition on the order it lands on: the candidate, the distance, the costs
compared, the verdict and the reason. Each disposition is appended, so an order with several
candidates keeps every verdict, and re-disposing one adds a paragraph. Replacing an order's
reasoning outright drops those paragraphs, so a later note is appended as a paragraph of its
own, after a blank line. A fixed table applies. A supersede that cites only build
cost, or a candidate sharing only a layer, comes back as extend. Interactively, a supersede
stands only after you are asked, because it widens the task and owes a migration. A supersede
naming no cost dimension is refused until you say what it compared. Autonomously, a supersede
comes back as extend, with a reason in the order asking you to revisit it on an attended run. A
decline cites no cost, because nothing is compared, and stands in both modes.

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
its own `verify` commands, then the configuration gate of your framework's implement recipe, a
block of commands the build runs, every line exiting clean. An order with no commands runs the
gate alone. The
behavioural proof lives with the order that consumes the result. An order that runs tools to
change state is a `gate` order too, such as a dependency update or a database update.

A configuration order is sized around the operation and owns every file that operation rewrites.
Deleting a field owns each display that lists it. An order that owns the field's files alone and
leaves the displays to other orders cannot import on its own, so its gate fails.

An order whose deliverable is a document, a dependency review or a report, writes no test
either. Such an order owns files under the project folder, in a folder the project commits, the
task folder's `deliverables/` by default. A report may land beside earlier reports elsewhere in
the project folder. Never `records/`, which the project ignores. It carries
`proof: record`, and design sets that value itself once every owned file lies under the project
folder, unless you set a proof by hand. Its proof is its done-when rows. The checkpoint judges them, the build reads that
judgement in place of the tests, and the reviewer reads the document whole against them. It
lands no commit in the code repository. Its commits are the project folder's.

An order whose deliverable is what a page shows, a layout or a rendered block at each viewport,
writes no test either. It carries `proof: observe`, names at least one surface, and has at least
one done-when row. Each done-when row is the sentence a model judges. After the build, AIDA opens
each surface at each viewport in a browser and judges each row against what renders. It judges
the verification clause of each machine criterion the order owns as a row of its own. It keeps a
screenshot per surface and viewport as the evidence. The build reads that record as the order's
own check. The judge on the record is a model, never a person, and completion puts each such
criterion to you to accept. The design check refuses an `observe` order that declares a test,
names no surface, or has no done-when row.

An order that builds code on a task with no automated tests writes no test either. It carries
`proof: confirm`, and design sets that value itself when the order's first file is code, unless
you set a proof by hand. It needs at least one done-when row. Each row is a sentence you confirm
at review. The design check refuses a `confirm` order that declares a test or has no done-when
row.

Design picks the proof from what the order produces. Code that a test can pin gets `tests`, or
`confirm` on a task with no automated tests. Tools run that change state get `gate`. A document
or an analysis gets `record`, and what only a person or a browser can see gets `observe`. A machine-verified criterion does not mean a test,
because every kind proves one in its own way.

Creating an order and updating one both print `impliedProof:`, beside the proof the order
declares. It says `record` when every file the order owns lies under the project folder. It says
`any kind` when the order owns a machine-verified criterion, since what the order produces
decides. It says `not tests` when the order owns criteria and none of them is machine-verified.
An order owning nothing implies nothing, and the line says so. When the product is truly
unclear, `tests` stays the default. A wrongly tested configuration order wastes one build, and a
wrongly untested code order ships unproven.

An order that changes a page or a screen names it from the project's surface file,
`.visual-review/surfaces.json`. When no
visual or browser test covers that kind of surface, design offers the setup once per task,
interactively only, unless you declined it. Yes runs the setup now. Not this task records
nothing. No is project-wide, and design never asks again. Naming a surface does not make the
review stage's surface row a test. On a `tests` order, design refuses a test description that
names one of the order's surfaces. Either describe what a spec observes, and the tests step
writes it as a file. Or reopen scope so the criterion reads `person`, and the surface row
verifies it at review.

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
record or the observation. It finds a gate order declaring a test. It finds a record order declaring a test or missing a
done-when row. It finds a record order owning a file outside the project folder, or under a
path the project ignores. It finds an observe order declaring a
test, naming no surface, or missing a done-when row. It finds an order no owner reaches and a
dependency cycle. It finds
two orders declaring one file, a wildcard in an owned file, and an id that resolves to nothing.

The check asks that question the other way too, and reports without holding the close. It prints
`impliedProofDisagrees:` with every test order that owns criteria of which none is machine-verified.
Which of the other three proofs fits is a judgment, so no exit code holds it.

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
Of every order, it asks whether the order owns every file its operation rewrites. It reads the
owned list against the couplings your framework's design recipe names, such as a service and
its definition file. It also reads each criterion an order owns against that criterion's own
verification clause. A clause naming nothing that would settle the criterion is a finding on the
contract. The fix is the criterion rewritten at scope, never a proof kind that carries it into the
build.

Each reader is dispatched with the run mode, the task folder, its lens and the recipe's path,
one per line, and nothing else. Each reads the contract from `alignment.json`, and treats the
rendered page beside it as a copy that answers nothing. Each reader writes one findings file,
`records/design-critique-<lens>.md`. A finding is blocking
when implementation would build the wrong thing or could not start, and a concern otherwise.
They never repeat what the check counted, and a clean report names what it compared. A lens whose
file never arrives is dispatched once more. If it fails again, the close leaves it out and says so.
The project ignores `records/`, so the close moves each finished file into `design/` and commits
it. A file whose critic never finished moves there too, named `unfinished-design-critique-<lens>.md`.
The close does not count it, because it is not evidence the close judged. It is committed because
it is the only copy of what that critic wrote before it stopped, and a second dispatch answers
differently.

You answer each finding, because a critic that can block trains the builder to write for the
critic. Interactively, design shows the findings grouped by order, and each takes one answer:
change the order, then check again, or leave it with a reason. Design writes the reason into
the order's reasoning so it outlives the conversation. Each change is answered with the changed
lines, and the turn ends; design never asks whether it is ready to close. A finding on the
contract is a scope question. Autonomously, design asks nothing and changes nothing. The
findings stay in their files, and the close commits them and records the paths and the count.
You read them later, from this branch or from another machine. The close never blocks on the
critique, in either mode. Interactively, the close asks you for one line: how many findings
changed an order, and how many were left with a reason. It records the line beside the count.
Unattended, the record says `none`.

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
`person` or `nobody`. It also holds the recipe verdict and the critique files with their count
and your outcome line. Those files are in the same commit, so the paths the record cites open
for a reader who has only the branch.

Implementation reads this record on its first run, before it freezes anything, and refuses to
start on a contract or an order that no longer matches the hash. That is what catches an order
edited after design closed. Changing a closed design is supported: edit the order, then close
again, and the new hash replaces the old. A reopen that only adds or removes an owned file or a
done-when row may skip the research and guide reading. That reading shapes an order, not its file
list. A change to an order that implementation already started halts that order for design drift.
Put the design back and the next build clears the halt, or take the restart.

After the close, the distiller, the same reader scope and research dispatch, checks whether the
record stands alone without the conversation that produced it. Does each approach carry its
reason, and is each rejected alternative named? It never blocks. Design shows each gap it
names; acting on one is an edit and a second close. A malformed distiller record is renamed
beside its original path, dated, and a fresh distiller runs with the rule it broke. A second
malformed record stops for you.

Interactively, design stops here and names the next command, `/aida:implement <task-id>`.
Autonomously, it starts implementation itself. Each stage refuses to start without the previous
stage's record, so the chain cannot run out of order.
