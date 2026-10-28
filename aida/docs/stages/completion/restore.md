# The restore commit

Completion makes one commit in the task's worktree. It puts back the files that
`task environment up` changed for the worktree's own site, so the merge does not carry them.

## What it does

`task environment up` changes some files so the worktree runs its own site, such as a site name in
a framework's configuration. Merged, those changes would rename or change the main checkout's
site. So, at the close, completion:

1. takes the worktree's site down, while the site still has the worktree's name;
2. puts each of those files back to its content where the branch started, or removes it when it
   did not exist there;
3. commits that, in one commit.

A task with no such files gets no commit, and its site still goes down at the close. A file you already put back needs
nothing, whatever your commit says. When every file is already back, completion makes no commit.
The pull request body names each restore commit, yours and its own, so a reviewer sees why those
files are not in the diff.

When completion cannot put a file back safely, it puts nothing back and writes a warning that
names the repair. See [completion refuses](../../when-it-stops/completion-refused.md).

## Put the files back after review, not before

Let completion make this commit, after review. A restore commit that puts back a file the branch
started with makes review refuse, because the site commands its checks run could then reach the
main checkout's site. Review tells you to revert that commit, review, and put the files back
afterwards. Only a commit that removes files `up` added may come before review.

## Why it works this way

- Trunk must keep its own site settings. The worktree's settings serve one worktree only.
- The site goes down first, because after the commit its name would point at the main checkout's
  site.

Source: skills/completion/SKILL.md, skills/completion/references/close.md, skills/completion/scripts/completion-actions.sh, skills/review/scripts/review-actions.sh
