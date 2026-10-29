---
name: design
description: This skill should be used when a task's criteria are grounded and it is time to decide how to build them, for example "design this task", "write work orders", "architect this feature", "plan the build", or "Phase 2". It writes one work order per unit of build, each naming the criteria it serves and the one it owns, and checks that every criterion is covered and every work order traces to something real.
argument-hint: "[close] [<task-id>]"
arguments: [taskId]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/design/scripts/design-actions.sh *), Bash(${CLAUDE_PLUGIN_ROOT}/skills/research/scripts/research-actions.sh *), Bash(${CLAUDE_PLUGIN_ROOT}/skills/surfaces/scripts/surfaces-actions.sh decline *), Bash(${CLAUDE_PLUGIN_ROOT}/skills/surfaces/scripts/surfaces-actions.sh read), Bash(${CLAUDE_PLUGIN_ROOT}/skills/task/scripts/task-actions.sh defer-surface *), Bash(${CLAUDE_PLUGIN_ROOT}/skills/project/scripts/project-actions.sh recipe-source *), Agent, EnterWorktree
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
named in the grant too. So is the project skill's `recipe-source` lookup. Any other Bash command
still asks for approval. Dispatching an agent needs no approval either; it is also named in this
skill's own grant.

`design-actions.sh` and `research-actions.sh` take a text value from a file. Write the text with the
Write tool in the session's scratchpad folder. With no scratchpad, write it in the task folder, and
delete it after the call. Then pass `@/<absolute path>` as the value. Use this for a text that names
a command, such as git. Claude Code refuses a command whose quoted text names git when the session
works in a worktree.

**The dispatch message is the role, the run mode and the paths.** Name the role on the Agent
call, and set the model where the step says. The message itself is one line per item: the run
mode, `interactive` or `autonomous`, then each path the step hands over. One word a step names,
a lens or a stage, is a line too. Nothing else goes in. The role's rules and its return shape
live in its agent definition, which reaches it on every dispatch. So the message restates
neither, and two runs of one step hand the role the same words. Each dispatch below names this
shape and lists its own paths.

## Determine the run mode

Look for a stated run mode on the task active in this conversation. Found, and it says
`autonomous` or `light`: act autonomously through this whole invocation. Anything else,
including no active task: act interactively, the safe default. Decide this once, at the start.
A mode that names stages in brackets, such as `autonomous (implement)`, covers this stage only
when the list names `design`; otherwise this stage is interactive.

## Find the task

Resolve the active project's own folder first, then the task, `<taskId>` when given or whichever
task is already active in this conversation. Neither known: say so in one line and name the task
skill. Stop; there is nowhere to write.

An invocation line whose first word is `close` is the person's yes on the design. The task is
the word after it, or the active one. Go straight to "Close the design" below. When no
`design-critique-*.md` exists yet, under `records/` or under `design/`, run "Critique the design"
first. An earlier close moved the files into `design/`, so look in both. A name that begins
`unfinished-` is a critique that stopped, and it counts as no critique here. A light task runs no
critique, so go straight to the close.

Once found, the task's own folder is `<projectPath>/tasks/<task-id>`. Every call below takes that
folder.

## Read what is already there

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/design/scripts/design-actions.sh read "<task_folder>"
```
This prints summary lines. `contract:` says present or absent and `contract-file:` names the
file. `criteria:` and `non-goals:` list ids only. `work-orders:` is a count, and one `work-order:`
line names each file already on disk. Read the criteria's text from the contract file when
drafting.

`read` is the one call here that runs from anywhere. Every other call refuses at exit 79 when
the task builds in its worktree and this window is elsewhere. The refusal names the tree and the
route that works from here, either the `EnterWorktree` tool or the call started with
`cd <worktree> &&`. Take the route it names, the way `/aida:next` does, and run the call again.

`contract: absent`: say so in one line and name the scope skill. Stop; a work order with nothing
to serve is nothing this stage can check.

`work-orders:` above zero: this is a resumed or repeated run. Read each named file before
drafting anything new, rather than starting over.

A reopen that changes only owned files, done-when rows or accounted findings on an existing
order may skip the research and guide reading below. Those calls are `add-owned-file`,
`remove-owned-file`, `add-done-when`, `remove-done-when` and `account`. The reading informs an
order's shape, not its file list. The route is the change, then `check`, `close` with the verdict the last
`design-closed.json` records, and `distill`. A reopen that creates or merges an order, removes
one with `remove --id --reason`, or changes an order's interface, criteria or dependencies, reads
as a first run does. Recording an old merge with `remove --merged-into` changes no order, so it
takes the cheap route above. Once implementation has a snapshot, an order `create` adds enters
the build at the next `start`, after this close. A defect that a review found is fixed on the
task branch, and implementation's `finish` runs again.

Four changes do not stop an order that implementation already started: an added owned file, an
`account` call, a reason added with `update --append-reasoning`, and a row marked with
`update --absence-reviewed`. Once design closes again,
the next `start` takes that order's live copy in place, even when the order closed. Any other
change to a started order stops it for design drift at the next `start`. Two routes lead back.
Restore the design and `start` clears the stop. Or take the redo in the implement skill's
`references/finish.md`, which rebuilds the order against the new design. The cheap reopen stays cheap for an order that has not started.

Then start design:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/design/scripts/design-actions.sh start "<task_folder>"
```
Research is optional. When it has not closed, `start` goes on and writes a warning to the task
record; say so to the person. A `NOTE:` line names a stated mechanism edited after research
grounded it; read that claim as ungrounded.

Then account for each research finding. Each `<task_folder>/research/<search>.md` holds the
findings of one search, numbered from 1. A finding is named `<search>#<n>`. Each finding is used
by an order or set aside with a reason. A finding that names a collaborator, a service, a
convention or a constraint is used by the order it affects. A finding that says nothing was found
is accounted for too. A need no finding covers is looked up first, as "Look up what you decided
to use and research did not" says. Once the orders a finding affects exist, record the finding on
every one of them:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/design/scripts/design-actions.sh account "<task_folder>" \
  --id <woId> --finding <search>#<n> [--set-aside "<why this order does not use it>"]
```
Without `--set-aside`, the order uses the finding, and the build brief carries its text. A
second call for the same finding on the same order replaces the entry. `--remove` in place of
`--set-aside` deletes it. `check` prints an `unaccounted:` line for each of three cases. A finding
is in no order's list. Research changed a finding's text after it was recorded. An entry names a
finding research no longer holds. A person's `close` writes each one to the task record as a
warning. An unattended `close` refuses, exit 7. Both modes account the same way.

Then read `<task_folder>/records/playbooks.md`. It holds the plays research loaded,
the rules this project and this person want followed. Name a play that decides an order's shape
by its id in that order's `reasoning`.

## Read the guides and recipes research found

Research named these without opening them, so design is the first read. Research recorded an
address for each; open it through the navigator the same way, and read a project's own guide file
directly. Open a tooling recipe with the navigator's `tooling --name` mode, by the name research
recorded. One agentic recipe covering the work means the decision is already made: follow it.
Its `## Verifier` becomes the proof of each order it covers, as "Carry the proof from its source"
says. Two: read both, pick the one that fits, say why, and build from that one alone. None:
architect from the findings and from this project's own conventions; this is where design
quality shows.

Record each body as it is read, once the navigator has given its path on disk:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/design/scripts/design-actions.sh read-guide "<task_folder>" \
  --path "<the body's path on disk>" [--name "<the name research gave it>"]
```
It writes one entry per path, with the body's sha256 and the date, to
`<task_folder>/design-guides-read.json`. Give `--name` when research named the guide, so the
entry joins its finding. A second read of the same path replaces the entry and keeps the name
when none is passed. A path naming no file is refused: record only what was read. Nothing else
records which bodies design opened, and a later session cannot ask this one.

`read` and `start` print `guidesRead:`, the count. On a resumed run, when `work-orders:` was
above zero, they also print one `guide:` line per entry: `changed`, `unchanged` or `missing`.
Read the `changed` ones, and the ones research named that no entry records. A `missing` body is
gone from its recorded path; resolve it through the navigator again and read it. Skip the
`unchanged` ones; a body the first run read, and that has not moved since, is not read again. No
entry at all means the first run recorded nothing, and every body is read.

## Read the process recipe for this project's framework

The project's own sources answer before the catalog, so ask them first, once per framework:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/project/scripts/project-actions.sh recipe-source "<projectPath>" design <framework>
```
It prints one line, or nothing. `RECIPE: <path> source=<folder>`: take that path and skip the
navigator. `RECIPE: catalog`, with or without `searched=<folders>`, or no line: ask the
navigator's process-recipe lookup for this project's framework at the design stage. A folder
that holds nothing is not an answer, so a folder miss never skips the navigator. When
`searched=` is present, record those folders beside the navigator's answer. A later reader then
tells a folder miss from a project with no folder. The no-recipe path below is reached only
after the navigator answers that none exists. The navigator answers whether one is
available and, when it is, a path to the body on disk. Read the body from that path. Never fetch a
catalog address yourself and never read a cached copy behind the navigator's back.
Verdict words and a missing heading follow
`${CLAUDE_PLUGIN_ROOT}/skills/tool/references/reading-a-recipe.md`.

**Three answers, not one.** No recipe for this framework, a listing that could not be reached, and
a failed network are three different things, and only the first says anything about the framework.
Record which one happened, in those words.

**Judge the fit once, after the body is read and before the first order.** Does this method, by
its `description`, Goal and Preconditions, describe the work the criteria and non-goals name? Keep
the verdict, the path and one sentence of reason for `close`. On `false`, interactive: say so with
the reason, then ask one question with four answers. Continue with the recipe, continue without
it (the fallback below), write the recipe first, or stop. Autonomous: continue with the recipe
and record `false`.

This is what makes the work orders right, and no check below can replace it. Read it for what
AIDA cannot know on its own:

- What kinds of thing a work order can be about here. In Drupal a module, a service, a plugin, a
  theme, a component, a configuration entity. This is what an order is sized around.
- What is built with configuration rather than code. A view or a content type is a work order
  with no code in it. It states no test. It is created with `--proof gate`. Its proof is its own
  verify lines, then the implement recipe's `## Configuration gate` lines. The recipe's sizing
  rule decides what it owns.
- What is a document rather than code or configuration: a dependency review, a report, a note.
  Such an order owns files under the project folder, in a folder the project commits, the task
  folder's `deliverables/` by default. A report may land beside earlier reports elsewhere in
  the project folder. Never `records/`, which the project ignores. It states no test.
  Its proof is its done-when rows, so it is created with `--proof record`. `add-owned-file`
  sets that value itself once every owned file lies under the project folder, on an order
  created with no `--proof`. Such a file must live in a folder the project commits: the design
  check refuses a record order that owns an ignored path.
- What is proved by what a page shows rather than by a test. A layout, a rendered block, a
  page as it renders. Such an order is created with `--proof observe`. It names at least one
  `--surface` and declares no test. Each done-when row is the sentence a model judges. After
  the build, the orchestrator opens the page the order builds at one size in a browser. It
  judges the row against what renders, with a screenshot as the evidence. Write each row as one thing
  the page must show. The judge is a model. At review's close, the person answers each such
  criterion from the acceptance verifier's evidence.
- What has to exist beside a class for it to work: a services entry, a route, a permission, a
  schema. Name these in the order, or whoever builds it invents them.
- What one unit exposes to another, which is what the `interface` field holds.
- Where business logic belongs, and what a thin layer may contain. An order that puts logic in
  the thin layer is drafted wrong.
- The entry point every feature has that is not a screen. Name it in the order that builds the
  feature, so the feature is reachable without its UI.
- What order the framework forces, where it forces one.

**The proof follows what the order produces.** Ask what the order leaves behind when it is done,
and pick the kind from that answer:

- Code that a test can pin: `tests`.
- Tools run that change state, such as a dependency update, a database update or a
  configuration export: `gate`. Nothing new exists for a test to pin, and a test written for it
  only restates a file.
- A document or an analysis, such as a report or a review: `record`.
- A document, a recipe, a skill or agent file, or hand-written configuration in the code
  repository: `confirm`. It holds no logic for a test to prove. The reviewer reads it, and the
  person confirms each done-when row at review. `add-owned-file` sets this value itself when
  every owned file is a document or configuration. A `gate` order is never this case.
- Something only a person or a browser can see: `observe`.
- Code, on a task whose contract says it has no automated tests: `confirm`. Nothing runs a
  test. The implementer builds it, one reviewer reads the diff, and the person confirms each
  done-when row at review. `add-owned-file` sets this value itself on such a task, on an order
  created with no `--proof` whose first file is code. The person may pick another kind with
  `update --proof`.
- Changes to tests alone, from an approved test cleanup. A merge, a shrink or a rewrite is a
  `tests` order that owns only test files, and it `reuses` the code its tests call. Whole files
  to delete are one tests-only order: `confirm`, owning only files of the cleanup run the goal
  names. Name each file in a done-when row, and make the order depend on every `tests` order.

A machine-verified criterion does not mean `tests`. Tests prove one, and so do the gate lines and
run lines. A text-only order proves none, so the check refuses it. A look or a record order's
reading proves none either, so the check refuses one an `observe` or `record` order owns, unless a
run line proves it.
Code with logic gets tests even when it owns no machine-verified criterion.
`create` and `update` print `impliedProof:` beside the proof the order declares. It says
`record` when every owned file lies under the project folder. It says `confirm` on a task with no
automated tests, and when every owned file is a document or configuration. Otherwise it says
`any kind` for a machine-verified criterion. What the order produces decides. When the product is truly unclear,
`tests` stays the default, on a task that has tests. A wrongly
tested configuration order wastes one build, and a wrongly untested code order ships unproven.

**No recipe covers this framework:** say so, and write `written without framework input` into the
`reasoning` of every order in this pass. Do not invent a kind of unit and do not guess at a
framework convention.
Interactive, when the navigator found no recipe: ask whether to write the recipe first, before
drafting anything. Reached from a `false` fit, that answer was already put with the fit
question, so do not ask it again. The shape is in
`${CLAUDE_PLUGIN_ROOT}/templates/process-recipe-design.md`, which carries the sections the catalog
requires and the five things design needs from a framework. Skip the ask for a framework that
`task.json`'s `recipesDeclined` names; research recorded that answer.

## The stated approach

A task may carry a stated approach in `task.json`'s `mechanismHints`, recorded by scope. Read it
as a claim, never as a specification, whatever its `status`. Weigh it against what research found
the ordinary way; a `required` status means it must be followed once judged sound, not that it is
exempt from judgment. `start` compared each claim against the hash research recorded at its close.
A claim `start` printed a `NOTE:` for was edited after research looked at it, so its grounding no
longer covers it. Judge it as ungrounded, and send it back to research when it matters.

## The reuse decision

For every prior-art candidate research handed over, ranked by closeness, give it an answer:
reuse, extend, supersede, or decline, in that order. An unanswered candidate is a proposal nobody
acted on. A candidate you find yourself gets an answer too, not only research's list: an exported
configuration entity of the same kind as the unit, say. Decline is the answer for a candidate you
weighed and set aside; recorded, it is told apart later from one nobody weighed.

Decide fit by the candidate's own distance (same name, same directory, same layer) and by version
5's own cost model: build cost is paid once, carry, agent and risk cost are paid forever. A
candidate is not always code; an existing view or content type is a candidate too, and extending
it may produce no code at all.

Record the disposition through the script that will own the work order it lands on, never only in
your own reasoning. Once that work order exists, give the script the candidate, its closeness as
research stated it, the cost dimensions compared, the verdict, and why:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/design/scripts/design-actions.sh --run-mode <interactive|autonomous> \
  dispose "<task_folder>" --id <woId> --candidate "<what research found>" \
  --distance <same-name|same-directory|same-layer> --cost <build|carry|agent|risk[,...]> \
  --verdict <reuse|extend|supersede|decline> --why "<why this verdict>" \
  [--path "<where it lives>" --interface "<what it exposes>"]
```
Give `--path` and `--interface` whenever the order's build or tests will call the candidate.
`--path` is where the reused thing lives, relative to the code repository: a file, or a
configuration path when the candidate is not code. When the return names several paths, give the
file the order calls as `--path`. The other paths stay in the interface text. `--interface` is
the text `internal-searcher` returns, word for word. Do not read the candidate's source here, and
do not reword the return. The test author may not read the source either, and the tests brief
carries this text in place of it. A dispose that omits both records no reuse.

Before that dispose, dispatch `internal-searcher` once per candidate the order's build or tests
will call, with the message this file names. Its lines are the role, the run mode and the word
`interface`. Then come the candidate as research named it, the order file's path, the code path,
and the project folder. The code path is the task's worktree, from the `worktree:` line. A
`worktree: none` means the project's code path.
**Light:** dispatch once for all orders. Repeat the candidate line and the order line, one pair
per candidate, before the code path. Pass each returned block as that candidate's `--interface`.

A decline takes no `--cost` and no `--path`: nothing is compared, and nothing is reused. Its
`--why` names what was weighed. It stands in both modes, because a decline with a reason is a
recorded decision, not a downgrade.

The script applies a fixed table and appends the outcome to the order's `reasoning`, one
paragraph per candidate. Re-disposing a candidate adds a paragraph; the last one stands. It
prints `disposition:`, which is what stands. A supersede citing only build cost or no cost
dimension, or a candidate sharing only a layer, comes back as `extend`. Autonomous, a supersede
comes back as `extend`. Each downgrade is in the `reasoning` and is a warning in the task record.
A reuse or extend citing no cost dimension stands, with the thin reasoning recorded, because there
is nothing to downgrade it to.

Interactive, ask the person once before a supersede. Name the candidate, how close it is, and that
a supersede widens this task and owes a migration. A yes is `--verdict supersede`. A no is the
verdict the person chose.

A rejection that lives only in the conversation is not a rejection anyone can check later.

**Autonomous:** once every disposition of an order is recorded, dispatch `disposition-confirmer`
once for that order, with the message this file names. One confirmer judges every candidate of
the order. Its lines are the role and the run mode. Then the order file's path, from the
`DISPOSED:` line. Then the verdict file's path, from the `confirmFile:` line. Then the code
path, which is the task's worktree, from the `worktree:` line that `dispose` prints beside it.
A `worktree: none` means the project's code path. A dispatch that names
no role runs as the general agent with write tools and this session's model. This one must write
nothing but its verdict file to mean anything.

Never this conversation's own account: being denied that is the entire reason the role exists,
and handing it over turns the check into the decision reading itself. Record what it found with
`update --append-reasoning`, which adds a paragraph after the text `dispose` wrote.

`close` reads each disposition made unattended against its order's verdict file. A missing
value, or a value the confirmer answered differently, is a warning in the task record, one line
per disposition. The builder and the architecture reviewer both read the reused interface, and
both stop on a misfit. To take the confirmer's value, dispose that candidate again with it.

Interactive runs do not dispatch it. A person read the reasoning, and the role has nothing to add.

## Look up what you decided to use and research did not

Design names things research had no reason to search for: a particular module, a framework API, a
pattern. Those were not decisions yet when research ran, so no search covered them. An order's
interface can also need a collaborator, a service, an input source or a convention that no
finding covers. How a class in this framework gets the current time is one such question. A
question a quick lookup can answer is looked up, never guessed, before the close.

First read what research already searched for. Every `research/<search>.json` carries
`searchedFor`, the words that search used. A name inside those words was searched, and the answer
is already in that file. Do not pay for it twice.

For a name that was not searched, look in this order, and stop at the first answer:

1. This project's own code. Dispatch `internal-searcher` with the words to search.
2. The catalog. Dispatch `catalog-identifier` with the words to search. It identifies only. It
   returns names and never resolves a body, so one name costs one lookup. Read a body only when
   a match is worth reading.
3. When no guide or recipe covers it, what reputable sources recommend. Dispatch
   `outward-searcher`, one subject.

Each dispatch carries the message lines that `${CLAUDE_PLUGIN_ROOT}/skills/research/SKILL.md`
names for that role, under "Dispatch one agent per search".

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

An order holds a handful of behaviours, not a feature. The design check warns on an order with
more than eight done-when rows, or more than three for each criterion it owns.
Three to seven build steps, ten at the most. Split when the steps mix independent concerns, or
mix phases. Merge two orders when each has fewer than three steps, they address the same
component, and they cannot run in parallel anyway. The script folds one into the other:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/design/scripts/design-actions.sh merge "<task_folder>" \
  --into <woId> --from <woId> --reason "<why the two are one order>"
```
Every list on the folded order joins the survivor's, without duplicates. The folded order's
`interface` and `reasoning` are appended to the survivor's, each under a line `From <woId>:`.
The title and the diff budget stay the survivor's; the output says `carried:` and `dropped:` so
nothing goes unseen. Retitle with `update` when the survivor's title no longer covers what it
owns. The folded order's file is removed, and every `dependsOn` that named it now names the
survivor. The folded id, the survivor and the reason go into `design-removed.json`, the same
record `remove` writes. The two proofs must agree; set one order's `--proof` first when they do
not. Never remove or edit an order file by any other means. A write outside the script prints
nothing, so nothing records that it happened.

An order that no longer earns its place, for example after the contract changed, leaves
through the script with its reason:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/design/scripts/design-actions.sh remove "<task_folder>" \
  --id <woId> --reason "<why the order is gone>"
```
The script deletes the order's files and records the id and the reason in
`design-removed.json`. The close copies that list into `design-closed.json`. A removed id is
never minted again. Move a dependency or a criterion with `update` first. The design check
refuses a dependsOn that names nothing. It also names a criterion left with no serving order or
owner. For an order implementation started, fold it into the order that takes its work with
`merge`. Implementation's `start` stops it for design drift, and `drop` sets its records aside.
A finding that the removed order accounted for shows in `check`. Account for it again.

An order folded before `merge` wrote that record left no entry, so the design shows a gap in its
numbers. Record it with the survivor and a reason:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/design/scripts/design-actions.sh remove "<task_folder>" \
  --id <woId> --merged-into <woId> --reason "<why the order was folded>"
```
The script refuses an id that is still an order, and an id the record already holds. `check`
lists each such id under `unrecordedIds:`. Recording changes no order, so it stops nothing. Then
run `check`, `close` with the verdict the last `design-closed.json` records, and `distill`, as for
an owned-file reopen. The close copies the entry into its record.

A test that no longer belongs on an order leaves through the script too. The merge may have
doubled it, or the order became a `gate`:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/design/scripts/design-actions.sh remove-test "<task_folder>" \
  --id <woId> --description "<the test's description, exactly as declared>"
```
The design check refuses a `tests` order that owns a machine-verified criterion and declares no
test. Add the replacement first.

A done-when row or an owned file leaves the same way. Moving a file to the order the sizing rule
names leaves its rows on the old order. The checkpoint would then judge that order on a file it
may not write:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/design/scripts/design-actions.sh remove-done-when "<task_folder>" \
  --id <woId> --text "<the row's text, exactly as declared>"
"${CLAUDE_PLUGIN_ROOT}"/skills/design/scripts/design-actions.sh remove-owned-file "<task_folder>" \
  --id <woId> --path "<the path, exactly as declared>"
```
Each prints what it removed. The design check refuses an order with no owned file, because it
gives the builder no boundary. Add the replacement first, or fold the order with `merge`. A
`record` order left with no file under the project folder loses its proof, and the output says so.
Set `--proof` again if that was wrong.

A shared decision, like one base class serving two later orders, lives in the order that builds
the shared thing, in its own `reasoning`. The orders that depend on it point at it through
`dependsOn`; nothing else needs to hold that reasoning.

## Draft each work order

For each unit of build: agree its title, which criteria it serves, and, when it produces the
observable outcome a criterion describes, which one it owns. Most orders own none. Exactly one
order owns each criterion; if two orders both seem to produce the same outcome, that is a sign the
work is split wrong, not a sign both should claim it.

**Light:** the first order, `wo1`, is the walking skeleton. It is a tiny version that links the
input, the logic and the output end to end along the demo path. Every other order depends on it,
directly or through its chain, and `check` refuses one that does not. A project keeps at most
one script that walks the demo path. `start` prints the `path-script:` line, and its first word
says the case. `create`: `wo1` also owns that script. For a page, it sits where the harness reads
its tests. For a command surface, it is the file the command runs. A person registers it with
`/aida:surfaces`. `registered`: the project has the script, and no order writes or extends it.
`check` refuses an order that owns one of its files, `wo1` included.
`declined` or `off`: no order writes one. A change to the script goes through `/aida:surfaces`
with a person.

Create it:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/design/scripts/design-actions.sh create "<task_folder>" \
  --title "<what this builds>" \
  [--criteria-served <id[,id...]>] [--criteria-owned <id[,id...]>] \
  [--non-goals <id[,id...]>] [--depends-on <id[,id...]>] \
  [--interface "<what it exposes to what depends on it>"] \
  [--reasoning "<why, if this is a shared decision>"] \
  --diff-budget "<a plain-words signal, e.g. small: one class and its test>" \
  [--proof <tests|gate|record|observe|confirm>] [--surface <id>]...
```
This mints the next id and writes the file, and prints the id and the fields set. It never prints
the record; read the file at the printed path when a field is needed. `dependsOn` may name a work order not yet created in
this conversation; the id space is shared and minted in order, so naming it ahead of its own
`create` call is safe as long as it is created before design finishes.

Write `--interface` so that it names each exposed element in backticks. That is the service id,
the class, the interface, the method, the route, the hook and the config key. The build brief
lists only the backtick-quoted names, and the builder names each one in its record, which the
reviewer compares. So write a choice the builder makes, such as two calls it may pick from, as plain text. An order
that exposes nothing takes no `--interface`.

Start `--diff-budget` with `small`, `medium` or `large`. The build reads the first word. An order
whose budget starts with `large` gives its builder a second resume at the turn limit. Number the
parts of such an order in its reasoning, as `(1)`, `(2)` and so on. The builder commits after each
part, so a stop loses one part and not the order.

Name a `--surface` when the order changes a page or a screen a person sees, by its id in the
surface registry. Most orders name none.

Before naming one: this order changes a page, and `<projectPath>/project.json` has `surfaces` null
or a kind that is off and not declined. Skip a kind that `read` names under `surfaces-deferred:`.
Before you ask, run `"${CLAUDE_PLUGIN_ROOT}"/skills/surfaces/scripts/surfaces-actions.sh read`.
When its `surface-branch:` names a branch, offer nothing. Name that branch, and say the surface
file reaches this task once that branch lands on the trunk. Interactive only, offer the setup once
per task, naming every such kind. Say so in one line. Ask whether to set the surfaces up now, per kind, with a
recommended answer per kind. Give three answers per kind: yes, not this task, or no. Say in the ask
that "no" is project-wide and "not this task" is not. A yes on a kind invokes the `surfaces` skill
through the Skill tool, naming that kind. Do this once per kind said yes to. This order then
names the id the setup registered. "Not this task" on a kind runs
`"${CLAUDE_PLUGIN_ROOT}"/skills/task/scripts/task-actions.sh defer-surface --project "<projectPath>" <task-id> <kind>`,
and no later stage of this task asks again. A no on a kind
runs `"${CLAUDE_PLUGIN_ROOT}"/skills/surfaces/scripts/surfaces-actions.sh decline <kind>`,
project-wide, and that kind is never asked again. Autonomous: nothing is offered. A page scope did
not see is often first named here.

Then, one call per item, add what the order still needs:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/design/scripts/design-actions.sh add-owned-file "<task_folder>" \
  --id <woId> --path "<a file or a directory this order may write, never a glob>"
```
A configuration unit is sized around the operation, by the recipe's rule, and owns every file
that operation rewrites. Deleting a field owns each display that lists it. An order that owns
the field files alone and leaves the displays to other orders cannot import on its own. The
same rule holds for code. An order that changes a class owns every file the recipe couples to
that class. A constructor change, for one, rewrites the service definition. A file added here
to an order the build already started is taken in place at the next `start`, once design has
closed again on the live files. Nothing stops when nothing else on the order changed.

A file that several orders only add to may have more than one owner. A list of enabled modules
and a dependency manifest are examples. Each order that adds to it passes `--shared` with that
path. An order can then enable the module it builds, and does not wait for another order. Two
orders that own one path, and do not both mark it shared, still fail the check. A file that one
order rewrites belongs to that order alone. A lock file that a tool generates is such a file.
Nothing checks that a shared change only adds, so the reviewer of each order reads that order's
own changes to the file.
```
"${CLAUDE_PLUGIN_ROOT}"/skills/design/scripts/design-actions.sh add-done-when "<task_folder>" \
  --id <woId> --text "<what must be true for this order to be finished>"
"${CLAUDE_PLUGIN_ROOT}"/skills/design/scripts/design-actions.sh add-test "<task_folder>" \
  --id <woId> --description "<the one behaviour this test proves>"
```
Write an absence as a done-when row of its own. An absence says the change added nothing of a
named kind, such as no new dependency or no static call to the container. No test can watch it
fail, so the build routes it to review by its exact words. A row that joins it to a behaviour,
such as "contains no static call and saves no entity", cannot be routed without a reopen.

A criterion whose `verifiedBy` is `machine`, on the `tests` order that owns it, needs a test
here. The check below refuses an order that skips this. The other kinds declare no test. The
configuration check judges a `gate` order's machine criterion at build time. A `record` order has
no checkpoint: its reviewer reads the document against its done-when rows. A model judges an `observe` order's done-when rows
against its surfaces after the build. The person confirms a `confirm` order's done-when rows at
review. A criterion whose `verifiedBy` is `person` needs no test.

A test is what this page defines:
`${CLAUDE_PLUGIN_ROOT}/skills/implement/references/what-a-test-is.md`. Add its file to the order
with `add-owned-file`. The test author writes into it, and the freeze refuses a test in a
file the order does not own. Each description names the one behaviour its test proves, and that
page says what a test is not.

To change a scalar or an id list on an order already created, `update` takes the same flags as
`create`, replacing whichever are given:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/design/scripts/design-actions.sh update "<task_folder>" \
  --id <woId> [--title <text>] [--criteria-served <id[,id...]>] \
  [--criteria-owned <id[,id...]>] [--non-goals <id[,id...]>] [--depends-on <id[,id...]>] \
  [--interface <text>] [--reasoning <text>] [--strike-reasoning <n>]... \
  [--append-reasoning <text>]... [--diff-budget <text>] \
  [--proof <tests|gate|record|observe|confirm>] [--surface <id>]...
```
`--reasoning` replaces the whole field, the paragraphs `dispose` wrote included. To keep them,
pass `--append-reasoning`: it adds the text as a new paragraph after a blank line. The two
flags are refused together.
When a critique or a person changes a rule that a reasoning paragraph states, strike that
paragraph. Pass `--strike-reasoning <n>` with the new rule in `--append-reasoning`. Count n
from 1 in the order's `.md`. The old paragraph stays, marked `[struck]`, and no brief
carries it. Do not leave both rules live: the builder reads every live paragraph.
To strike several paragraphs, repeat `--strike-reasoning` in one call. Count each n before the
call. One n that names no live paragraph refuses the whole call, and nothing is written.
`update` prints `struck:` with the paragraphs it struck. A repeated `--append-reasoning` adds
each text as its own paragraph, in the order given.
When `--proof` becomes `gate`, `record`, `observe` or `confirm`, `update` prints
`stillNamesATest:` naming each of `interface`, `reasoning` and `diffBudget` that still names a
test file.

## Carry the proof from its source

The knowledge that covers an order says how to verify it. Carry that onto the order, in the
form its kind takes. A `run` entry is one command a script runs. A `check` entry is one sentence
a model judges. Every entry cites its source and says whether it is binding.

**An agentic recipe covers the order.** Copy its `## Verifier`:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/design/scripts/design-actions.sh verify "<task_folder>" \
  --id <woId> --recipe "<the recipe body's path on disk>" [--not-binding]
```
The script copies each entry of the `verifier:` block as a run entry, with its `pass` and its
`kind`. It copies
each numbered item of the prose as a check entry, verbatim. It reads nothing else, and it never
turns a sentence into a command. A recipe may carry a `verifier:` block, a prose list, or both.
Pass `--not-binding` when research said the source is not one this project accepted.

**No recipe covers it, and research found how to verify it.** Add one entry per finding:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/design/scripts/design-actions.sh verify "<task_folder>" \
  --id <woId> --run "<one command>" [--pass "<exit 0 | stdout empty | stdout contains <text>>"] \
  [--kind <config-assert|live-site|self-fixture>] [--criterion <cN>] --cite "<the source research recorded>"
"${CLAUDE_PLUGIN_ROOT}"/skills/design/scripts/design-actions.sh verify "<task_folder>" \
  --id <woId> --check "<one sentence to judge>" [--kind <config-assert|live-site|self-fixture>] \
  --cite "<the source research recorded>"
```
Write a `--run` only when the source gives the command. Prefer a command whenever it does. A
source that describes a result in words gives a `--check`. Such an entry is never binding.
Give `--kind live-site` when the check needs a served site; the source says so or it does not.
A research `--run` never runs until a person approves it at the close. Without that, the
reviewer judges it as a check.
Give `--criterion` when the command's output alone proves a machine criterion the order owns,
such as a linter run. That criterion then needs no test. When run lines prove every machine
criterion an order owns, give the order `--proof confirm`. The lines run in its check, and the
person confirms its done-when rows at review. On a `tests` order, the freeze runs the line over
the test author's files, and the row-checker judges whether the line proves the whole clause. A
clause that names two tools needs a line for each.
A line runs unattended when it equals, word for word, an `argv` in the project's check recipe
`check_commands`. Any other research line needs the person's approval at the close.
`--clear` empties the list, and `--recipe` replaces it.

A run line is argv, never a shell, so `--run` refuses a shell character. A recipe entry with one is
skipped, with a warning. It also refuses a
pass outside the three forms. Read the refusal and write the entry again, or leave it out and
say why in the `reasoning`.

What each kind does with the entries:

- `gate`: the run entries run first, then the `## Configuration gate`. The worse verdict stands.
- `tests`, `record` and `observe`: the run entries run in the order's first deciding check,
  after its own answer, from the code worktree. The check is met only when both are.
- `confirm`: the run entries run the same way. A failing entry stops the build. A passing one
  leaves the check waiting for the person.
- Every kind: the reviewer judges each check entry. On an `observe` order the look also judges
  each `live-site` check as a row of its own, because only that kind shows on a page.

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
This reads every work order's JSON and writes its report to `<task_folder>/records/design-check.json`.
It prints `status:`, the report's line count and `report:` with the path. When the status is not
zero it adds one `open:` line naming what stops the design. It prints one `unattended:` line for
each finding that stops only an unattended close, and one `warning:` line for each finding that
never stops. The report holds:

- a work order file with a missing, empty or malformed required field;
- every criterion with no work order serving it, and every criterion owned by zero or by more
  than one work order;
- every work order serving no criterion;
- every work order that owns a machine-verified criterion and declares no test, unless its proof
  is `gate`, `record`, `observe` or `confirm`;
- every work order whose proof is `gate` and that declares a test;
- every work order whose proof is `record` and that declares a test, owns a file outside the
  project folder or under a path the project ignores, or has no done-when row;
- every work order whose proof is `observe` and that declares a test, names no surface, or has
  no done-when row;
- every work order whose proof is `confirm` and that declares a test, or has no done-when row;
- every work order whose proof is `confirm` and that owns a file a test glob matches. The globs
  are the ones this project's earlier freezes recorded. A tests-only order is exempt;
- every work order whose proof is `confirm` on a task with tests, unless it is text only, run
  lines prove every machine criterion it owns, or it is a tests-only order;
- every tests-only order with an owned file no done-when row names, or a row that names no owned
  file, and every one that does not depend on each `tests` order of its task;
- every work order that owns a test another task froze, while that task is not complete;
- every work order whose proof is `tests` and whose every owned file is a document or
  configuration;
- every machine-verified criterion owned by an order whose every owned file is a document or
  configuration, a `gate` order excepted;
- every machine-verified criterion owned by an `observe` or `record` order, unless a run line
  proves it;
- every machine-verified criterion that a `confirm`, `observe` or `record` order rests on a
  research run line that never runs: not binding, not approved, and not a check command. This
  stops only an unattended close;
- every work order that owns nothing and that no owning order depends on, directly or through
  the chain, and every dependency cycle;
- on a light task, every work order that owns a file of the registered script that walks the demo
  path;
- two work orders sharing a declared owned file that one of them does not mark `--shared`;
- any criterion, non-goal, or work order id named anywhere that resolves to nothing real.

`check` also prints `verifyNotBinding:`, the orders holding an entry that is not binding.
Interactive: before the close, show each such order's entries with their sources. Say that the
source is not one this project accepted. The person keeps each entry, drops it with `--clear`,
or asks for another source. A kept run entry runs only when the person also approves it, in
every run mode. The approval is the person's answer, recorded with the task skill's
`person-answer.sh`, step `design close`, with the lines as the words. Then pass `--approve-runs` to
the close, and the close stamps each such entry. Without the answer, `--approve-runs` refuses with
exit 70 and prints the command. Autonomous: the line and the rendered order carry it to a person
later. A `confirm`, `observe` or `record` order can rest a machine-verified criterion on such a
line. Then the autonomous close stops instead, because nothing would prove that criterion.

`check` also prints `impliedProofDisagrees:`, at every exit code. It names every work order whose
proof is `tests` that owns criteria of which none is machine-verified. The design still closes with
those orders open, because which of the other proofs fits is a judgment. Either the order
owns a machine-verified criterion after all, which `update --criteria-owned` sets. Or its proof is
one of the others, which `update --proof` sets. Read the `verification` clause of each
criterion the order owns, and ask what would settle it.

`check` also prints `absenceJoined:`, at every exit code. It names each done-when row that holds a
negation word and the word `and`, by order and row number. This is best effort, because a script
cannot parse a clause, and it never blocks the close. Read each row it names. When a row joins an
absence to a behaviour, remove it with `remove-done-when`. Then add each clause with its own
`add-done-when` call. When a row does not join the two, mark it reviewed:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/design/scripts/design-actions.sh update "<task_folder>" \
  --id <woId> --absence-reviewed <row>...
```
The order keeps the row's text, and `check` stops naming that row. A row whose text changes is
named again. Repeat `--absence-reviewed` to mark several rows of one order in one call.

`check` also prints `interfaceUnquoted:`, at every exit code. It names each order whose interface
holds no name in backticks. A script cannot tell whether prose names a code element, so the line
never blocks the close. Rewrite each such interface with `update --interface`, and quote each
element it exposes.

`check` also prints `interfaceUnowned:`, at every exit code. It names each path an order's
interface holds in backticks that the order does not own, no reuse of it declares, and no order
in its `dependsOn` owns. A `./` prefix and a `:line` or `::member` suffix are ignored. The build
brief lists every backticked name for the builder's record. A builder leaves out a path it did not
touch, and the reviewer finds the two texts apart. It is best effort, and it never blocks
the close. Answer each one: write the path as plain text with `update --interface`, or add the
reuse with `dispose --path --interface`.

`check` also prints `interfaceShaped:`, at every exit code. It names each name in backticks in an
order's interface that holds `<` or `{`. Such a name is often a shape, such as `type.<id>`. The
builder's record can name a shape only by repeating its text, which the reviewer reads. A generic
type holds `<` too, so the line never blocks the close. Name each real element instead, or write
the shape as plain text with `update --interface`.

`check` also prints `interfaceChoice:`, at every exit code. It names each pair of names in
backticks that an order's interface joins with `or`. Such a pair is often a choice the builder
makes, and a builder that takes one option leaves the other out of its record. The line never
blocks the close. Write a choice as plain text with `update --interface`. Leave a pair whose two
names must each exist, such as two exit codes.

`check` also prints `callsUndeclared:`, at every exit code. It names each `name()` call in an
order's done-when rows and tests that no interface the order declares holds. It reads the order's
own interface, its reuses and its `dependsOn` orders. The test author may not open source, so a
missing signature stops the tests. It is best effort, and a call a clause denies is named too. It
never blocks the close. Answer each one: add the reuse with `dispose --path --interface`, or say
why the call needs no signature.

Exit 0: nothing stops the design, subject to the judgment step above. An `unaccounted:` line
names a research finding in no order's list, with its id and the first line of its text. Account
for each one, as "Then account for each research finding" says. A person's close writes it to the
task record as a warning, and an unattended close stops on it.

Exit 5: a finding stops the design. The `open:` line names each one. Read the report file when the
lines are not enough, and fix the specific order each line names. The same repairs answer the
`unattended:` and `warning:` lines:
  - a work order file that is broken, not valid JSON, not an object, or with a missing or
    malformed required field, needs another `update` call;
  - a criterion with no serving order needs a work order that names it in `--criteria-served`;
  - a criterion with no owner, or with more than one, needs its `--criteria-owned` reconciled so
    exactly one order claims it;
  - a work order serving nothing needs a real `--criteria-served`, or it should not exist;
  - a work order missing a required test needs an `add-test` call;
  - a `gate` order declaring a test needs a `remove-test` call for it, or `--proof tests` if it
    builds code after all;
  - a `record` order declaring a test needs a `remove-test` call for it. One owning a file
    outside the project folder needs `--proof tests` if it builds code after all. One owning a
    file under an ignored path needs `remove-owned-file`, then a path the project commits. One
    with no done-when row needs an `add-done-when` call;
  - an `observe` order declaring a test needs a `remove-test` call for it. One naming no
    surface needs `update --surface <id>`. One with no done-when row needs an `add-done-when`
    call;
  - a `confirm` order declaring a test needs a `remove-test` call for it, or `--proof tests` if
    the task has tests after all. One with no done-when row needs an `add-done-when` call. Each
    row is a sentence the person confirms at review, so write it as one thing they can check. A
    `confirm` order on a task with tests that owns code needs `update --proof tests` and its
    tests, unless run lines prove every machine criterion it owns;
  - a `tests` order that owns only documents or configuration needs `update --proof confirm`,
    or `record` when its files lie under the project folder;
  - a machine-verified criterion on an order that owns only documents or configuration is a
    person's. Change it to `person` with scope's `update --verified-by person`, or give it to an
    order that builds code;
  - a machine-verified criterion on an `observe` or `record` order is a person's too. Change it
    the same way, add a run line that proves it, or give it to an order that builds code;
  - a `confirm` order that owns a test file needs `remove-owned-file` for it. Nothing runs that
    file, and the freeze never sees it. When the task does have tests, a person answers yes in
    scope instead, and the order takes `update --proof tests` and its tests;
  - an order that owns nothing is reached only when an owning order depends on it. Add it to
    that owner's `--depends-on`. The edge points from the owner to the order it needs, never the
    other way. An order no owner needs is dead work, unless it owns a criterion of its own. The
    entry point that is not a screen belongs in the order that builds the feature, as above, not
    in an order of its own; an order for it alone needs a criterion that names it;
  - a cycle needs one of the `dependsOn` edges in it removed;
  - a light order that owns the registered demo-path script needs `remove-owned-file` for it. A
    change to that script goes through `/aida:surfaces` with a person;
  - a criterion that rests on a research run line nobody approved needs the person's yes at an
    attended close, with `--approve-runs`, or another proof;
  - overlapping owned files need one order's `ownedFiles` narrowed so the paths do not repeat,
    or `--shared` on both orders when each only adds to the file;
  - a wildcard in an owned file needs the directory named instead, or each file added, because
    implementation derives what the test author may not read from this list and reads it as paths;
  - an unknown id needs correcting to one that actually exists.

Then check again. Exit 3: the script could not run the check at all. Read its stderr and fix the
named problem, then check again.

Design is done when this check finds nothing that stops it. Implementation refuses to start on
an `open:` finding, so leaving one only moves the stop to a later and more expensive place. A
`warning:` line never stops the close. Show each one to the person. The close writes it to the task
record, and review lists it. An `unattended:` line stops an unattended close, because nobody reads
it before the build.

## Critique the design

`check` printed `critique: skipped, light run`: dispatch no critic, and go to the close. The check
logged the skip.

Once the check comes back clean, and before closing, have three readers who were not in this
conversation read the orders. The check counted ids; it read no sentence. Dispatch
`design-critic` three times, in parallel, with the message this file names. Its lines are the
role, the run mode, the task folder, and one lens of `contract`, `reuse` and `buildability`.
Add the design recipe's path when one was read. Add the ids `check` printed on `closedOrders:`
when that line is not `none`. A dispatch that names no role runs as the general
agent with write tools. Never give it a summary of this conversation: being denied that account
is why the role exists.

Each critic writes `<task_folder>/records/design-critique-<lens>.md`, a findings table and a
`findings: N` last line. Wait for all three files. A file that never arrives, or arrives without
its `findings:` line, means that lens was not read. Dispatch it again, once. If it fails twice,
say so and go on: the close leaves that file out and names it. Then run `check` before you read
the files, also when an earlier session wrote them. `check` removes each row that names only
closed orders, and prints `critiqueDropped:`. Read the three files, never the dispatch replies.

The close moves each finished file into `<task_folder>/design/` and commits it with the record.
A critic goes on writing into `records/`, which the project ignores: a critique is a working file
until the close decides it is evidence. The close moves an unfinished file there too, under the
name `unfinished-design-critique-<lens>.md`, and leaves it out of the count. It is the only copy
of what that critic wrote before it stopped.

A person reads the findings, because a critic that can block trains the builder to write for the
critic. The critic decides nothing about closing, and neither does the count.

**Interactive:** show the findings grouped by work order, each with its severity, what it found,
why it matters and what would fix it. The person decides what to change. Nobody answers each
finding one by one: a finding nobody acted on stays in its file, which the close commits. A change
is one of the `update`, `add-owned-file`, `add-done-when` or `add-test` calls above, then `check`
again. Closed orders are not critiqued. A finding on `contract` is a scope question: ask, and use
the scope skill's own update path when the contract has to change.

Answer each change with the lines the call printed, and end the turn. Do not show the orders
again, and do not ask whether the design is ready to close. The close below is an action the
person takes, never a question this skill asks. Scope learned this from a run that asked for a
yes on the whole contract after each of five corrections.

**Autonomous:** ask nothing and change nothing. The findings stay in the three files, and the
close below commits them and records their paths and the count, so a person sees them later. Say
once, at the end of this run, that the critique's findings were recorded and not judged.

## Close the design

The close is the approval, and there is no second approve action. An interactive close records
that a person was present, and that record is the yes. The person closes by running
`/aida:design close <task-id>`, or by saying in their own words that the design is right. Map
those words to the call below. Autonomous, nobody says so: run it once the check is clean. Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/design/scripts/design-actions.sh --run-mode <interactive|autonomous> \
  close "<task_folder>" --recipe-fit <true|false|unsure> --recipe-path <path> --recipe-reason "<one sentence>" \
  [--critique-outcome "<one line>"]... [--approve-runs]
```
Pass the fit verdict judged above. Pass `--no-recipe` instead only when no recipe body was read.
`close` refuses with neither, and a later close restates the verdict rather than carrying it over.
Unattended, `close` stops on an `unattended:` line, exit 5, and on an unaccounted finding, exit 7.
A person's close writes those lines, each `warning:` line and each disposition no confirmer agreed
with to the task record, and closes.

On a first close, interactive, when critique files exist: ask the person for one line. It names
how many findings changed an order and how many were left with a reason. Pass it as
`--critique-outcome`. The record holds it as `critique.outcome` beside the files and the count,
and `close` prints it as `critiqueOutcome:`. Autonomous: pass one line that says the findings were
recorded and not judged. A count alone said nothing about what changed.
A re-close after a reopen, with no new critique file, needs no flag in either mode. `close`
keeps the last record's answer and prints `critiqueCarriedFrom:`, naming the close that gave it.
When an order was added, removed or merged since that close, the answer is still carried. The
close writes a warning to the task record that names both sets of orders.

This runs the design check again. It writes `design-closed.json` only when that check finds nothing
that stops the design.
The record is committed when the stage closes: `close` commits the task folder, and the work order
edits above commit nothing. Closing records what design closed on: a hash over the contract and every work order, the run mode,
and who was present. Pass the run mode you settled at the start. An interactive close records
`person`, an autonomous one records `nobody`, and implementation reads which. It also records the
critique files it moved into `design/`, their finding count and the outcome line. So a person sees
later what was read and answered before closing, and can open the files the record names.

A design left open at exit 5, with a reason recorded in an order's own `reasoning`, is not closed.
Resolve the open item first, or record why it cannot close yet, and tell the person before you
stop.

Implementation reads this record before it freezes anything. It refuses to start on a contract or
a work order that does not match the recorded hash. This is what catches a work order edited after
design closed but before implementation started.

Did a work order change after closing? Close again. A second close is allowed and expected. It
replaces the old hash with the new one. Closing again is the supported way to change a design that
already closed.

Once `design-closed.json` is written, dispatch `distiller` once, with the message this file
names. Its lines are the role, the run mode, the task folder, the stage `design`, and the paths
of `design/*.json` and `design-closed.json`. Never a summary of this conversation. It writes
`records/design-distill.json`. **Light:** scope and research dispatched no distiller, so this one
dispatch names all three stages. Write `scope` and the path of `alignment.json`, then `research`
and its paths, then `design` and its paths. `distill` then prints a `stage:` line before each
stage's lines, and a `stale` on any stage means this same dispatch again. Then run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/design/scripts/design-actions.sh distill "<task_folder>"
```
It prints `standsAlone:` and one `gap:` line per gap, and exits 0 on either value. Show each
`gap:` line; acting on one is an `update` and a second close. `standsAlone: stale` means the
orders or the close changed after the distiller read them: dispatch it again, then run the same
call again. `standsAlone: none` means the sidecar was missing or unusable, and the task record
holds a warning. The scope skill states the one retry rule under "The distill check".

Then hand off to `implement`, as `${CLAUDE_PLUGIN_ROOT}/skills/next/references/handoff.md` says:
interactive, name `/aida:implement <task-id>` and stop; autonomous, invoke it when the run mode covers it.

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
