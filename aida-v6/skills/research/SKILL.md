---
name: research
description: This skill should be used when a task's scope contract is approved and its criteria need grounding before design starts, for example "research this task", "find prior art", "check for an existing library", "look for a guide", "check this assumption", or "Phase 1". It fans out one small search per subject, records each search's findings in its own file, and checks that every criterion has a finding and every finding cites a criterion.
disable-model-invocation: true
argument-hint: "[<task-id>]"
arguments: [taskId]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/research/scripts/research-actions.sh *), Agent
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

Every write below goes through `research-actions.sh`, named in this skill's own grant, so it
runs without asking. Any other Bash command still asks for approval. Dispatching an agent needs
no approval either; it is also named in this skill's own grant.

## Determine the run mode

Look for a stated run mode on the task active in this conversation. Found, and it says
`autonomous`: act autonomously through this whole invocation. Anything else, including no
active task: act interactively, the safe default. Decide this once, at the start.

Research never blocks on this choice the way scope does. The run mode only changes what happens
at two points below, a missing process recipe and an unaccepted guide source; everything else
runs the same way in both modes.

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
This reports whether the task has an approved contract, lists its criteria, and lists any
research file already on disk for this task, with each file's search name and how many findings
it holds.

No contract: say so in one line and name the scope skill. Stop.

A contract with research files already present: this is a resumed or repeated run. Read each
listed file before deciding what is still missing, rather than starting over.

## Start the stage

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/research/scripts/research-actions.sh start "<task_folder>"
```
This creates the task's `research` folder and prints the criteria list again, for reference
while planning searches. It is safe to run more than once; it never overwrites anything.

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
  here; the outside search covers those.
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
  or record that nothing confirmed it.
- **An assumption that needs checking.** Named because a mechanism the task leans on might have
  changed. Checking it has three outcomes, not one: true, false, or could not be settled. All
  three finish the check and all three are worth recording; a false assumption is one of the
  most useful things research produces.

How many searches run is set by what these criteria actually need. A task with three criteria
that all rest on the same library may need one search, not three.

## Dispatch one agent per search

For each search decided above, dispatch one agent with a narrow brief: the words to search, the
bound (this project's own code, a package registry, the guide catalog, the open web), and the
shape of what to return, findings with a source and nothing else. The agent never sees this
conversation and this conversation never sees what the agent read, only what it reports back.
That isolation is what keeps the cost bounded.

Tell the agent plainly: recall is not a finding. If it already believes it knows the answer,
it still runs the search and reports what the search found, not what it remembered.

An agent that comes back with prose about how it searched, rather than findings with a source
and a date, has not done the job. Ask it again, or record what it did find and note the rest as
not searched.

## Record each finding

For every finding an agent returns, record it under that search's own name:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/research/scripts/research-actions.sh record "<task_folder>" \
  --search <slug> --text "<what was found, or that nothing was>" \
  --source "<where it came from>" [--criteria-served <id[,id...]>]
```
`<slug>` is lowercase letters, digits and single hyphens, and it names the file: a search called
`prior-art-internal` writes its findings to `research/prior-art-internal.json`, and `record` then
renders `research/prior-art-internal.md` from it. Nothing reads the rendered file back; it is for
the design stage to read. Call `record` once per finding; calling it again with the same
`--search` adds another finding to the same JSON file, and the rendered markdown with it, rather
than replacing it.

`--criteria-served` takes the criterion ids from the contract read above, comma separated, for
example `c1,c3`. Attach every id this finding actually speaks to. Leave it out when a finding
speaks to none: an empty list is allowed, and it is itself checked below, not silently accepted.

A search that found nothing is still recorded, once, with `--text` saying so plainly, for
example "looked and found nothing: no maintained package covers this without pulling in a whole
framework". Silence and a negative result look identical from outside; only the recorded
negative tells design it is safe to decide without searching again.

Never write a finding from memory. If nothing was dispatched to check something, it is not
recorded as found; it is either dispatched or left for the next pass.

## Reading the catalog

Everything published in the catalog is read through the navigator: guides, tooling recipes,
process recipes, agentic recipes. Research never fetches a catalog address itself and never reads
a cached copy directly.

**A process recipe is looked up, never searched.** Ask the navigator's process-recipe lookup for
this project's framework at the research stage. It answers with whether one is available and, when
it is, a path to the body on disk. Read the body from that path. The body is never streamed into
the conversation, which is what keeps a recipe affordable.

**Three answers, not one.** A recipe that does not exist for this framework, a listing that could
not be reached, and a network that failed are three different things and only the first is a fact
about the framework. Record which one happened, in those words. Treating the second or the third
as "this framework has no recipe" writes a false finding that nothing later can tell from a true
one.

**A source this project configured itself is read directly.** The navigator serves the published
catalog. A project pointing at its own folder is a different source and research reads it the
ordinary way.

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
reuse, extend, or supersede, in that order. Research does not choose between candidates that all
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

Interactive: ask whether to create one, through the current create-on-miss path, before moving
on.

Autonomous: record the missing recipe as a note in the finding's own text and continue. Do not
invent a framework-specific rule in its place.

## When the contract needs more

If a search shows a criterion is too vague to check against (research.md's open question: a
criterion that gives no bound), do not invent a bound. Say so, name the scope skill, and move on
to what can be checked.

## Run the coverage check

Once every planned search has been dispatched and recorded, run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/research/scripts/research-actions.sh check "<task_folder>"
```
This reads every research file's JSON and reports, in one JSON object:

- a research file with a missing, empty or malformed required field;
- a `criteriaServed` id that names no criterion in the contract;
- every criterion the contract holds that no finding anywhere cites (`criteriaWithNoFinding`);
- every finding whose `criteriaServed` is empty (`findingsWithNoCriterion`).

A task whose `research` folder does not exist yet is not an error: it is reported as research not
started, with every criterion uncovered, the same as an empty `research` folder that does exist.

Exit 0: nothing to do. Report research complete.

Exit 4: a research file itself is broken: not valid JSON, not an object, or a missing or
malformed required field. Fix that file with another `record` call, or by hand, and check again.

Exit 3: the script could not run the check at all. Read its stderr and fix the named problem,
then check again.

Exit 5: the schema is fine but the coverage is not. For each id in `criteriaWithNoFinding`,
dispatch another search for that criterion specifically. For each entry in
`findingsWithNoCriterion`, decide by hand: a genuine "looked and found nothing" that never tied
to one criterion can stand as recorded; a positive finding attached to nothing is work nobody
asked for, so either attach it to the criterion it actually serves or leave it out. Then check
again.

Research is done when this check reaches exit 0, or when every remaining gap has been looked at
and deliberately left, with the reason recorded in the finding's own text.

## Research never blocks

Research decides nothing, so there is nothing for a person to approve. It never asks permission
to look something up, and every finding carries its source, so a wrong finding is checkable
afterward by anyone. Autonomous mode runs every step above the same way, taking the noted branch
at a missing recipe or an unaccepted source instead of stopping to ask.

## What this skill never does

It never reads a guide or a recipe it finds. It names it and moves on; design reads it.

It never picks between two candidates or two sources that both pass their own test. It ranks and
hands the ranking to design.

It never writes a finding with no source. A claim from memory is a lead for one search, never
the answer research records.

It never treats an empty `criteriaServed` as an error to avoid. It is allowed, and it is exactly
what the coverage check looks for on the other side.
