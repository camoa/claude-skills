# drupalorg-cli — the issue / MR / pipeline CLI

The `issue`, `submit`, and `pipeline` skills wrap this tool. This reference is the
single source of truth for what it is, how to install it, how authentication works,
and what it can and cannot do. Skills point here instead of repeating these details.

## What it is

`mglaman/drupalorg-cli` is a command-line tool that talks to Drupal.org and GitLab
(`git.drupalcode.org`) through their REST APIs — it manages issues, issue forks,
branches, and merge requests from the terminal. It auto-detects whether a project's
issues live in the classic Drupal.org queue or have migrated to GitLab work items, and
accepts work-item references and merge-request URLs directly.

## The executable is `drupalorg` — not `drupalorg-cli`

`drupalorg-cli` is the **package / repository name**. The **command on `PATH` is
`drupalorg`**. Always shell out `drupalorg <subcommand>`, never `drupalorg-cli …`.

Detect whether it is installed:

```bash
command -v drupalorg
```

## Install

**Requirements:** PHP 8.1+ with cURL, and Git.

**Recommended — PHAR download** (the project's preferred method):

```bash
curl -OL https://github.com/mglaman/drupalorg-cli/releases/latest/download/drupalorg.phar
chmod +x drupalorg.phar
mv drupalorg.phar /usr/local/bin/drupalorg
```

**Composer global install — deprecated** (the project marks this path deprecated; use
the PHAR unless a contributor specifically needs the Composer install):

```bash
composer global require mglaman/drupalorg-cli
```

The Composer install puts the binary in Composer's **global bin directory**, which is
often *not* on `PATH` by default. Find it with `composer global config bin-dir
--absolute` (commonly `~/.config/composer/vendor/bin`) and add that directory to
`PATH`, or `command -v drupalorg` will fail even though the tool is installed.

Confirm the install either way: `drupalorg --version`.

## Authentication — read vs. write

The tool's auth requirement depends on the operation. `setup` checks this; `issue`'s
fork/push step depends on it.

- **Read operations** (`issue:show`, `mr:list`, `project:issues`, `issue:search`, …)
  hit **public** Drupal.org / GitLab APIs — no credentials needed for public projects.
- **Write / push operations** — `git push` to an issue fork, and the `/do:` issue-bot
  commands — need the contributor's own **drupal.org credentials**. Specifically: an
  **SSH key registered on the contributor's drupal.org account**, because issue-fork
  git remotes use SSH URLs (`git@git.drupal.org:…`).

**The plugin and the CLI cannot set this up — it is the contributor's account action.**
Register a key at *drupal.org → My account → SSH keys*. Verify it works:

```bash
ssh -T git@git.drupal.org
```

A working key greets the contributor by drupal.org username. If push fails with a
permission error, the missing/unregistered SSH key is the first thing to check.
Credentials are the contributor's own — never store or transmit them.

## What the CLI can and cannot do

Run `drupalorg list` for the authoritative command set on the installed version, and
`drupalorg <command> --help` for a command's exact name and arguments — names can drift
between releases, so confirm against the install rather than assuming.

**Command groups** (current as of v0.10.x):

| Group | Operates on |
|-------|-------------|
| `issue:*` | An **existing** issue / issue fork — fork, branch, checkout, assign, label, apply, patch, interdiff, link, search, show, set up the remote |
| `mr:*` | An **existing** merge request — list, status, diff, files, logs |
| `project:*` | A project — issues, kanban, releases, release notes |
| `maintainer:*` | Maintainer views — issues, release notes |
| `skill:*` / `mcp:*` | Drupal AI skill install; MCP server mode |

**Two things the CLI does NOT do — do not invent a subcommand for either:**

1. **No `issue:create`.** Every `issue:*` command operates on an issue that already
   exists. A *new* issue is filed through the **web UI** — the project's Drupal.org
   issue queue, or its GitLab issues page if it has migrated. `contribution-issue`
   drafts the issue (title, summary, steps, component, version) and guides the
   contributor to file it, then resumes with the new issue ID.
2. **No `mr:create`.** On GitLab a merge request is created by **pushing the
   issue-fork branch** — `issue:branch` / `issue:checkout` set up the fork + branch;
   the contributor develops, commits, and `git push`es, and GitLab opens the MR (the
   push output includes a create-MR URL). `submit` then uses `mr:list` / `mr:status`
   to confirm and report it.

## Safe invocation

Invoke only **fixed subcommands** — never build a subcommand name from user input.
Before passing any identifier, validate it: issue IDs must match `^[0-9]+$`, project
machine-names `^[a-z][a-z0-9_]*$`. Reject anything that does not match rather than
shelling out with it. Never interpolate unsanitized input into a shell command.
