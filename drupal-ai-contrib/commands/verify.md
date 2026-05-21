---
description: "Run the local verification inner loop for a Drupal contribution — the drupalci-parity gate set at CI strictness, the AI-policy gate, and the eval gate, every gate passing only on a captured artifact. Use when user says 'verify Drupal contribution', 'run the gates', 'check before submitting', 'drupalci parity', 'drupal-ai-contrib verify'."
allowed-tools: Read, Bash, Glob, Grep, Skill, Task, WebFetch
argument-hint: "[project-path]"
---

# Verify — Local drupalci-Parity + AI-Policy + Eval Gates

Thin entry point. The centerpiece: evidence over assertion — never a bare "passes".

## Usage

`/drupal-ai-contrib:verify [project-path]`

## Parameters

- `$1` — project path (optional). Defaults to the current directory.

## Steps

1. Resolve the project path. If no `.gitlab-ci.yml` is found, report the gap and point
   the contributor at `/drupal-ai-contrib:setup` for that gap only — do not refuse to run.
2. Invoke the `drupal-ai-contrib:contribution-verify` skill via the Skill tool, passing
   the resolved path.
3. Present the skill's per-gate report: each gate's actual blocking status, PASS / FAIL
   / UNRUN, and the captured artifact. Opt-in variants are listed UNRUN. State the
   environment-match status.

## Notes

The worker skill environment-matches first (installs the CI-target core), mirrors each
enabled drupalci job locally at CI strictness, runs the AI-policy gate (every
contribution) and the eval gate (best-effort), and re-fires any gate whose path was
edited after it last passed.
