---
name: design
description: This skill should be used when a task's criteria are grounded and it is time to decide how to build them, for example "design this task", "write work orders", "architect this feature", "plan the build", or "Phase 2". It writes one work order per unit of build, each naming the criteria it serves and the one it owns, and checks that every criterion is covered and every work order traces to something real.
disable-model-invocation: true
argument-hint: "[<task-id>]"
arguments: [taskId]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/design/scripts/design-actions.sh *), Bash(${CLAUDE_PLUGIN_ROOT}/skills/research/scripts/research-actions.sh *), Agent
---

# Design

Design decides how, and writes work orders. The work orders and the order they run in are the
architecture: there is no separate architecture document, no overview file, and no file per
component. A work order is a small unit of build that four roles can each act on without asking
what was meant: one writes the tests, one writes the code, one criticises the result, one applies
fixes.

Design does not write code and does not run tests. It does not decide whether a criterion is
right; that was scope's conversation. It reads what research found, decides fit, and writes the
orders that build it.

Design's own records go through `design-actions.sh`, named in this skill's own grant, so they run
without asking. One write below goes elsewhere. A lookup is recorded through the research skill's
`research-actions.sh`, because that script is the single producer of a research finding, and it is
named in the grant too. Any other Bash command still asks for approval. Dispatching an agent needs
no approval either; it is also named in this skill's own grant.

## Determine the run mode

Look for a stated run mode on the task active in this conversation. Found, and it says
`autonomous`: act autonomously through this whole invocation. Anything else, including no active
task: act interactively, the safe default. Decide this once, at the start.

## Find the task

Resolve the active project's own folder first, then the task, `<taskId>` when given or whichever
task is already active in this conversation. Neither known: say so in one line and name the task
skill. Stop; there is nowhere to write.

Once found, the task's own folder is `<projectPath>/tasks/<task-id>`. Every call below takes that
folder.

## Read what is already there

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/design/scripts/design-actions.sh read "<task_folder>"
```
This reports whether the task has an approved contract, lists its criteria and non-goals, and
lists any work order already on disk for this task.

No contract: say so in one line and name the scope skill. Stop; a work order with nothing to
serve is nothing this stage can check.

Work orders already present: this is a resumed or repeated run. Read each one's own file before
drafting anything new, rather than starting over.

Then read every file under `<task_folder>/research/`, one search at a time. Each holds findings
for one subject: prior art inside the project, prior art outside it, guides and recipes, what
reputable sources recommend, or an assumption checked. A criterion with no research at all is not
a reason to stop; it means design decides from nothing found, same as when research covered it.

## Read the guides and recipes research found

Research named these without opening them, so design is the first read. Research recorded an
address for each; open it through the navigator the same way, and read a project's own source
directly. One agentic recipe
covering the work means the decision is already made: follow it. Two: read both, pick the one
that fits, say why, and build from that one alone. None: architect from the findings and from
this project's own conventions; this is where design quality shows.

## Read the process recipe for this project's framework

Ask the navigator's process-recipe lookup for this project's framework at the design stage. It
answers whether one is available and, when it is, a path to the body on disk. Read the body from
that path. Never fetch a catalog address yourself and never read a cached copy behind the
navigator's back. A source this project configured itself, a folder of its own, is read the
ordinary way.

**Three answers, not one.** No recipe for this framework, a listing that could not be reached, and
a failed network are three different things, and only the first says anything about the framework.
Record which one happened, in those words.

This is what makes the work orders right, and no check below can replace it. Read it for what
AIDA cannot know on its own:

- What kinds of thing a work order can be about here. In Drupal a module, a service, a plugin, a
  theme, a component, a configuration entity. This is what an order is sized around.
- What is built with configuration rather than code. A view or a content type is a work order
  with no code in it, and it still states a test.
- What has to exist beside a class for it to work: a services entry, a route, a permission, a
  schema. Name these in the order, or whoever builds it invents them.
- What one unit exposes to another, which is what the `interface` field holds.
- What must exist beside a class for the unit to work: a services entry, a route, a permission,
  a schema. Name these in the order, or whoever builds it invents them.
- What order the framework forces, where it forces one.

**No recipe covers this framework:** say so, and write `written without framework input` into the
`reasoning` of every order in this pass. Do not invent a kind of unit and do not guess at a
framework convention.
Interactive: ask whether to write the recipe first, before drafting anything. The shape is in
`${CLAUDE_PLUGIN_ROOT}/templates/process-recipe-design.md`, which carries the sections the catalog
requires and the five things design needs from a framework.

## The stated approach

A task may carry a stated approach in `task.json`'s `mechanismHints`, recorded by scope. Read it
as a claim, never as a specification, whatever its `status`. Weigh it against what research found
the ordinary way; a `required` status means it must be followed once judged sound, not that it is
exempt from judgment. The grounding-hash check that would catch a claim edited after research
looked at it is not yet built; until it is, read the claim as recorded and judge it on its current
merits.

## The reuse decision

For every prior-art candidate research handed over, ranked by closeness, give it an answer:
reuse, extend, or supersede, in that order. An unanswered candidate is a proposal nobody acted on.

Decide fit by the candidate's own distance (same name, same directory, same layer) and by version
5's own cost model: build cost is paid once, carry, agent and risk cost are paid forever. A
candidate is not always code; an existing view or content type is a candidate too, and extending
it may produce no code at all.

Record the disposition through the script that will own the work order it lands on, never only in
your own reasoning: once that work order exists, set its `reasoning` field to name the candidate,
the disposition, and why, with:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/design/scripts/design-actions.sh update "<task_folder>" \
  --id <woId> --reasoning "<candidate, disposition, and why>"
```
A rejection that lives only in the conversation is not a rejection anyone can check later.

**Autonomous:** after recording a disposition, dispatch `disposition-confirmer` to check it. Name
the role; a dispatch that names none runs as the general agent with write tools and this session's
model, and this one has to be read-only to mean anything.

Give it the written reasoning and the files it cites, and nothing else. Never this conversation's
own account: being denied that is the entire reason the role exists, and handing it over turns the
check into the decision reading itself. It answers agree, disagree, or downgrade, with what it
compared. Record what it found the same way, appended to the same `reasoning` field.

Interactive runs do not dispatch it. A person read the reasoning, and the role has nothing to add.

## Look up what you decided to use and research did not

Design names things research had no reason to search for: a particular module, a framework API, a
pattern. Those were not decisions yet when research ran, so no search covered them.

First read what research already searched for. Every `research/<search>.json` carries
`searchedFor`, the words that search used. A name inside those words was searched, and the answer
is already in that file. Do not pay for it twice.

For a name that was not searched, ask the navigator to identify guides and recipes covering it.
Identify only. It returns names and never resolves a body, so one name costs one lookup. Read a
body only when a match is worth reading.

Record the answer through research's own record action. The research store keeps one producer
that way, and the finding is checked the same way as every other:

```
"${CLAUDE_PLUGIN_ROOT}"/skills/research/scripts/research-actions.sh record "<task_folder>" \
  --search design-lookup-<name> --searched-for "<the words this lookup searched for>" \
  --text "<what was found, or that nothing was>" --source "<where it came from>" \
  --criteria-served <id[,id...]>
```

**One lookup is one search, with a name of its own.** `<name>` is the thing you looked up, in
lowercase letters, digits and single hyphens: `design-lookup-responsive-image`. Never put two
lookups in one search. A search records one set of words, and a second set is refused.

**Always give the criteria.** You are looking this up for a work order, and that order serves
criteria, so give their ids. A finding attached to no criterion is reported as work nobody asked
for, and it turns the research check red.

Record a nothing too. A name looked up with no guide behind it is a fact the implementation stage
needs, and it stops the same lookup running again there.

Do this again while drafting, whenever an order names something new. A guide found late still costs
less than a guide found after the code is written.

## Design never silently changes the scope

Drafting work orders turns up criteria nobody wrote, and criteria that cannot be built as stated.
Neither is design's to fix alone.

Interactive: say what was found and ask the person before proceeding, then use the scope skill's
own update path if the contract needs to change.

Autonomous: record what was found in the work order's own `reasoning` field and continue. A
recorded note reaches a person; a silent change or a silent skip does not.

## Size a work order

Three to seven build steps, ten at the most. Split when the steps mix independent concerns, or
mix phases. Merge two orders when each has fewer than three steps, they address the same
component, and they cannot run in parallel anyway.

A shared decision, like one base class serving two later orders, lives in the order that builds
the shared thing, in its own `reasoning`. The orders that depend on it point at it through
`dependsOn`; nothing else needs to hold that reasoning.

## Draft each work order

For each unit of build: agree its title, which criteria it serves, and, when it produces the
observable outcome a criterion describes, which one it owns. Most orders own none. Exactly one
order owns each criterion; if two orders both seem to produce the same outcome, that is a sign the
work is split wrong, not a sign both should claim it.

Create it:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/design/scripts/design-actions.sh create "<task_folder>" \
  --title "<what this builds>" \
  [--criteria-served <id[,id...]>] [--criteria-owned <id[,id...]>] \
  [--non-goals <id[,id...]>] [--depends-on <id[,id...]>] \
  [--interface "<what it exposes to what depends on it>"] \
  [--reasoning "<why, if this is a shared decision>"] \
  [--diff-budget "<a plain-words signal, e.g. small: one class and its test>"]
```
This mints the next id and writes the file. `dependsOn` may name a work order not yet created in
this conversation; the id space is shared and minted in order, so naming it ahead of its own
`create` call is safe as long as it is created before design finishes.

Then, one call per item, add what the order still needs:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/design/scripts/design-actions.sh add-owned-file "<task_folder>" \
  --id <woId> --path "<path or glob this order may write>"
"${CLAUDE_PLUGIN_ROOT}"/skills/design/scripts/design-actions.sh add-done-when "<task_folder>" \
  --id <woId> --text "<what must be true for this order to be finished>"
"${CLAUDE_PLUGIN_ROOT}"/skills/design/scripts/design-actions.sh add-test "<task_folder>" \
  --id <woId> --description "<what this test must observe>"
```
A criterion whose `verifiedBy` is `machine`, on the order that owns it, needs at least one test
here; the check below refuses an order that skips this. A criterion whose `verifiedBy` is
`person` needs no test, though one is never wrong to add.

To change a scalar or an id list on an order already created, `update` takes the same flags as
`create`, replacing whichever are given:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/design/scripts/design-actions.sh update "<task_folder>" \
  --id <woId> [--title <text>] [--criteria-served <id[,id...]>] \
  [--criteria-owned <id[,id...]>] [--non-goals <id[,id...]>] [--depends-on <id[,id...]>] \
  [--interface <text>] [--reasoning <text>] [--diff-budget <text>]
```

## Serving a criterion is not completing it

The decidable half is what the check below counts: an owner exists, is exactly one, and declares
a test when the criterion needs one. Whether the named order actually produces the outcome, and
whether its tests actually observe it, is judgment, and it needs a person.

**Interactive:** for each criterion, show it beside the one order claiming to own it, and ask
whether that order is really going to produce this outcome. One order to look at, not a list of
every order that mentions the criterion. A no means the work is drafted wrong; revise the orders
involved before moving on.

**Autonomous:** do not skip this and do not mark it passed. State plainly, once, at the end of
this run, that per-criterion ownership was judged by shape only and not by a person, and name
which criteria that leaves unconfirmed. This is not a failure; it is the honest state of an
unattended run, and it is what the end-of-task review will actually test.

## Run the design check

Once every criterion has a drafted owner, run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/design/scripts/design-actions.sh check "<task_folder>"
```
This reads every work order's JSON and reports, in one JSON object:

- a work order file with a missing, empty or malformed required field;
- every criterion with no work order serving it, and every criterion owned by zero or by more
  than one work order;
- every work order serving no criterion;
- every work order that owns a machine-verified criterion and declares no test;
- every work order that owns nothing and cannot reach an owner by walking `dependsOn`, and every
  dependency cycle;
- two work orders sharing a declared owned file;
- any criterion, non-goal, or work order id named anywhere that resolves to nothing real.

Exit 0: nothing to do. Design is finished, subject to the judgment step above.

Exit 4: a work order file itself is broken: not valid JSON, not an object, or a missing or
malformed required field. Fix it with another `update` call, or by hand, and check again.

Exit 5: the schema is fine but a content or cross-order check is not. Read the named list and fix
the specific order it names:
  - a criterion with no serving order needs a work order that names it in `--criteria-served`;
  - a criterion with no owner, or with more than one, needs its `--criteria-owned` reconciled so
    exactly one order claims it;
  - a work order serving nothing needs a real `--criteria-served`, or it should not exist;
  - a work order missing a required test needs an `add-test` call;
  - an order that reaches no owner needs a `--depends-on` pointing toward the order it supports,
    or it is dead work and should be dropped;
  - a cycle needs one of the `dependsOn` edges in it removed;
  - overlapping owned files need one order's `ownedFiles` narrowed so the paths do not repeat;
  - an unknown id needs correcting to one that actually exists.

Then check again. Exit 3: the script could not run the check at all. Read its stderr and fix the
named problem, then check again.

Design is done when this check comes back clean. Nothing else counts as done.

An earlier version of this skill said a content or cross-order problem could be left open with a
reason recorded in an order's own `reasoning`. It cannot. Every one of those problems is an
assumption implementation builds on: a criterion with no order producing it, a criterion two orders
both claim, and two orders declaring the same file. Implementation refuses to start on any of them
and tells the person to finish design, so leaving one open only moves the stop to a later and more
expensive place.

## Close the design

Once design is done, close it. Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/design/scripts/design-actions.sh close "<task_folder>"
```

This runs the design check again. It writes `design-closed.json` only when that check exits clean.
Closing records what design closed on: a hash over the contract and every work order.

A design left open at exit 5, with a reason recorded in an order's own `reasoning`, is not closed.
Closing needs a clean check. Resolve the open item first, or record why it cannot close yet, and
tell the person before you stop.

Implementation reads this record before it freezes anything. It refuses to start on a contract or
a work order that does not match the recorded hash. This is what catches a work order edited after
design closed but before implementation started.

Did a work order change after closing? Close again. A second close is allowed and expected. It
replaces the old hash with the new one. Closing again is the supported way to change a design that
already closed.

## What this skill never does

It never writes a single overview file or a file per component. The work orders are the whole
deliverable.

It never mints a second id for a criterion or a non-goal. It only ever names the ids scope already
minted in `alignment.json`.

It never treats a criterion nobody could confirm as owned as if it were owned. An autonomous run
says plainly what it did not judge.

It never reads `design/<id>.md`, the rendered file, back into anything. It is for the four roles
who build from a work order to read; nothing here parses it.

It never accepts an opinion from a source research marked as not accepted by this project as
settling anything on its own. It informs the design; it does not decide it.
