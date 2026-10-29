# Change the code path or the stack

Use `/aida:project set-code-path` when your code moved, and `/aida:project set-frameworks` when
AIDA named the wrong stack or none.

## Move the code path

Type `/aida:project set-code-path <project> <new path>`. `<project>` is the project's name or its
current code path.

Without a new path, AIDA uses the current directory when it looks like code, and names it.
Otherwise it asks "Where does the code live now?"

AIDA writes the new path into the project file and the registry row, commits the change, and runs
the check. The same path as before prints `UNCHANGED` and changes nothing.

Two things refuse a new path. A path that another project already holds, as its code path or its
project folder, is refused, and nothing changes. A path that [the check](check.md) refuses as unsafe
is undone: AIDA puts the old path back in both places before it reports the refusal. Give another
path.

## Set the stack by hand

Type `/aida:project set-frameworks <project> <framework> [<framework>...]`. AIDA writes the list
into the project file, commits the change, and runs the check.

Use it when the check says `frameworks` is missing, or when detection named the wrong stack. A
project with no stack is not ready for work.

## With nobody present

Both actions do the same thing in both run modes. One step differs. On a task that runs autonomous
or light, `set-code-path` with no path given accepts the current directory without asking, when it
looks like code. When AIDA can propose nothing, it halts, because nobody can say where the code went.

## Why it works this way

- Only the project's owner knows where moved code went. AIDA uses what it can detect and names it,
  and asks when it can detect nothing.
- A refused path is undone at once, so the project never points at a location AIDA would not
  work in.

Source: skills/project/SKILL.md, skills/project/scripts/project-actions.sh
