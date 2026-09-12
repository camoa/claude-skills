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

Dispatch `catalog-identifier` twice more, for the `test-execution` point and the `review` point,
each for this order's framework. These are two more recipes, neither the `implement` one above.
Pass both paths straight through to `build-record` below; do not open either here. The script
reads the `## Test commands` block of the first and the `## Check commands` block of the second
itself, the same two files preconditions already resolved for the baseline.

## Assemble what the implementer may see

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh build-brief "<task_folder>" <order id>
```

It reads the frozen copy and the frozen tests, and it emits six things: this order's own record
with the files it owns, the frozen tests for it with the criterion each carries, every order it
depends on with its declared interface, how many attempts this order has used of the count it is
allowed, and `headNow`, the code repository's own commit at the moment of this call. That count is
two unless a person has granted this order one more; see `references/finish.md`. It is the order's
own recorded allowance, never the constant alone.

**A dependency that has closed carries a second text beside the declared one, `interfaceRecord`:**
what its own builder actually wrote about what it exposes. When it exists, it is what this unit's
code is written against, not the declaration alone. Three files once said the record carries
forward and none of them did; `build-brief` is what actually forwards it now.

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
It refuses (exit 75) when the open record names a different task than this one: closing another
task's record would leave that task's own role holding every permission the record withheld.

## Record the attempt

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh build-record "<task_folder>" <order id> \
  --interface <path to the record the builder wrote> \
  --report <path to the builder's report> \
  --started-at <the commit the attempt began from> \
  --test-recipe <framework>=<path to the test-execution recipe> \
  --check-recipe <framework>=<path to the review recipe> \
  [--value <name>=<value>]... \
  [--nothing-ran <literal substring>]
```

The commit the attempt began from is `build-brief`'s own `headNow`, read before the implementer
starts, not after. Without it nothing can tell this order's changes from what was already there.
Equal to the code repository's own current commit, or not an ancestor of it, refuses (exit 71):
either makes the range this attempt claims false.

**`build-record` refuses when the code repository's tree is not clean.** The implementer commits
its own work before it returns. A dirty tree means that commit did not happen. This attempt is not
recorded. Interactive puts that to the person. Unattended halts the order with that reason.

`--test-recipe` and `--check-recipe` are paths only, one pair per framework, the same two files
`references/preconditions.md` already resolved for the baseline. The script parses `## Test
commands` and `## Check commands` itself: the suite command, the command that runs this order's
own frozen tests, and the three tool commands, each with its own argv, `{paths}` placeholder,
`signal` and `extensions` keys, and which rows a framework declares absent. Nothing here retypes a
command. A `{paths}` token expands to this order's own owned files, relative to codePath, and never
reaches a shell.

**Two frameworks may not both command one tool.** The same refusal preconditions.md names (exit
72) applies here: a project whose two frameworks each carry a coding-standards row, say, gives
nothing here two answers to choose between.

**The check recipe must be the one the baseline used.** A check recipe that resolves to a
different file than the baseline read refuses (exit 73), naming both: a tool's own result is
compared against the baseline it ran against, and a changed recipe makes that comparison false.

Pass `--value <name>=<value>` for a placeholder a command carries, the same as
`references/preconditions.md` does. Pass `--nothing-ran <literal substring>` only when the
framework's own recipe names no `silent_pass` marker of its own; where it does, the script reads
that marker and this flag is not read.

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

A failed check is not a failed order. It is this attempt's result, and the order has as many
attempts as its own allowed count says, two unless a person has granted more. Say which check
failed and what it printed, and let the person decide whether to spend the next one.

An unknown on interface-record does not spend the attempt. The declaration named no backticked
element, so nothing there was countable, and the disagreement goes to the reviewer instead. Every
other unmet or unknown does.

**order-tests is the floor.** Every other check may answer undeclared and still let the order go on
to `checks-passed`, the same rule step two applies to a precondition nobody declared. order-tests
may not. It is the one check that says this order's own code does what its tests ask. Undeclared or
unknown there means nothing here ran, so the order stays at `code-written`, whatever the other
seven answered.

The record carries `executed`, how many of the eight actually ran a command, a diff or a hash
rather than reading undeclared. Say that count to the person: eight checks answering does not by
itself say the code was tested.

The attempt counter lives in the ledger and is incremented here, and the order's state moves with
it: `checks-passed` when every check but order-tests answered met or undeclared (interface-record's
own unknown excepted) and order-tests itself answered met, `code-written` otherwise. When the
failing attempt was the last one allowed, the script writes the halt and its reason into the ledger
at that moment. It says so. Nothing here un-halts one. Go back to the skill body for what happens
to the run.
