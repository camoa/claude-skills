# Guides

Research names the guides that cover each criterion and opens none. Design reads them. Review
checks that the code follows them.

You type nothing to use guides. They come from the catalog, through the `dev-guides-navigator`
plugin. A folder of guides is not read: see
[Use your own folders before the catalog](your-own-sources.md#the-layout-of-each-kind).

## At research

Research asks the catalog which guides and recipes cover each criterion. Its summary keeps two
lists apart:

- the names that matched, each with its kind: guide, process recipe, tooling recipe or agentic
  recipe;
- the names that matched nothing.

A name that matched nothing is a finding too. It says the catalog does not cover that name. A
catalog that could not be reached is named as unavailable, never as a catalog that held nothing.
Research does not decide whether a match is worth reading. Design decides.

## At design

Design is the first stage that reads a guide body. It opens each one research named, and records
each body it read. It also looks up anything a work order names that research did not search, and
records a lookup that found nothing. So implementation never asks the same question again.

An agentic recipe that covers the work means the decision is already made, and design follows it.
With two, design picks the one that fits and says why. With none, design works from the findings
and the project's own conventions.

## At review

The reviewer reads the guide bodies design opened. A change that does not follow a guide research
cited is a finding under the guides check. A guide the code contradicts is also counted as a
catalog note in the review summary.

When no guide body is on disk, review searches once for current practice for the frameworks, and
the reviewer judges against what it finds. When that search finds nothing, review asks you
whether any guide covers the task. If none does, you judge the diff yourself, met or unmet. See
[Review](../stages/review/README.md).

## Why it works this way

- A name costs one lookup, and opening a body costs ten. Research names and design reads, so a
  body is opened once, where it is used.
- A missing guide is a reason to look, never a reason to skip the check.

Source: skills/research/SKILL.md, skills/design/SKILL.md, skills/review/references/reviewer.md,
skills/review/references/close.md, agents/catalog-identifier.md
