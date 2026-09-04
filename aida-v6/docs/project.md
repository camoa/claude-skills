# The project

A project ties one code path to the work AIDA does on it. Everything else — tasks, stages,
recipes — happens inside a project. This page covers how a project is found, created, and
switched, what the check does, and how both run modes affect these steps.

One skill answers all three questions: which project owns this folder, create one, or switch to
another. Type `/project`, with or without arguments. Most of the time you type nothing: AIDA
already knows which project a folder belongs to.

## What a project is

A project is three things:

- **A folder** with a small state file and a human notes file beside it. The state file holds the
  facts a script reads — the code path, the frameworks, and a handful of settings that start empty
  and fill in as later stages need them. The notes file is yours: write anything there, and nothing
  ever parses it.
- **An entry in AIDA's own list**, mapping the code path to that folder. This is how a session in
  a different working directory still finds the right project.
- **A git repository of its own.** Every project gets one. It tracks text — the state file, the
  notes, and the small records each stage writes — and ignores everything else by default, so a
  new kind of file is left out rather than silently let in. If something did get ignored that
  should have been tracked, the check names it.

A project always points at code. There is no docs-only project and no project with an unknown
code path — a fresh project names where the code will live even before anything exists there.

A project covers one code path. Two plugins living in the same repository are two projects, not
one project with two parts, each registered by its own path. Work done in one does not turn up
when you are working in the other, even in the same repository.

## Finding your project

Run `/project` with no arguments. AIDA looks at the current directory and finds the most specific
registered code path that contains it — if a directory sits inside more than one registered
project, the closest match wins. Found or not, AIDA then runs the check (below) and reports what
it sees.

If nothing matches, AIDA offers to create a project here. Decline once, and it remembers: it will
not ask again for this folder. Accept, and creation runs, described next.

**A session identifies the project by code path only.** Standing in some other folder — a working
folder that is neither the code nor the project's own folder — resolves to no project, on purpose.
Being inside the code is one way to be recognized, never the only way; recognition also comes from
switching to a project by name, described below.

## Creating a project

`/project create <path> [framework...]`

Creation asks for exactly two things: where the code lives, and what stack it's written in.
Nothing else. Give both as arguments and nothing is asked. Give neither, and AIDA asks for them.

From those two facts, AIDA writes the project's state file with defaults for everything else,
adds the project to its list, and turns the project folder into a git repository. Then the check
runs once, and normally has nothing to report.

Later stages add more to the state file as they run — which recipe each stage adopted, whether
visual regression or end-to-end testing is set up, whether a memory hook is installed, and so on.
None of that is asked at creation. Each of those fields is filled in by the stage that needs it,
the first time it is needed.

## Switching to another project

`/project switch <name-or-path>`

Switch looks the target up in AIDA's list and, if found, loads that project into the current
conversation. Nothing is written to disk.

That matters: switching is a fact about this conversation, not a lasting pointer. Open a new
terminal in the same folder afterward, and it resolves fresh by code path, exactly as if the
switch had never happened. If you work across two projects from one folder often, switch each
time you need the other one.

## The check

The check is a script, never a judgment call by the model. It compares the project's state file
against the shape it should have and reports what it finds. It runs automatically every time you
report, create, or switch a project, and you can also run it directly against a project folder.

Three things can come back:

| What the check finds | What happens |
|---|---|
| Everything present and well-formed | Nothing is said. |
| A field missing, or present but the wrong shape | Named, with the step that produces it offered as the repair. |
| The code path no longer exists on disk | Reported as a fact. Nobody but you can say where the code went, so nothing offers to fix this automatically. |

Repair means running the one step that produces that field again — never the whole creation
interview, and never a guess. A field already present is never overwritten, so running the check
twice in a row changes nothing.

Checking is cheap, so it always runs. Repairing is not, so it is only ever offered, never forced.
A stage that later needs a field the check flagged as missing can trigger that one repair on the
spot, without your having to run the check yourself first.

## Interactive and autonomous work

AIDA runs in two modes: interactive, where a person is present to answer, and autonomous, where
nobody is. Which mode applies belongs to the task doing the work, not to the project — a project
keeps no mode of its own. A task that states no mode is treated as interactive, because assuming a
person is present is the safer of the two guesses.

Two moments in this page would otherwise stop and ask:

- **Offering to create a project** on a folder nothing is registered to. Interactively, AIDA asks.
  Under an autonomous task, AIDA records that the offer was made and declined, and moves on —
  nothing is lost, because no project was going to exist without an answer either way.
- **Offering to repair a field the check finds missing.** Interactively, AIDA asks. Under an
  autonomous task, AIDA records that a repair was proposed with nobody present to answer, and
  moves on. The field stays missing until something repairs it later.

One moment does stop outright, in either mode: creating a project with neither a code path nor a
framework given, and nobody present to supply them. There is nothing to found the project on, so
AIDA reports what is missing instead of guessing at a path or a stack.

## Using your own guides, playbooks, and recipes

By default, every new project reads from AIDA's hosted catalog. A project can instead supply its
own source for guides, playbooks, or process recipes — a local folder, or a site your team
prefers — and where it does, its own source wins over the catalog. This can be set per kind of
content and even per stage, so a team's own method for one stage can stand alongside the catalog's
answer for every other stage.

The project's state file already reserves the place for this: an ordered list of sources, written
at creation with one entry — the hosted catalog — and a way to override that order per stage and
framework. **The screen that lets you add your own source and set precedence is not built yet.**
Until it is, every project reads from the catalog only. This page will be updated once that
surface exists, and the ordered-list mechanism is designed so nothing about creating or switching
a project changes when it does.
