---
# Routing block, first and in this order. Whoever is resolving reads to here and decides.
name: <framework>_design_architecture
capability: design
description: Use when a <framework> project enters design and must turn researched requirements into work orders. Says what kinds of thing the work can be about, what one unit exposes to another, what must exist beside the code, and what order this framework forces.
# Metadata, read only after a match.
label: Architecture design (<Framework>)
recipe_schema_version: 1.0.0
version: 0.1.0
recipe_class: process
framework: <framework>
authors:
  - name: <author>
license: <license>
---

<!--
A process recipe for the design stage. One per framework, and only one: the lookup resolves by
stage and framework and takes the first match.

The catalog owns the form: nine required sections, the three routing keys, and the rule that a
recipe references canonical sources rather than restating them. This template covers the part AIDA
owns, which is what design asks and what it needs back.

The thing to understand before writing one. Design produces work orders, and the orders plus the
order they run in are the architecture. There is no architecture document. This recipe returns the
units and their order to AIDA, which records them as work orders. Do not write a file.
-->

## Goal

What a good <framework> architecture is, in one paragraph, and what this recipe decides.

Say that the recipe returns units and their order to the caller, which records them. It does not
produce a document and it writes nothing.

## Opinion

The rules that make an architecture right in this framework, each with its reason. Where business
logic belongs. What a thin layer is allowed to contain. What the language or the framework enforces
for you, and what it leaves to discipline.

**Design decides; it does not build.** Say it here. No code, no registration, no install.

## Preconditions

What must be true for the method to run.

## Input contract

```yaml
code_path: string             # absolute path to the project root
requirements: string          # what is being built
acceptance_criteria:          # the outcomes a person can see when the task is done
  - id: string
    text: string
non_goals:                    # what is deliberately out of scope
  - id: string
    text: string
prior_art:                    # what research found, ordered by closeness, with no verdict
  - what: string              #   design decides reuse; research did not
    where: string
run_mode: string              # optional; interactive | autonomous
```

Research returns candidates and no recommendation. Do not take a verdict as input, and do not
return one in place of a decision.

## Sequence

The steps that turn requirements into units. Five things AIDA cannot know and needs from here.

**1. What kinds of thing the work can be about.** The buildable units of this framework: a package,
a module, a service, a component, a plugin, a theme. This is what a unit is sized around, and
getting it wrong produces work sized around files rather than around what the framework builds.

**2. What is built with configuration rather than code.** Where this framework answers a need
without anyone writing code, say so and say what such a unit looks like. It is still a unit of work
and it still states what its test must observe. Where the framework has no such thing, say that
plainly rather than leaving it silent.

**3. What must exist beside the code for a unit to work.** A registration entry, a route, a
permission, a schema, a manifest line. Name them, because a unit missing them is not finished, and
whoever builds it will otherwise invent what is missing.

**4. What one unit exposes to another.** What the surface, the entry point or the seam is called
here, and where it is declared. AIDA records this so the units depending on it can be built against
it.

**5. What order this framework forces.** Where one kind of unit must exist before another, say so
and why. Where the framework forces no order, say that.

Then the framework's own decision method: which pattern each unit takes, judged against stated
criteria rather than habit, and anchored to a real file in the framework's own source that whoever
builds it can open. A recommendation with no file path to study is incomplete.

**Return the units and the order.** AIDA records them as work orders. Write no file.

## Data flow

What comes in, what state is read, what opinion is applied, what is referenced, what is emitted.

## State-awareness contract

That the method reads the project's existing layout before deciding, so a design extends what is
there instead of colliding with it. That it is read-only: nothing written, nothing registered,
nothing installed.

## Verifier

The checks made after this recipe runs, each decidable by looking. At minimum: every unit names its
kind, its surface, and where its files live; every pattern choice names its reasoning and a real
file to study; the order is stated; and the project is unchanged.

## References

The guides this recipe cites rather than restates, and the framework sources it reads.

## What this recipe does not decide

**Test levels.** A work order says what each test must observe. Which tier that becomes belongs to
the recipe for the build stage, where the tier names already live. Do not name them here.

**Whether a candidate is safe to depend on.** Research took those readings and this recipe consumes
them.

**Coding standards, and anything about how the code will be written.** That is the build stage.
