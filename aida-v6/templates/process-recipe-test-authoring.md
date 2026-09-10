---
# Routing block, first and in this order. Whoever is resolving reads to here and decides.
name: <framework>_test_authoring
capability: test-authoring
description: Use when a <framework> project must write the tests for one unit of work before any production code exists. Says which level a behaviour belongs at, where the file goes and what it is called, how the criterion it specifies is traced to it, and what a <framework> test may not do.
# Metadata, read only after a match.
label: Test authoring (<Framework>)
recipe_schema_version: 1.0.0
version: 0.1.0
recipe_class: process
framework: <framework>
authors:
  - name: <author>
license: <license>
---

<!--
A process recipe for the step that writes the tests. One per framework, and only one: the lookup
resolves by stage and framework and takes the first match, so a second one for the same framework is
unreachable.

The catalog owns the form: nine required sections, the three routing keys, and the rule that a
recipe references canonical sources rather than restating them. This template covers the part AIDA
owns, which is what the step that writes tests asks and what it needs back.

TWO FACTS ABOUT THE READER DECIDE EVERY SECTION. Check each sentence you write against both.

  1. It cannot read production source. Not the unit being built, and not any unit already built. A
     rule that begins "look at the class" is a rule this reader cannot follow. State it against the
     behaviour the test must observe and the names the unit declares.

  2. It cannot write production code. It writes the test, watches it fail, and stops. A sentence
     that would have it make the test pass belongs in the implement recipe, which a different
     context reads.

Fill every section. A section left as a placeholder is a recipe that resolves and answers nothing,
which is worse than no recipe, because the step will report that it read one.
-->

## Goal

What this recipe answers for a <framework> project, in one paragraph: which level a behaviour
belongs at, where its file goes and what it is called, how the criterion is recoverable from it, and
what a test here may not do.

**This recipe stops at red.** Say so here, in your own words, and name the two files the rest lives
in: the implement recipe for the half that makes a test pass, and the test-execution recipe for the
command that runs one.

## Opinion

The rules that make this framework's tests correct rather than generic. Each with its reason.

**The levels, as a table.** One row per level: the level, where its files live, the condition that
selects it, and what it costs relative to the others. The selecting condition is the hard column,
because it has to be answerable from the criterion rather than from the code. "Needs a database" is
usable. "The class has three collaborators" is not.

**The default, stated outright.** A reader told to choose the smallest level that answers the
question reaches for the cheapest and fakes whatever stands in its way. Say which level this
framework actually wants first, and why. The stack-neutral definition of a unit test is a set of
dependency exclusions and a speed target, which excludes almost nothing and will not stop a wrong
choice on its own.

**What is outside the loop.** Name any suite in this stack that runs against something already
built. Say that those are written after the behaviour exists, never substitute for a level chosen
here, and are reported separately.

Mechanics stay in the knowledge guides and are referenced. How a base class is extended, how a
fixture is built, how a runner is configured.

## Preconditions

Most frameworks have none, and that is a complete answer rather than a gap. This step writes files
and runs nothing, so it usually has no machine-checkable environment condition of its own. The
conditions for running a test belong to the test-execution recipe, beside the commands they are
conditions of.

Say that in prose, then declare it, because a heading with prose and no key is indistinguishable
from a misspelled key:

```yaml
preconditions: []
```

Declare a real entry only where something must exist before a test can be written.

## Input contract

The fields the caller supplies. Start from these and add only what this framework needs.

```yaml
code_path: string        # absolute path to the project root
<unit>: string           # the module, package or crate the test belongs to
criterion_id: string     # the identifier of the criterion this test specifies
behavior: string         # what the test must observe, in a sentence
interface: string        # the names this unit declares, and the names its dependencies declare
test_level: string       # optional; one of the levels in the table above
```

Say what the reader does when `interface` is empty. It is the only thing this reader gets about code
that already exists, and it is a declaration rather than source.

## Sequence

Numbered steps, dry-run first. **The sequence ends at red.** If you write a step that produces
working code, it belongs in the implement recipe.

1. Select the level, from the behaviour and the declared interface. Say what to do when the
   behaviour cannot be placed without opening the code: stop and report, because the choice then
   belongs earlier and somebody needs to know.
2. Place and name the file. Directory, file name, and the name of the test function or method,
   stated as an instruction. Cite the implement recipe's declaration as the authority for the
   machine-readable pattern rather than repeating it here.
3. Put the criterion identifier at the end of the test's own name, delimited so it cannot be part of
   a longer token, because a bare `c3` otherwise matches a name ending `C30`. Write the local
   spelling, and say plainly if a house coding standard forbids the obvious separator. If this
   framework has something better than the name, an attribute or a marker the runner selects on, use
   it and say how a script reads it back out.
4. Write the test, in the shape this framework expects. Assert on what the criterion names and
   nothing else.
5. Watch it fail, through the test-execution recipe, reading the failure signal it declares rather
   than the exit status. Say what a real red run looks like here, and what the two impostors look
   like: a harness that never reached the behaviour, and a run that selected nothing and exited
   zero. Say that a test passing on arrival is rewritten once, then reported as proving nothing.
6. Stop, and say what it returns.

## Data flow

Input, output, and the boundaries. The boundaries are the same for every framework: reads no
production source, writes only inside the test tree, runs no command except through the
test-execution recipe, and produces no task record of its own.

## State-awareness contract

How to find an existing test for a behaviour in this framework's tree, so the reader updates rather
than duplicates. Say the constraint out loud: the test tree is readable and the production code is
not.

## Verifier

Checkable statements about the result, six to nine of them, each confirmable without redoing the
work. These belong in every framework's list:

- Each test carries its criterion identifier at the end of its name, recoverable by string
  comparison and not as part of a longer token.
- Each test sits where its level requires and is named as this recipe says.
- Each new test was seen to fail, and the recorded failure is an assertion that ran and did not hold
  rather than a harness error or a run that selected nothing.
- No production file was written or changed.

Then add this framework's own. The valuable ones are the local shapes of a test that passes without
proving anything: a call whose return value is not asserted, an assertion on a surface nothing pins,
a level that fakes the thing it was supposed to exercise. One line each, with the repair.

## References

Four tables, each headed "referenced, not authored here": this framework's knowledge guides; the
stack-neutral test-first discipline, with a row saying it describes one person doing red, green and
refactor while this reader does red and stops; the sibling process recipes for the implement half
and for the command that runs a test; and external origins, naming the source rather than only the
fact.
