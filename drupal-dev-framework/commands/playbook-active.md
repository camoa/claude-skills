---
description: "Display the project's currently-active playbook configuration: subscribed sets, local playbook file, recent conflicts. Read-only — no writes. Introduced v3.15.0."
allowed-tools: Read, Bash, Skill
---

# Playbook Active

Read-only view of the project's playbook state. Shows subscribed sets, local playbook file, recent conflict log entries.

## Usage

```
/drupal-dev-framework:playbook-active
```

## What this does

### Step 1 — Resolve project state

Invoke `project-state-reader` to get `playbookSets[]`, `playbookSetsSource`, `userPlaybook`, `userPlaybookState`, `playbookResolutions[]`.

### Step 2 — Read local playbook (if set)

If `userPlaybookState == "set"`, invoke `scripts/playbook-read.sh` to get play count + warning count. Otherwise skip.

### Step 3 — Read conflict log (if exists)

```bash
LOG="<project>/.claude/playbook-conflicts.log"
if [ -f "$LOG" ]; then
  tail -n 10 "$LOG" | jq -r '"\(.detected_at) [\(.conflict_type)] \(.topic): winner=\(.winner)"'
fi
```

### Step 4 — Print summary

Format:

```
Playbook configuration for <project>:

  Subscribed sets (<source>):
    - drupal/best-practices/camoa
    - drupal/best-practices/lullabot
  
  Local playbook:
    Path:   /home/me/projects/idexx/docs/playbook.md
    State:  set
    Plays:  19 (warnings: 19)
  
  Multi-set resolutions:
    - font-sizing → drupal/best-practices/camoa
    - bem-methodology → drupal/best-practices/lullabot
  
  Recent conflicts (last 10):
    2026-04-24T23:45:00Z [local-vs-shipped] font-sizing: winner=local
    2026-04-23T12:00:00Z [multi-set-contradiction] bem-methodology: winner=lullabot
```

When fields are absent, render `none` or `(empty)`:

```
  Subscribed sets (default):
    (empty — plugin defaults are also empty)
  
  Local playbook:
    State:  unset
    Tip:    Run /drupal-dev-framework:set-user-playbook to configure
```

## What this does NOT do

- Does NOT write
- Does NOT load guides into context
- Does NOT trigger conflict surface (just reads what's already logged)

## Related

- `/drupal-dev-framework:set-playbook-sets` — change subscribed sets
- `/drupal-dev-framework:set-user-playbook` — change local playbook path
- `/drupal-dev-framework:playbook-capture` — add new plays
- `/drupal-dev-framework:playbook-review` — walk existing plays
