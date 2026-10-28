# After the merge

You push and merge the pull request yourself. AIDA never pushes and never merges. After the merge,
prune the task's worktree.

## Pushing

A hook refuses `git push` in the session. To let the session push on your machine, create one
file that only `sudo` can create:

```
sudo mkdir -p /etc/claude && sudo touch /etc/claude/allow-push
```

While the file exists, the session pushes. `sudo rm /etc/claude/allow-push` closes the gate. A
force push stays refused, and so do a mirror push and a delete of a remote branch.

## What else the hook refuses

The same hook refuses commands that throw work away or publish it:

- a hard reset, `git clean`, a forced branch delete, and a checkout or restore of the whole tree;
- a recursive delete of root, your home folder, the working folder, or a folder above them;
- a recursive delete of the session's scratchpad folder, a folder above it, or a glob directly
  under it;
- `gh repo sync`, `gh pr merge`, and a `gh api` call that changes a branch;
- a write to AIDA's own hooks, and a Write or Edit that puts `disableAllHooks` in a `.claude`
  settings file.

The hook is best effort, not a boundary. It reads text, so a command built at run time, an encoded
string, or another language that runs git gets past it. A settings file written through Bash gets
past it too. `AIDA_ALLOW_DANGEROUS=1` in the shell that launched the session turns it off. The
hook's own header lists every form it catches and every form it cannot.

## Prune the worktree

Run `/aida:task prune` from the main checkout, never from inside a tree it may remove. It lists the
trees and asks once which go. It refuses a tree whose site was adopted, and names the tear-down
route. It keeps a tree another task builds in. See [the task pages](../../task/README.md).

## A task that will not be merged

Close the task anyway. A task that stays open sits in `/aida:next` forever. Say why the work ended
in the reason, or in the summary when review passed. The pull request body stays in the folder as
the account of what was done. Then prune: prune keeps an unmerged branch that holds a commit of its
own, and AIDA never deletes one.

## Why it works this way

- Publishing is a person's act. A model that cannot push cannot ship work nobody approved.
- Each tree and site costs disk and a running project, so prune removes them once the work is in.

Source: hooks/deny-destructive-commands.sh, skills/task/scripts/task-actions.sh, skills/completion/SKILL.md
