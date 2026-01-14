---
name: task-folder-migrator
description: Use when migrating existing single-file tasks to folder-based structure - preserves content, creates organized folders, backs up originals
version: 3.0.0
---

# Task Folder Migrator

Migrate single-file tasks to the new v3.0.0 folder-based structure.

## Activation

Activate when:
- User says "migrate tasks to new structure"
- User says "convert task files to folders"
- User invokes `/drupal-dev-framework:migrate-tasks`
- Before upgrading from v2.x to v3.0.0

## What This Does

Converts old-style single-file tasks into new folder structure:

**Old Structure (v2.x):**
```
implementation_process/in_progress/
└── settings_form.md    # Everything in one file
```

**New Structure (v3.0.0):**
```
implementation_process/in_progress/settings_form/
├── task.md              # Tracker with links
├── research.md          # Phase 1 content
├── architecture.md      # Phase 2 content
└── implementation.md    # Phase 3 content
```

## Workflow

### 1. Identify Project Path

Get project path from `project_state.md` or ask user:
```
Where are your task files located?
Default: {cwd}/implementation_process/in_progress/
```

### 2. Scan for Old-Style Tasks

Use `Glob` to find single `.md` files:
```
{project_path}/implementation_process/in_progress/*.md
```

If no `.md` files found, report: "No old-style tasks found. All tasks already using v3.0.0 structure."

### 3. Present Migration Plan

For each task file found, show:
```
## Tasks to Migrate

Found {N} task(s) in old format:

1. settings_form.md
2. content_entity.md
3. field_formatter.md

Proceed with migration? (Creates backups with .bak extension)
```

Wait for user confirmation.

### 4. Migrate Each Task

For each task file:

#### A. Read Existing Content

Use `Read` on `{task_name}.md` to load full content.

#### B. Parse Sections

Extract content by searching for markdown headers:

- **Research section:** Content between `## Research` or `## Phase 1` and next `##` header
- **Architecture section:** Content between `## Architecture` or `## Phase 2` and next `##` header
- **Implementation section:** Content between `## Implementation` or `## Phase 3` and next `##` header
- **Other sections:** Goal, Acceptance Criteria, Related Tasks, Notes

#### C. Create Folder Structure

Use `Bash` to create directory:
```bash
mkdir -p "{project_path}/implementation_process/in_progress/{task_name}"
```

#### D. Write New Files

**1. Create task.md (Tracker):**

Use `Write` to create `{task_name}/task.md`:

```markdown
# Task: {task_name}

**Created:** {original_date or today}
**Current Phase:** {detect from content}

## Goal
{extract from original Goal section}

## Phase Status
- [{x if research exists}] Phase 1: Research → See [research.md](research.md)
- [{x if architecture exists}] Phase 2: Architecture → See [architecture.md](architecture.md)
- [{x if implementation exists}] Phase 3: Implementation → See [implementation.md](implementation.md)

## Acceptance Criteria
{extract from original Acceptance Criteria section}

## Related Tasks
{extract from original Related Tasks section}

## Notes
{extract from original Notes section}
```

**2. Create research.md (if content exists):**

If Research section found, use `Write` to create `{task_name}/research.md`:
```markdown
# Research: {task_name}

{paste Research section content here}
```

**3. Create architecture.md (if content exists):**

If Architecture section found, use `Write` to create `{task_name}/architecture.md`:
```markdown
# Architecture: {task_name}

{paste Architecture section content here}
```

**4. Create implementation.md (if content exists):**

If Implementation section found, use `Write` to create `{task_name}/implementation.md`:
```markdown
# Implementation: {task_name}

{paste Implementation section content here}
```

#### E. Backup Original

Use `Bash` to rename original file:
```bash
mv "{project_path}/implementation_process/in_progress/{task_name}.md" \
   "{project_path}/implementation_process/in_progress/{task_name}.md.bak"
```

### 5. Report Results

After migrating all tasks, report:

```
## Migration Complete ✓

Migrated {N} task(s) to v3.0.0 structure:

1. settings_form/ ✓
   - task.md
   - research.md
   - architecture.md
   - Backup: settings_form.md.bak

2. content_entity/ ✓
   - task.md
   - research.md
   - Backup: content_entity.md.bak

Original files backed up with .bak extension.

**Next Steps:**
1. Verify migrated tasks: Check {project_path}/implementation_process/in_progress/
2. Delete backups when confident: rm *.md.bak
```

## Edge Cases

| Situation | Handling |
|-----------|----------|
| No sections found | Create task.md only with all content |
| Task already migrated | Skip, report "already v3.0.0 format" |
| Empty sections | Don't create file for that phase |
| Backup file exists | Append timestamp: {task}.md.bak.{timestamp} |
| Permission error | Report error, skip task, continue |

## Stop Points

STOP and ask user if:
- More than 10 tasks to migrate (confirm large migration)
- Backup file already exists (overwrite?)
- Project path looks wrong

## Important Notes

- **Always create backups** - Users can delete them later
- **Preserve all content** - Don't lose any information
- **Simple extraction** - Just split by headers, don't rewrite
- **Idempotent** - Safe to run multiple times

## Example Output

```
Migrating: settings_form.md

Creating: settings_form/
  ✓ task.md (tracker with links)
  ✓ research.md (Phase 1 content)
  ✓ architecture.md (Phase 2 content)
  ✗ implementation.md (no content found)

Backup: settings_form.md → settings_form.md.bak

Migration complete for settings_form
```
