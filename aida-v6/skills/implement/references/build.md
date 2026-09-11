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
  --order-tests <argv token>...
```

The commit the attempt began from is read before the implementer starts, not after. Without it
nothing can tell this order's changes from what was already there.

`--suite` and `--order-tests` are the commands from the framework's recipe, one argv token per
flag. The script runs them inside the code repository and never hands either to a shell.

## Read the four checks to the person

This step runs four of the eight deciding checks, and the record says so in its own words. Never
report the four as all of them.

- **order-tests.** Do this order's own frozen tests pass.
- **suite-regression.** Does anything that passed at the baseline now fail.
- **owned-files.** Did the change stay inside the files this order owns.
- **frozen-tests.** Does every frozen test file still hash to what the freeze recorded.

A failed check is not a failed order. It is this attempt's result, and the order has two attempts.
Say which check failed and what it printed, and let the person decide whether to spend the second.

The attempt counter lives in the ledger and is incremented here. An order out of attempts is
halted, and nothing here un-halts one.
