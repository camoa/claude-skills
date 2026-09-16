---
type: llm
weight: 1
---
This case exists because of a live run (`sources/nyc-defects-2026-09-14.md`, item 14, in the
AIDA docs repository) where the scope skill rendered the contract and asked for approval after
each of five corrections. The file shape here comes from `claude plugin eval init --bare`, the
scaffolder, not from documentation: the local mirror of the Claude Code documentation has no
`claude plugin eval` page. The scaffolder offers no scripted multi-turn conversation, so the
five corrections arrive as one task and the response is graded as one transcript.

A successful response does all of this:

- The draft is written through `init`, `set-goal`, `add --author designer` and
  `add-non-goal`, rendered once, and shown whole, with one question: what is wrong or missing.
- Each of the five corrections is answered with the changed lines only: the `UPDATED:`,
  `ADDED:`, `REMOVED:` or `GOAL SET` line and the summary the script printed, or one line saying
  the draft already holds it. Corrections 2 and 4 pass `--author owner`. Nothing is rendered
  after a correction, and no reply asks whether the contract is now right.
- Over the whole response, a question that asks for a yes or no on the whole contract, in any
  wording, appears at most once. Zero is the behaviour the skill describes; one is tolerated;
  two or more fails this case.
- The close is the `approve` action of `scope-actions.sh`, run once, after the distiller is
  dispatched, with `promoted:` and `standsAlone:` shown. It is not the `distill` action, and
  `approve` does not run before the fifth correction is answered.

The response fails when the approval question appears more than once, when `render` runs
after a correction the person did not ask to see, when `approve` runs early, or when the close
is missing.
