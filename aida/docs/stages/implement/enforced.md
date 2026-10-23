# What is enforced

Some rules on a dispatched role are applied by hooks while its dispatch is open. Others are only
written down for a later reader. This page says which is which.

## Applied by a hook

- **Reads.** The test author and the checker may not read production source. The implementer and
  the fixer may not read another order's source. The hook covers the Read and Grep tools and the
  plain shell reads: `cat`, `head`, `tail`, `less`, `more`, `sed`, `awk`, `grep`, `rg` and `nl`.
- **Runtime forms.** The test author is refused a shell command that names a form on AIDA's list
  of code-reading commands, such as `php:eval` or `ReflectionClass`. A runtime shows the code's
  shape as surely as its source.
- **Frozen tests.** Every dispatched role is refused a write to a frozen test or support file,
  except the test author of the order that froze it.
- **Owned files.** The implementer is refused a write in the code outside its order's files. The
  fixer is held to the order's files plus the paths you allowed for the round. A `mkdir` of a
  folder an owned file needs passes.
- **The main checkout.** Each role works in the task's worktree. While a dispatch is open, the
  hooks refuse it the denied reads and every write in the project's main checkout. That includes
  git run there and a copy in or out.
- **The stop lines.** An implementer's first return is blocked once when its answers file lacks
  the stop and deviation lines.
- **Destructive commands.** For every role and for the main session, a hook refuses any `git push`,
  a hard reset, `git clean`, `git branch -D`, a checkout or restore of the whole tree, a recursive
  delete of the home, working or scratchpad folder, `gh pr merge` and `gh repo sync`. A person
  pushes.

## The limits

A path a shell builds at run time passes the read hook. A test runner still loads a denied base
class, because a run command is not a read. In the worktree, git can still show the changes to a
denied file. A PHP file the test author writes and runs passes, and so does any runtime form not
on the list. The rule exists to stop a role opening the source because that is the obvious way to
write a test. A role that works around it on purpose has failed in a way no hook catches.

A write inside the order's files but outside a fix's scope is not refused. The reviewer finds it
when it reads the fix diff.

## Only recorded

- The paths a role may write, other than the implementer's and the fixer's owned files.
- The builder's five answers. Nothing checks that they came before the write, or that the diff
  stayed inside them.

## A value written as a path

You may see a value passed as `@/<path>`. AIDA writes some text, such as a reason that names a git
command, to a file first. Claude Code refuses a quoted git text in a command when the session works
in a worktree.

## Why it works this way

- A rule a model is asked to follow is weaker than a permission the runtime applies. So the rules
  that keep the tests apart from the code are hooks.
- AIDA says where each hook stops, so nobody reads a recorded rule as an applied one.

Source: skills/implement/SKILL.md, hooks/deny-prior-source.sh, hooks/deny-frozen-test-writes.sh,
hooks/require-stop-lines.sh, hooks/deny-destructive-commands.sh, scripts/introspection-forms.txt
