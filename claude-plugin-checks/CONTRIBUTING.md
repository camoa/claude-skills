# Contributing to claude-plugin-checks

## The one rule that decides what belongs here

**Does the check encode a fact Anthropic can change?**

If yes, it does not belong, however useful it looks today. Hook event names,
model tiers, reserved marketplace names, manifest key allowlists, character caps
and enum members all have an owner, and a check that writes one down is wrong the
day the owner changes it.

What belongs is structure — does the path resolve, does the file parse — and
self-consistency — does the file disagree with itself. Neither goes stale.

The same rule governs what a finding is allowed to *say*. Naming a collision is
structure. Asserting which side of it wins is a claim about Claude Code, and if
nobody has measured it, the finding does not make it.

If another tool already performs a check correctly, run theirs. `run-checks.sh`
is where that happens, and it passes their output through untouched.

## Where a change goes

A new rule is a function in an existing module under `scripts/cpc/rules/`, or a
new module beside them exposing `PREFIX`, `NAME` and `run(root, report)`. It adds
findings and nothing else. If you find yourself writing an exit code, a JSON key,
a tree walk or a `--strict` branch inside a rule, it belongs in `result.py` or
`walk.py` instead — three copies of that plumbing is what the last version had,
and the same blind-spot defect was present in all three.

## Before a change lands

1. `pytest tests/` and `bash tests/exit-codes-spec.sh` both pass.
2. Every new rule has a test that fires on a fixture carrying the defect **and**
   one that stays silent on a twin without it. A rule that only ever fires is not
   a rule.
3. Every new rule is mutation-verified: break its branch, watch the tests go red,
   put it back. Note which mutation you ran.
4. The plugin checks itself clean: `bash scripts/run-checks.sh .`
5. Run it against a few real plugins. Both defects that got past a green suite in
   this plugin's history were found that way and neither was found by a test.

## Three outcomes, never two

A check that could not look reports `UNCHECKED` and exits 3, and is counted apart
from both pass and fail. This covers a missing dependency, an unreadable
directory and an empty subject set alike. A false all-clear is worse than
silence.
