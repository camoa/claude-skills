---
description: Main entry point - show project status, switch projects, or start new one
allowed-tools: Read, Glob, AskUserQuestion
---

# Brand Command

Single entry point that adapts to context - show status, switch projects, or initialize.

## Workflow

1. **Check current location**
   Look for `brand-philosophy.md` in current directory.

2. **If IN a brand project:**
   Show project status dashboard:

   ```
   📁 Project: {project-name}

   Brand Philosophy: ✓ Configured

   Templates:
   - presentations: {list or "none yet"}
   - carousels: {list or "none yet"}

   Recent outputs:
   - {list last 3-5 outputs with dates, or "none yet"}

   Quick actions:
   - /presentation or /carousel - create content
   - /outline <template> - get outline template + AI prompt
   - /template-presentation or /template-carousel - create template
   - /brand-palette - generate alternative color palettes
   - /brand-extract - update brand philosophy
   ```

   Then ask: "What would you like to do?"

3. **If NOT in a brand project:**
   Scan for existing projects:
   - Look for directories containing `brand-philosophy.md` in current directory and one level up
   - Also check common locations if none found nearby

   **If projects found:**
   ```
   You're not in a brand project. I found these nearby:

   1. acme-corp/ - Brand philosophy configured
   2. startup-xyz/ - Brand philosophy pending

   Which project would you like to open, or start a new one?
   ```

   Use AskUserQuestion with options:
   - List found projects
   - "Create new project"

   **If no projects found:**
   ```
   No brand projects found nearby. Would you like to create one?
   ```

   If yes, guide to `/brand-init`

4. **If user selects existing project:**
   - Set the selected project path as the working context
   - Read brand-philosophy.md from that project folder
   - Show the project status dashboard (same as step 2)
   - All subsequent commands in this session should use paths relative to the selected project

   Example: If user selects "palcera/", then:
   - Read `palcera/brand-philosophy.md`
   - Templates are at `palcera/templates/`
   - Outputs go to `palcera/presentations/` or `palcera/carousels/`

## Status Dashboard Details

When showing status, gather:

**Brand Philosophy:**
- Check if `brand-philosophy.md` exists and has content beyond placeholder
- If placeholder only: "⚠️ Pending - run /brand-extract"
- If configured: "✓ Configured"

**Templates:**
- Glob `templates/presentations/*/template.md` - list names
- Glob `templates/carousels/*/template.md` - list names

**Recent Outputs:**
- Glob `presentations/*/` and `carousels/*/`
- Sort by date (folder name starts with YYYY-MM-DD)
- Show last 3-5

## Output

- Project status dashboard (if in project)
- List of available projects (if not in project)
- Clear next steps

## Notes

- This is the "home base" command - run it anytime to orient yourself
- Non-destructive - only reads and reports, never modifies
- When a project is selected, remember the project path for all subsequent commands in the session
- Do NOT tell users to `cd` and restart - just work with the project directly using full paths
