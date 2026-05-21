---
description: "Run honest fresh-context review of a Drupal contribution — isolated reviewer agents with no session narrative check the work against scope, standards, security, and the AI policy. Use when user says 'review Drupal contribution', 'honest review', 'fresh-eyes review', 'pre-submission review', 'drupal-ai-contrib review'."
allowed-tools: Read, Glob, Grep, Skill, Task, Bash
argument-hint: "[project-path]"
---

# Review — Honest Fresh-Context Review

Thin entry point. A builder cannot objectively review its own work.

## Usage

`/drupal-ai-contrib:review [project-path]`

## Parameters

- `$1` — project path (optional). Defaults to the current directory.

## Steps

1. Resolve the project path and confirm there is a contribution diff to review (an
   issue-fork branch vs. its target). If none, report it and stop.
2. Invoke the `drupal-ai-contrib:contribution-review` skill via the Skill tool, passing
   the resolved path.
3. Present the skill's findings report: per-finding severity (blocker / should-fix /
   suggestion), file:line location, and concrete fix; and the plain verdict — ready for
   `submit`, or another development pass needed.

## Notes

The worker skill dispatches the `fresh-context-reviewer` agent (no build narrative) and
delegates the SOLID / DRY philosophy review to `code-quality-tools`.
