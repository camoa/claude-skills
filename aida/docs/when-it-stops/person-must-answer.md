# A run with nobody present stops for a person

A light or autonomous run still meets calls only a person may make. AIDA never makes them for
you. It refuses the call, records nothing, and tells you what waits. You answer, and the run
goes on.

## What you see

- **Exit 70.** A person's answer was passed with nobody present: a review row, a completion
  reason, the forgetting of an adopted site, a test confirmation, a tool install, or a project
  write such as the task rule.
- **Exit 68.** A person's judgement in the build: the three ways out of a stop, `go-on`, `redo`
  and `drop`, and `start --leftovers keep`. These
  refuse in every run mode until your answer is on record.
- **Exit 55 or 100.** A ruling on a finding, or an `--allow` for a fix round, in every run mode.
- **Exit 70 from `set-run-mode`.** A change of run mode needs your answer, in every run mode.
- **A stop.** The order stops with its reasons, and the run ends with a report.
- **"The offer waits for a person".** A site offer, a project setup, a split or a recipe offer
  that nobody was there to answer. Nothing is recorded, so it comes back.

## How to answer

- **Approve the prompt.** The refusal prints the command that records your answer. Claude runs it,
  and Claude Code shows you a permission prompt with your words. This works for the build's calls,
  the run-mode switch, design's approval of command lines, review's close, completion's close and
  the adopted site. See [the person's answer](../task/person-answer.md).
- **Set the task interactive**, through that same prompt, then run the stage again and answer when
  it asks. This works for review, completion and the adopted site.
- **Run it yourself with a person present.** A tool install and a project write such as the task
  rule take no recorded answer.

## What does not stop

Two decisions never stop an unattended build: a finding that names no file to change, and a
departure from the design. Each waits as pending. The order closes and the build goes on. The task
review asks you each one before its verdict.

## What a run decides without you

- With several open tasks, `/aida:next` lists them, says none was chosen, and goes on.
- With no project, `/aida:project` says the directory is not set up and goes on.
- A mode such as `autonomous (implement)` covers only the stages it names. The other stages ask
  you as usual.
- A light run reads as autonomous everywhere, and it skips named steps. Each skip is logged in
  `COMPROMISES.md` in the task folder. See [light runs](../task/light.md).

Approving what an unattended scope drafted is on [approve the contract](../stages/scope/approve.md).

## Why it works this way

- **A model never stands in for a person.** A judgement nobody made, recorded as if a person made
  it, is worse than a stop.
- **The record keeps the run mode.** A coordinator running many tasks can pass your answer
  without switching each task to interactive.
- **Claude Code asks, not AIDA.** AIDA cannot see who answers a prompt. What that guarantees is on
  [the person's answer](../task/person-answer.md).

Source: skills/implement/references/finish.md, skills/task/SKILL.md, skills/completion/SKILL.md, skills/review/references/close.md, scripts/lib/recipes.sh, skills/tool/scripts/tool-actions.sh
