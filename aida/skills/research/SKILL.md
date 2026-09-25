---
name: research
description: This skill should be used when a task's scope contract is approved and its criteria need grounding before design starts, for example "research this task", "find prior art", "check for an existing library", "look for a guide", "check this assumption", or "Phase 1". It fans out one small search per subject, records each search's findings in its own file, and checks that every criterion has a finding and every finding cites a criterion.
argument-hint: "[<task-id>]"
arguments: [taskId]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/research/scripts/research-actions.sh *), Bash(${CLAUDE_PLUGIN_ROOT}/skills/playbooks/scripts/playbook-actions.sh *), Bash(${CLAUDE_PLUGIN_ROOT}/skills/project/scripts/project-actions.sh recipe-source *), Bash(${CLAUDE_PLUGIN_ROOT}/skills/task/scripts/task-actions.sh decline-recipe *), Bash(${CLAUDE_PLUGIN_ROOT}/skills/scope/scripts/scope-actions.sh set-tests *), Agent, EnterWorktree
---

# Research

Research finds out what is already true, so the design stage does not have to guess and does not
have to look things up itself. It answers five questions, for each criterion that needs one: has
someone built this already; are there guides or recipes covering it; do reputable sources
recommend a way to do it; is an assumption the task leans on still true; and it hands the answers
to the design stage in a form design can act on without looking again.

Research does not decide. It reports what exists and what is true of it. Choosing between two
usable options is design's work. Research does not read to the bottom of anything: a subject is
never exhausted, so the criteria are what stop this stage, never the subject.

Every finding names where it came from and when it was looked at. A finding with no source is
not a finding, and the model's own recall is never the answer, only a lead worth confirming with
one search.

Every write below goes through `research-actions.sh`, or `playbook-actions.sh` for the playbook
load, or the task skill's `decline-recipe` for a declined recipe, or scope's `set-tests` for the
automated tests answer. All four are named in this skill's own grant, so they run without asking,
and so does the project skill's `recipe-source` lookup. Any other Bash command still asks for
approval. Dispatching an agent needs no approval either; it is also named in this skill's own
grant.

**The dispatch message is the role, the run mode and the inputs.** Name the role on the Agent
call. The message itself is one line per item: the run mode, `interactive` or `autonomous`, then
each input the step hands over. An input is a path, the words a search is given, or one word a
step names, a stage or a set id. Nothing else goes in. The role's rules and
its return shape live in its agent definition, which reaches it on every dispatch. So the
message restates neither, and two runs of one step hand the role the same words. Each dispatch
below names this shape and lists its own inputs.

## Determine the run mode

Look for a stated run mode on the task active in this conversation. Found, and it says
`autonomous`: act autonomously through this whole invocation. Anything else, including no
active task: act interactively, the safe default. Decide this once, at the start.
A mode that names stages in brackets, such as `autonomous (implement)`, covers this stage only
when the list names `research`; otherwise this stage is interactive.

Research never blocks on this choice the way scope does. The run mode changes what this skill
asks at three points below: a recipe fit of `false` or `unsure`, a missing process recipe, and a
test runner found for a task with no automated tests. The split step and the close differ too,
and each says so where it stands. Everything else runs the
same way in both modes.

## Find the task

Research runs against a task that already has an approved scope contract. Resolve the active
project's own folder with the project skill first, then the task, `<taskId>` when given or
whichever task is already active in this conversation. Neither known: say so in one line and
name the task skill. Stop; there is nowhere to write.

Once found, the task's own folder is `<projectPath>/tasks/<task-id>`. Every call below takes
that folder.

## Read what is already there

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/research/scripts/research-actions.sh read "<task_folder>"
```
This prints summary lines. `contract:` says present or absent and `contract-file:` names the
file. `criteria:` lists the ids, and `criteria-by-designer:` lists the ids no person ever
approved. `worktree:` names the task's own git worktree, where the code is read and the spike
runs. `none` means the code path, as for a task made before every task had one.
`automated-tests:` is the contract's answer to whether this task has automated tests: `yes`, `no`
or `not-asked`. `recipes-declined:` names each framework a person declined a recipe for, or
`none`. One `search:`
line names each research file already on disk with its finding count.
Read the criteria's text from the contract file.

`read` is the one call here that runs from anywhere. Every other call refuses at exit 79 when
the task builds in its worktree and this window is elsewhere. The refusal names the tree and the
route that works from here, either the `EnterWorktree` tool or the call started with
`cd <worktree> &&`. Take the route it names, the way `/aida:next` does, and run the call again.

`contract: absent`: say so in one line and name the scope skill. Stop.

`criteria-by-designer:` names any id: say so in one line, with the ids. Interactive: say that the
contract carries criteria a run wrote on the person's behalf. Name `/aida:scope` as the place to
approve or change them. Research does not block, so go on after saying it. Autonomous: say the
same line for the record and go on. The fact is already on disk, in each criterion's `author`
field, so write nothing new.

`search:` lines present: this is a resumed or repeated run. Read each named file before deciding
what is still missing, rather than starting over.

`inputs:` says what the task's `inputs/` folder holds: `absent`, `empty`, or `present` with one
`input:` line per file, to three levels deep. That folder holds material captured before the task
existed. Read every `input:` path before any search runs. This material is input, never a finding.
It names things to search for. Record a claim from it only once a search confirms it with a
source. Two exceptions, both written by research itself on an earlier run: a page saved at
`inputs/<slug>.md` and a tree under `inputs/prior-art/`. Each is already a recorded finding's
source, so it needs no search to confirm it.

No `search:` line, and `research.v5.md` or a `research.v5/` folder exists in the task folder.
This is a first run on a version 5 task, and those files are its research. Read them. Record each
finding that still holds through `record` below, one search per version 5 file. `--search` is
`version-5-<file-slug>`, the file's name slugged. `--searched-for` is the file's own title or
subject line. `--source` names the version 5 file. `--criteria-served` names the criterion the
finding serves now. Dispatch a search only for a criterion those files do not cover. The coverage
check then says what is left. Version 6 parses nothing back. So the stage that reads the old
research is the conversion, and there is no converter.

## Start the stage

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/research/scripts/research-actions.sh start "<task_folder>"
```
This creates the task's `research` folder and prints the criterion ids again, for reference
while planning searches. It is safe to run more than once; it never overwrites anything.

`subscriptions:` names the catalog playbook sets this project subscribes to, or says `none`.
When it names any, dispatch `playbook-loader` once, with the message this file names: the role,
the run mode, the task folder and those ids. It writes `records/playbooks-catalog.json`. Then, in
every case, run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/playbooks/scripts/playbook-actions.sh load "<task_folder>"
```
It reads the person's file, the project's file and the loader's record, and writes
`records/playbooks.json`. Show its `record:`, `rendered:`, `source:` and `plays:` lines. Say an
`unreachable` set in one line, and go on; the next run tries again. The plays are the rules
every later role follows. This step loads them once, where the task's evidence starts, so design
and implementation read one record and never fetch. Research itself cites no play.

## Read the parent's research

A task made by a split carries `parent` in its `task.json`, the parent task's id. Read that
field before planning any search. Absent, or the file does not hold it: go to the next section.

Present: the parent's research folder is `<projectPath>/tasks/<parent>/research/`, a sibling of
this task's own folder. Read every `<search>.json` in it. Then walk this task's criteria. Skip a
criterion this task already holds a finding for. The `search:` lines from `read` name every file
already on disk, and "Read what is already there" says to read each one first. `record` only
appends, so a repeated run would otherwise record the parent's findings a second time. Record
each parent finding that answers a criterion here, through `record` below, one `--search` per
parent file, named `parent-<the parent's search name>`. `--searched-for` is that file's own
`searchedFor`. `--text` is the finding's own text. `--source` holds the finding's `source` and
its `lookedAt` date, so the finding still names where it came from and when it was looked at.
`record` stamps today, which is when this task wrote the finding down, and the source says when
the parent looked. Never claim a fresh look at something nobody looked at again.
`--criteria-served` names this task's own criterion ids, from the contract read above. A parent
criterion id means nothing here, because this task's contract minted its own.

Dispatch a search only for a criterion nothing in that folder covers. Research is the most
expensive thing AIDA does, so a child that re-runs its parent's searches pays twice for one
answer.

The parent's folder is gone or unreadable: plan every search as if this task had no parent, and
say so in one line. A missing parent is not a failure.

This step asks nothing. It runs the same way in both run modes.

## Decide which searches are needed

Walk the criteria list. For each criterion, or each small group of related criteria, work out
which of the five questions above actually apply to it. Not every criterion needs every
question. A criterion about a UI label rarely needs a library search; a criterion about parsing
a file format often does.

Typical search subjects, named by what they read, not by a fixed roster:

- **Prior art inside this project.** Load the process recipe for this project's framework and
  read where this project's own code lives, where its own configuration lives, and which paths
  are out of bounds. The recipe derives those from the project's own manifest. Then search by
  proximity of name over things already named: class and service names, file and directory
  paths, the layer something sits in. Read each candidate's own docblock, the top of the file,
  never the whole file. A file with no docblock is reported as having none, which is itself a
  signal. Search the configuration store the same way where the framework has one, because an
  existing view or content type is prior art that needs no code. A configuration file has no
  docblock, so the recipe says what to read in its place. Core and contributed code are noise
  here; the outside search covers those. The project's own task records are prior art as well.
  The searcher also reads `<project>/tasks/`, so "have we built this" is asked of this project's
  history. A hit names the task and what it changed. Prior art that lives only on another branch
  or an old commit is invisible to the searcher, which has no git. Extract those files with
  `git show <ref>:<file>` into `<task_folder>/inputs/prior-art/<branch>/`, and name that folder
  as a line in the searcher's message.
- **Prior art outside this project.** A library, a module, a package that already does this.
  Apply the three-part test to anything found: is it maintained, is it used, is it supported. A
  process recipe for this project's own framework may refine that test; when none exists, apply
  the plain three-part test and say the recipe is missing (see "A missing process recipe" below).
- **Guides and recipes.** Ask the navigator's identify mode what covers this criterion, and
  search any source this project configured itself. Name what is found and say which kind it is:
  a guide, a tooling recipe, or an agentic recipe. Do not open any of them. Identifying is the
  whole job and design is the reader. The identify report says which catalogs it searched and
  which it could not reach; a catalog it could not reach is not a catalog that held nothing, and
  the finding says so.
- **What reputable sources recommend.** A current, dated source, never the model's own recall
  stated as fact. A memory of "the right way to do this" is a lead: confirm it with one search,
  or record that nothing confirmed it. Ask also how those sources verify the result: the command
  they run, and what a pass prints. Record the command verbatim, with its source. Design turns
  it into the order's own proof.
- **An assumption that needs checking.** Named because a mechanism the task leans on might have
  changed. Checking it has three outcomes, not one: true, false, or could not be settled. All
  three finish the check and all three are worth recording; a false assumption is one of the
  most useful things research produces.
- **A spike.** For a design question no document answers, for example whether one approach
  handles a case, and only when the searches above came back empty. A spike answers one question
  and is never kept. It is not dispatched: this conversation writes and runs it. It runs in the
  task's worktree, the `worktree:` line above, and `<codePath>` below means that tree. Read
  `<codePath>/.gitignore` first: when no line names `.aida-spike/`, say so and stop, and write
  nothing. Otherwise write a small runnable experiment under `<codePath>/.aida-spike/` and run
  it. Record the answer as a finding: `--source` is that folder path, and `--text` holds what
  ran and what it printed. Delete the folder before the coverage check closes research. The
  check refuses (exit 6) while it exists, so nothing throwaway ships. Carry the idea forward,
  never the code: design authors it fresh.

When `automated-tests:` reads `no`, the search inside this project asks one more thing. Is there a
test runner that covers the changed code? Name it in the searcher's words, with its
configuration file as the source. Serve the finding to the criteria the changed code serves.

How many searches run is set by what these criteria actually need. A task with three criteria
that all rest on the same library may need one search, not three. The search inside this project
is the exception: run it on every task that changes code.

## Dispatch one agent per search

**Name the role on every dispatch.** Three roles cover every dispatched subject above, and each one
carries its own tool set and its own limits, applied by the runtime:

| Search subject | Role |
|---|---|
| Prior art inside this project | `internal-searcher` |
| Prior art outside this project | `outward-searcher` |
| Guides and recipes | `catalog-identifier` |
| What reputable sources recommend | `outward-searcher` |
| An assumption that needs checking | `outward-searcher` |

A dispatch that names no role runs as the general agent, with every tool and this session's own
model, and nothing the roles promise holds. `internal-searcher` has no web tools at all, which is
what makes "prior art in this project" a claim about this project rather than about the internet.

For each search decided above, dispatch its role with the message this file names. Its lines are
the role, the run mode, the words to search, and the bound. The `internal-searcher` message
carries the code path and the project folder in place of the bound. The code path is the task's
worktree, from the `worktree:` line. The `catalog-identifier` message carries the project folder
and the project's frameworks beside the bound. Without those two the agent cannot ask this
project's own folders, and an agentic recipe a project put in its own folder is never named.
The agent never sees this conversation and this conversation never sees what the agent read,
only what it reports back. That isolation is what keeps the cost bounded.

What is this step's job is what to do with a bad return. An agent that comes back with prose
instead of findings with a source and a date has not done the job. Ask it again, or record what it
did find and note the rest as not searched.

A `fetch-failed` finding is a search snippet, not the page. Record it as returned, with
`fetch-failed` in `--text`, so design knows the fact is a snippet. This conversation may then
fetch that one page itself, undispatched: one page, one question. The spike folder rules do not
apply. Save what came back at `<task_folder>/inputs/<slug>.md`. Record a second finding with
`--source` the address. Its `--text` holds what the page said, that this conversation fetched it,
and where it is saved.

## Record each finding

For every finding an agent returns, record it under that search's own name:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/research/scripts/research-actions.sh record "<task_folder>" \
  --search <slug> --searched-for "<the words this search searched for>" \
  --text "<what was found, or that nothing was>" \
  --source "<where it came from>" [--criteria-served <id[,id...]>]
```
`<slug>` is lowercase letters, digits and single hyphens, and it names the file: a search called
`prior-art-internal` writes its findings to `research/prior-art-internal.json`, and `record` then
renders `research/prior-art-internal.md` from it. Nothing reads the rendered file back; it is for
the design stage to read. Call `record` once per finding; calling it again with the same
`--search` adds another finding to the same JSON file, and the rendered markdown with it, rather
than replacing it.

`--searched-for` holds the words this search searched for. Words, not a sentence about how the
search ran: "responsive images, image styles, picture element". Give the same value on every
`record` call for one search. A second value is refused, because the search is the unit. A search
that broadens takes a new `--search` name of its own.

Those words bound every finding in the file. A search that found nothing proves nothing outside
the words it used. The design stage reads them to know what it must look up for itself, because
design names modules and APIs that were not decisions yet when research ran.

`--criteria-served` takes the criterion ids from the contract read above, comma separated, for
example `c1,c3`. Attach every id this finding actually speaks to. Leave it out when a finding
speaks to none: an empty list is allowed, and it is itself checked below, not silently accepted.

A search that found nothing is still recorded, once. `--text` says so plainly, for example
"looked and found nothing: no maintained package covers this without pulling in a whole
framework", and `--searched-for` holds the words it used. It serves the criterion its search was
dispatched for, so `--criteria-served` names that id. Silence and a negative result look
identical from outside; only the recorded negative tells design it is safe to decide without
searching again.

Never write a finding from memory. If nothing was dispatched to check something, it is not
recorded as found; it is either dispatched or left for the next pass.

## Reading the catalog

Everything published in the catalog is read through the navigator: guides, tooling recipes,
process recipes, agentic recipes. Research never fetches a catalog address itself and never reads
a cached copy directly.

**A process recipe is looked up, never searched.** The project's own sources answer before the
catalog, so ask them first, once per framework:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/project/scripts/project-actions.sh recipe-source "<projectPath>" research <framework>
```
It prints one line, or nothing. `RECIPE: <path> source=<folder>`: take that path and skip the
navigator. `RECIPE: catalog`, with or without `searched=<folders>`, or no line: ask the
navigator's process-recipe lookup for this project's framework at the research stage. A folder
that holds nothing is not an answer, so a folder miss never skips the navigator. When
`searched=` is present, record those folders beside the navigator's answer. A later reader then
tells a folder miss from a project with no folder. The no-recipe path below is reached only
after the navigator answers that none exists. The navigator answers with whether
one is available and, when it is, a path to the body on disk. Read the body from that path. The
body is never streamed into the conversation, which is what keeps a recipe affordable.
Verdict words and a missing heading follow
`${CLAUDE_PLUGIN_ROOT}/skills/tool/references/reading-a-recipe.md`.

**Judge the fit once, after the body is read and before the first dispatch.** Does this method,
by its `description`, Goal and Preconditions, describe the work the criteria and non-goals name?
Record the verdict on the search inside this project, on any one `record` call, with `--recipe-fit
<true|false|unsure> --recipe-path <path> --recipe-reason "<one sentence>"`. On `false` or `unsure`,
interactive: say the verdict with the reason. Then ask whether to continue with the recipe, without
it (the fallback below), or stop. Autonomous: continue with the recipe, record the verdict as
judged, and say so. `unsure` is recorded as `unsure`, never rounded to `true` or `false`.

**Three answers, not one.** A recipe that does not exist for this framework, a listing that could
not be reached, and a network that failed are three different things and only the first is a fact
about the framework. Record which one happened, in those words. Treating the second or the third
as "this framework has no recipe" writes a false finding that nothing later can tell from a true
one.

**A source this project configured itself is read through `recipe-source`.** The navigator serves
the published catalog. A project pointing at its own folder is a different source, and the command
above is how research reads it.

## What a found recipe means

A found guide or recipe's `--text` says which class it is, since design's next step depends on
it:

- A **tooling recipe** means the tool exists and can be installed.
- A **process recipe** means the framework's own procedure for this is already written down.
- An **agentic recipe** means the decision is already made, for a source this project has
  configured. Say so in the text. A source this project has not configured, the live-search
  case, is not automatically trusted: say in the text that the source is not one this project
  accepted, so design knows the opinion is not binding.

## Prior art candidates, in order

For a candidate found inside this project, record it as ordered evidence, never as a verdict.
State how close it is (same name, same directory, same layer) in `--text`, and let design answer
reuse, extend, supersede, or decline, in that order. Research does not choose between candidates that all
pass; it hands them over ranked by closeness and lets design decide fit.

## A missing process recipe

When the lookup answers that no process recipe covers this project's framework, record that the
recipe is missing and fall back.

When the lookup could not run at all, record that instead, in those words, and fall back the same
way. The fallback is the same; the finding is not.

The fallback depends on the search. For prior art outside this project, apply the plain
three-part test: maintained, used, supported. For prior art inside this project, search from the
project root and say in the finding that the bound on custom code was not enforced. Do not guess
the framework's directory layout.

Interactive: skip the ask for a framework the `recipes-declined:` line of `read` names; a person
already answered. Otherwise name the framework and ask whether to write one before moving on. The
answers are three: write one now, not now, or not for this framework. The shape is in
`${CLAUDE_PLUGIN_ROOT}/templates/process-recipe-research.md`, which carries the sections the
catalog requires and what research asks at each one. Publishing it is the catalog's own
create-on-miss path. "Not for this framework" is recorded on the task:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/task/scripts/task-actions.sh decline-recipe --project "<projectPath>" <task-id> <framework>
```
It writes `recipesDeclined` in `task.json`, which `read` prints as `recipes-declined:`. Design
reads the same field and skips its own ask. Implementation never asks; it records the missing
recipe and goes on.

Autonomous: record the missing recipe as a note in the finding's own text and continue. Do not
invent a framework-specific rule in its place.

## When the contract needs more

If a search shows a criterion is too vague to check against (research.md's open question: a
criterion that gives no bound), do not invent a bound. Say so, name the scope skill, and move on
to what can be checked.

## Check the automated tests answer

Do this before the coverage check, so its commit carries any change. It applies only when
`automated-tests:` reads `no` and a finding names a test runner that covers the changed code.
Interactive: say the runner and its source in one line. Ask one question: keep "no automated
tests", or change it to yes. On a change, run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/scope/scripts/scope-actions.sh --run-mode interactive \
  set-tests "<task_folder>" --automated yes
```
Autonomous: keep the answer, and say the runner in one line. A person decides at the next window.

## Run the coverage check

Once every planned search has been dispatched and recorded, run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/research/scripts/research-actions.sh check "<task_folder>"
```
This reads every research file's JSON and writes its report to `<task_folder>/records/research-check.json`.
It prints `status:`, the report's line count and `report:` with the path. When the status is not
zero it adds one `open:` line with the uncovered ids and the counts. The report holds:

- a research file with a missing, empty or malformed required field;
- a `criteriaServed` id that names no criterion in the contract;
- every criterion the contract holds that no finding anywhere cites (`criteriaWithNoFinding`);
- every finding whose `criteriaServed` is empty (`findingsWithNoCriterion`).

A task whose `research` folder does not exist yet is not an error: it is reported as research not
started, with every criterion uncovered, the same as an empty `research` folder that does exist.

Exit 0: nothing to do. The record is committed when the stage closes: a clean check commits the
task folder, and `record` commits nothing. Dispatch `distiller` once, with the message this file
names. Its lines are the role, the run mode, the task folder, the stage `research`, and the
paths of `research/*.json` and `records/research-check.json`. Never a summary of this
conversation. It
writes `records/research-distill.json`. Then run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/research/scripts/research-actions.sh distill "<task_folder>"
```
It prints `standsAlone:` and one `gap:` line per gap, and exits 0 on either value. Show each
`gap:` line; acting on one is another `record` call. Exit 2 means the sidecar was not written.
Send the same agent one message: write the file and read it back. An agent has reported a write
it never made. Dispatch a fresh one only when exit 2 repeats. Exit 4 means the sidecar was
malformed. The script set it aside at the `setAside:` path it printed. Dispatch a fresh
distiller, with the rule it broke quoted from `agents/distiller.md`. Then run the same call
again. A second exit 4 stops for the person: show the stderr line and the path set aside. A
dispatch that ends before the role's first write is the third case. The scope skill states the
rule under "The distill check": once more with the same message, then once on `model: sonnet`.

Then show what research found, before anything else. This is a presentation, not a question.
Research asks nothing here, and the person speaks up only when something looks missing. Read
each rendered `research/<search>.md`. Show, per search, one line per finding with its source.
Then pull three things out of those findings and name them on their own. The guides and recipes
the catalog identified, by name. Each prior art candidate, with how close it is, as recorded;
design decides reuse, extend, supersede or decline, not research. Each assumption from scope that a
finding showed false, in one sentence. A count and a next command are not a presentation. The
findings are what design acts on, so the person sees them here or not at all.

Exit 4: a research file itself is broken: not valid JSON, not an object, or a top-level field
such as `searchedFor` missing or malformed. No action wrote such a file and none repairs it,
`drop` included. Say which file and what is wrong with it, and stop; a person decides what it
was. A broken finding inside a readable file is exit 5, below.

Exit 3: the script could not run the check at all. Read its stderr and fix the named problem,
then check again.

Exit 6: the coverage is clean but the spike folder named on the `spike:` line still exists.
Delete that folder, then check again. Nothing else is missing.

Exit 5: the file reads, but a finding or the coverage is wrong. For each id the `open:` line
names under criteria with no finding, dispatch another search for that criterion specifically.
Every finding names the criterion it serves, so repair each entry in the report's
`findingsWithNoCriterion`.
The report gives each one as a file path and an `index`, the finding's position in that file. A
"looked and found nothing" finding serves the criterion its search was dispatched for, so serve
it:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/research/scripts/research-actions.sh serve "<task_folder>" \
  --search <slug> --index <n> --criteria-served <id[,id...]>
```
A positive finding attached to nothing is work nobody asked for: serve it with the criterion it
serves, or drop it:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/research/scripts/research-actions.sh drop "<task_folder>" \
  --search <slug> --index <n>
```
`serve` rewrites that one finding's `criteriaServed`; `drop` removes that one finding, and
removes the file when no finding is left. A `drop` moves every later finding in that file down
by one, so the report's other indexes for that file are stale. Repair one entry, run `check`
again, then the next. A finding citing an id the contract does not hold is listed in the
report's `unknownCriteriaIds` the same way. Serve it with the ids it does serve. A finding with
a missing or malformed field is listed by path and `index` too. Drop it with `drop`, then
`record` it again with every field. Calling `record` alone, with the same `--search`, appends a
second finding and leaves the first one as it was, so it repairs nothing.

Research is done only when this check reaches exit 0. Nothing is left deliberately open, because
design refuses to start until the report holds exit 0.

## Offer a split

Research asks the split question once, here, because closed research is the first real evidence
of how many pieces the task holds. The recommendation is the value and a person decides; nothing
in this section splits on its own.

After `distill` reports, dispatch `split-advisor` once, with the message this file names: the
role, the run mode, and the task folder. It writes `records/research-split.json`. Then run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/research/scripts/research-actions.sh split-read "<task_folder>"
```
It prints `recommendation:`, `children:`, one `child:` line per child with its criterion count,
and `reason:` with the first sentence. Show those lines.

Exit 2: the advisor wrote no sidecar. Send it one message to write and read back, then run
`split-read` again. Still exit 2:
say the advisor wrote no sidecar. Go on flat. Exit 4 means the sidecar was malformed. The script
set it aside at the `setAside:` path it printed. Dispatch a fresh split-advisor, with the rule
it broke quoted from `agents/split-advisor.md`. Then run the same call again. A second exit 4
stops for the person: show the stderr line and the path set aside.

`recommendation: flat`: say so in one line. Go on.

`recommendation: split`, interactive: read the sidecar's `children`. Show each child's id,
goal and criterion ids. Ask one question: split as recommended, change it, or keep it flat. On
yes, invoke the task skill through the Skill tool, once, with `split` and the parent's task id.
Pass the children, goals and criteria exactly as recommended. That action takes each criterion's
text, not its id; read the texts from the contract file named on the `contract-file:` line. Then
name `/aida:scope <child-id>` for each child. Stop. On a
change, take the person's children, goals and criteria. Run the same. On no, record nothing
more. Go on.

`recommendation: split`, autonomous: say in one line that the advisor recommended a split and
recorded it at the sidecar path. Go on flat. A person decides at the next window.

Interactive: stop here. Name the next command for the person, `/aida:design <task-id>`, and never
invoke it yourself. Autonomous: invoke `aida:design` through the Skill tool, once, with the task
id, and stop if it refuses. Invoke it only when the mode covers design too; otherwise end as
interactive does, naming the command. Each stage refuses to start without the previous stage's
record, so a stage cannot run out of order. That is why this chain is safe.

## Research never blocks

Research decides nothing about the problem, so there is nothing for a person to approve. It never
asks permission to look something up, and every finding carries its source, so a wrong finding is
checkable afterward by anyone. The questions it asks are the two above, the automated tests
answer, and the split. The split comes after its own work is done. Autonomous mode runs every step
the same way, apart from those four and the close. At each of the first three, it takes the noted
branch instead of asking.

## What this skill never does

It never reads a guide or a recipe it finds. It names it and moves on; design reads it.

It never picks between two candidates or two sources that both pass their own test. It ranks and
hands the ranking to design.

It never writes a finding with no source. A claim from memory is a lead for one search, never
the answer research records.

It never treats an empty `criteriaServed` as an error to avoid. `record` accepts it, and it is
exactly what the coverage check looks for on the other side. The check names every empty one,
and research closes only once each one names a criterion.
