# Research

Research finds out what is already true before anyone designs. It runs after scope approves the
contract, and it works for the design stage. Design should never have to guess, and never have
to look something up itself. Run it with `/aida:research <task-id>`, or with no id to run
against the task active in this conversation.

For each acceptance criterion that needs it, research answers five questions. Has someone built
this already? Are there guides or recipes that cover it? Do reputable sources recommend a way to
do it? Is an assumption the task leans on still true? And it hands the answers to design in a
form design can act on without looking again.

## What research does not do

Research does not decide. It reports what exists and what is true of it. Choosing between two
usable options is design's work, because a research stage that picks has become design.

Research does not read to the bottom of anything. A subject is never exhausted, so the criteria
are what stop this stage, never the subject. It is done when every criterion has a finding and
every finding cites a criterion.

Research never records a claim from memory. Every finding names where it came from and when it
was looked at, and a finding with no source is not a finding. The model's own recall is only a
lead: it says where to look, and one search confirms it or records that nothing did.

Research never reads a guide or a recipe it finds. It names the thing and moves on, because
loading is where the cost is, and a summary of a guide is worse than the guide. Design reads the
full text in its own context, only when it needs it.

## Before it starts

Research needs a task, and that task needs a scope contract. Two things stop it before any
search runs. No task is known: it says so, names the task stage, and stops. The task has no
contract: it says so, names the scope stage, and stops, because there is nowhere to write. It
checks that a contract exists, not that a person approved it. It lists any criterion that only
the model wrote, so you see those before they are researched.

If the task folder holds material captured before the task existed, research reads all of it
first. That material is input, never a finding. It names things to search for, and a claim from
it is recorded only once a search confirms it with a source.

A second run on the same task reads the searches already on disk before deciding what is still
missing. Nothing starts over. A task from version 5 keeps its old research. The first run reads it
and records each finding that still holds, one search per old file. New searches run only for
what those files never covered.

## The playbooks loaded here

Research is where the task's playbooks are loaded, once, because this is where the task's
evidence starts. Design and implementation then read one record and never fetch. A loader
fetches each catalog set the project subscribes to. A second step merges those plays with your
own file and the project's file into one record in the task folder.

The record marks each source as loaded, absent, empty, or unreachable, with a count. A set the
catalog could not serve is said in one line and never reads as "nothing to follow"; the next run
tries again. Research itself cites no play. What a playbook is and where the plays reach the
roles is on [Playbooks](playbooks.md).

## The three places it looks

Each search is one small agent with a narrow brief: the words to search, the bound, and the
shape of what to return. The agent never sees the conversation, and the conversation never sees
what the agent read, only what it reports. That isolation is what keeps the cost bounded. How
many searches run is set by what the criteria need, not by a fixed roster. Three criteria that
rest on the same library may need one search.

**Your own code and configuration.** This search exists to stop one failure. A project has a
generic chat class, a later task needs a chat, and the model writes a different one. The
searcher looks by proximity of name over things already named, then reads the top of each
candidate, its docblock, never the whole file. A file with no docblock is reported as having
none, which is itself a signal, since undocumented code is where duplicates breed.
Configuration counts as prior art too: an existing view or content type solves a problem with
no code written. The project's own task records are searched the same way, so "have we built
this" is asked of the project's history. This searcher has no web tools, because prior art
inside a project is a claim about this project. A web result answers a different question
without saying so. This search runs on every task that changes code.

Where the project's own code lives, as against framework and vendor code, is a framework
convention, so it comes from the process recipe below. The searcher hands candidates over
ranked by how close each is, same name, same directory, same layer. Closeness is a fact; fit is
judgment, and design answers reuse, extend, or supersede, in that order.

**Outside the project.** A library, a module, a package that already does this; what reputable
sources recommend; or one assumption that might have changed. One subject per search, and a
current, dated source every time. Anything found is judged on three things that transfer to
every stack: is it maintained, is it used, is it supported. Checking an assumption has three
outcomes, true, false, or could not be settled, and all three are recorded. A false assumption
is one of the most useful things research produces.

**The catalog.** The navigator is the plugin that reads the guide catalog. Research asks it
which guides and recipes cover each criterion, and records the names and which kind each is.
Where the catalog comes from is on [Where content comes from](sources.md). A tooling recipe means
the tool exists and can be installed. A process recipe means the framework's procedure is
already written down. An agentic recipe means the decision is already made, when it comes from
a source this project accepted. From any other source the opinion is recorded as not binding,
in both modes, so design decides normally. A catalog that could not be reached is not a catalog
that held nothing, and the finding says which happened. A source you configured yourself, a
folder of your own, is read directly.

**A spike, rarely.** Some design questions no document answers. Research answers one of those
only once the searches came back empty. It writes a small experiment under `.aida-spike/` in
the task's code path, which is the worktree when one exists, and runs it. That folder must
already be in the project's `.gitignore`, or nothing is written. The answer is recorded as a
finding. The folder is deleted before research closes, and the coverage check refuses while it
exists. Design writes the real code fresh.

## The process recipe

Some things change by framework: where custom code lives, and how to read whether a candidate is
safe to depend on. A Drupal beta usually means a module wants more sites running it; a beta
elsewhere can mean the interface is still moving. Those readings live in a process recipe for
your framework, looked up once, before the first search. A folder you declared answers first,
and the catalog answers when no folder holds it.

Research reads the recipe body and judges once whether it describes the work the criteria name.
When it does not, research says so and asks whether to continue with it, without it, or stop.
Autonomously it continues with the recipe and records the misfit.

When no recipe covers your framework, research records that and falls back. Outside, it applies
the plain three-part test. Inside, it searches from the project root, and the finding says the
bound on custom code was not enforced. It never guesses a framework's layout. Interactively it
then offers to write a recipe with you, from a template that carries the sections the catalog
requires. Autonomously it records the gap and continues.

A recipe that does not exist, a listing that could not be reached, and a network that failed are
three different findings. Only the first says anything about your framework. Research records
which one happened, in those words, because a false "no recipe" can never be told from a true
one afterwards.

## What a finding looks like

Each search writes one record, and `research/<search>.md` in the task folder is rendered from
it for you and design to read. Nothing reads the rendered page back, so an edit to that page
records nothing; the check, the advisor and the distiller read the record. At the top of the
page sit the words the search searched for, because those words bound every finding below. A
search that found nothing proves nothing outside them. Design reads the words to know what it
must still look up itself.

Each finding then holds four things: what was found, where it came from, the date it was looked
at, and which criteria it serves. A search keeps one set of words for its whole life. A search
that broadens takes a new name, so its earlier findings never claim a bound they were not found
under.

"Looked and found nothing" is recorded, once, as a finding. Silence and a negative result look
identical from outside, and design cannot go back and look. So the recorded nothing is what
tells design it is safe to decide.

A finding can be recorded with no criterion, on purpose. Forbidding that would make a finding
attached to nothing unrecordable, and the coverage check below could then never catch it. It
cannot stay that way; the check refuses until every finding cites a criterion.

If a search shows a criterion is too vague to check against, research does not invent a bound.
It says so, names the scope stage, and moves on to what it can check.

## The coverage check

Once every planned search is recorded, research runs one check over all of them. It reads the
contract and every search file, in both directions. Every criterion the contract holds must have
a finding somewhere, and every finding must cite a criterion. The same data, grouped the other
way, is the report, so nothing is authored twice.

The check refuses on five things:

- A finding with a missing or broken field. Research drops it and records it again. A file that
  is not JSON, or broken above its findings, is one no AIDA action wrote. Research names it and
  stops, and you decide what it was.
- A finding citing a criterion id the contract does not hold. Research serves it with the ids it
  does serve.
- A criterion no finding cites. Research dispatches another search for that criterion.
- A finding tied to no criterion. A genuine "looked and found nothing" serves the criterion it
  looked for, so research serves it with that id. A positive finding attached to nothing is work
  nobody asked for, so research serves it with the criterion it serves or drops it. Serving and
  dropping are their own actions on one finding, because recording again adds a finding and
  removes none.
- The spike folder still on disk. Delete it, then check again; nothing else is missing.

Research is done only when the check passes. Every gap is closed one of three ways: recording
again, serving or dropping a finding, or changing the contract through scope. Nothing is left
deliberately open, because design refuses to start until this check has passed. A clean check
commits the task folder; nothing before it is committed.

After the check, research dispatches a reader, the distiller, over the findings on disk, never
the conversation, and it says whether they stand alone. Each gap it names is one advisory
line, and acting on one is another recorded finding. It blocks nothing.

## What research shows at the close

Research closes by showing what it found. This is a presentation, not a question: research asks
nothing here, and you speak up only when something looks missing. The findings are what design
acts on, so you see them here or not at all.

Per search, one line per finding with its source. Then three things pulled out on their own.
The guides and recipes the catalog identified, by name. Each prior art candidate with how close
it is, as recorded, with the reuse decision left to design. And each assumption from scope that
a finding showed false, in one sentence.

## The split advice

Closed research is the first real evidence of how many pieces a task holds, so this is where AIDA
asks once whether to split. An advisor reads the closed research from disk, never the
conversation, and recommends flat or split, with a reason. A task with three or fewer criteria
stays flat unless your own words in the task file asked for a split. No count above three forces
one either.

Interactively, a split recommendation shows each proposed child with its goal and criteria. It
asks one question: split as recommended, change it, or keep it flat. A yes creates the children
and names `/aida:scope <child-id>` for each, since every child gets its own contract. What a
split hands down is on [A task](task.md). After a split, research stops there: the children's
scope commands are the next step. Autonomously, the recommendation is recorded and the task
goes on flat; you decide at the next window.

When the task stays flat, research names `/aida:design <task-id>` and stops. It never starts
design for you.

## Autonomous runs

Research runs the same way in both modes, because it decides nothing about the problem. Looking
something up needs no permission, and every finding carries its source, so a wrong finding is
checkable afterwards by anyone who opens it. Scope needs a person because every later stage
verifies a wrong criterion faithfully. A wrong finding is caught the moment its source is read.

Autonomously, four things differ. A recipe that does not fit is used anyway and the misfit
recorded. A missing recipe becomes a recorded note instead of an offer to write one. A split
recommendation is recorded, not acted on. At the end research invokes design
itself, and stops if design refuses. Each stage refuses to start without the previous stage's
record, which is why the chain is safe.
