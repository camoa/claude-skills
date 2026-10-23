# Run the design check

The design check compares every work order with the scope contract. It counts and matches ids,
and reads no sentence. Design is done only when this check comes back clean.

The check runs before the critique and again inside the close. Its report is
`records/design-check.json` in the task folder.

## What holds the close

The check holds the close on anything the build would rest on: a criterion with no owner or two,
an order that serves nothing, a proof kind that does not fit what the order declares, two orders
that own one file, an id that names nothing. Each open item names the order it is on. Every
refusal, and what clears it, is in
[The design check refuses to close](../../when-it-stops/design-check.md).

No open item can be left with a reason. The build refuses to start on any of them, so leaving one
open only moves the stop to a later and more costly place.

Two names in an interface joined by `or` also hold the close. Design writes a real choice as
plain text, or keeps the pair when both names must exist. A kept pair whose text changes is open
again.

## Lines that inform and never hold the close

- `impliedProofDisagrees:` a `tests` order that owns no machine-verified criterion. Design changes
  the proof or the owned criteria.
- `absenceJoined:` a done-when row that may join an absence to a behaviour. Design splits it into
  one row per clause, or marks it reviewed. A reviewed row is named again when its text changes.
- `interfaceUnquoted:` an interface with no name in backticks.
- `interfaceUnowned:` a path in an interface that the order does not own, does not reuse, and no
  order it depends on owns. Design writes it as plain text, or records the reuse.
- `interfaceShaped:` a name in backticks that holds `<` or `{`, which is often a shape and not a
  name.
- `callsUndeclared:` a call in a done-when row or a test that no interface declares. The test
  author cannot read the code to learn its signature.
- `unrecordedIds:` a work order number below the highest with no order and no removal on record,
  often an order merged long ago. Design records which order took its work, and why.
- `verifyNotBinding:` an order with a verify line that is not binding. See
  [Where an order's verify lines come from](verify.md).

Each of these is best effort, because a script cannot read prose.

## Why it works this way

- A script that compares a criterion's words to a test's words matches a phrase, and a phrase
  match proves only a phrase. So the check counts ids, and people and critics read the prose.
- An item left open here stops the build later, where it costs more.

Source: skills/design/SKILL.md, skills/design/scripts/design-actions.sh, scripts/check-design.sh
