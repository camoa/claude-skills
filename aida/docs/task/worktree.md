# The task worktree and its site

Every task builds in its own git worktree, on the branch `feature/<name>`. Every stage action of
the task runs inside that tree and refuses from anywhere else.

## Where it is

The tree sits in a folder named `<code folder>.worktrees`, beside the code checkout unless the
project records another worktree base. The tree itself is `<code folder>-<name>`. The tree is
outside the code checkout because a tool that registers projects by folder cannot see a tree
nested inside one.

## Getting in

There are three routes. A refusal names the one that works where the call ran.

- **AIDA moves the session in.** After `create` or `/aida:next`, AIDA asks to enter the tree.
  Approve the prompt. This works only from a session inside the code checkout.
- **You type `/cd <path>`.** It moves this session into the tree and keeps the conversation. It
  needs Claude Code 2.1.169 or later. Or start `claude` from inside the tree.
- **A prefix on every command.** AIDA starts each command with `cd <path> &&`. This works from
  anywhere. Use it when you decline the prompt or when entry refuses.

A stage called from outside the tree refuses with the path and the route to take. See
[when it stops](../when-it-stops/).

## A tree that is not on disk

- `/aida:next` says the recorded path is not on this machine and names no route in.
- Scope, research and design run without the tree.
- The first action that needs the code makes the tree again. It computes the path on this
  machine and records the new path. A tree you moved with `git worktree move` is found, not made
  again.
- A folder at the recorded path that git does not list as a worktree is refused. Remove that
  folder, and the next action that needs the code makes the tree again.

## The site

A worktree has the branch's files and no running site. A review or a baseline taken there needs
the worktree's own site. So after the tree is made, AIDA offers to bring one up, from the
framework's worktree-environment recipe. The offer comes at `create`, and again when a stage
starts the task while the task records no answer. An unattended run makes no offer and records
nothing, so the offer waits for a person.

```
/aida:task environment <task-id> show
/aida:task environment <task-id> up
/aida:task environment <task-id> down
/aida:task environment <task-id> not-applicable -- <reason>
```

- `show` prints the commands `up` would run and runs its checks. It changes nothing.
- `up` brings the site up and records its address. If the worktree already runs a site, `up`
  adopts it: it takes no seed, so that site's database stays as it is.
- `down` takes the site down. An adopted site stays up.
- `not-applicable` records your no, with your reason, so the offer does not come again.

`up` and `not-applicable` are a person's answers, so an unattended run refuses them; see
[answer for a person](person-answer.md). `down` runs unattended, because a torn-down copy loses
nothing. When no framework has a recipe,
AIDA records that the worktree has files and no site.

When `up` changed files in the worktree for its site, completion takes the site down and puts
those files back, so the merge does not carry them. `/aida:task prune` removes the worktrees of
complete tasks, one yes per tree; see [completion](../stages/completion/README.md).

## Why it works this way

- One tree per task keeps two sessions on one project out of each other's files.
- A recorded path from another machine is not an address here, so AIDA computes it again.

Source: skills/task/SKILL.md, skills/next/SKILL.md, scripts/lib/task-helpers.sh, skills/task/scripts/task-actions.sh
