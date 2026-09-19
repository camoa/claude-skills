# Implementation

Implementation builds the work orders design wrote, one at a time. Each order is built against
tests written before the code, by a context that never writes the code, and frozen before the
code starts. That sentence is the whole stage. The reason is what a reviewer with no reference
does. It checks the code against itself, shares the writer's blind spots, and finds something new
every round, so the loop never ends. The fix is a reference outside both the writer and the
reviewer, and the reference is the tests.

You type one command to begin, `/aida:implement <task-id>`, or say "start implementing this
task". From then on the stage runs from the conversation. It tells you what it did, what each
check answered, and where each record is. It asks a question only where a script cannot decide.
Every question opens with one plain sentence that names the decision and what each answer causes.
You may be returning to the terminal days later with none of the order in mind.

## What happens before anything is built

The start takes a snapshot of the contract and the work orders and opens the ledger. From here
the build reads the snapshot and never the live design files, so a design edited mid-build is
noticed rather than quietly built.

Design must have closed on exactly these files. On its first run, AIDA re-derives design's close
hash from the live contract and work orders and refuses when it disagrees. That means design
closed once and something changed since, so close design again. A resumed run compares the live
files against the snapshot instead and reports drift. A changed work order drifts. A changed
criterion drifts every order that serves or owns it. The snapshot then takes the live contract,
so no test is written from a sentence the person has since replaced. An order serving none of
the changed criteria is untouched. The snapshot is taken here rather than at design
close because a person can close design, edit an order, then start.

A resumed run refuses two more things. When the branch was rewritten under the build, by a
rebase or an amend, the commit the ledger started from is on no branch. AIDA says so, rather
than labelling the baseline with it or computing a range git cannot resolve. You name the commit
the branch now builds on, the ledger keeps the old value beside the new, and the baseline is
retaken. When the baseline on disk was written by an earlier version, in a shape this one cannot
subtract from, AIDA names the retake. No build attempt is spent on it. A resumed run also names
the orders whose design predates the proof field. Each is proved by tests unless design sets the
gate on it. An order the live design no longer holds is dropped from the snapshot when it has not
started, and named. When it has started it halts, and the restart drops it.

Three more things refuse before a line is written. The project is not a git repository, the code
checkout is on no branch, or the build would land on the repository's own trunk branch. A commit
on a detached head belongs to no branch, which this build must never risk. When there is no
`origin` remote, the trunk cannot be derived. AIDA continues and tells you the trunk was not
confirmed. That is a check that could not look, not a pass. A first run compares nothing, so it
reports drift as not checked, never as none found.

## Can this repository test at all

The next step runs once per build. It answers whether a test can run here, and it takes a
baseline of what is already broken.

AIDA resolves two recipes per framework the project declares: one for running tests, one for the
review tools. A project that declares no framework refuses here, because no recipe can be chosen
for it. A lookup has three answers that are not the same thing. The catalog holds none for this
framework, the listing could not be reached, or the fetch failed. Only the first says anything
about the framework. AIDA records which one happened rather than treating an unreachable catalog
as a recipe that declared nothing.

The test-execution recipe declares what must be true before a test runs. Each condition answers
in one of four words:

| Verdict | What it means | What happens |
|---|---|---|
| met | it looked and the answer is yes | the build goes on |
| unmet | it looked and the answer is no | stop; the condition, framework and owner are named |
| unknown | it could not look, say a checker is not installed | stop |
| undeclared | the recipe named no conditions | the build goes on, and AIDA says so |

Undeclared is never reported as conditions that passed. A checker that is not installed says
nothing about the condition it was meant to probe. A recipe declaring nothing has answered, and
stopping on it would mean no project on that framework ever builds. On unmet or unknown you
decide what to do; an autonomous run halts there. A command that carries a placeholder, such as
the test runner a Python project names, needs a value from you. AIDA never guesses one.

Two refusals end the whole run here rather than later. A framework whose recipe can run neither
one test file nor the tests for changed paths. No order on it could ever have its own tests run.
And two frameworks whose review recipes each command the same tool, coding standards say. That
gives one question two answers, and AIDA refuses rather than choose. The same refusal returns at
every later step that runs the tools. The way past is one check recipe for the task, or two tasks.

Then AIDA runs each framework's cheapest test command, the one that proves the harness reports at
all, and takes the baseline. The whole suite runs once, because the orders' tests do not exist
yet and no framework maps changed paths to the tests that cover them. The coding-standards,
static-analysis and security tools run over the files the orders own, since they take paths.

**A red baseline is recorded, never refused.** Knowing it is the point. Without it, a repository
with one old failure blocks every order forever. A builder chasing a failure it did not cause
spends every attempt it has. What each run printed is kept whole. Every later check subtracts
those lines from its own run, so only a new line counts against an order. Numbers are set aside
first, so a shifted line number does not read as new. For the suite, that holds only when the
recipe names the lines that report a failed test. Without that, a red suite still reads unmet on
every attempt. The subtraction holds no parser. A finding whose text changed reads as new, and
one fixed and reintroduced reads as old. The baseline belongs to the commit the build started
from; a run at a different commit refuses rather than overwrites.

## Writing the tests for one order

An order is ready when every order it depends on has closed. For each ready order, a test author
writes the tests, watches each one fail, and stops. It is a separate context from the one that
will write the code, on a mid tier. It may not read production source, this order's or any order
already built, and a hook refuses the read. If it saw the code, the tests would describe the code
instead of the intent, which is the failure this stage exists to prevent. It may not write
production code either. That bound is recorded on the dispatch, not applied by a hook.

What it does see is the order's criteria with their verification sentences, the boundaries the
order names, and the declared interface of each order it depends on. It sees the interface of
anything design recorded as reused, since a reused module belongs to no work order. It also sees
the framework's recipe for writing tests: where a test file goes, which levels exist, and how a
criterion id attaches to a test. A framework with no such recipe has no path through this step,
and AIDA says so rather than writing tests from habit.

Each test carries the id of the criterion it proves at the end of its name. A script can then
check a row with a string comparison, and a runner can select one criterion's tests by name.
Exactly one order owns each criterion, and most orders own none. An order that serves a criterion
without owning it cannot observe an outcome a later order builds. Its tests prove its own
done-when instead, and those names end with the order's id. An order that neither serves nor owns
any criterion refuses here; the repair is the work order, so close design again. A criterion a
person verifies gets no test. The author writes a checklist line for it, copying the verification
sentence whole, and the review stage asks you those lines at its close.

**A red run is read against the framework's failure signal, never the exit status.** Three of the
five frameworks exit zero when a filter selects nothing, so a mistyped test name reports success.
The recipe names two markers: what the harness prints when an assertion did not hold, and what it
prints when it never reached the behaviour. Only the first is a red. The second is a setup gap,
and the freeze refuses it, because nothing in that output says the behaviour is absent. One order
is the exception: the one that creates the unit. No test can assert before the module exists, so
for that order alone the harness error is the expected red, and the author writes no scaffold.

A test green on its first run has four outcomes. The test was wrong: corrected once. Still green,
and the author can name the existing code that satisfies it: frozen, with that reason recorded
for the reviewer. Still green with nothing to name: reported by name, and the step stops. Failed:
frozen with its red run. A green test is never deleted quietly and never weakened into failing.

When the author returns, the coding-standards tool runs over the new test files, and a finding
goes back to the author before the freeze. This is the one place the tests' own standards are
judged, because the build step leaves the frozen tests out of its tool checks.

## Who confirms the tests prove the criteria

Before anything is frozen, one row per criterion goes to a checker. A row holds the criterion,
its verification sentence, and the names of the tests that claim to prove it. A test of the order's
own done-when gets a row beside them, keyed by the order's id, with the done-when text. The
question is whether those tests exercise the sentence beside them. The failure it catches is a
test measuring something adjacent and easier than what was asked.

The checker runs in both modes, on the top tier, and reads each named test against the
test-authoring recipe and the sentence. A person shown test names cannot see what it sees. Asking
about every row added a turn and no judgement the checker had not already given. A
confirmed row is therefore the checker's in both modes. You are asked only about a row it
rejected, one question per row. The question says in plain words that the checker doubts the new
tests prove one requirement. Confirming keeps them; rejecting sends them back. Then it names the
requirement, the tests, the checker's note and the answer it recommends. A row you
reject goes back to the test author, and the repaired test goes through the checker again.
Nothing freezes while a rejected row stands.

Unattended, there is nobody to ask. A rejected row halts the order, with the checker's note as
the reason, and the run takes the next ready order. The ledger records who judged each row, so
the rows no person read can be listed later. A model ruling on a test with nobody watching is
weaker evidence than a person's. The record says so rather than marking the row passed.

Once every row reads confirmed, the tests are frozen: a hash per file, recorded, and a commit of
those files alone on the task branch. A commit that fails, for want of a git identity say,
refuses the freeze with git's own message. From here a hook refuses a write to a frozen file from
every dispatched role except the test author of the order that froze it. The code is written from
a tree that already holds the tests.

A freeze is not a lock. You are not a role, and you are not refused. If you edit a frozen test
yourself, the hook lets the write through and tells you which file changed and which order froze
it. Nothing re-records the hash, though, so the order's next attempt fails its frozen-tests
check. A test that turns out wrong is not repaired in place; the way back is to restart the order,
described under the halts below.

The author often writes a base class or a fixture beside the tests, and the tests stand on it.
The freeze takes each such file with the tests: hashed, committed in the same commit, and recorded
as a support file. The hook guards it the same way, and a change to it fails the frozen-tests
check the same way a changed test does. Without this the implementer, which owns the file, could
rewrite the setup under the tests with every check still met. The author's work would also land
in the implementer's own diff. A support file a test pattern matches is a test, and the freeze
refuses it under that name.

## A configuration order

A work order whose deliverable is exported configuration, a Drupal view or a content type, has
`gate` as its proof kind; design created it that way. No test author is dispatched and no row goes
to the checker, because a test that reads the YAML back cannot fail for the right reason. The
order freezes with no test, and with a checklist line for each criterion a person verifies. Its
build runs the implement recipe's configuration gate lines instead, in the task's worktree. Every
line exiting zero is met; the first line that does not is named, with its output. The check reads
unknown when the task has no running site recorded, so bring the environment up first. The proof
of what the configuration does lives with the tests of the order that consumes it. When the order
closes, its criteria are recorded as judged by the gate, a third judge beside person and model.

## A document order

A work order whose deliverable is a document in the task folder, a dependency review or a
report, has `record` as its proof kind. It owns files under the task folder only, and lands no
commit in the code repository. No test author is dispatched. Its done-when rows are its
checkpoint. The row-checker, or you, confirms that each row names something a reader can check
from the document alone. The freeze records that judgement. The implementer writes the
document and commits it in the project folder, staging its owned files alone. The build reads
the range, the tree and the diff from the project folder's history. The empty-range refusal
and the unchanged refusal compare against that history. The suite and the three tool checks
read undeclared, naming the proof kind. The done-when check takes the place of the tests, met
when the row was confirmed. The reviewer is handed the document by path and the task folder's
diff, and reads it whole against the done-when rows. When the order closes, its criteria are
recorded as judged by whoever judged the row, a person or a model, never the gate.

Every diff for such an order is the task folder's alone: the owned-files check, the review diff
and the fix patch. AIDA commits the project folder between a build brief and its record, when a
note is saved or another task closes a stage. None of that is the implementer's. Inside the task
folder, the files AIDA's own scripts write are set aside before the owned list is compared.
Those are the task record, the contract, the stage folders and the notes. The check's detail
says how many. A file a person writes is never set aside, so a second document the order does
not own still fails the check.

## Writing the code

An implementer, a mid-tier context, writes the code for one order until its frozen tests pass. It
sees the implement recipe for its framework, which carries the coding rules, and a brief. The brief
holds the order, its owned files, the frozen tests with the criterion each carries, and the
interface of each order it depends on. Where a dependency has closed, that is the record its builder
wrote about what it actually exposes, not the declaration alone. Before it edits anything, it writes
five answers into its report. They name the most surgical fix, what stays untouched, what it reuses,
the lines it expects to add and delete, and the files and blocks it targets. The reviewer reads the
diff against those answers.

It writes only inside the files its order owns. It may not change a test; a hook refuses the
write and names the order that froze the file. It may not read another order's source; what
another unit exposes is its interface record. It is refused the recipe that writes tests, because
that file chooses a level and names a test, and this reader may do neither. It stops rather than
working around a test that seems wrong or an interface that does not fit. Interactive, the stop
comes to you; autonomous, it halts the order and records what was left. It commits its own work
before it returns. A dirty tree means that commit did not happen, and the attempt is not recorded.

After each attempt, eight checks run. These are scripts, and no model reads anything here.

1. **order-tests.** Do this order's own frozen tests pass. On a configuration order this slot is
   the configuration gate instead, and on a document order the done-when judgement.
2. **suite-regression.** Does anything that passed at the baseline now fail. A suite row the
   recipe costs `end-of-task` does not run here: the check reads deferred, and finishing the
   stage runs that row once.
3. **coding-standards**, **static-analysis** and **security.** Does the tool raise anything the
   baseline did not already have.
4. **owned-files.** Did the change stay inside the files this order owns.
5. **frozen-tests.** Does every frozen test file still hash to what the freeze recorded.
6. **interface-record.** Does the builder's record name every element the order's declared
   interface names in backticks.

The three tool checks run over the order's owned files minus its frozen tests. The implementer
may not write the tests, so the tools judge only what it may write. An owned file outside the
code repository is left out too, because a tool run in the repository cannot see it. So is an
owned file the order deleted, because the tools refuse a missing path. The detail says how many
were left out. The first check is the floor.
Every other check may answer undeclared and the order still goes on. Order-tests must answer
met, because it is the one check that says this code does what its tests ask. AIDA also tells
you how many of the eight actually ran a command, a diff or a hash. Eight answers do not by
themselves say the code was tested. A record that would hold fewer than eight is refused rather
than written, naming the absent check. The interface check is the one script that cannot decide
alone, because both sides are prose. It counts what it can, that every backticked element is
present, and the disagreement goes to the reviewer as a finding. A declaration naming nothing in
backticks reads unknown and does not spend the attempt.

A failed check is not a failed order. It is this attempt's result, and an order has two attempts
unless you grant one more. AIDA says which check failed and where the tool's output is, and you
decide whether to spend the next one. When the last allowed attempt fails, the order halts at that
moment, with the check named. A halt nobody sees until they ask is one an unattended run never
sees.

An attempt stopped by the three tool checks alone has a second route. A tool refusing a path it
was handed is AIDA's fault, not the implementer's, and the code needs no second build. You can
run the eight checks again over the range that attempt recorded. No implementer is dispatched
and no attempt is spent. AIDA offers that route beside the next build when it applies. It
refuses when no attempt was recorded, when the code moved since the attempt, and when a test or a
suite stopped the attempt. That failure is the implementer's work, and a re-check is not a free
retry. The record keeps the attempt and its range, takes the new checks, and keeps the replaced
verdicts beside them with the date.

## The review of one order

An order that passed its checks gets one review, ever. A second pass is where a loop that cannot
end comes from. The reviewer runs on the top tier, because a critic runs at the top model whatever
the tier of the work it judges. It is given the criteria and non-goals, the diff as a file, the
frozen tests, the eight check results, and both interface texts. It is given the builder's
report too, as claims and never as proof, so a reason in it never lowers a finding's severity. It
writes its findings and nothing else; a probe file left in the code is a refusal.

When the interface check read unknown, nothing is asked, in either mode. AIDA says in one line
that no named element of the interface could be counted. The reviewer reads the declared
interface and the builder's record itself, and its finding cites the criterion if they disagree.
Both texts are in its brief. Asking you to compare them put the reviewer's own comparison to a
person, from the same two texts. A model ended up answering for you.

Every finding cites one criterion or one non-goal. A finding citing neither is recorded and never
reaches a fixer; the review stage decides what becomes of it. That rule removes the cheap false
positives before any fixer runs. A finding that hits a non-goal is a finding like any other when
you are present. On an autonomous run it halts the order, naming the non-goal.

## Fixing what the review found

One fixer per round takes every open finding, in severity order, with the union of their fix
scopes. Not one fixer per finding: a wave of them costs more than the work it fixes. The first
round runs on a mid tier, the second on the top tier. The fixer may not change a test, and it may
not fix a finding not on its list. A finding whose scope is too small is reported, not widened.
You rule on it; an autonomous run halts the order with the report as the reason.

After each round, seven of the eight checks run again, every one but the interface record. A fix
that breaks a passing test has not fixed anything. A check answering unmet or unknown spends
the round and leaves every finding open. Then the reviewer returns in verify mode and gives each
finding one verdict, addressed or not addressed, read against the fix diff only. Attempted is not
addressed. New breakage inside the fix diff opens as a finding. Anything it notices outside the
fix diff is recorded and opens nothing, so a round never grows.

An order has two fix rounds. At the cap, each finding still open needs a ruling from you:
`wrong`, `deferred`, or `load-bearing`, with a reason. The first two let the order close with the
finding recorded, and the review stage judges a deferred one again. The third halts the order
with the finding as the reason. It reaches you as an escalation, not a question with an obvious
answer. Autonomous, the order halts instead.

Closing an order records the commit range it produced and decides the criteria it serves or owns.
A machine-verified criterion reads confirmed once every order serving it has closed and every
judgement on it reads confirmed. A person-verified criterion stays `not-judged` until the review
stage asks you its checklist. Those are the row words, `confirmed`, `rejected` and `not-judged`.
Review answers each criterion in its own words, met, unmet or unanswered, and a confirmed row
with no failing test is what it reads as met. AIDA tells you how many rows across the whole
ledger a model judged rather than a person, so you can find and re-judge exactly those. Then it
moves to the next ready order.

## When an order halts

One order halting does not stop the run. Only the orders that depend on it wait; everything else
that is ready still builds, and the run stops only when nothing is ready. Then AIDA reports what
halted, the reason the ledger holds, and what is waiting on it. Every halt has a clearing action.

**Attempts spent.** You read the two recorded attempts and decide which of three things is true.
The test is wrong, and no action repairs it in place: the order restarts, below. The order is
wrong, too big or with an interface that does not fit, which is design's to fix. Or the code is
hard, and you write it yourself; the checks judge your code the same way. If the order needs one
more attempt, you grant it with a reason. A third automatic attempt is never one of the three,
and unattended none of them is the model's to pick: the run ends with the report.

**Budget spent.** A run has a ceiling when the task's own `task.json` sets a budget in dispatches
or minutes. The spend is recomputed from the ledger before every dispatch, so nothing a builder
writes can reset it. Raise the budget in `task.json` first; a grant alone brings the halt back.

**Design drift** has the restart. Running the build again after a design change compares the live
design to the snapshot. An order drifts when its own file changed, or when a criterion it serves
or owns changed. An order that has not started is taken fresh from the live design, once
design has closed on it. Nothing halts for it, because nothing was built against its old shape. An
order that has started, with frozen tests or a build record, halts, and so does every order that
depends on it. Restarting moves only the halted orders' records aside, resets them to not started,
and keeps every finished order. A finished order is never redone for a change it never depended on.
Design has to close again on the live files first. A restart is a person's judgement, so an
autonomous run cannot take it.

**Every other halt is yours to clear.** Unattended, that is a row the checker rejected or a
finding on a non-goal, with nobody to rule. In either mode it is a fixer's scope too small, a
finding ruled load-bearing, or a tree a role left dirty. Fix rounds spent with findings open halt
the same way. A grant refuses them and the restart does not see them. You do what the reason
names: repair the test, rule on the finding, commit the tree. Then you clear the halt with a
reason, and AIDA records both in the ledger and says which step the order resumes at. Clearing a
halt is a person's judgement, so an autonomous run cannot take it. A wrong frozen test can also
be repaired through design. Edit the order, close design again, and run the build again; the
order then halts for drift and the restart takes it fresh.

## Finishing the stage

Once every order is closed, none is halted, every machine-verified criterion reads confirmed, and
the code tree is clean, AIDA runs the whole suite once at the final commit. A red baseline is
subtracted the same way the per-attempt checks subtract it. A suite that fails, or cannot be
decided, refuses to finish. AIDA names the new failure lines and the file holding the whole
output, and the route is a fix commit and a second finish. A recipe with no suite row passes
and the record says so. Then the stage records itself done in `implementation/finished.json`.
That one file holds the commit range the stage produced, the suite's verdict, and each order's
own range and rounds. It holds each criterion's state and who judged it, and the checklists for
the criteria a person verifies. It holds
the findings ruled deferred with their reasons, and how many rows a model judged. The task folder is
committed then; mid-stage writes stay uncommitted until then. Finishing ends implementation only and
never changes the task's own state. Interactive, AIDA names the next command, `/aida:review
<task-id>`, and never runs it for you. Autonomous, it runs the review stage once and stops if that
refuses.

## Coming back to a build

The ledger, `implementation/ledger.json`, is the state of the build, not a log. It holds each
order's step, its halt reason, its attempts and rounds, each row's state with who judged it and
why, and the commit range that built each order. Read it first, before the records. It survives a
compaction. A person arriving after an autonomous run reads the rows a model judged to decide
where to look. Running `/aida:implement <task-id>` again resumes. The start reports which orders
are in flight, which halted and why, and which are ready, then continues with the next ready one.
The tool grants a skill holds last one turn, so the same command may prompt for permission again
partway through a long build. That is how grants work, not a fault in the build.

## What is enforced, and what is only recorded

The read denials and the frozen-test refusal are hooks the runtime applies. The read denial covers
the Read and Grep tools and not the shell. The test author runs its own tests, so it holds a
shell, and a `cat` of a denied file is not refused. The rule exists to stop a role opening the
source because that is the obvious way to write a test about it. A role working around it on
purpose has already failed in a way no hook catches. Three things are recorded and enforced by
nothing: the paths a role may write, the fixer's fix scope, and the builder's five answers. A
write outside the fix scope surfaces when the reviewer reads the fix diff, not as it happens.
