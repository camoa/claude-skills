# Write the code for one work order

This step runs once per work order, after that order's tests are frozen. The tests are the
reference now. Nothing below may change one.

## Resolve the recipe for this step

Dispatch `catalog-identifier` to ask the navigator's process-recipe lookup for the `implement`
point and each framework the project declares. Name the role: a dispatch that names none runs as
the general agent with every tool, and the role exists so a catalog listing lands in the agent and
not here. Three answers, not one: no recipe for this framework, a listing that could not be
reached, and a failed network are different things.

This recipe carries the rules applied while code is written. The implementer opens it itself, from
the path. Do not read the body here.

Do not give the test-authoring recipe to the implementer. It chooses a level and names a test, and
this reader may do neither. Pass its path to `dispatch-open` as `--deny-read`.

Dispatch `catalog-identifier` a second time, for the `review` point and this order's framework.
When that recipe carries a `check_commands` data block, it names three tool commands,
coding-standards, static-analysis and security. Each is an argv per tool, with `{paths}` as a
placeholder. Each row also carries its own `signal` and `extensions` keys, where present.
These are what `build-record` runs below, the same commands the baseline already ran against.

When the recipe carries no such block, pass no tool flag for it. The three checks then record
undeclared, and the report says the recipe declares no tool for that check. Never read a tool's
name out of the recipe's own prose.

## Assemble what the implementer may see

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh build-brief "<task_folder>" <order id>
```

It reads the frozen copy and the frozen tests, and it emits five things: this order's own record
with the files it owns, the frozen tests for it with the criterion each carries, the declared
interface of every order it depends on, and how many attempts this order has used of the two it is
allowed.

It refuses when the tests for this order were never frozen, when an order this one depends on has
no completion record, and when the attempts are already spent. Read a refusal and act on it.

That list is the withheld list. Pass what it emits and nothing else.

## Open the dispatch record, then dispatch the implementer

Open it first:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh dispatch-open "<task_folder>" implementer <order id> \
  --deny-read <path of the recipe that writes the tests>
```
The script derives the rest itself from the frozen snapshot: this role is denied every other
order's owned files, and allowed its own. Never type those paths here. It prints both lists, and
an order that declares nothing it owns refuses rather than opening a dispatch with nowhere to
write.

**Then dispatch `implementer`.** Name the role. A dispatch that names none runs as the general
agent with this session's own model, and the record just opened matches nothing: the hook compares
the agent's own type against the role in the record, so an unnamed dispatch is an unenforced one.

Give it the path to the `implement` recipe for its framework, what `build-brief` emitted, and
nothing else.

**It writes code only inside the files its order owns.** Not another order's, whatever it finds
there.

**It may not change a test.** A test that seems wrong is a reason to stop, not to edit. A hook
refuses the write and names which order froze the file.

**It may not read another order's source.** What another unit exposes is its interface record. A
hook refuses the read while the dispatch is open.

**It stops rather than working around anything.** A test that seems wrong, an interface that does
not fit, or the attempts running out are all stops. Interactive puts the stop to the person.
Unattended halts the order and records what was left.

Ask it to return what it changed, one line on the tests, the path to the interface record it wrote,
and any concern. Under fifteen lines. The interface record is prose about what this unit exposes,
and it is what the next order's tests are written against.

Close the record as soon as the role returns, whether it succeeded or not:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh dispatch-close "<task_folder>"
```

## Record the attempt

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh build-record "<task_folder>" <order id> \
  --interface <path to the record the builder wrote> \
  --report <path to the builder's report> \
  --started-at <the commit the attempt began from> \
  --suite <argv token>... \
  --order-tests <argv token>... \
  --standards <argv token>... \
  --static-analysis <argv token>... \
  --security <argv token>... \
  [--standards-signal empty-stdout] [--standards-extensions <comma list>] \
  [--static-analysis-signal empty-stdout] [--static-analysis-extensions <comma list>] \
  [--security-signal empty-stdout] [--security-extensions <comma list>] \
  [--standards-absent <reason>] [--static-analysis-absent <reason>] [--security-absent <reason>]
```

The commit the attempt began from is read before the implementer starts, not after. Without it
nothing can tell this order's changes from what was already there.

**`build-record` refuses when the code repository's tree is not clean.** The implementer commits
its own work before it returns. A dirty tree means that commit did not happen. This attempt is not
recorded. Interactive puts that to the person. Unattended halts the order with that reason.

`--suite` and `--order-tests` are the commands from the framework's `implement` recipe, one argv
token per flag. `--standards`, `--static-analysis` and `--security` are the three tool commands
from the `review` recipe, resolved above, one argv token per flag. A token that is exactly
`{paths}` is a placeholder. The script expands it itself, to this order's own owned files, one
argv token per file, relative to codePath. Never expand it here, and never hand any of the five to
a shell.

Each tool takes two more flags, straight from the same `check_commands` row in the `review`
recipe, its own `signal` and `extensions` keys. Pass `--standards-signal empty-stdout` (and the
same for the other two) only when the recipe's row names that signal. It marks a tool that exits 0
whether it found something or not, `gofmt -l` among them. A clean run and a dirty one are then told
apart by whether anything landed on standard output, not by the exit code.

Pass `--standards-extensions <comma list>` (and the same for the other two) when the row names one.
`{paths}` then expands to only this order's owned files carrying one of those extensions. An order
with none of them records that tool's row as undeclared, with the reason, rather than met.

Pass `--standards-absent <reason>` (and the same for the other two) when the recipe's row is
declared absent, with the recipe's own reason text.

## Read the eight checks to the person

This step runs all eight deciding checks. The record holds every one.

- **order-tests.** Do this order's own frozen tests pass.
- **suite-regression.** Does anything that passed at the baseline now fail.
- **coding-standards.** Does the coding-standards tool raise anything the baseline did not already
  have.
- **static-analysis.** Does static analysis raise anything the baseline did not already have.
- **security.** Does the security tool raise anything the baseline did not already have.
- **owned-files.** Did the change stay inside the files this order owns.
- **frozen-tests.** Does every frozen test file still hash to what the freeze recorded.
- **interface-record.** Does the interface record name every element the order's own declared
  interface names in backticks.

A failed check is not a failed order. It is this attempt's result, and the order has two attempts.
Say which check failed and what it printed, and let the person decide whether to spend the second.

An unknown on interface-record does not spend the attempt. The declaration named no backticked
element, so nothing there was countable, and the disagreement goes to the reviewer instead. Every
other unmet or unknown does.

The attempt counter lives in the ledger and is incremented here, and the order's state moves with
it: `checks-passed` when no check answered unmet or unknown (interface-record's own unknown
excepted), `code-written` otherwise. An undeclared check continues, the same rule step two
applies. When the failing attempt was the last one allowed, the script writes the halt and its
reason into the ledger at that moment. It says so. Nothing here un-halts one. Go back to the skill
body for what happens to the run.
