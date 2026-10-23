# Install the task rule

Type `/aida:project task-rule <project>` to add a short block to your repository's `CLAUDE.md`. The
block says that work which produces findings or decisions goes through a task, and that a small fix
does not need one.

## What you do

AIDA offers the task rule once, at [create](create.md). You can also type
`/aida:project task-rule <project>` at any time. AIDA shows what will change, a new block or a
refreshed one, and asks for a plain yes or no.

On yes, AIDA writes the block into `<code path>/CLAUDE.md`, between two marker lines. A file that
already holds the block keeps one copy, refreshed in place. A version 5 block in the same file is
removed, so the file never holds two task rules.

## Decline or remove it

- `/aida:project task-rule <project> --decline` records your no. AIDA does not offer the rule again.
  It refuses when the block is already installed; use `--remove` for that.
- `/aida:project task-rule <project> --remove` takes every task-rule block back out and leaves the
  rest of the file as it was.

## The version 5 block

When your `CLAUDE.md` holds the block version 5 wrote, the check says so on every run. That block
names `/ai-dev-assistant:` commands that no longer exist. AIDA offers to rewrite it once in each
call. Yes replaces it with the current block. No records the decline, and the check then states the
fact without the offer.

## When it refuses

- The project has no code path, or the code path does not exist yet. There is no repository to
  write into.
- A line in `CLAUDE.md` opens a block that no end marker closes. The text below may be yours, so
  AIDA neither rewrites nor removes it. Fix the line the report names by hand.
- With nobody present, AIDA refuses to install, decline or remove the rule, and writes nothing.

See [When it stops](../when-it-stops/).

## Why it works this way

- A `CLAUDE.md` is an instruction the model must follow, in a repository you own. Only you can ask
  for one.
- A recorded no is never asked again, so nobody's silence counts as an answer.

Source: skills/project/SKILL.md, skills/project/scripts/project-actions.sh
