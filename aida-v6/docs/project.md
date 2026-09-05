# The project

A project ties one code path to AIDA's own work on it: its tasks, its stages, and the
recipes it reads. Everything else in AIDA happens inside a project, so a project is the
first thing AIDA needs from you.

One skill answers every question about a project: which one owns this folder, create one,
switch to another, or close one out. Type `/project`, with or without arguments.

You type it yourself. Creating, switching, and closing all change what is on disk or which
project this conversation uses. Nothing here runs on Claude's own judgment: nothing invokes
it for you. A session-start hook says which project owns your directory before your first
turn; run `/project` yourself for the full report, or to create, switch, or close one.

## What a project is

A project is three things:

- **A folder**, holding a state file and a notes file. The state file holds every fact a
  script reads: the code path, the name, the frameworks, the lifecycle state, and settings
  that start empty and fill in as later stages run. The notes file is yours; nothing ever
  parses it.
- **An entry in AIDA's own list**, mapping the code path to that folder. This is how a
  session in a different working directory still finds the right project. The entry copies
  the name, the last-used date, and the lifecycle state, so those three questions never
  need thirty-one files opened to answer them.
- **A git repository of its own.** Every project gets one. It tracks text: the state file,
  the notes, and the small records each stage writes. It ignores everything else by
  default, so a new kind of file is left out, not silently let in. If something got ignored
  that should have been tracked, the check names it.

A project always points at code. There is no docs-only project, and no project with an
unknown code path: a fresh project names where the code will live, even before anything
exists there. A project covers one code path; two plugins living in one repository are two
projects, each registered by its own path, and work done in one never turns up in the
other.

The state file is the truth about a project. The list is an index built from copies of what
the state file says, kept only so a directory or a name can be resolved without opening
every project's own file. When the two disagree, the state file wins, and the check says so
rather than picking one quietly.

## Creating a project

`/project create <path> [framework...]`

Creation asks for three facts: where the code lives, what stack it is written in, and what
to call it.

The code path is proposed, not asked blind: standing inside the code when you run this,
AIDA offers the current directory and you confirm it. Give a path as an argument and that
is used instead, still confirmed. Standing somewhere that is not the code, AIDA has nothing
to propose and asks directly.

The framework comes from the code itself: a composer file, a package file, a go module, a
Python project file, or a Drupal info file. This is a deterministic read, done by a script,
never guessed. Give framework names as arguments and detection is skipped for the ones you
named; detection runs for the rest. Only when nothing is recognised does AIDA ask what stack
this is.

The name is always asked. Deriving it from the code folder would save one question and buy
a collision problem the moment two projects share a folder name, so this is the one fact
creation never infers.

Once every fact is known, AIDA writes the project's state file with defaults for everything
else, adds the project to its own list, and turns the project folder into a git repository.
Then the check runs once. If the code already exists on disk, the check normally has
nothing to report. If it does not exist yet, the check says so, and that is expected for a
fresh project, not a problem.

Later stages fill in the rest as they run: which recipe each stage adopted, which sources
answer for which kind of content, whether visual regression or end-to-end testing is set
up, whether a memory hook is installed, and whether the task rule has been offered. None of
this is asked at creation; each field is filled in by the stage that first needs it.

**Safety on the code path.** This value is the root for everything AIDA later does against
your disk: worktrees, harness installs, the task rule, prior-art search. A path naming a
system root or your home directory is refused outright, and so is any path above your home
directory. A path outside your home is accepted, with a warning, because plenty of code
lives there on purpose.

## Finding your project

Run `/project` with no arguments. AIDA works out which project you mean before you type
anything else, in this order.

1. **The current directory sits inside a registered code path.** That project wins. This is
   the common case, and it needs nothing remembered: standing inside a project's own code
   is enough to be recognised.
2. **The directory is not code, and AIDA remembers the project you last chose from it.**
   That remembered choice wins, because nothing else answers. This is the case for a
   documentation folder, or an AIDA session folder whose code lives somewhere else.
3. **Both are true, and they disagree.** The registered code path wins over the remembered
   choice. Being told you are on another project because you said so weeks ago, from a
   folder that has since moved on, is the more surprising failure. Switching by hand still
   works for the rest of this session.
4. **Neither is true.** AIDA shows your projects, ordered by when you last used each one,
   and you pick one. That folder now works on that project for this session.

Found, AIDA runs the check and reports what it sees. Not found anywhere, AIDA offers to
create a project here instead. Decline once, and it remembers: it will not ask again for
this folder.

Opening an older project this way is the same operation as opening a brand new one: it
becomes the active project for this conversation, and the check runs on the way in.

## Switching to another project

`/project switch <name-or-path>`

Switch looks the target up by its exact name or its exact code path, never by ancestry, and
loads it into the current conversation if found. Not found, AIDA says so and stops.

Switching from inside a directory that is not itself a registered code path is remembered:
the next time you run `/project` from that same directory with no arguments, this is the
project it finds, per case 2 above. Switching from inside a registered code path changes
only this conversation; a directory that already resolves on its own is not worth
remembering a second way.

## The check

The check is a script, never a judgment call by the model. It compares the project's state
file against the shape it should have, and reports what it finds. It runs automatically
every time you report, create, or switch a project. You can also run it directly against a
project folder.

Three things can come back from comparing the file against its shape:

| What the check finds | What happens |
|---|---|
| Everything present and well-formed | Nothing is said. |
| A field missing, or present but the wrong shape | Named, with the step that produces it offered as the repair. |
| The code path does not exist on disk | Reported as a fact. Right after creating a project, this is expected. Anywhere else, only you can say where the code went, and nothing here fixes it. |

A schema checks shape, not truth: it says a code path is a string shaped like an absolute
path, not that the folder still exists, and it cannot say two entries in the list share a
name, because a schema expresses one entry's own shape, not a relationship between two
entries. So the check runs the schema comparison, then runs the tests a schema cannot
express, and says which it did: whether the project folder is a git repository at all, and
whether it holds work that was never committed. Either finding is a fact worth seeing before
you start a new stage on top of it; neither is repaired automatically.

Repair means running the one step that produces a flagged field again. It is never the
whole creation interview, and never a guess, and it never overwrites a value already
present, so running the check twice in a row changes nothing. Checking is cheap, so it
always runs; repairing is not, so it is only ever offered.

## Ending a project

A project carries one of three lifecycle states, and every transition between them is
reversible: reopening is another write, in either file.

- **Active** is normal. It appears in your project list and is offered as work.
- **Complete** means the work is done. It still resolves when you stand in its code, it is
  still readable, and it stops being offered.
- **Archived** means parked: not worth considering for now, on hold, or the work went away
  for other reasons. It still resolves, because a directory that silently answers nothing is
  worse than one that says this project is archived, but it stays out of your project list
  unless you ask to see archived ones too.

The state file is authoritative for this value; the list carries a copy, so it can be shown
without opening every project's own file, and the reason for a change lives in the commit
that made it, never in the state value itself.

Closing a project that still has unfinished work says what is still open and lets you
decide, rather than refusing outright or pretending nothing was left.

**Unregistering is not one of the three states.** It drops the project from AIDA's list and
leaves the folder untouched, so it is recoverable by pointing at the folder again. This is
the answer for a duplicate entry or a mistake, not for work that is merely done or parked.

## Cleaning up

**AIDA never removes a project folder.** Cleanup stops at unregistering and uninstalling,
and names the path so you can delete it yourself if you choose to. That keeps the whole
project surface non-destructive on your filesystem.

Deleting a project's entry never touches your code, and unregistering never touches the
project folder either.

Uninstalling removes only AIDA's own instructions: the marker-delimited task-rule block, when
one was installed. It never touches tests, test configuration, or any tooling. A harness AIDA
scaffolded, once it lands, belongs to the code the same way a linter does, and removing it
would be deleting your tests rather than tidying up after AIDA.

The memory hook has no installer yet in this build. Uninstalling reports what it would remove,
the primer, its script copy, and the settings entries, once that installer exists; today it
touches none of them, since none of them exist to touch.

Cleanup is usually plural, once a project list carries a real last-used date and a real
state: a project whose code path is gone, a duplicate entry, and one you have registered but
never actually opened are the three cases worth finding at once rather than one at a time.

## Interactive and autonomous work

AIDA runs in two modes: interactive, where a person is present to answer, and autonomous,
where nobody is. Which mode applies belongs to the task doing the work, not to the project:
a project keeps no mode of its own. A task that states no mode is treated as interactive,
because assuming a person is present is the safer of the two guesses.

Two moments on this page ask a question, and each has an autonomous branch:

- **Offering to create a project** on a folder nothing is registered to. Interactively, AIDA
  asks. Under an autonomous task, AIDA records that the offer was made and declined, and
  moves on: no project was going to exist without an answer either way.
- **Naming a new project at creation.** Interactively, AIDA asks. Under an autonomous task
  with no name given as an argument, there is nothing to found the project on, so AIDA halts
  and reports exactly what is missing, the same as it does for a missing code path or a
  framework nothing could detect. This is the one step that halts rather than guessing,
  because creation writes a folder and a list entry that a guessed name would make wrong
  from the start.

The check itself never asks, in either mode. When it finds a field missing, it names the
field and the step that produces it, the same way whether a person is present or not. Under
an autonomous task, it also records that nobody was present to decide on a repair; the field
stays missing until its producer runs.

## Using your own guides, playbooks, and recipes

Guides, playbooks, process recipes, and agentic recipes are one mechanism, not four separate
ones. A project declares as many sources as it wants, and each source says what it provides,
what it answers for, and where it ranks against every other source offering the same kind of
content. Mixing is the point: your playbooks can come from your own folder, your process
recipes from the hosted catalog, and your guides from a site your team trusts, all at once.

A new project declares no sources at all: the list starts empty, for every kind of content.
Declaring is cheap and fetching is lazy, so nothing is fetched from the hosted catalog, or
from anywhere else, until a later stage first needs a guide, a playbook, or a recipe and
finds no source declared for that kind. Pointing a kind at your own source instead, a local
folder or a site you trust, makes that source win over the catalog for that kind.
You can set this per kind, per stage, and per framework: a team's own method for one stage
can stand alongside the catalog's answer for every other stage.

**Which playbooks apply is its own decision, separate from where they are found.** A source
says where playbooks can be found; subscribing to one is a standing choice, recorded per
framework, so a Drupal project's playbook subscriptions and a Python project's never mix by
accident the way they could before.

A source's own precedence applies per kind it provides, not as one number covering
everything it offers, because a source's playbooks winning says nothing about whether its
process recipes should win too.

Declaring a source is cheap: it writes one entry. Fetching what it provides is lazy: a stage
resolves the actual guide, playbook, or recipe body the first time it needs one, following
whichever source is declared to answer. A cell no stage ever reaches is never paid for.

A source that is a folder is read as a directory listing. The hosted catalog is read through
the guides navigator. A site or a live search can fail, or return nothing, and what either
returns was written by nobody you configured: a body from a source you configured is used
directly, and a body from an open search is shown to you before it is used, because that is
the one place a model's own find enters the process as if it were an authority.
