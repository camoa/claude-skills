# Dispatch the reviewer, then record the findings

This step runs once the checks are recorded. One dispatch answers six checks and the mutation
survivors. One call records what came back.

## Assemble the brief

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/review/scripts/review-actions.sh brief "<task_folder>"
```
It refuses at exit 62 when `checks` recorded nothing, because five of the seven lenses read its
results.

It writes the brief to `review/brief.json`. The brief holds the criteria and the non-goals from the
frozen contract, every work order, the path to `review/diff.patch`, the research records and the
paths they cite, the results of checks 4 to 8 with every tool row and every mutation survivor, and
the findings implementation ruled deferred.

The call prints three things: the brief's own path, the path the findings go to at
`review/findings.json`, and the counts. Read neither file into this conversation, per SKILL.md.

## Dispatch the architecture reviewer

**Dispatch `architecture-reviewer`.** Name the role, per SKILL.md. Set the model to opus on the
Agent call: a critic runs at the top model whatever it judges. Give it the brief's **path**, and tell
it to read that file first. Give it the findings path as well. **The prompt carries no brief
content.** The role opens every body itself, and pasting one here spends this conversation's context
on what the file already holds.

**One dispatch carries all seven lenses.** Seven dispatches would read the same diff at seven times
the cost, and a finding does not change because a different context raised it. The lens words are
fixed, and a check reads its verdict off the lens that raised the finding:

| Lens | The check it answers |
|---|---|
| `non-goals` | check 2, the task did what it said it would not do |
| `solid` | check 9, a principle finding with file, lines and rule |
| `dry` | check 10, duplication, including against untouched code |
| `architecture` | check 11, the code does not match the orders design wrote |
| `guides` | check 12, a guide research cited was not followed |
| `practices` | check 16, an accepted framework practice was not applied |
| `mutation` | a survivor inside code a criterion covers |

No dispatch record is opened, and none can be: `dispatch-open` requires a work order id, and a task
level review has no order. SKILL.md says what follows from that. The role holds Read, Glob, Grep and
Write, and no Bash, so it runs nothing.

**Its read is wider than the per order reviewer's, deliberately.** Duplication against untouched code
and coupling across orders cannot be seen inside a diff, so it holds Glob and Grep over the code
path. Do not narrow that by hand.

**Check 16 asks the catalog for nothing.** An agentic recipe is searched for by capability, and that
search resolves no body, so there is no path to ask for. A recipe research never found was never a
practice this project accepted. The reviewer opens the paths the research records already hold.

## Record the findings

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/review/scripts/review-actions.sh findings "<task_folder>" \
  --findings <path to the reviewer's findings file>
```
It refuses at exit 51 when the code path moved, or its tree went dirty, since `checks` ran. A file
the role left behind is caught there, rather than read as a finding.

It records checks 2, 9 to 12 and 16, and every finding, and it prints one summary line per check with
the counts. Each of those checks reads met when its lens returned nothing, unmet when that lens
returned a finding, and unknown when the findings file is absent or unreadable. **An absent verdict is
never a clean one**, and version 5 paid for that four times.

## Classify every finding

- **A finding citing a criterion** is this task's work. That criterion reads unmet, and the task is
  not done.
- **A finding citing a non-goal** is this task's work the other way. The task did what it said it
  would not do.
- **A finding citing neither** is recorded with `disposition: follow-up`, and named in the report,
  whatever the run mode. Interactive, offer to run the task skill once per finding, so a person
  creates it. No producer exists that creates a task without interviewing a person, which is why this
  step records rather than creates. Folding a finding in silently is what scope exists to prevent.
- **Severity overrides the third case only.** A high severity security fault is raised at once, to the
  person, because leaving it queued ships it. The severity words are high, medium and low.

**The builders' reports are refused as authority.** They are unverified claims, and a reason in one
never lowers a finding's severity. The earlier stages' conversations go with them.

**The per order findings are refused as settled.** A finding implementation ruled deferred at its fix
round cap is not closed. `finished.json` carries each with its reason and the id it linked to, so the
first two cases above apply to it, and this step classifies it again. A deferral is a person saying
not now, never a person saying this is fine.

Report the findings by lens, with a count and the id each one cites, and name the findings file's own
path for the person to open. Name every finding carrying `disposition: follow-up` as work nobody has a
task for yet. Do not read the evidence bodies into this conversation, per SKILL.md.
