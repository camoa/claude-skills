---
name: design
description: This skill should be used when a task's criteria are grounded and it is time to decide how to build them, for example "design this task", "write work orders", "architect this feature", "plan the build", or "Phase 2". It writes one work order per unit of build, each naming the criteria it serves and the one it owns, and checks that every criterion is covered and every work order traces to something real.
argument-hint: "[close] [<task-id>]"
arguments: [taskId]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/design/scripts/design-actions.sh *), Bash(${CLAUDE_PLUGIN_ROOT}/skills/research/scripts/research-actions.sh *), Bash(${CLAUDE_PLUGIN_ROOT}/skills/surfaces/scripts/surfaces-actions.sh decline *), Bash(${CLAUDE_PLUGIN_ROOT}/skills/project/scripts/project-actions.sh recipe-source *), Agent, EnterWorktree
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

## Determine the run mode

Look for a stated run mode on the task active in this conversation. Found, and it says
`autonomous`: act autonomously through this whole invocation. Anything else, including no active
task: act interactively, the safe default. Decide this once, at the start.
A mode that names stages in brackets, such as `autonomous (implement)`, covers this stage only
when the list names `design`; otherwise this stage is interactive.

## Find the task

Resolve the active project's own folder first, then the task, `<taskId>` when given or whichever
task is already active in this conversation. Neither known: say so in one line and name the task
skill. Stop; there is nowhere to write.

An invocation line whose first word is `close` is the person's yes on the design. The task is
the word after it, or the active one. Go straight to "Close the design" below. When no
`records/design-critique-*.md` exists yet, run "Critique the design" first.

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
the task builds in its worktree and this window is elsewhere. The refusal names the tree. Call
the `EnterWorktree` tool with that path, the way `/aida:next` does. Then run the same call
again.

`contract: absent`: say so in one line and name the scope skill. Stop; a work order with nothing
to serve is nothing this stage can check.

`work-orders:` above zero: this is a resumed or repeated run. Read each named file before
drafting anything new, rather than starting over.

Then start design:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/design/scripts/design-actions.sh start "<task_folder>"
```
Exit 6: research has not closed on this task. Research is required and is never skipped, so name
the research skill and stop. A `NOTE:` line names a stated mechanism edited after research
grounded it; read that claim as ungrounded.

Then read every file under `<task_folder>/research/`, one search at a time. Each holds findings
for one subject: prior art inside the project, prior art outside it, guides and recipes, what
reputable sources recommend, or an assumption checked. A finding that says nothing was found is
not a reason to stop. Design decides from nothing found, same as when research covered it.

Then read `<task_folder>/records/playbooks.md` the same way: it holds the plays research loaded,
the rules this project and this person want followed. Name a play that decides an order's shape
by its id in that order's `reasoning`.

## Read the guides and recipes research found

Research named these without opening them, so design is the first read. Research recorded an
address for each; open it through the navigator the same way, and read a project's own source
directly. One agentic recipe
covering the work means the decision is already made: follow it. Two: read both, pick the one
that fits, say why, and build from that one alone. None: architect from the findings and from
this project's own conventions; this is where design quality shows.

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
the reason, then ask whether to continue with the recipe, without it (the fallback below), or
stop. Autonomous: continue with the recipe and record `false`.

This is what makes the work orders right, and no check below can replace it. Read it for what
AIDA cannot know on its own:

- What kinds of thing a work order can be about here. In Drupal a module, a service, a plugin, a
  theme, a component, a configuration entity. This is what an order is sized around.
- What is built with configuration rather than code. A view or a content type is a work order
  with no code in it. It states no test. Its proof is the implement recipe's
  `## Configuration gate` lines, so it is created with `--proof gate`. The recipe's sizing rule decides what it owns.
- What is a document rather than code or configuration: a dependency review, a report, a note.
  Such an order owns files under the task folder only, in a folder the project commits, such as
  `<task_folder>/deliverables/`. Never `records/`, which the project ignores. It states no test.
  Its proof is its done-when rows, so it is created with `--proof record`. `add-owned-file`
  sets that value itself once every owned file lies under the task folder, on an order created
  with no `--proof`. Such a file must live in a folder the project commits: `add-owned-file`
  refuses an ignored path on a record order.
- What has to exist beside a class for it to work: a services entry, a route, a permission, a
  schema. Name these in the order, or whoever builds it invents them.
- What one unit exposes to another, which is what the `interface` field holds.
- Where business logic belongs, and what a thin layer may contain. An order that puts logic in
  the thin layer is drafted wrong.
- The entry point every feature has that is not a screen. Name it in the order that builds the
  feature, so the feature is reachable without its UI.
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
  --verdict <reuse|extend|supersede|decline> --why "<why this verdict>" [--confirmed] \
  [--path "<where it lives>" --interface "<what it exposes>"]
```
Give `--path` and `--interface` whenever the order's build or tests will call the candidate.
`--path` is where the reused thing lives, relative to the code repository: a file, or a
configuration path when the candidate is not code. `--interface` is what it exposes, in your own
words, read from the code. Name the class or service id, the method the tests call, its arguments,
and the keys of what it returns. Read the code for this; design may. The test author may not, and
the tests brief carries this text in place of the source. A dispose that omits both records no
reuse.

A decline takes no `--cost` and no `--path`: nothing is compared, and nothing is reused. Its
`--why` names what was weighed. It stands in both modes, because a decline with a reason is a
recorded decision, not a downgrade.

The script applies a fixed table and appends the outcome to the order's `reasoning`, one
paragraph per candidate. Re-disposing a candidate adds a paragraph; the last one stands. It
prints `disposition:`, which is what stands. A supersede citing only build cost, or a candidate sharing
only a layer, comes back as `extend`. Autonomous, a supersede comes back as `extend`, with the
reason in the `reasoning`. A reuse or extend citing no cost dimension stands, with the thin
reasoning recorded, because there is nothing to downgrade it to.

Interactive, the script refuses a supersede until the person has been asked. Ask this: the
candidate, how close it is, and that a supersede widens this task and owes a migration; does it
stand? A yes is `--confirmed`. A no is the verdict the person chose. A supersede citing no cost
dimension is refused the same way; ask what it compared, then call again.

A rejection that lives only in the conversation is not a rejection anyone can check later.

**Autonomous:** after recording a disposition, dispatch `disposition-confirmer` to check it. Name
the role; a dispatch that names none runs as the general agent with write tools and this session's
model, and this one has to be read-only to mean anything.

Give it the paragraph `dispose` wrote last, and the files it cites, and nothing else. Never this conversation's
own account: being denied that is the entire reason the role exists, and handing it over turns the
check into the decision reading itself. It answers agree, disagree, or downgrade, with what it
compared. Record what it found with `update --reasoning`, appended to the text `dispose` wrote.

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
component, and they cannot run in parallel anyway. The script folds one into the other:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/design/scripts/design-actions.sh merge "<task_folder>" \
  --into <woId> --from <woId>
```
Every list on the folded order joins the survivor's, without duplicates. The folded order's
`interface` and `reasoning` are appended to the survivor's, each under a line `From <woId>:`.
The title and the diff budget stay the survivor's; the output says `carried:` and `dropped:` so
nothing goes unseen. Retitle with `update` when the survivor's title no longer covers what it
owns. The folded order's file is removed, and every `dependsOn` that named it now names the
survivor. The two proofs must agree; set one order's `--proof` first when they do not. Never
remove or edit an order file by any other means. A write outside the script prints nothing, so
nothing records that it happened.

A test that no longer belongs on an order leaves through the script too. The merge may have
doubled it, or the order became a `gate`:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/design/scripts/design-actions.sh remove-test "<task_folder>" \
  --id <woId> --description "<the test's description, exactly as declared>"
```
It refuses the last test of a `tests` order that owns a machine-verified criterion, the rule the
check applies. Add the replacement first.

A done-when row or an owned file leaves the same way. Moving a file to the order the sizing rule
names leaves its rows on the old order. The checkpoint would then judge that order on a file it
may not write:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/design/scripts/design-actions.sh remove-done-when "<task_folder>" \
  --id <woId> --text "<the row's text, exactly as declared>"
"${CLAUDE_PLUGIN_ROOT}"/skills/design/scripts/design-actions.sh remove-owned-file "<task_folder>" \
  --id <woId> --path "<the path, exactly as declared>"
```
Each prints what it removed. The last owned file is refused, because an order that names no
file gives the builder no boundary. Add the replacement first, or fold the order with `merge`. A
`record` order left with no file under the task folder loses its proof, and the output says so.
Set `--proof` again if that was wrong.

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
  --diff-budget "<a plain-words signal, e.g. small: one class and its test>" \
  [--proof <tests|gate|record>] [--surface <id>]...
```
This mints the next id and writes the file, and prints the id and the fields set. It never prints
the record; read the file at the printed path when a field is needed. `dependsOn` may name a work order not yet created in
this conversation; the id space is shared and minted in order, so naming it ahead of its own
`create` call is safe as long as it is created before design finishes.

Name a `--surface` when the order changes a page or a screen a person sees, by its id in the
surface registry. Most orders name none.

Before naming one: this order changes a page, and `<projectPath>/project.json` has `surfaces` null
or a kind that is off and not declined. Interactive only, offer the setup once per task, naming
every such kind. Say so in one line. Ask whether to set the surfaces up now, per kind, with a
recommended answer per kind. Give three answers per kind: yes, not this task, or no. Say in the ask
that "no" is project-wide and "not this task" is not. A yes on a kind invokes the `surfaces` skill
through the Skill tool, naming that kind. Do this once per kind said yes to. This order then
names the id the setup registered. "Not this task" records nothing for that kind. A no on a kind
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
the field files alone and leaves the displays to other orders cannot import on its own.
```
"${CLAUDE_PLUGIN_ROOT}"/skills/design/scripts/design-actions.sh add-done-when "<task_folder>" \
  --id <woId> --text "<what must be true for this order to be finished>"
"${CLAUDE_PLUGIN_ROOT}"/skills/design/scripts/design-actions.sh add-test "<task_folder>" \
  --id <woId> --description "<what this test must observe>"
```
A criterion whose `verifiedBy` is `machine`, on the order that owns it, needs at least one test
here; the check below refuses an order that skips this. Two orders are the exception. One created
with `--proof gate` declares no test, and the configuration check judges its owned machine
criterion at build time. One whose proof is `record` declares no test either, and its done-when
rows, judged at the checkpoint, stand in for the test. A criterion whose `verifiedBy` is
`person` needs no test, though one is never wrong to add.

To change a scalar or an id list on an order already created, `update` takes the same flags as
`create`, replacing whichever are given:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/design/scripts/design-actions.sh update "<task_folder>" \
  --id <woId> [--title <text>] [--criteria-served <id[,id...]>] \
  [--criteria-owned <id[,id...]>] [--non-goals <id[,id...]>] [--depends-on <id[,id...]>] \
  [--interface <text>] [--reasoning <text>] [--diff-budget <text>] [--proof <tests|gate|record>] \
  [--surface <id>]...
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
This reads every work order's JSON and writes its report to `<task_folder>/records/design-check.json`.
It prints `status:`, the report's line count and `report:` with the path. When the status is not
zero it adds one `open:` line naming what is open. The report holds:

- a work order file with a missing, empty or malformed required field;
- every criterion with no work order serving it, and every criterion owned by zero or by more
  than one work order;
- every work order serving no criterion;
- every work order that owns a machine-verified criterion and declares no test, unless its proof
  is `gate`;
- every work order whose proof is `gate` and that declares a test;
- every work order whose proof is `record` and that declares a test, owns a file outside the
  task folder, or has no done-when row;
- every work order that owns nothing and that no owning order depends on, directly or through
  the chain, and every dependency cycle;
- two work orders sharing a declared owned file;
- any criterion, non-goal, or work order id named anywhere that resolves to nothing real.

Exit 0: nothing to do. Design is finished, subject to the judgment step above.

Exit 4: a work order file itself is broken: not valid JSON, not an object, or a missing or
malformed required field. Fix it with another `update` call, or by hand, and check again.

Exit 5: the schema is fine but a content or cross-order check is not. The `open:` line names each
problem. Read the report file when the line is not enough, and fix the specific order it names:
  - a criterion with no serving order needs a work order that names it in `--criteria-served`;
  - a criterion with no owner, or with more than one, needs its `--criteria-owned` reconciled so
    exactly one order claims it;
  - a work order serving nothing needs a real `--criteria-served`, or it should not exist;
  - a work order missing a required test needs an `add-test` call;
  - a `gate` order declaring a test needs a `remove-test` call for it, or `--proof tests` if it
    builds code after all;
  - a `record` order declaring a test needs a `remove-test` call for it; one owning a file
    outside the task folder needs `--proof tests` if it builds code after all; one with no
    done-when row needs an `add-done-when` call;
  - an order that owns nothing is reached only when an owning order depends on it. Add it to
    that owner's `--depends-on`. The edge points from the owner to the order it needs, never the
    other way. An order no owner needs is dead work, unless it owns a criterion of its own. The
    entry point that is not a screen belongs in the order that builds the feature, as above, not
    in an order of its own; an order for it alone needs a criterion that names it;
  - a cycle needs one of the `dependsOn` edges in it removed;
  - overlapping owned files need one order's `ownedFiles` narrowed so the paths do not repeat;
  - a wildcard in an owned file needs the directory named instead, or each file added, because
    implementation derives what the test author may not read from this list and reads it as paths;
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

## Critique the design

Once the check comes back clean, and before closing, have three readers who were not in this
conversation read the orders. The check counted ids; it read no sentence. Dispatch the
`design-critic` role three times, in parallel, each with the task folder and one lens:
`contract`, `reuse`, `buildability`. Name the role; a dispatch that names none runs as the
general agent with write tools. Give it the task folder, the lens, and the path of the design
recipe read above, when one was. Never give it a summary of this conversation: being denied that
account is why the role exists. The `buildability` critic reads the recipe's own sentence on a
configuration unit and asks it of every `gate` order.

Each critic writes `<task_folder>/records/design-critique-<lens>.md`, a findings table and a
`findings: N` last line. Wait for all three files. A file that never arrives, or arrives without
its `findings:` line, means that lens was not read. Dispatch it again, once. If it fails twice,
say so and go on: the close leaves that file out and names it. Read the three files, never the
dispatch replies.

A person reads the findings, because a critic that can block trains the builder to write for the
critic. The critic decides nothing about closing, and neither does the count.

**Interactive:** show the findings grouped by work order, each with its severity, what it found,
why it matters and what would fix it. Take one answer per finding: change the order, or leave
it. A change is one of the `update`, `add-owned-file`, `add-done-when` or `add-test` calls above,
then `check` again. A leave needs a reason from the person. Write it into that order's
`reasoning` with `update`, appended to what is there, so the reason outlives this conversation.
A finding on `contract` is a scope question: ask, and use the scope skill's own update path when
the contract has to change.

Answer each change with the lines the call printed, and end the turn. Do not show the orders
again, and do not ask whether the design is ready to close. The close below is an action the
person takes, never a question this skill asks. Scope learned this from a run that asked for a
yes on the whole contract after each of five corrections.

**Autonomous:** ask nothing and change nothing. The findings stay in the three files, and the
close below records their paths and the count, so a person sees them later. Say once, at the
end of this run, that the critique's findings were recorded and not judged.

## Close the design

The close is the approval, and there is no second approve action. An interactive close records
that a person was present, and that record is the yes. The person closes by running
`/aida:design close <task-id>`, or by saying in their own words that the design is right. Map
those words to the call below. Autonomous, nobody says so: run it once the check is clean. Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/design/scripts/design-actions.sh --run-mode <interactive|autonomous> \
  close "<task_folder>" --recipe-fit <true|false|unsure> --recipe-path <path> --recipe-reason "<one sentence>"
```
Pass the fit verdict judged above. Pass `--no-recipe` instead only when no recipe body was read.
`close` refuses with neither, and a later close restates the verdict rather than carrying it over.

This runs the design check again. It writes `design-closed.json` only when that check exits clean.
The record is committed when the stage closes: `close` commits the task folder, and the work order
edits above commit nothing. Closing records what design closed on: a hash over the contract and every work order, the run mode,
and who was present. Pass the run mode you settled at the start. An interactive close records
`person`, an autonomous one records `nobody`, and implementation reads which. It also records the
critique files under `records/` and their finding count, so a person sees what was read before closing.

A design left open at exit 5, with a reason recorded in an order's own `reasoning`, is not closed.
Closing needs a clean check. Resolve the open item first, or record why it cannot close yet, and
tell the person before you stop.

Implementation reads this record before it freezes anything. It refuses to start on a contract or
a work order that does not match the recorded hash. This is what catches a work order edited after
design closed but before implementation started.

Did a work order change after closing? Close again. A second close is allowed and expected. It
replaces the old hash with the new one. Closing again is the supported way to change a design that
already closed.

Once `design-closed.json` is written, dispatch the `distiller` role once, with the task folder,
the stage `design`, and the paths of `design/*.json` and `design-closed.json`. Never a summary of
this conversation. It writes `records/design-distill.json`. Then run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/design/scripts/design-actions.sh distill "<task_folder>"
```
It prints `standsAlone:` and one `gap:` line per gap, and exits 0 on either value. Show each
`gap:` line; acting on one is an `update` and a second close. Exit 2 means the sidecar was not
written. Send the same agent one message: write the file and read it back. An agent has reported
a write it never made. Dispatch a fresh one only when exit 2 repeats. Exit 4 means the sidecar is
malformed; say so.

Interactive: stop here. Name the next command for the person, `/aida:implement <task-id>`, and
never invoke it yourself. Autonomous: invoke `aida:implement` through the Skill tool, once, with
the task id, and stop if it refuses. Invoke it only when the mode covers implement too; otherwise
end as interactive does, naming the command. Each stage refuses to start without the previous
stage's record, so a stage cannot run out of order. That is why this chain is safe.

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
