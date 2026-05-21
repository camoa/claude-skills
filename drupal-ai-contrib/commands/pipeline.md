---
description: "Fetch the real GitLab merge-request pipeline for a Drupal contribution and gate on it — the authoritative final check. Use when user says 'check the pipeline', 'real CI status', 'is the contribution done', 'drupalci pipeline', 'drupal-ai-contrib pipeline'."
allowed-tools: Read, Bash, Glob, Grep, Skill, WebFetch
argument-hint: "[mr-url|issue-id]"
---

# Pipeline — Confirm the Real drupalci Pipeline

Thin entry point. The authoritative final gate — a contribution is not done until the
real pipeline is green.

## Usage

`/drupal-ai-contrib:pipeline [mr-url|issue-id]`

## Parameters

- `$1` — an MR URL or issue ID (optional). If absent, the worker skill resolves the MR
  from the current issue-fork branch.

## Steps

1. If `$1` is given, validate it: an issue ID must match `^[0-9]+$`; an MR URL must
   match `^https://[A-Za-z0-9._/-]+/-/merge_requests/[0-9]+$` (the host/path segment
   admits only URL-safe characters — no spaces, shell metacharacters, or control
   characters). Reject anything else — ask for a valid issue ID or MR URL rather than
   passing a malformed value on.
2. Invoke the `drupal-ai-contrib:contribution-pipeline` skill via the Skill tool,
   passing `$1`.
3. Present the skill's per-job report: name, status, blocking vs. `allow_failure` vs.
   manual, the job-log link; and the plain verdict — is the contribution done, or what
   remains.

## Notes

The worker skill reads the pipeline honestly — a green pipeline can hide a red
`allow_failure` job or un-run manual opt-in variants; those are surfaced, never implied
as coverage.
