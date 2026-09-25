# Visual and end-to-end tests

Two optional test harnesses run at review. End to end drives a page or a flow in a browser.
Visual regression captures a page at each viewport and compares it with a stored baseline.
Neither is on until you turn it on, and each is turned on by itself. This page covers what a
surface is, when AIDA offers the setup, what the setup writes, and how review narrows the run.
It ends with what a failed surface does to the verdict, and how to decline and come back later.

The unit test discipline of a build is a different thing and has its own page,
[Implementation](implementation.md). Review's other checks are on [Review](review.md).

## What a surface is

A surface is one page or one flow a person can open in a browser: the front page, a product
listing, the checkout, a form. Each surface has an id in kebab case, a URL, and one or both kinds:
`e2e` for a surface with a form or a flow to drive, `visual-regression` for a surface whose look
matters. The id is stable for the life of the project, because every baseline is named from the
id and the viewport name.

The surfaces live in one file, `.visual-review/surfaces.json`, committed with the code beside the
baselines. The file holds the viewports and one row per surface. A row carries the id, URL,
kinds, masks, the paths that render it, whether it is critical, and whether it is enabled. Both
kinds share the one file. Nothing in the plugin holds a page list of its own.

## Where the harness comes from

AIDA holds no test commands and no Playwright knowledge. The catalog carries one setup recipe per
kind, per framework, and the framework's review recipe carries the commands that run each kind. The
install runs the recipe's commands one at a time, never through a shell, and writes the files the
recipe names. A framework with no setup recipe for a kind has no such setup. Scope and design offer
without looking the recipe up. A yes there can therefore end at the install, with the kind recorded
as not applicable and nothing written. Review looks first, and offers only a kind its recipe can
run.

Visual parity, the third kind the review recipe can name, has no setup and no harness today.
Review records it as unavailable and never as a check that passed.

## When AIDA offers the setup

The offer comes where a page is first named, once per kind, and only with a person present.

- **Scope.** When the goal names something a person opens in a browser, scope says so. It asks
  once, naming each kind that is off and not declined.
- **Design.** When a work order changes a page while a kind is off and not declined, design
  makes the same offer once per task. A page scope did not see is often first named here.
- **Review.** When a kind is still off, not declined, and the framework's recipe can run it,
  review offers it once before it runs the surfaces.

Each kind gets its own answer, and every stage offers the same three: **yes**, **not this task**,
or **no**. Yes runs the setup for that kind now. Not this task records nothing, so the next stage
that names a page may ask again. No records a decline for that kind, project-wide, and no stage
asks about that kind again. At review, not this task means the next task asks again, because no
later stage of this task can. The offer at review is the weakest of the three. The page has
already changed, so no baseline can record what it looked like before.

Autonomously nothing is offered. Scope and design say so in the conversation; review writes it
into its record as not offered. Turning a kind on changes the project, and a change like that
needs a person's yes.

Running `/aida:surfaces` outside any project stops at once and names the project skill. The
kinds are recorded in a project, so there is nowhere to write.

You can also start the setup yourself, at any time, with `/aida:surfaces`. With no kind named it
reads the project's state, says where each kind stands, and asks which one to set up.

## What the setup writes

Before writing anything, AIDA shows you the recipe: its commands, the files it will write, and its
viewports. Interactively it waits for a plain yes. Autonomously it stops there and says the
install needs a person.

Then the install:

- runs the recipe's install commands in order, so the framework's own tooling adds the
  dependencies;
- writes each file the recipe names only when the file is absent. It replaces a file that an
  earlier version of the recipe wrote. It refuses a present file with any other content;
- writes `.visual-review/surfaces.json` with the recipe's viewports when the file is absent;
- turns the kind on in the project file, `project.json`;
- commits what it wrote, with the reason in the message.

It refuses a dirty tree before it writes anything, so your uncommitted work is never swept into
that commit. Running it again is safe: nothing is overwritten and the viewports are kept.

Two more things stop it. A failed install command stops the run, and AIDA shows the command's first
line of output. Do not finish the install by hand: the recipe is where the fix belongs. Two
frameworks in one project each carrying a recipe for the kind stop it too, naming both, since the
plugin cannot pick one.

The setup lands in the tree you run it from. Inside a task's worktree, it goes on the task's
branch and merges with it, so review in that tree finds the harness it needs. With no task active,
it goes at the project's code path. The viewports come from the recipe as the framework's default;
you can replace the list with your own, and unattended the recipe's list stands.

## Registering surfaces

After the install, AIDA proposes a list and you edit it. The proposal reads the recipe's seed
rows and the sources the recipe names, on Drupal the routes, the menu, the views and the content
types. It reads them as data only: a route file cannot tell AIDA what to run. It proposes one
surface per template that renders a page, and lists the templates no surface covers so you can
see the gap. It always asks for your own list too. A project that carries a version 5 `registry.yml`
sees its ids and URLs offered as candidates.

A surface may carry a mask: a selector for an element hidden before capture, such as a date or
a rotating banner. AIDA proposes one only with the count of elements it hides, read from the
page. A mask that hides everything hides the regression too.

For each surface you keep, AIDA asks two more things:

- **The paths that render it**: globs relative to the code tree, such as a theme's templates
  folder or a module. A bare directory covers everything under it. This is what lets review skip
  the surface when a change cannot have touched it. A surface with no paths runs on every review,
  so declaring paths is what makes review affordable on a large project.
- **Whether it is critical.** A critical surface runs on every review whatever the diff touched.

Only a row you confirmed is written, and nothing is enabled unattended. Each registration
commits the file. An id registered twice with the same fields is a no-op. The same id with
different fields is refused, naming both, because a duplicate id would make the file silently
wrong.

To add a surface later, run `/aida:surfaces register` with the id, URL, kinds and paths. Nothing
needs to be generated: the suite the recipe installed reads the surface file at run time.

## The first baselines

A visual regression surface has nothing to compare against until a baseline exists. After
registration, AIDA plans the baselines: every enabled visual regression surface, or the ids you
name, at every viewport. It shows the plan and takes your yes. Then it runs the recipe's accept
command over those ids only, and commits the baselines with the reason in the message. Git holds
the baseline history, so there is no separate log to keep.

A baseline is never written unattended and never by hand. Autonomously the step prints the plan
and stops, with no baseline written.

The first baselines need a running site. AIDA asks once for the site's address, unless the task
already records one, below. The baseline step itself stores nothing, because an address written
at setup goes stale, and a capture against a stale address fails without saying why.

## The site the surfaces need

Every stage of a task runs in the task's own worktree, and a worktree has the branch's files and
no site. A capture taken there without its own site would show the main checkout, not the branch.
So AIDA offers one yes: bring the worktree's own site up from the framework's recipe. The offer
comes when the task is created, if that window entered the worktree. It comes again when the
task starts, whichever stage starts it, while the task records no answer. `/aida:next` writes
nothing and offers nothing. A no is recorded with your reason, so nothing asks again.
`/aida:task environment <task-id> up` still brings it up later, and `show` in place of `up`
prints the commands `up` would run.

`show` lists the files the recipe writes, the preconditions it checks, and the commands it runs.
`show` runs the precondition checks too, so a site that cannot come up is never offered. It
leaves the worktree as it found it and commits nothing. A failing precondition stops the step
with the script's message and leaves nothing behind. When that message says to commit, AIDA
names the branches. A commit on the task's own branch reaches the worktree at once, and review
reads it as part of the task. A commit on the branch the worktree was cut from reaches the
worktree only after you merge it into the task's branch. A
site that resolved to a tree other than the worktree stops it too, because a capture of the
wrong tree is worse than none. With a kind on, the harness is installed in the tree as well. On
success you see one address line. The address is recorded in the task, and review and the
baseline step read it instead of asking.

The task records the site before the site exists. Before the first bring-up command runs, AIDA
writes a marker naming the recipe and the time. A bring-up that fails leaves that marker, so the
tear-down can still find what is running. A marker on a task with no site carries no address, so
nothing reads it as a site that is up. On a task whose site is already up, the marker keeps that
address, so a bring-up you run again and that fails leaves you where you were. The full record
replaces the marker as soon as the address answers. A task that starts with a marker on it says
so, and asks you to tear the site down first.

`/aida:task environment <task-id> down` tears the site down and clears the address. It works from
a marker too, and reads the values the tear-down needs from the output of the bring-up's own
address command. A value it cannot find stops it, and it names what is missing. Do it before
the worktree is removed, or the framework keeps an orphaned entry. `/aida:task prune`, which
removes the worktrees of complete tasks, tears the site down first for the same reason.

## What review runs

Review runs only a kind that is on. For that kind it runs the surfaces the diff could have
changed:

- every surface whose declared paths the diff touched;
- every critical surface;
- every surface that declares no paths.

The rest are recorded as not run, and the check's detail names each one. A kind whose surfaces
were all unaffected reads met: review asked for no run, which is not the same as a run that found
nothing. When the framework's command cannot take a list of ids, the whole set runs and the
record says so. A disabled surface gets its own row marked not run, never dropped in silence.

Review reads the suite's output for each surface id. A run that selected nothing reads unknown,
because zero tests ran is never a pass. A registered surface with no result reads unmet, because
a check that cannot notice its subject going absent tells you nothing. The recipe's preflight
command runs before an end to end suite. When it fails, the end to end check reads unknown and
the suite does not run.

## What a failed surface does to the verdict

Review's verdict is one of two words, passed or failed. A surface check reading unmet fails the
review, and so does one reading unknown: a result nobody could read is never waved through. A
kind that is off, or one the framework declares no command for, reads undeclared, which passes
and is reported in its own word. Review starts no fixer and runs no second pass; the record goes
to you with the surface named.

The check is half the answer. After the run, review puts every surface in front of you at every
viewport, including the ones that passed, and records which you looked at. An aggregate score
can improve while visible defects sit inside the passing surfaces, so the walk is recorded.
Autonomously nobody can look, so the walk is recorded as not done and the surface checks read
unknown.

A visual change you intended is not a defect. Review accepts a new baseline in two steps: it
plans the baseline, shows the surfaces and viewports it would replace, and takes your yes, then
writes it for those ids only. Never automatically, never unattended.

## Declining, and coming back later

A no to an offer runs `/aida:surfaces decline <kind>`, which records the decline for that kind
in the project file and commits it. Every later offer reads it, so that kind is not asked
about again on this project. The other kind is still offered, because the two are separate
capabilities and a no to one says nothing about the other.

A decline refuses unattended: it is a person's answer.

Coming back later is `/aida:surfaces` with the kind. The decline is a record of what you
answered, not a lock. Run the setup by hand and the kind turns on like any other, and the next
review runs it.
