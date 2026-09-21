# Finishing a task

Completion is the sixth stage, and the shortest. It runs once, after review has closed. It asks
you for the few things a script cannot know. Does each leftover finding become a task? Why does
the task close when review did not pass? What was done, in a line? Then it writes a pull request
body, records on what grounds the task closed, and marks the task complete.

Run it yourself, from the task's worktree: `/aida:completion <task-id>`. Leave the id off and
completion takes the task active in this conversation. With neither known, it names `/aida:next`
and stops. When the task's worktree is on disk and your window is outside it, every action but
the first read refuses, naming the worktree and where your window is;
[continuity](continuity.md) has the general rule. On an
autonomous task review invokes completion for you, once, when review closes.

[A task](task.md) says what the move to complete does to the task itself: one field changes, and
nothing moves. This page is about everything around that field.

## What completion never does

Completion runs no check and dispatches no model. It re-derives no verdict; it reads the one
review wrote. It changes no code and repairs no finding. It calls no remote: no GitHub, no push,
no merge. You open the pull request from a file it writes, and you merge it.

It is a separate stage from review so that you can run your own reviews between the two. A
review of your own, or a colleague's, fits between review's verdict and the close.

## What AIDA reads first

Before it asks anything, completion reads the task folder and tells you where it stands:

- the task's state and run mode;
- whether the contract, the finished record and the review record exist;
- the review verdict;
- each finding review left for a follow up task, and whether that task exists yet;
- how many children are still open.

It ends with one line saying whether the task closes on the verdict or on your reason. That read
writes nothing.

A task already complete stops here. AIDA names the record it wrote the first time and does
nothing more.

The verdict is one of four words, because they are four different facts:

| Word | What it means |
|---|---|
| `passed` | review ran and every check and criterion held |
| `failed` | review ran and a check or a criterion did not hold |
| `unfinished` | review started and never closed |
| `none` | there is no review record at all |

## The follow up tasks

Review records a finding that cites neither a criterion nor a non-goal as work for a follow up
task, because folding it into this task silently is what scope exists to prevent. Review may
have offered you a task for it already. Completion offers again for each finding that still has
none, one question per finding. Each question names the finding's id, its severity, and the task
id it will get.

A yes creates the task the same way `/aida:task create` does. Its goal is the finding's evidence
and one sentence naming where it came from. The task id is the source task's id followed by the
finding's id. Nobody has to name it, and completion can see it exists by its folder.

A high severity finding is different: a queued security fault ships if nobody tracks it. Leaving
one with no task refuses the close until you either create the task or say in a sentence why not.
The sentence goes into the record and the pull request body. A finding below high severity may be
left with no reason.

## Closing without a passed review

A `passed` verdict closes the task with nothing asked. Any other word closes only on your word,
and AIDA asks why, in one sentence. That sentence is not a bypass. The record keeps it, and so
does the pull request body, so a later reader knows the grounds. AIDA never invents a reason and
never suggests one.

Three cases land here:

- **Review failed.** A check read unmet or unknown, or a criterion read unmet or unanswered. A
  criterion you were meant to verify by hand, and nobody answered, fails the review too. So a
  task carrying one closes only on a reason.
- **Review never closed.** Something stopped it before the verdict.
- **There is no review record.** A task started under version 5 has no contract, no build
  record and no review. It still closes, on your reason, and the body says in words that nothing
  was checked. Refusing would strand every old task.

A parent task refuses to close while any of its children is open. Close the children first; the
last child's close tells you the parent is ready.

## What a model observed

A criterion owned by an order a model judged through a browser is put to you before the close.
AIDA asks one question per criterion. It shows each row the model judged: the sentence, the
surface and viewport, and the verdict. It names the screenshot so you can open it. You say
whether you accept the observation. A no closes the task only on your reason, the way a failed
verdict does. The record keeps each answer. The pull request body says beside the criterion that
a model judged it from a screenshot, with the path, and whether you accepted it. On an autonomous run
nobody is asked, and the record and the body say the observations were not accepted by a person.

## The summary

AIDA asks for one or two lines on what was done, unless the conversation already says it. It
appends the summary to the task's goal file under a dated completed heading. On an autonomous
run, or when you give none, it writes one line naming the grounds instead.

## Saved notes become plays

Every decision you saved mid-stage with `/aida:task save` is a note in the task folder. Before
the close, completion lists the notes and asks one yes or no per note. A yes drafts the five
fields from the note: the domain, the title, the rule, the reason and where it applies. You
correct the draft, and AIDA appends the play to the project's playbook. The note is the
candidate; you name the play.

[Playbooks](playbooks.md) says where the play goes and who reads it. A title that is already a
play is refused; give another. The record counts the notes completion offered, whatever you
answered.

## The pull request body

The close writes `completion/pr-body.md` inside the task folder and prints the path. It never
prints the body; a body in the conversation costs context and gains nothing. Open the file, and
open the pull request from it by hand, changing nothing in it first.

Every section reads one field of one record. Completion computes nothing, and a missing record is
written in words, never left blank, so the body claims only what a record holds. A version 5 task
gets a body that says there is no contract, no commit range, and nothing was checked.

| Section | What it carries |
|---|---|
| Goal | the goal from the scope contract |
| Success criteria | every criterion with the verdict review gave it |
| Non-goals | the non-goals from the contract |
| Commit range | the range the build finished, the branch, and the worktree to push from |
| Review audit | one line per check, one per surface, and a line with the counts |
| Review | the verdict, and every finding grouped by what review decided about it |
| Grounds for closing | who closed the task, on which verdict, and the reason when one was given |
| Follow-up tasks | each finding with its task, or the reason it was left with none |
| Catalog notes | what review saw that a guide or a recipe should hear about |

Two of these do work for the person who reviews the pull request.

The **audit list** says, for each check, how its verdict arose. It ran; a record field decided
it; the project turned it off; or it could not look. A check could not look when a recipe, a
row, a tool or a file was absent. The list names it in that word, never as a pass. One line
per surface follows, run or not run with the reason, then a line counting each word. The reader
sees what did not run before they see the verdict.

The **criteria** carry their verdicts, and a criterion that reads `unanswered` is one nobody
verified. It is a row review asks a person to answer by hand, and on an autonomous run there was
nobody to ask. Or it is one a test answers, and the suite could not run. Either way the pull
request reviewer still has to verify it by hand, and the body puts it where that reviewer will
look.

The commit range section adds two lines when they apply. When the branch has no upstream, it
says to push before opening the pull request. When the task has a worktree, it names the branch
and the worktree, and says what to run after the merge, below.

## The move to complete

The close writes the body, then its own record at `completion/completed.json` in the task
folder. Last, it calls the task action that sets the state to complete. That action is the only
writer of the state, and it commits the record, the body and the state together.

The record says what the state cannot. It holds the verdict the task closed on, whether a person
or nobody closed it, and the reason. It lists every follow up finding with its task, or the
reason it was left with none. Nothing archives a completed task. Its folder stays, with
everything every stage wrote.

When `/aida:task` refuses at that last step, the body and the record are already written.
Answer what it said, then run completion again with the same answers. The rarer stops write
nothing and each names its own repair: a record completion cannot read, a child whose folder is
missing, a follow up task the task skill refused to create.

The close ends by naming `/aida:next`. When the task is the last open child of a parent, it says
the parent closes next.

## The merge, and what comes after

You merge the pull request. AIDA never does, and never pushes: a hook refuses `git push` in
the session. You can open that gate on your own machine, for as long as you want, with one
file only `sudo` can create: `sudo mkdir -p /etc/claude && sudo touch /etc/claude/allow-push`.
While it exists, the session pushes; `sudo rm /etc/claude/allow-push` closes it. A force push
stays refused. Once the branch is merged, the task's worktree and its site are the last things
left, and they cost disk and a running project each.

Completion ran inside the worktree; pruning runs outside it. Run `/aida:task prune` from the
main checkout, never from inside a tree it may remove. It lists every complete task that still
records a worktree, one line each. The line holds the path and the branch. It says whether the
branch is merged into the checkout's current branch, whether the tree is on disk, and whether a
site is up. Then it asks a plain yes or no per tree, one at a time, never once for all of them.

For each yes it tears the site down when one is up, removes the worktree, and deletes the branch
only when it is merged. It clears the worktree from the task's record and commits. Nothing is
ever forced: a tree with uncommitted changes stops the action, names the tree, and touches
nothing after it. Fix that tree by hand and run prune again.

If you remove a worktree by hand instead, run `/aida:task environment <task-id> down` first.
Otherwise the framework keeps an orphaned site registered to a folder that is gone.

## A task that will not be merged

Sometimes the work stops: the pull request is declined, or the goal is dropped. Close the task
anyway. A task that just stays open sits in `/aida:next` forever. Say why the work ended in the
reason, when review did not pass, or in the summary, when it did. The pull request body is
written and never opened; it stays in the folder as the account of what was done.

Then prune the worktree. Prune names an unmerged branch before it asks, and a yes removes the tree
and keeps the branch. AIDA never deletes an unmerged branch; if you want it gone, delete it
yourself.

## On an autonomous run

Completion reads the run mode from the task. AIDA accepts a person's answer only when a person
is present, so every question above has its own unattended branch:

- **Follow up tasks.** Every finding still without a task gets one, and completion lists them.
  A task changes the contract least, and the fixed id means nobody has to name it.
- **A review that did not pass.** The close halts, naming the verdict it read, and writes
  nothing. A script inventing a reason would be a bypass, so the task waits for a person.
- **A high severity finding left with no task.** The tasks were created first, so this refusal
  fires only when that creation failed.
- **The summary.** One line naming the grounds.
- **Saved notes.** Completion offers none, and the record says so. Nobody is present to name a
  play.
- **Pruning.** Prune prints the list and removes nothing. A worktree goes only on a person's yes.
