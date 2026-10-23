# Answer each reuse candidate

Every candidate research found gets one answer: reuse it, extend it, supersede it, or decline it.
Design records the answer, with its reason, in the reasoning of the order it lands on.

## How design decides

Design weighs how close the candidate is: same name, same directory, or same layer. Then it
weighs cost. Build cost is paid once. Carry cost, agent cost and risk cost are paid forever. A
candidate is not always code. An existing view or content type is a candidate too, and extending
it may produce no code at all. A candidate design finds itself gets an answer as well.

A decline records that the candidate was weighed and set aside. It cites no cost, because nothing
was compared.

## The fixed rules

A fixed table checks each answer:

- A supersede that cites only build cost comes back as extend.
- A supersede of a candidate that shares only a layer comes back as extend.
- A supersede that cites no cost at all: interactive, design asks you what it compared, and
  records nothing until you answer. Autonomous, it comes back as extend.
- Interactive: a supersede stands only after design asks you. A supersede widens the task and
  owes a migration.
- Autonomous: a supersede comes back as extend, with the reason in the order.

A reuse or an extend stands, whatever its distance and its cost.

Re-answering a candidate adds a paragraph to the reasoning. The last answer stands.

## What the builder gets

When the order's build or tests call the candidate, design records where it lives and what it
exposes. A read-only searcher reads the code and returns that text, and design records it word
for word. The test author may not read the code, so this text stands in for it.

## On an autonomous run

Once every answer on an order is recorded, a confirmer reads the written reasoning and the files
it cites, and nothing else. It agrees, disagrees or downgrades. Design adds its answer to the
order's reasoning.

The autonomous close refuses while an answer lacks the confirmer's agreement. What clears it is
in [The design check refuses to close](../../when-it-stops/design-check.md).

Interactive runs use no confirmer. You read the reasoning yourself.

## Why it works this way

- An unanswered candidate is how a project ends up with a second class beside the first.
- A rejection that lives only in the conversation cannot be checked later.
- The confirmer never sees the conversation, because a decision checked against its own
  narrative is not checked.

Source: skills/design/SKILL.md, skills/design/scripts/design-actions.sh,
agents/disposition-confirmer.md
