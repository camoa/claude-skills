---
description: "Capture a new play (opinionated rule) into the project's local user playbook. Drafts entry with What/Rationale/When/Example fields, shows diff, appends on user confirmation. Introduced v3.15.0."
allowed-tools: Read, Write, Edit, Bash, Skill
argument-hint: [<short description of the rule>]
---

# Playbook Capture

Interactive flow that drafts a new play and appends it to the project's local user playbook file. The user is the deterministic approval gate — no write happens without explicit confirmation, with a diff preview.

## Usage

```
/drupal-dev-framework:playbook-capture                                # ask user to describe
/drupal-dev-framework:playbook-capture "Use BEM mod-* for utilities"  # short description hint
```

## What this does

### Step 1 — Resolve project context + check userPlaybook

Invoke `project-state-reader`. If `userPlaybookState != "set"`:
> Refuse with: "No user playbook configured for this project. Run `/drupal-dev-framework:set-user-playbook` first."

If `userPlaybookState == "set"`, continue.

### Step 2 — Gather intent from user

If a description was passed as arg, use it as the seed. Otherwise ask:
> What play do you want to capture? Paste a sentence or short description of the rule.

### Step 3 — Draft entry

Compose a play entry per `references/playbook-schema.md` v1.0:

```markdown
### <Title — concrete rule statement>

**What:** <one-line restatement>
**Rationale:** <why this rule; what breaks without it>
**When it applies:** <scope — file types, contexts, exceptions>
**Example:**

```<lang>
// Wrong
<bad>

// Right
<good>
```
```

Use session context (recent files modified, recent decisions discussed) to populate the example block when possible. If no context fits, leave the example block empty with a `// (no example yet)` comment — user can fill in later.

### Step 4 — Pick target section

Read the existing playbook via `playbook-read.sh` to enumerate H2 section names.

Ask:
> Save under which section?
> 1. <existing H2 1>
> 2. <existing H2 2>
> ...
> N+1. New section (you'll name it)

User picks. If new, ask for the section name.

### Step 5 — Show diff preview

Construct the proposed file content (existing + new play + section if needed). Use a unified diff format:

```diff
@@ Section: CSS / SCSS @@

+### Use BEM mod-* prefix for utility-only files
+
+**What:** Utility-only files use BEM with the mod-* prefix.
+**Rationale:** Standardizes utility class naming...
+**When it applies:** Files under themes/<sub>/scss/utilities/.
+**Example:**
+
+```scss
+// Right
+.btn.mod-large { ... }
+```
+
```

Print the diff.

### Step 6 — Confirm

Ask:
> [y]es write / [n]o cancel / [e]dit draft

- `[y]` → use `Edit` (or `Write` for full file rewrite if simpler) to apply the change. Confirm with: `✓ Saved to <userPlaybook>`. Print updated total play count.
- `[n]` → discard. No write. Confirm with: `✗ Cancelled. No changes written.`
- `[e]` → return to Step 3 with the user's revisions; re-show diff at Step 5.

## Error cases

| Scenario | Behavior |
|---|---|
| `userPlaybookState != "set"` | Refuse; exit 2; suggest `/set-user-playbook` |
| User cancels | Exit 0; no write |
| Write failure | Print error; exit 1; original file unchanged |
| Append produces malformed playbook (parser fails post-write) | Print warning; suggest manual review; do NOT roll back (write already happened — soft-nudge posture) |

## Soft-nudge posture

- Never writes without explicit user confirmation
- Always shows diff before write
- User can `[e]edit` the draft as many times as needed
- Cancel is a first-class option

## Related

- `/drupal-dev-framework:playbook-review` — walk existing plays for keep/update/remove
- `/drupal-dev-framework:playbook-active` — display current state
- `/drupal-dev-framework:set-user-playbook` — configure the local playbook path
- `references/playbook-schema.md` — entry structure
- `/drupal-dev-framework:complete` — surfaces candidate plays at task completion (auto-detected from session); user can accept and route to this capture flow
