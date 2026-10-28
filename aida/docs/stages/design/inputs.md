# What design reads

Design reads every research finding, the plays research loaded, the guides research named, and
the process recipe for your framework. Then it looks up anything it decided to use that research
did not search for.

## Every research finding

Each finding is used by a work order, or set aside on it with a reason. A finding that names a
collaborator, a service, a convention or a constraint is used by the order it affects. A finding
that says nothing was found is accounted for too. The builder sees each used finding in its
build brief.

A finding in no order's list is a warning at the close with you present, and stops an
unattended close: see
[The design check refuses to close](../../when-it-stops/design-check.md).

## The plays

Design reads `records/playbooks.md`, the rules this project and you want followed. A play that
decides an order's shape is named in that order's reasoning.

## The guides and recipes research named

Research named these without opening them, so design reads them first. On a later run, design
does not read a guide again when it has not changed. One recipe
that covers the work means the decision is made, and design follows it. Two, and design reads
both and picks the one that fits. None, and design builds from the findings and your project's
own conventions.

## The process recipe for your framework

Your project's own recipe folders answer first. Design asks the catalog only when they hold no
design recipe for your framework. The recipe tells design what an order can be about here, what
is built with configuration and not code, and what has to exist beside a class for it to work.

Design judges the recipe's fit once, before the first order. Interactive, a poor fit gets one
question with four answers: continue with the recipe, continue without it, write the recipe
first, or stop. Autonomous, design continues with the recipe and records the verdict.

No recipe, a catalog that could not be reached, and a failed network are three different answers,
and design records which one happened. With no recipe, every order says it was written without
framework input. Interactive, design asks whether to write the recipe first, unless you already
declined recipes for this framework at research.

## A stated approach

An approach you stated at scope is read as a claim, never as a specification. A `required`
approach is followed once design judges it sound. An approach edited after research looked at it
is treated as ungrounded.

## A lookup research did not make

Design often names something research had no reason to search for: a module, a framework API, a
pattern. Design looks it up before the close, and never guesses. It skips a name research already
searched for. It looks in your project's code first, then the catalog, then outside sources. It
records each answer, a nothing included, as a research finding of its own.

## Why it works this way

- A finding nobody accounts for is research that paid for nothing, or a constraint the build
  never saw.
- The framework recipe holds what AIDA cannot know alone, and no check can replace it.
- A lookup recorded here does not run again during the build.

Source: skills/design/SKILL.md, skills/design/scripts/design-actions.sh,
skills/project/scripts/project-actions.sh
