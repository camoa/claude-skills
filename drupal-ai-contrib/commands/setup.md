---
description: "Onboard and environment-match a Drupal contribution workspace — DDEV with the workflow-matched add-on, CI gate config, and the Drupal AI skills. Use when user says 'set up Drupal contribution', 'contribution environment', 'scaffold a contrib module', 'drupal-ai-contrib setup'. Idempotent — does only what is missing."
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Skill, AskUserQuestion
argument-hint: "[project-path]"
---

# Setup — Drupal Contribution Environment

Thin entry point. Onboarding is optional, idempotent, and never a gate.

## Usage

`/drupal-ai-contrib:setup [project-path]`

## Parameters

- `$1` — project path (optional). Defaults to the current directory.

## Steps

1. Resolve the project path (`$1` or the current directory). If it is not a directory,
   ask the contributor for the path.
2. Invoke the `drupal-ai-contrib:contribution-setup` skill via the Skill tool, passing
   the resolved path.
3. Present the skill's result: the detected workflow and issue system, environment
   status, the resolved gate set, AI-skill status, and the environment-match result.

## Notes

`contribution-setup` writes scaffolding files only with explicit confirmation and only
within the target project. A contributor with a ready environment can skip straight to
`/drupal-ai-contrib:issue`.
