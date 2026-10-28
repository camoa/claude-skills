# After the merge

You push and merge the pull request yourself. AIDA never pushes and never merges. After the merge,
prune the task's worktree.

## Pushing

A hook asks you before the session runs `git push`. Claude Code shows its permission prompt, and
the command runs only when you approve it.

## What else the hook asks about

The same hook asks before other commands that throw work away or publish it:

- a hard reset, `git clean`, a forced branch delete, and a checkout or restore of the whole tree;
- a recursive delete of root, your home folder, the working folder, or a folder above them;
- a recursive delete of the session's scratchpad folder, a folder above it, or a glob directly
  under it;
- `gh repo sync`, `gh pr merge`, and a `gh api` call that changes a branch.

Where Claude Code cannot show a prompt, the hook refuses the command: in bypassPermissions mode,
in dontAsk mode, and in a headless run. A role AIDA dispatched is refused too, and it stops and
reports the command to you.

The hook refuses a write to AIDA's own hooks, and a Write or Edit that puts `disableAllHooks` in a
`.claude` settings file. It does not ask about those.

The hook is best effort, not a boundary. It reads text, so a command from a variable, a script
file, an alias, an encoded string, or another language that runs git gets past it. A settings file
written through Bash gets past it too. `AIDA_ALLOW_DANGEROUS=1` in the shell that launched the
session turns it off, which is how an unattended run pushes. The hook's own header lists every
form it reads and every form it cannot.

## Prune the worktree

Run `/aida:task prune` from the main checkout, never from inside a tree it may remove. It lists the
trees and asks once which go. It refuses a tree whose site was adopted, and names the tear-down
route. It keeps a tree another task builds in. See [the task pages](../../task/README.md).

## A task that will not be merged

Close the task anyway. A task that stays open sits in `/aida:next` forever. Say why the work ended
in the reason, or in the summary when review passed. The pull request body stays in the folder as
the account of what was done. Then prune: prune keeps an unmerged branch and names it, and AIDA
never deletes one.

## Why it works this way

- Publishing is a person's act. A model that cannot push cannot ship work nobody approved.
- Each tree and site costs disk and a running project, so prune removes them once the work is in.

Source: hooks/deny-destructive-commands.sh, skills/task/scripts/task-actions.sh, skills/completion/SKILL.md
