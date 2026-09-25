# Review

Review is the fifth stage. It runs once per task, after implementation has closed every work
order and recorded the task as finished. It judges the whole task's change against the contract
scope approved and implementation froze, every criterion and every non-goal, at the final commit.
Sixteen checks answer, one reviewer reads the change through eight lenses, you answer what only
a person can, and one verdict comes out. You run it with `/aida:review <task-id>`.

Review repairs nothing and starts no fixer. A reviewer with no reference outside the code checks
the code against itself, so a second round finds new things forever. Here the reference is the
frozen contract and the frozen tests, and once those are answered the review is done.

Review is not completion either. It never marks the task complete and writes no pull request
body. The task stays in progress, and [finishing](finishing.md) moves it, so you can run your own
reviews between the two.

## What review judges

Implementation reviewed each work order alone, at that order's commit. Review reads the change
set implementation recorded: one diff from the commit the build started at to the final commit.
It judges that whole. Two orders that pass alone can fail together, which is why the tools run
again here.

It refuses to start while the code repository has uncommitted work, because the recorded range
is a claim about what the repository holds. Commit or set aside what is loose, and run it again.
It refuses too when the repository has moved past the commit the range ends at. A review of code
that is no longer there is not a review. The way past that is below, under a failed review.

An empty range is reported as empty, and a branch nobody has pushed is reported as unpushed. Work
on one machine is worth less than work that is pushed, so the report says so.

## After a failed review

A failed review hands you the record and stops. Two paths lead on. The usual one is to fix the
code: commit the fix on the task branch, then run `/aida:implement <task-id>` again. Its start
reports the contract as changed and halts nothing. Every order is already closed, so its next
step is finish, which rewrites the range from the build's start commit to the new head and
commits the task folder. Then `/aida:review <task-id>` runs from the first step, and the old
record is archived first. One caveat: the fix commit belongs to no order. A file no order owns
reads unmet at the check that every change serves a criterion, so keep the fix inside the files
the orders own.

The other path is to close the task without a passed review. Completion takes a one-sentence
reason from you and records it, interactively only. [Finishing a task](finishing.md) covers it.

## The sixteen checks

Every check is a question with one answer. They fall into four groups.

**The contract.** Four checks read the frozen contract against what was built.

| Check | The question |
|---|---|
| every criterion | is each criterion met, by its tests or by your answer |
| every non-goal | did the task do something it said it would not do |
| everything serves a criterion | is every changed file owned by an order, and every hunk there for a reason |
| a test per criterion, and mutation | was each criterion signed off on a real test, and can the tests fail |

**The tools.** Four checks run the commands the framework's recipe declares, over the whole task
at the final commit. They are coding standards, static analysis, security, and the full test
suite. A recipe may declare more rows, such as a duplication tool or a design-metrics tool. Each
adds one check, so the list can run past sixteen on such a framework.

**The reviewer's lenses.** One reviewer reading the diff answers five checks. They are SOLID,
DRY, architecture fit, the guides research cited, and the framework practices this project
accepted, including the plays in your [playbook](playbooks.md). The same reviewer answers the
non-goal check whole. Mutation testing makes small changes to the code and runs the tests; a
change no test catches is a survivor. The reviewer also judges every hunk for purpose and reads
those survivors, so two of the contract checks are half script and half reviewer.

The same reviewer answers one more check, which exists only when the build sent it something. A
done-when clause that asserts an absence says the change added nothing of a named kind. No second
engine for one job. No new dependency. No static call to the container. No test of it can be watched
failing, so the tests step froze none and routed the clause here instead. The reviewer reads each
routed clause against the whole diff and answers met, unmet or unknown. It also says whether a test
could have watched the clause fail. A clause that could have had a test was routed around the rule
that every test is watched failing. So that answer fails the review, and you see the clause named.
One check covers them all, and it reads unknown when one clause reads unknown, so a clause nobody
could judge fails the review. When no order routed a clause, the check reads not-needed and passes.

**The surfaces.** Three checks run the end to end and visual harnesses when the project has them,
and record [your walk](testing.md#what-a-failed-surface-does-to-the-verdict) of every surface.
[Visual and end-to-end tests](testing.md) covers setting them up, what each one looks at, and
how a new baseline is accepted.

## The five answers a check can give

| Answer | What happened | What it does to the verdict |
|---|---|---|
| met | it looked, and the answer is yes | passes |
| unmet | it looked, and the answer is no | fails the review |
| unknown | it could not look: a tool did not run, a file was missing, a lens never answered | fails the review |
| undeclared | the framework's recipe names no tool for it, marks it absent, or the row does not apply to what this task built | passes, reported in its own word |
| not-needed | no order in this task asked for it, so it was never going to run | passes, reported in its own word |

Undeclared passes because the framework has answered: it has no such tool, and blocking there
would block every project on that framework. Unknown fails because a result nobody could read is
never waved through. A report that every layer ran and found nothing, while one tool had not
run, is the claim this word exists to stop. A check with two inputs that got one answers from
that one and names the other. So one network failure does not stop every review.

A criterion answers in three words instead: met, unmet, or unanswered. A criterion nobody could
reach is not one that failed, and unanswered is never a pass.

## A task that writes documents rather than code

An order may be proved by its record rather than by a test. Its deliverable is a document, and it
is committed in the project folder. A task built only from such orders moves no commit in the code
repository. The checks that read the code say so, rather than pass over nothing.

The check that every change serves a criterion reads undeclared. The range holds nothing, and the
deliverables are in another repository this check does not open. The three tool rows and the
mutation row read undeclared for the same reason. The suite reads not-needed: no order runs a
test, so no suite was ever going to run.

The criteria are still answered. An order proved by its record, or by a configuration gate, has
its owned criteria judged during the build, and review reads that judgement. A criterion so
judged reads met, the same as one a passing test proves.

Every lens has the same rule. Each one judges the code diff, which holds nothing here, so each
reads undeclared. The guides check and the framework practices check read the research records
too. Research that cited no source leaves both undeclared. No research record at all leaves both
unknown. Met means somebody judged something.

On a task that also changes code, the lenses read that diff. A document deliverable is not in it,
and review does not hand the reviewer its path. So that half of a mixed task goes unjudged by the
lenses, and the answer you get is about the code.

## The baseline, so an old finding does not fail a new task

Before the build started, implementation ran the same tools over the files the orders own and
kept every line each tool printed. That is the baseline. At review, a tool whose baseline was
already red has that old output subtracted from what it prints now, line by line. Numbers and
runs of dots are set aside first, so a shifted line number does not read as new. No new line
reads met. A new line reads unmet, and the record lists the first twenty with the full count. The
suite subtracts the same way, on the lines the recipe says carry a failure.

When finishing the build ran the suite, review does not run it again. It reads that result, at
the same commit, and its suite row reads the output finishing kept. That row can then never read
unmet or unknown, because finishing refused those before it wrote its record.

A finding that predates the build is not this task's, and blocking on it would block every task
forever. The baseline covers only the files the orders own, so a finding in a file no order owns
counts as this task's. The contract check already reports that file as work nobody asked for.

The subtraction is honest only while both runs read the same recipe, so review refuses when the
recipe it resolved is not the baseline's. That is rare: the catalog's review recipe changed while
the task was open. Nothing retakes a baseline mid-task, because a baseline reads the tree before
the task and the tree now holds this task's code.

You have two ways past, and the second costs something. Review again against the recipe body the
baseline read. The refusal prints its path and its sha256, and nothing in AIDA restores a body the
catalog replaced. Or abandon the baseline: move `implementation/baseline.json` and
`implementation/baseline-output/` out of the task folder and run `/aida:implement <task-id>`, whose
preconditions step takes a new one. That new baseline reads the tree as it stands, so the tool
checks subtract this task's own findings and pass on findings this task added. Do it only
deliberately.

## Narrowing the surfaces

Each registered surface declares the paths that render it, and may be marked critical. A surface
runs when the diff touched one of its paths, when it is critical, or when it declares no paths.
The rest are recorded as not run and named. A kind whose surfaces were all unaffected reads met.

## The audit list

After the close, review prints one line per check: its name, its answer, and how it came about.

| Word | What it says |
|---|---|
| ran | a command or a lens ran and returned the answer |
| read | a record decided it, and nothing ran |
| off | the project turned it off, the recipe declares the row absent, or no order asked for the check |
| could-not-look | a recipe, a row, a file or a tool was missing, so the answer is unknown or undeclared |

Then one line per surface, and a line of counts. You see this before the verdict word, so what
did not run is in front of you first. Completion puts the same list in the pull request body.

## One verdict, and what stops it

The verdict is one of two words, passed or failed, decided by four rules in order.

1. A check reading unmet fails the review.
2. A check reading unknown fails the review.
3. Met and undeclared both pass, and undeclared is reported in its own word.
4. A criterion reading unmet or unanswered means no sign off, whatever the checks said.

The report names the check or the criterion that caused a fail. Beside the verdict it names every
check reading undeclared and every check reading unknown. It gives the count of criteria
unanswered and the count of catalog notes. A catalog note is one of four things. A guide the code
contradicts. A recipe whose command no longer runs. A pattern the framework wants and no guide
names. A recipe that research or design judged not to fit this task. Review writes nothing to the
catalog; you decide whether a note becomes a proposal.

## Findings, and what each one becomes

The reviewer reads a brief review assembled for it. Its dispatch is the run mode, the brief's
path and the findings path, one per line, and nothing else. The brief holds the criteria, the
non-goals, every
work order, the diff, the research records, the tool results and the survivors. It is not given the
builders' reports or any earlier conversation, because a builder's claim is not evidence. It
reads wider than a diff on purpose, since duplication against untouched code and coupling across
orders cannot be seen inside one. It runs at the top model, as every critic in AIDA does.

Every finding names its lens, its file and lines, its evidence, and a severity of high, medium or
low. Then it cites one criterion or one non-goal, or neither, and that decides what it is.

- **It cites a criterion.** The work is this task's. That criterion reads unmet, and the task is
  not done.
- **It cites a non-goal.** The task did what it said it would not do.
- **It cites neither.** It is work nobody has a task for. Interactively, review offers one follow
  up task per finding, and a yes creates it from the evidence. Autonomously, it is recorded and
  named, and no task is created. Folding such work in silently is what scope exists to prevent.

Severity overrides the third case only: a high severity security fault is raised to you at once,
because leaving it queued ships it. A finding implementation deferred at its fix round cap is not
settled either. Review judges it again, because a deferral was you saying not now, never fine.

## The close, and its commit

The close asks you the checklist rows for the criteria a person verifies, each row word for
word as implementation froze it, once. You answer met or unmet per row. A machine-verified
criterion needs no answer from you: it reads met when its row was confirmed and no failing test
carries its id. A criterion owned by an order a model observed through a browser reads met when
every row of that order's observed record is met. It reads unmet when one row is not. On a task
with no automated tests, a criterion that an order you confirm owns is yours to answer too, and
so is one it serves when it owns none. Its rows are that order's done-when sentences, and you
answer met or unmet for the criterion.

The close then writes the criterion answers and the verdict into the review record,
`review/review.json` in the task folder, and commits the task folder. The steps before it commit
nothing. An existing record is archived beside the new one with its date and commit, never
overwritten, so a defect one pass found is never lost to the next pass's record.

The close writes one thing back into the contract: each criterion's verdict. That write changes
the contract's hash, so the next thing that reads the contract reports it as changed. The report
says review made that write, so you do not read it as a contract somebody edited.

Interactively, review stops here and names `/aida:completion <task-id>`. It never runs it for you.

## When a check reads unknown

Find the check in the audit list, where it carries the word could-not-look. Then find the cause.

| Cause | What to do |
|---|---|
| the catalog listing could not be reached, or the recipe fetch failed | reach the catalog, then review again |
| the reviewer's findings file was missing or unreadable | review again |
| the playbook record was never loaded | run `/aida:research <task-id>` again; it loads the playbooks at its start. Then review again |
| the tool printed nothing, and the baseline kept nothing to compare | open the tool's output in the record and see why |
| the suite, or a surface run, selected no tests | make the suite select tests, then review again |
| the end to end preflight command failed, so the suite never ran | fix what the preflight checks, such as the site being up, then review again |
| the walk of the surfaces was not done, on an autonomous run | review again with a person present |

A second review starts only when you ask for one, and it starts from the first step, against
the code as it stands now. The old record is archived first, so nothing found before is lost.

## Autonomous runs

Every question review asks has an autonomous branch, recorded rather than assumed. A person's
answer is accepted only when a person is present.

| Question | Interactive | Autonomous |
|---|---|---|
| a criterion a person verifies | you answer met or unmet | unanswered, and no sign off |
| the walk of the surfaces | you walk every one | recorded as not done, and the surface checks read unknown |
| a finding citing neither a criterion nor a non-goal | a follow up task is offered | recorded, and no task is created |
| a new baseline for a surface | planned, shown, confirmed, then written | refused, and recorded as refused |
| setting up a surface | offered once | not offered, and recorded as not offered |

So an autonomous run cannot sign off a task carrying one person-verified criterion, because a
check that could not run has established nothing. After the close, an autonomous run invokes
completion itself, once, and stops if it refuses.
