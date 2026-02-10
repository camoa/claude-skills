# Migration Guide: v2.x → v3.0.0

This guide helps you migrate from v2.x single-file tasks to v3.0.0 folder-based structure.

## What Changed

**v2.x Structure (Old):**
```
implementation_process/in_progress/
└── task_name.md    # Everything in one file
```

**v3.0.0 Structure (New):**
```
implementation_process/in_progress/task_name/
├── task.md              # Tracker with links
├── research.md          # Phase 1 content
├── architecture.md      # Phase 2 content
└── implementation.md    # Phase 3 content
```

## Why This Change?

**Problems with v2.x:**
- Single files become too large
- Hard to navigate mixed content
- No clear separation by phase
- Difficult to find specific information

**Benefits of v3.0.0:**
- ✅ Each phase has own file
- ✅ Files stay small and focused
- ✅ Easy navigation (max 4 files)
- ✅ Simple flat structure

## Migration Steps

### 1. Backup Your Projects

Before upgrading, backup all project files:

```bash
# Backup implementation_process folder
cp -r ~/workspace/claude_memory/projects/my_project/implementation_process \
      ~/workspace/claude_memory/projects/my_project/implementation_process.backup
```

### 2. Install v3.0.0

```bash
/plugin install drupal-dev-framework@camoa-skills
```

### 3. Run Migration

**Option A: Automatic (Recommended)**

Navigate to your project and run `/next`:

```bash
/drupal-dev-framework:next
```

The command automatically detects old v2.x format and migrates your tasks before continuing. You can then immediately select and work on tasks.

**Option B: Manual**

Run the migration tool explicitly:

```bash
/drupal-dev-framework:migrate-tasks
```

### 4. Review Migration

The migration tool will:
- ✅ Scan for `.md` files in `in_progress/`
- ✅ Create folder for each task
- ✅ Parse sections (Research, Architecture, Implementation)
- ✅ Create separate files for each phase
- ✅ Create backup files (`.md.bak`)

Example output:
```
## Tasks to Migrate

Found 3 task(s) in old format:

1. settings_form.md
2. content_entity.md
3. field_formatter.md

Proceed with migration? (Creates backups with .bak extension)
```

After migration:
```
## Migration Complete ✓

Migrated 3 task(s) to v3.0.0 structure:

1. settings_form/ ✓
   - task.md
   - research.md
   - architecture.md
   - Backup: settings_form.md.bak

2. content_entity/ ✓
   - task.md
   - research.md
   - Backup: content_entity.md.bak

3. field_formatter/ ✓
   - task.md
   - research.md
   - architecture.md
   - implementation.md
   - Backup: field_formatter.md.bak
```

### 5. Verify Migration

Check each migrated task:

```bash
# List task folders
ls -l implementation_process/in_progress/

# Check a specific task
ls -l implementation_process/in_progress/settings_form/
cat implementation_process/in_progress/settings_form/task.md
```

Verify:
- ✅ All content preserved
- ✅ Files in correct locations
- ✅ Links work in task.md
- ✅ No data loss

### 6. Delete Backups

When confident migration succeeded:

```bash
# Delete all backup files
rm implementation_process/in_progress/*.md.bak
```

## Manual Migration (Optional)

If you prefer manual control:

### For Each Task:

1. **Create folder:**
   ```bash
   mkdir implementation_process/in_progress/task_name/
   ```

2. **Create task.md:**
   ```markdown
   # Task: task_name

   **Created:** {date}
   **Current Phase:** {detect from old file}

   ## Goal
   {from old Goal section}

   ## Phase Status
   - [{x if done}] Phase 1: Research → See [research.md](research.md)
   - [{x if done}] Phase 2: Architecture → See [architecture.md](architecture.md)
   - [ ] Phase 3: Implementation → See [implementation.md](implementation.md)

   ## Acceptance Criteria
   {from old file}

   ## Related Tasks
   {from old file}
   ```

3. **Create research.md** (if Research section exists):
   ```markdown
   # Research: task_name

   {paste ## Research section content}
   ```

4. **Create architecture.md** (if Architecture section exists):
   ```markdown
   # Architecture: task_name

   {paste ## Architecture section content}
   ```

5. **Create implementation.md** (if Implementation section exists):
   ```markdown
   # Implementation: task_name

   {paste ## Implementation section content}
   ```

6. **Backup original:**
   ```bash
   mv task_name.md task_name.md.bak
   ```

## Troubleshooting

### Migration Tool Doesn't Find Tasks

**Problem:** "No old-style tasks found"

**Solution:**
- Check you're in correct project directory
- Verify tasks are in `implementation_process/in_progress/`
- Ensure files end with `.md` (not directories)

### Content Missing After Migration

**Problem:** Some content not in new files

**Solution:**
- Check backup file: `task_name.md.bak`
- Manually copy missing content to appropriate file
- Report issue at https://github.com/camoa/claude-skills/issues

### Permission Errors

**Problem:** "Permission denied" during migration

**Solution:**
```bash
# Fix permissions
chmod -R u+w implementation_process/
# Try migration again
```

### Multiple Backups Created

**Problem:** Files like `task.md.bak.1736852400`

**Solution:**
- Timestamp added to prevent overwriting
- Delete oldest backups manually when confident

## Rollback

If you need to rollback to v2.x:

1. **Restore from backup:**
   ```bash
   rm -rf implementation_process/in_progress/*
   cp implementation_process.backup/in_progress/*.md \
      implementation_process/in_progress/
   ```

2. **Downgrade plugin:**
   ```bash
   /plugin install drupal-dev-framework@2.1.0@camoa-skills
   ```

## FAQ

**Q: Can I use v3.0.0 with existing v2.x projects?**
A: No, you must migrate tasks first using `/drupal-dev-framework:migrate-tasks`

**Q: Will migration change my code files?**
A: No, only task tracking files are modified. Your actual code is untouched.

**Q: Can I migrate one task at a time?**
A: Yes, run migration then immediately move other `.md` files elsewhere temporarily.

**Q: What if I have custom sections in my task files?**
A: Migration preserves all content. Custom sections go into the appropriate phase file based on location.

**Q: Do I need to update commands after migration?**
A: No, all commands automatically work with v3.0.0 structure.

## Getting Help

- **Issues:** https://github.com/camoa/claude-skills/issues
- **Discussions:** https://github.com/camoa/claude-skills/discussions
- **Tag:** `drupal-dev-framework` and `migration`

## Summary

1. ✅ Backup projects
2. ✅ Install v3.0.0
3. ✅ Run `/drupal-dev-framework:migrate-tasks`
4. ✅ Verify migration
5. ✅ Delete backups when confident

The migration preserves all content while organizing it for better maintainability!
