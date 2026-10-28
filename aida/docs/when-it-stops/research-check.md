# The research check refuses to close

Research is optional, and its check stops little. Design starts without it and writes a warning.
The full list is on [the research check](../stages/research/check.md).

## What warns, and what stops

- **A coverage gap.** A criterion has no finding, a finding serves no criterion, or a finding names
  a criterion or a finding that does not exist. With you present, each is a warning in the task
  record, and research closes. AIDA searches again for an uncovered criterion, ties a finding to
  the criterion it serves, or drops it. With nobody present, a gap that is not a finding with no
  criterion stops the close (exit 5), because nobody reads the warning before design builds on it.
- **The runner check never ran.** The contract says the task has no automated tests, and the check
  that looks for a test runner has not run. It is a warning. What that check asks you is on
  [no automated tests](../stages/research/tests.md).
- **A spike folder is still there.** `.aida-spike/` still exists in the task's worktree, or in the
  code path when the task has no worktree. It is a warning. Delete the folder.
- **Exit 5: a research file is broken.** It is not valid JSON, or a field is missing, empty, the
  wrong shape or not allowed, at any level. That includes a finding with no text, no source or a
  bad date. No action wrote it that way and none repairs it. Research names the file and stops.
  You decide what the file was, and repair or remove it.
- **A criterion too vague to check.** AIDA does not invent a bound. It says so and names
  `/aida:scope`, where you make the criterion checkable.

## The split advice

After the check, research asks an advisor whether the task should split. When the advisor writes
nothing usable, research sends it once more. A second miss is a warning, and the task goes on
unsplit.

## The close summary

At each stage close an agent writes a short summary of the stage. When it writes nothing usable,
the stage sends it once more. A second miss is a warning, and the stage closes.

## Why it works this way

- **A gap stops only when nobody is there.** Design builds from the findings, so a criterion
  nobody researched is designed from a guess. A person reads the warning, and decides.
- **A broken file waits for a person.** No step wrote it, so no step can tell what it meant.

Source: skills/research/SKILL.md, skills/research/scripts/research-actions.sh, scripts/check-research.sh, scripts/research-schema.json, skills/scope/SKILL.md
