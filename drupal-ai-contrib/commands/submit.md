---
description: "Create or update a Drupal merge request and generate the AI-disclosure comment at the policy threshold. Use when user says 'submit Drupal contribution', 'open a merge request', 'update the MR', 'submit patch', 'drupal-ai-contrib submit'. Wraps drupalorg-cli."
allowed-tools: Read, Bash, Glob, Grep, Skill, Task, WebFetch
argument-hint: "[issue-id]"
---

# Submit — Create / Update the Merge Request

Thin entry point. Prepares the policy-required AI disclosure with the MR.

## Usage

`/drupal-ai-contrib:submit [issue-id]`

## Parameters

- `$1` — the issue ID (optional). If absent, the worker skill resolves it from the
  current issue-fork branch.

## Steps

1. If `$1` is given, **reject it unless it matches `^[0-9]+$`** (issue IDs are
   numeric) — ask for a valid issue ID rather than passing a malformed value on.
2. Invoke the `drupal-ai-contrib:contribution-submit` skill via the Skill tool, passing
   `$1`.
3. Present the skill's result: the MR URL, target branch, the AI-disclosure decision
   and where it was placed, the issue status set, and the next step (`pipeline`).

## Notes

The worker skill surfaces — but does not silently block on — unmet preconditions
(`verify` not green, `review` not run). It fetches the current AI-contribution policy
live via the `ai-policy-checker` agent to decide the disclosure threshold.
