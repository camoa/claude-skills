# Saved notes become plays

Each decision you saved mid-stage with `/aida:task save` is a note in the task folder. Before the
close, completion offers each note as a play for the project's playbook.

## What completion asks

It lists the notes, one line each with the date and the first line of text. You say yes or no per
note. With no notes, it asks nothing.

For each yes, it drafts five fields from the note: the domain, the title, what the play says, the
reason, and when it applies. You correct the draft. Then completion appends the play to the
project's `playbook.md` and commits it. A title that is already a play is refused; give another.

The record counts every note offered, whatever you answered. For where plays go and who reads
them, see [sources](../../sources/README.md).

## Why it works this way

- A decision saved mid-stage is a candidate. A person names the play, so the playbook holds only
  what a person chose.

Source: skills/completion/references/close.md, skills/playbooks/scripts/playbook-actions.sh
