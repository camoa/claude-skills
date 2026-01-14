---
description: Migrate v2.x single-file tasks to v3.0.0 folder structure
allowed-tools: Read, Write, Bash, Glob, Skill
argument-hint: none
---

# Migrate Tasks

Manually migrate v2.x single-file tasks to v3.0.0 folder-based structure.

## Usage

```
/drupal-dev-framework:migrate-tasks
```

## What This Does

1. Scans for old v2.x `.md` files in `implementation_process/in_progress/`
2. Shows migration plan with list of tasks to migrate
3. **Waits for user confirmation** (manual mode)
4. Migrates each task to folder structure
5. Creates backups (`.md.bak` files)
6. Reports results

## Manual vs Automatic

**This command (manual mode):**
- Shows full migration plan
- Waits for user confirmation
- User controls when migration happens

**Automatic mode (via /next):**
- When you run `/next` and old format detected
- No confirmation prompt
- Proceeds immediately

## Output Format

```
## Tasks to Migrate

Found 3 task(s) in old format:

1. settings_form.md
2. content_entity.md
3. field_formatter.md

Proceed with migration? (Creates backups with .bak extension)
[Wait for user confirmation]

Migrating: settings_form.md
  ✓ task.md (tracker)
  ✓ research.md (Phase 1)
  ✓ architecture.md (Phase 2)
  ✗ implementation.md (no content)
  ✓ Backup: settings_form.md.bak

Migrating: content_entity.md
  ✓ task.md (tracker)
  ✓ research.md (Phase 1)
  ✗ architecture.md (no content)
  ✗ implementation.md (no content)
  ✓ Backup: content_entity.md.bak

Migrating: field_formatter.md
  ✓ task.md (tracker)
  ✓ research.md (Phase 1)
  ✓ architecture.md (Phase 2)
  ✓ implementation.md (Phase 3)
  ✓ Backup: field_formatter.md.bak

## Migration Complete ✓

Migrated 3 task(s) to v3.0.0 structure.
Backups saved as .md.bak files.

Next Steps:
1. Verify migrated tasks in implementation_process/in_progress/
2. Delete backups when confident: rm *.md.bak
```

## What Gets Migrated

Old structure (v2.x):
```
implementation_process/in_progress/
└── task_name.md    # Everything in one file
```

New structure (v3.0.0):
```
implementation_process/in_progress/task_name/
├── task.md              # Tracker with links
├── research.md          # Phase 1 content
├── architecture.md      # Phase 2 content
└── implementation.md    # Phase 3 content
```

## Safety

- **Always creates backups** - Original files saved as `.md.bak`
- **Preserves all content** - No information lost
- **Idempotent** - Safe to run multiple times
- **Skip already migrated** - Won't re-migrate folders

## Error Handling

If migration fails for a task:
- Partial folders are cleaned up
- Original .md file kept intact
- Error logged
- Migration continues with next task

## Implementation

Invokes the `task-folder-migrator` skill in **manual mode**:
- User sees migration plan
- User confirms before proceeding
- Full control over migration process

## Related Commands

- `/drupal-dev-framework:next` - Automatic migration when old format detected
- `/drupal-dev-framework:status` - Check project status and task format

## See Also

- [MIGRATION.md](../MIGRATION.md) - Complete migration guide
- [README.md](../README.md) - Upgrading to v3.0.0 section
