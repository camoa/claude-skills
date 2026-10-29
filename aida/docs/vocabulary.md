# Vocabulary

These are the words AIDA holds to one sense, so one thing never has two names. The rows below
are the rows of `tests/vocabulary.txt` in the plugin. AIDA's pages and skills never use a word
from the "Not called" column for the thing in that row.

## The stages

| Word | What it names | Not called |
|---|---|---|
| scope | the first stage: the contract a task is judged against | |
| research | the second stage: what design needs, found in the code, outside it, and in the recipes | |
| design | the third stage: the work orders | |
| implement | the fourth stage: the build, per work order. Its folder and its prose name are implementation | |
| review | the fifth stage: sixteen checks over the whole task, one verdict | |
| completion | the sixth stage: closing a finished task. Not complete, which is the task action and the state value | |

## Check verdicts

| Word | What it names | Not called |
|---|---|---|
| met | a check that looked and the answer is yes | `satisfied` |
| unmet | a check that looked and the answer is no | `unsatisfied` |
| unknown | a check that could not look | `undecidable` |
| undeclared | a check the recipe never declared | |
| not-needed | a check the orders it covers did not ask for: today, the suite of a task whose every order is proved by its record | |
| warned | a suite check that failed while no test failed: the recipe names the lines that failed it. finish refuses on it unless a person accepts it | |
| deferred | put off to a later step: a suite check a record step left to finish, or a finding ruled for a later task | |

## Criteria, candidates and findings

| Word | What it names | Not called |
|---|---|---|
| unanswered | a criterion nobody answered | `unresolved` |
| decline | a dispose verdict: a candidate weighed and set aside, with the reason. Also a person's no to an offer | |
| severity | high, medium, low, on a finding | `major`, `minor`, `blocker` |
| status | open, addressed, ruled, pending, on a finding | |
| ruling | wrong, deferred, load-bearing, test-wrong, on a ruled finding | |

## The unit of work and its proof

| Word | What it names | Not called |
|---|---|---|
| work order | the unit of work: one build, one review, one commit | `epic`, `epics`, `slice`, `slices`, `batch`, `batches` |
| check | one blocking check a stage runs | `validate`, `validates`, `validated`, `validating`, `validation` |
| gate | the proof kind of a configuration order: the recipe's own lines decide it, not a test | |
| tests | the proof kind of a code order, the default: tests frozen before the code is written | |
| confirm | the proof kind of a code order on a task with no automated tests: the person answers its done-when rows at review | |
| observe | the proof kind of a page order: after the build, a model looks once at the page the order builds and judges each done-when row | |
| test | what the implement stage writes before the code, as skills/implement/references/what-a-test-is.md defines it | |
| frozen test | a test after the freeze: nothing changes it, so the code cannot bend it to pass | |
| surface | a page or a command that review runs end to end or for visual regression after the build. Never a test | |

## Records and sources

| Word | What it names | Not called |
|---|---|---|
| record | a file a stage writes as proof it ran, read by the next stage | |
| recipe | a catalog document a stage resolves for the project's framework | |
| source | where a play or a finding came from: a person's file, the project, a catalog set | |
| vocabulary | this list | `glossary` |

## Words used above

- **finish** is the last step of implement. It hands the task to review.
- **A done-when row** is one line of an order's own proof: what must be true once it is built.
- **Proved by its record** means the order's deliverable is a document, so no test proves it.
- **A dispose verdict** is design's answer on a reuse candidate: reuse, extend, supersede or
  decline.

`verify` and `audit` are not on the list. Each has a second real use in AIDA's prose.

## Why it works this way

- **One name per thing.** When two words name one thing, a reader has to guess whether they are
  two things. A model guesses too.

Source: tests/vocabulary.txt
