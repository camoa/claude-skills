# Desktop Scheduled Task — Quality Sweep (primary)

Use a Desktop Scheduled Task when the sweep needs local access (DDEV containers, composer autoload cache, drush, uncommitted changes, local MCP servers). This is the default choice for this plugin.

## Create

In Claude Code Desktop: **Schedule → New task → New local task**. Or ask Claude in any Desktop session: *"set up a daily code-quality audit at 7am."*

| Field | Value |
|---|---|
| **Name** | `quality-sweep` (becomes kebab-case folder under `~/.claude/scheduled-tasks/`) |
| **Description** | `Daily code-quality audit with dated report` |
| **Frequency** | Daily, 7:00 AM (or Weekdays if you don't want weekend runs) |
| **Working folder** | Project root |
| **Worktree toggle** | Off for audits against working tree; On for isolated dry-runs |
| **Permission mode** | **Never use `Ask` for scheduled tasks** — the run stalls at the first permission prompt with no human present. Use `acceptEdits` for read-only audits; `auto` if the sweep should fix auto-fixable findings |
| **Model** | Sonnet (audits don't need Opus) |

Click **Run now** once after creating — any permission prompt that fires during the first run can be "always allowed" so future runs don't stall.

## Prompt (project-type aware)

Paste this as the task prompt. It auto-detects Drupal vs Next.js and writes a dated report.

```markdown
Run a code-quality sweep.

1. Detect project type:
   - `composer.json` with `drupal/core` → Drupal
   - `package.json` with `next` → Next.js
   - Else → abort with "Unsupported project type"

2. Create `.reports/` if it doesn't exist; append `.reports/` to `.gitignore` if missing.

3. Run the full audit:
   - Drupal: `/code-quality-tools:audit`
   - Next.js: `/code-quality-tools:audit`

4. Write the summary to `.reports/quality-sweep-$(date +%Y-%m-%d).md` with:
   - Project type detected
   - Tools run and their exit status
   - Top 10 findings ranked by severity
   - Delta vs yesterday's report if present (files fixed, new regressions)

5. If any Critical or High severity findings are new since yesterday, tag the
   report title with "REGRESSION" so morning-me notices.

6. Do NOT commit or push. The working tree stays as I left it.

7. Summary line in stdout: "Quality sweep complete. N findings. See
   .reports/quality-sweep-YYYY-MM-DD.md"
```

## Variations

### Hourly security watch

Frequency: Hourly. Replace step 3 with `/code-quality-tools:security`. Drop the date-stamped filename in favor of `.reports/security-latest.md` (overwrite) so you're not spammed with files.

### Pre-commit sweep

Frequency: Weekdays, 5:30 PM. Add this as step 7:

```markdown
7. If findings are clean, print "Safe to commit. End-of-day state is clean."
   If findings exist, print the top 3 and suggest `/code-quality-tools:review` paths.
```

### Weekly deep review

Frequency: Weekly, Monday 6 AM. Replace step 3 with a chained run:

```markdown
3. Run in sequence:
   - /code-quality-tools:audit         (full)
   - /code-quality-tools:solid src/    (architecture)
   - /code-quality-tools:dry           (duplication)
   - /code-quality-tools:coverage      (test coverage)
```

Budget ~15 minutes; Desktop doesn't enforce a time limit but API cost scales with depth.

## Gotchas

- **Computer sleeps = run skipped.** Enable *Keep computer awake* in Desktop Settings → General if 7am slots matter. Missed runs get one catch-up on wake (whichever slot was most recent).
- **Task prompt lives on disk.** Edit at `~/.claude/scheduled-tasks/quality-sweep/SKILL.md` (or under `CLAUDE_CONFIG_DIR`). Frontmatter has `name` and `description`; body is the prompt.
- **Worktree toggle changes semantics.** On = fresh worktree per run, no uncommitted work seen. Off = your live working tree. For a true "snapshot of my WIP" audit, leave Off.
- **Schedule, folder, model, enabled state** are NOT in the on-disk file. Change them via Edit form or by asking Claude.

## See Also

- `scheduled-sweeps.md` — comparison of the three scheduling surfaces
- `cloud-routine-sweep.md` — machine-off fallback
- `premerge-gate-routine.md` — API-triggered CI gate (cloud only)
