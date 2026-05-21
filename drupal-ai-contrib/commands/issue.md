---
description: "Work the Drupal issue lifecycle — review prior work first, then create / comment on / claim an issue and check out its fork + branch with three-way fork handling. Use when user says 'Drupal issue', 'claim an issue', 'create an issue', 'check out issue fork', 'drupal-ai-contrib issue'. Wraps drupalorg-cli."
allowed-tools: Read, Bash, Glob, Grep, Skill, WebFetch, AskUserQuestion
argument-hint: "[issue-id|action]"
---

# Issue — Drupal Issue Lifecycle

Thin entry point. Reviews prior work first so the contribution is meaningful, not
duplicate.

## Usage

`/drupal-ai-contrib:issue [issue-id|action]`

## Parameters

- `$1` — an issue ID (e.g. `3456789`), or an action (`create`). Optional — if absent,
  the worker skill asks what the contributor wants to do.

## Steps

1. If `$1` is present and is not `create` (case-insensitive — `create`, `Create`,
   `CREATE` all count), it is an issue ID — **reject it unless it matches `^[0-9]+$`**
   (drupal.org / GitLab issue IDs are numeric). A non-matching, non-`create` argument
   is an error: ask for a valid issue ID, do not pass it on. If `$1` is `create` or
   absent, treat it as create / interactive.
2. Invoke the `drupal-ai-contrib:contribution-issue` skill via the Skill tool, passing
   `$1`.
3. Present the skill's result: the issue and its system + status, the prior-work
   finding, and the fork/branch state and action taken.

## Notes

The worker skill reviews existing comments, status, and MRs **before** acting, and
handles the issue-fork three ways — your fork (checkout), someone else's (surface,
coordinate, never clobber), or none (create the branch).
