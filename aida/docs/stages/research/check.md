# The coverage check

The coverage check asks two things: every criterion has a finding, and every finding cites a
criterion. A gap is a warning, and research closes. Research is optional, so design starts without
it and says so.

## What the check reads

The check reads the contract and every research file, in both directions. It writes its report to
`records/research-check.json`. A check that closes research commits the task folder. Nothing in research is
committed before that.

## When it warns, and when it stops

Research repairs most gaps itself and checks again. It searches again for a criterion no finding
cites, and ties a finding to the criterion it serves, or drops it. A gap can also close when you
change the contract through `/aida:scope`.

A broken research file stops research for you. With nobody present, a criterion with no finding
stops the close too, because nobody reads the warning before design. Each case is described on
[The research check refuses to close](../../when-it-stops/research-check.md).

A task with no `research` folder yet is not an error. The check reports every criterion as not yet
covered.

## Why it works this way

- A check that starts from the criteria cannot see work nobody asked for. Reading in both
  directions catches both a missed criterion and an extra finding.
- A finding with no criterion can be recorded on purpose. Otherwise the check could never catch
  one.

Source: skills/research/SKILL.md, skills/research/scripts/research-actions.sh, scripts/check-research.sh
