# Vocabulary

Every word AIDA holds to one sense, so the same thing is never called two names. Short by
design: a word is here because a check enforces it. The list itself is `tests/vocabulary.txt`
in the plugin, and `tests/vocabulary-spec.sh` flags every banned synonym in shipped prose.

| Word | What it names | Not called |
|---|---|---|
| scope, research, design, implement, review, completion | the six stages, named as their skills are; the implement skill runs the implementation stage, and the pages say implementation | |
| met, unmet, unknown, undeclared | a check's verdict: it looked and the answer is yes; it looked and the answer is no; it could not look; the recipe never declared it | `satisfied`, `unsatisfied`, `undecidable` |
| unanswered | a criterion nobody answered | `unresolved` |
| high, medium, low | a finding's severity | `major`, `minor`, `blocker` |
| open, addressed, ruled | a finding's status; a ruled finding is wrong, deferred or load-bearing | |
| work order | the unit of work: one build, one review, one commit | `epic`, `slice`, `batch` |
| check | one blocking check a stage runs | `validate`, `validation`. `audit` is not banned: it is the review action that lists how each verdict came about |
| gate | the proof kind of a configuration work order: the recipe's own lines decide it, not a test | |
| record (proof kind) | the proof kind of a document work order: its done-when rows decide it, not a test, and it lands no commit in the code repository | |
| record, recipe, source | a file a stage writes as proof it ran; a catalog document a stage resolves; where a play or a finding came from | |
| vocabulary | this list | `glossary` |

`verify` is not banned: a criterion's verify clause and the reviewer's verify mode are its own
senses. A word with a second legitimate use stays off the list, because the check cannot read
meaning.
