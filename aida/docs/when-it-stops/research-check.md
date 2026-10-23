# The research check refuses to close

Research closes only when its check passes, and design refuses to start until it does. A coverage
gap AIDA repairs itself and checks again. A few refusals stop for you. The full list is on
[the research check](../stages/research/check.md).

## What AIDA repairs itself

- **Exit 5: the coverage has a gap.** A criterion has no finding, a finding serves no criterion,
  or a finding names a criterion or a finding that does not exist. AIDA searches again for an
  uncovered criterion, ties a finding to the criterion it serves, or drops it. Then it checks
  again.
- **Exit 7: the runner check never ran.** The contract says the task has no automated tests, and
  the check that looks for a test runner has not run. Research runs it, then checks again. What
  that check asks you is on [no automated tests](../stages/research/tests.md).

## What stops for you

- **Exit 4: a research file is broken.** It is not valid JSON, or a field is missing, empty, the
  wrong shape or not allowed, at any level. That includes a finding with no text, no source or a
  bad date. No action wrote it that way and none repairs it. Research names the file and stops.
  You decide what the file was, and repair or remove it.
- **Exit 6: a spike folder is still there.** The coverage is clean, but `.aida-spike/` still
  exists in the task's worktree, or in the code path when the task has no worktree. A spike is a
  throwaway experiment, so research closes only once it is gone. Delete the folder, then check
  again.
- **A criterion too vague to check.** AIDA does not invent a bound. It says so and names
  `/aida:scope`, where you make the criterion checkable.

## The split advice

After the check, research asks an advisor whether the task should split. When the advisor writes
nothing after one reminder, research says so and goes on with the task unsplit. A second
malformed answer stops for you, with the error line and the path of the file set aside.

## The close summary

At each stage close an agent writes a short summary of the stage. When the agent fails three
times, the stage stops for you with the error. With nobody present, the run halts there.

## Why it works this way

- **Every criterion needs a finding.** Design builds from the findings, so a criterion nobody
  researched would be designed from a guess.
- **A broken file waits for a person.** No step wrote it, so no step can tell what it meant.

Source: skills/research/SKILL.md, skills/research/scripts/research-actions.sh, scripts/check-research.sh, scripts/research-schema.json, skills/scope/SKILL.md
