# Dispatch the reviewer, then record the findings

This step runs once the checks are recorded. One dispatch answers six checks and the mutation
survivors. One call records what came back.

## Assemble the brief

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/review/scripts/review-actions.sh brief "<task_folder>"
```
It refuses at exit 62 when `checks` recorded nothing, because five of the eight lenses read its
results.

It writes the brief to `review/brief.json`. The brief holds the criteria and the non-goals from the
frozen contract, and every work order. It holds the path to `review/diff.patch`. It holds the
research records and the paths they cite. It holds the results of checks 4 to 8, with every tool
row and every mutation survivor. It holds the findings implementation ruled deferred. It holds
`playbooksPath`: the path of `records/playbooks.json` when research loaded one, else null. It holds
`absenceClauses`: every done-when clause the tests step routed here, read from the ledger.

The call prints three things: the brief's own path, the path the findings go to at
`review/findings.json`, and the counts. Read neither file into this conversation, per SKILL.md.

## Dispatch the architecture reviewer

**Dispatch `architecture-reviewer`**, on opus, with the message SKILL.md names: the role, the run
mode, the brief's path, and the findings path. A critic runs at the top model whatever it judges.
**The prompt carries no brief content.** The role opens every body itself, and pasting one here
spends this conversation's context on what the file already holds.

**One dispatch carries all eight lenses.** Eight dispatches would read the same diff at eight times
the cost, and a finding does not change because a different context raised it. The lens words are
fixed, and a check reads its verdict off the lens that raised the finding:

| Lens | The check it answers |
|---|---|
| `non-goals` | check 2, the task did what it said it would not do |
| `solid` | check 9, a principle finding with file, lines and rule |
| `dry` | check 10, duplication, including against untouched code |
| `architecture` | check 11, the code does not match the orders design wrote, or business logic sits in the UI layer |
| `guides` | check 12, a guide research cited was not followed |
| `practices` | check 16, an accepted framework practice was not applied, or a play in `records/playbooks.json` was contradicted |
| `mutation` | a survivor inside code a criterion covers |
| `purpose` | check 3, a hunk that serves nothing, or fails one of the four purposefulness questions |

Check 3 reads met only when the script half found no unowned file and the `purpose` lens returned
nothing. A `purpose` finding turns the script half's row unmet and keeps the file and lines.

No dispatch record is opened, and none can be: `dispatch-open` requires a work order id, and a task
level review has no order. SKILL.md says what follows from that. The role holds Read, Glob, Grep and
Write, and no Bash, so it runs nothing.

**Its read is wider than the per order reviewer's, deliberately.** Duplication against untouched code
and coupling across orders cannot be seen inside a diff, so it holds Glob and Grep over the code
path. Do not narrow that by hand.

**The routed done-when clauses come back as one verdict each.** A clause that asserts an absence
says the change added nothing of a named kind. No test of it could be watched failing, so the tests
step routed it here instead (live-run row 184). The reviewer judges each one against the diff. It
writes `absenceVerdicts` in its findings file, beside the findings and the catalog notes. The three
words are met, unmet and unknown. `findings` records one row per clause, and one `absence-clauses`
check over them all. That check reads unmet when one clause reads unmet, unknown when one reads
unknown, and met when every one reads met. It reads not-needed when no order routed a clause. The
verdict rules then apply as they do to every other check, so a clause nobody could judge fails the
review. Do not judge a clause yourself and do not send one back: the reviewer reads the diff, and
this conversation does not.

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

It records checks 2, 9 to 12 and 16, and every finding. It lowers checks 3 and 4 where their lens
raised a finding. It records one row per routed done-when clause, and one more check for them all.
It prints one summary line per check with the counts.
Each of those checks reads met when its lens returned nothing, unmet when that lens
returned a finding, and unknown when the findings file is absent or unreadable. **An absent verdict is
never a clean one**, and version 5 paid for that four times. Check 16 has a floor before its lens,
described in `references/checks.md`: a playbook record that was never loaded reads unknown.

Checks 12 and 16 have one more floor, and it is the research records. Both read them and nothing
else. A task whose research records cite no source leaves both undeclared, because neither lens
had a guide or an accepted practice to judge against. A task with no research record at all leaves
both unknown, because nobody looked. Met means a judgement happened.

## Classify every finding

- **A finding citing a criterion** is this task's work. That criterion reads unmet, and the task is
  not done.
- **A finding citing a non-goal** is this task's work the other way. The task did what it said it
  would not do.
- **A finding citing neither** is recorded with `disposition: follow-up`, and named in the report,
  whatever the run mode. Interactive, offer one task per finding, and for each yes run:
  ```
  "${CLAUDE_PLUGIN_ROOT}"/skills/completion/scripts/completion-actions.sh follow-ups "<task_folder>" \
    --create <finding id>
  ```
  That script owns the task id, `<source task>-<finding id>`, and writes the goal from the evidence.
  Completion later finds the task by its folder, so no field is added. Autonomous, nothing is
  created here. Folding a finding in silently is what scope exists to prevent.
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
