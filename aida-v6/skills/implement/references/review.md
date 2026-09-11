# Review, fix and verify one work order

This step runs once an order reaches `checks-passed`. It reviews the code, repairs what a review
finds, and closes the order once nothing actionable is left open.

## Resolve the recipe for this step

Dispatch `catalog-identifier` to ask the navigator's process-recipe lookup for the `review` point
and this order's framework. Name the role: a dispatch that names none runs as the general agent
with every tool, and the role exists so a catalog listing lands in the agent and not here. When
this recipe carries a `check_commands` data block, it names the three tool commands,
coding-standards, static-analysis, security, as an argv per tool. Read each row's own `signal` and
`extensions` keys where present, from that same block.

When the recipe carries no such block, pass no tool flag for it below. The three checks then
record undeclared, and the report says the recipe declares no tool for that check. Never read a
tool's name out of the recipe's own prose.

## Review

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh review-brief "<task_folder>" <order id>
```
It refuses when the order is not at `checks-passed`, when the order is halted, or when a review
record already exists for it. **One order gets one review, ever.** Read a refusal and act on it.

It emits the criteria this order serves and owns, the non-goals, the order record, the diff as a
file, the frozen tests, the builder's report path, the eight check results, both interface texts,
and the path the reviewer's findings go to.

Check the interface-record result among the eight. Unknown means the declaration names nothing in
backticks, so the script could count nothing there. Interactive: before dispatching the reviewer,
put both texts, the declared interface and the builder's own record, to the person, and ask
whether they agree. If they say the two disagree, tell the reviewer where, when it is dispatched,
so its own finding can cite the criterion. Unattended: skip the ask. Give the reviewer both texts
and let it decide alone, and say in the report that nobody ruled on it.

A met verdict only means every backticked element is present verbatim. It does not rule out a
deeper disagreement between the two texts. Catching that is the reviewer's job, from both texts
already in the brief.

**Dispatch `reviewer`.** Name the role: an unnamed dispatch runs as the general agent and matches
no record. Set the model to opus. Give it the brief and nothing else, and tell it plainly that this
is review mode. The reviewer opens no dispatch record: its read is wide by design, one named file
outside the diff for one named risk. Its write is refused by the script, not by a hook, when the
code moved or the tree is dirty. Leaving a probe file behind is a refusal, not a finding.

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh review-record "<task_folder>" <order id> \
  --findings <path to the reviewer's findings file>
```
It refuses when a review record already exists for this order. It also refuses when the code path
moved, or its tree is dirty, since the build record. And it refuses when the findings file named
by `--findings` is missing, empty, or not the shape it reads. A finding citing neither a criterion
nor a non-goal, or an id the contract does not hold, is recorded but never reaches a fixer.

Unattended, a finding that hits a non-goal halts the order there, naming the non-goal. Interactive,
it is actionable like any other finding, and it goes to the person with the rest. No open
actionable finding: the order is reviewed and clean, so go to Close.

## Fix, one round at a time

Repeat this section while an actionable finding is open and a fix round remains.

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh fix-brief "<task_folder>" <order id>
```
It refuses when nothing is open, when the rounds are spent, or when the order is halted. It emits
the open findings in severity order, the union of their fix scope, the frozen tests, the report
path, and the round number.

Open the dispatch record before dispatching:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh dispatch-open "<task_folder>" fixer <order id> \
  --deny-read <path of the recipe that writes the tests>
```
The script derives the rest itself, the same way it does for the implementer: this order's owned
files allowed, every other order's denied. Deny the test-authoring recipe by hand, the same way
build.md does for the implementer: a fixer chooses no level and names no test, so that recipe is
not its to read.

**Dispatch `fixer`.** Name the role. Round one runs on sonnet. Round two runs on opus, set on the
Agent call. Give it the open findings, the fix scope union, the frozen tests, and its report path.
**It may not change a test**: a hook refuses the write. **It may not write outside the fix
scope.** No hook enforces that bound. The owned-files check after the round only bounds it to the
order's own files, which is wider than the scope. A write inside those files but outside the scope
is not caught there. It surfaces when the reviewer's verify mode reads the fix diff and reports it
under `outOfScope`.

Close the dispatch record as soon as it returns, whether it succeeded or not:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh dispatch-close "<task_folder>"
```

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh fix-record "<task_folder>" <order id> \
  --report <path to the fixer's report> \
  --started-at <the commit the round began from> \
  --suite <argv token>... \
  --order-tests <argv token>... \
  --standards <argv token>... \
  --static-analysis <argv token>... \
  --security <argv token>... \
  [--standards-signal empty-stdout] [--standards-extensions <comma list>] \
  [--static-analysis-signal empty-stdout] [--static-analysis-extensions <comma list>] \
  [--security-signal empty-stdout] [--security-extensions <comma list>] \
  [--standards-absent <reason>] [--static-analysis-absent <reason>] [--security-absent <reason>] \
  [--scope-insufficient <finding id>=<reason>]...
```
The `signal` and `extensions` flags are the same keys from the `review` recipe's `check_commands`
block, passed the same way build-record does. Pass `--standards-absent <reason>` (and the same for
the other two) when the recipe's row is declared absent, with the recipe's own reason text.
`--scope-insufficient` is repeatable, one per finding the fixer's report names as needing more
scope than it had. Interactive puts each one to the person. Unattended halts the order, naming the
finding.

**`fix-record` refuses when the code repository's tree is not clean.** The fixer commits its own
work before it returns. A dirty tree means that commit did not happen. This round is not recorded.
Interactive puts that to the person. Unattended halts the order with that reason.

This re-runs seven of the eight checks. Not interface-record: a fix round does not rewrite that
record. A check answering unmet or unknown spends the round and leaves every finding open. At the
round cap, the script halts the order itself, naming the check that stopped it. `review-brief` is
never run again for this order.

**When `fix-record` halted the order this way, stop here.** Do not dispatch the reviewer in verify
mode: `verify-record` refuses on a halted order. Report the halt instead, naming the check it
stopped on, the same way a halt at the build step is reported.

**Dispatch `reviewer` again, in verify mode.** Give it the open findings the fixer received, the
fix diff as a file, and the fixer's report. Choose the path its verdicts go to yourself, the same
way review-brief names its findings path, for example `<impl>/verify-<order id>-<round>.json`.
Nothing else: not the original diff, not an earlier round's verdicts.

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh verify-record "<task_folder>" <order id> \
  --verdicts <path to the reviewer's verdict file>
```
Addressed closes a finding. Not addressed keeps it open; attempted is not addressed. New breakage
inside the fix diff opens as a finding under the same rule. Anything the reviewer notices outside
the fix diff is recorded and opens nothing.

## Rulings, at the cap only

Once the rounds are spent, `verify-record` above refuses when a finding is still open and no
ruling names it: nothing is written yet, so this is a retry of that same call, not a new one. Each
open finding needs a ruling, `wrong`, `deferred`, or `load-bearing`, with a reason. Put the open
findings to the person and ask. Unattended, `verify-record` already halted the order instead.

Run the same call again, with one `--ruling` flag added per open finding:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh verify-record "<task_folder>" <order id> \
  --verdicts <path to the reviewer's verdict file> \
  --ruling <finding id>=<wrong|deferred|load-bearing>::<reason> \
  --ruling <finding id>=<wrong|deferred|load-bearing>::<reason>
```
`wrong` and `deferred` let the order close with the finding recorded. `load-bearing` halts the
order, the finding named as the reason. Interactive, this reaches the person as an escalation, not
a question with an obvious answer. A ruling missing for an open finding at the cap refuses.

## Close

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh close "<task_folder>" <order id>
```
It refuses when an actionable finding is still open, or when the last fix round was never
verified. It also refuses when the code repository's tree is not clean, or when HEAD is not where
the last record left it. On success it writes `lastStep = "closed"` and the commit range the order
produced.

**Close also decides the criteria this order serves or owns.** A machine-verified criterion reads
confirmed once every order serving it is closed and every judgement on it reads confirmed.
Otherwise it stays not-judged. A rejected judgement cannot reach here, since `tests-freeze` already
refused it, but the state is still derived from the judgements every time, never assumed. A
person-verified criterion stays at not-judged too: it carries a checklist instead of a judgement,
and completion is what confirms it.

It prints `{order, criteria, rowsJudgedByModel}`: the closed order's own ledger entry and each
affected criterion's row state and judge. It also reports how many rows across the whole ledger a
model judged rather than a person. Read that count to the person before moving on, so they can find
and re-judge exactly those rows.

Say plainly that the order is done, and move to whichever order is next ready.
