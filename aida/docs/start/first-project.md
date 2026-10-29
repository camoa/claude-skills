# Create your first project

Open Claude Code in your code folder and type `/aida:project create`. AIDA names the code path,
the name and the stack it found, asks only for what it cannot find, and writes the project.

## What you do

```text
/aida:project create
```

In a folder no project owns, the session start tells you so. Type `/aida:project` with no
argument and AIDA offers to make a project there. A plain yes runs the same steps. A no is
recorded, and AIDA does not offer again in that folder.

## What AIDA asks you

1. **The code path.** AIDA looks at the current folder. When it finds code, it uses that folder
   and names it. When it finds none, it asks where the code lives.
2. **The name.** The one you give, or the code folder's name made lower case. AIDA asks only when
   that name breaks the rule: lower case letters, digits and underscores, starting with a letter,
   such as `shop_site`.
3. **The stack.** AIDA detects `drupal`, `php-cli`, `node`, `go` and `python-cli` from the files
   in the code path. For any other stack, it asks you to name it. Use the name the catalog's
   recipes use, such as `claude-code-plugins` for a Claude plugin. A stack with no recipe still
   works: each stage says it found no recipe and goes on. Design first asks whether you want to
   write one, and review records that stack's checks as undeclared. See
   [sources](../sources/README.md).
4. **Where project folders go.** Asked once per machine. The default is
   `~/.claude/aida/projects`.
5. **Where task worktrees go.** Not asked. AIDA uses the folder that holds your code path, and
   names it.

## What happens

AIDA writes the project folder, makes it a git repository, registers the project, and runs the
project check. The check prints a report. A new project with no code yet gets a report that the
code path does not exist; that is normal.

Then AIDA makes two offers, once each:

- **The task rule.** A short block in your repository's own `CLAUDE.md`. It says that work goes
  through a task. Say yes or no. A no is recorded and not offered again.
- **A playbook source.** The rules every role that writes or judges code follows. AIDA offers
  the catalog sets for your stack, a folder of your own, or neither.

## What you get

A project folder that holds AIDA's own work on your code: its tasks and their records. Your code
stays where it is. From then on, a session opened in your code folder finds the project by
itself.

The project folder is not your code folder. AIDA refuses a code path at a system root, at your
home folder, or above it.

To switch projects, end one, or add your own sources, see [the project](../project/README.md).

Next: [run your first task](first-task.md).

## Why it works this way

- **The name is always asked.** Two code folders can share a folder name. A name you pick never
  collides that way.
- **The project lives outside your code.** AIDA's records do not land in your repository, and
  your repository does not decide where they go.

Source: skills/project/SKILL.md, scripts/detect-framework.sh
