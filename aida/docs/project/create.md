# Create a project

Type `/aida:project create`. AIDA asks for the code path, the name and the stack, asks where two
folders go, then writes the project and runs the check.

## What you do

Type `/aida:project create`, or `/aida:project create <path>` to name the code path. You can also
type `/aida:project` in a folder no project owns, and say yes when AIDA offers to create one.

## What AIDA asks

1. **The code path.** When the current directory looks like code, AIDA proposes it and names the
   file that proved the stack. When you gave a path, AIDA proposes that one. Confirm with yes.
   When AIDA has nothing to propose, it asks "Where does the code live?" The folder can be empty
   or not exist yet.
2. **The name.** AIDA always asks. A name starts with a lowercase letter, then holds only
   lowercase letters, digits and underscores. AIDA asks again when a name breaks this rule.
3. **The stack.** AIDA reads it from the files in the code path. Frameworks you name come first.
   When AIDA detects nothing, or the code path does not exist yet, it asks "What is the stack?"
4. **The projects folder.** Asked once on this machine, at the first project: "Where should
   project folders be stored?" The default is `~/.claude/aida/projects`. Later creates use that
   answer without asking. To change it, edit `~/.claude/aida/settings.json`.
5. **The worktree folder.** "Where should task worktrees go?" The default is the parent of the
   code path. [Set where task worktrees go](worktree-location.md) says what this controls.

## What happens

AIDA makes the project folder `<projects folder>/<name>`, writes `project.json` and
`project_state.md`, makes the folder a git repository with a first commit, and adds the registry
row. Then the check runs and you see its whole report. When the code path does not exist yet, the
report says "This folder does not exist." That result is normal for a new project.

Then AIDA makes two offers, once each:

- **The task rule.** A short block in your repository's `CLAUDE.md` that says work goes through a
  task. Yes installs it. No is recorded and not offered again. See [Install the task rule](task-rule.md).
- **A playbook source.** For each framework, AIDA lists the catalog playbook sets it found. You
  pick one, name a local folder, or decline. The [sources pages](../sources/) describe both.

## When it refuses

Create refuses, and writes nothing, when the name is already registered, when the code path is
already registered, when the project folder already exists on disk, or when the code path and the
project folder are the same place. A refused worktree folder is asked again.

When [the check](check.md) refuses the code path as unsafe, AIDA removes the folder and the
registry row it just wrote, then asks for another path. See [When it stops](../when-it-stops/).

## With nobody present

On a task that runs autonomous or light, AIDA halts when the code path, the name or the stack is
missing, because it cannot guess them. It uses the default projects folder. It asks no worktree
folder and records none, so the next create with a person present asks. It makes neither offer,
and says that both wait.

## Why it works this way

- The name is always asked. A name taken from the code folder collides as soon as two projects
  share a folder name.
- The project folder is never the code folder. AIDA's records keep their own history and never
  land in your repository.
- An offer nobody answered is not recorded. A recorded no is never asked again, so only a person
  may give one.

Source: skills/project/SKILL.md, skills/project/scripts/project-actions.sh, scripts/detect-framework.sh
