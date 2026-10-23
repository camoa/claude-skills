# Surfaces at review

Review runs each kind that is on, over the surfaces the change could reach. Then it puts every
surface in front of you, including the ones that passed.

## What review runs

Review runs nothing that is off. A kind marked on whose surface file is missing counts as off when
a person is present, so review offers the setup again. For each kind that is on, it runs:

- every surface whose declared paths the change touched;
- every critical surface;
- every surface that declares no paths.

The rest are recorded as not run, by name. A kind whose surfaces were all unaffected reads `met`:
no run was asked for. When the framework's command cannot take a list of ids, the whole set runs,
and the review says so. A disabled surface is recorded as not run, never dropped.

A run that selected nothing reads `unknown`, because zero tests ran is never a pass. A registered
surface with no result reads `unmet`. Before an end to end suite, the recipe's preflight command
runs. When it fails, the end to end check reads `unknown`.

Review uses the address the task records for its worktree site. See
[the task pages](../task/README.md).

## A light task

A light task runs no visual regression, and that check reads `undeclared`. End to end still runs,
because it is the one test a light run keeps. With no enabled critical end to end surface, the
check reads `unmet` and names `/aida:surfaces e2e`. A project that declined end to end reads
`undeclared` instead.

## What a surface does to the verdict

A surface check that reads `unmet` or `unknown` fails the review. A kind that is off, or one the
recipe declares no command for, reads `undeclared`. That passes, and the review reports it in that
word. Visual parity has no harness today, so review records it as unavailable, never as passed.
See [Review](../stages/review/README.md).

## The walk

After the run, review puts every surface in front of you, at every viewport, and records which
you looked at. On an autonomous run, nobody can look. The walk is recorded as not done, and the
surface checks read `unknown`.

## Accept an intended change

A visual change you intended is not a defect. Review accepts a new baseline in two steps. It shows
the surfaces and viewports it would replace and takes your yes. Then it writes the new baselines
for those ids only. It never does this automatically or unattended.

## Why it works this way

- An aggregate score can improve while visible defects sit inside the passing surfaces, so a
  person looks at all of them.
- A check that cannot notice its subject going absent tells you nothing, so a missing result is
  `unmet`.

Source: skills/review/references/surfaces.md, skills/surfaces/SKILL.md
