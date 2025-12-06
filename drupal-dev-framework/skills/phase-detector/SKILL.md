---
name: phase-detector
description: Use when determining project phase - analyzes memory folder structure to identify Phase 1, 2, or 3
version: 1.0.0
---

# Phase Detector

Analyze project memory folder to determine current development phase.

## Triggers

- Internal skill used by project-orchestrator
- Session start on existing project
- When phase is unclear

## Phase Definitions

### Phase 1: Research
**Focus:** Understand requirements, study existing solutions
**Code:** NO

### Phase 2: Architecture
**Focus:** Design components, choose patterns
**Code:** NO

### Phase 3: Implementation
**Focus:** Build with TDD, interactive development
**Code:** YES (with approval)

## Detection Logic

### Phase 1 Indicators
```
Score +1 for each:
- project_state.md exists but is minimal
- architecture/main.md is empty or missing
- No research_*.md files
- No component architecture files
- implementation_process/ is empty
```

If score >= 3: **Phase 1**

### Phase 2 Indicators
```
Score +1 for each:
- architecture/main.md has content
- research_*.md files exist
- Component architecture files exist
- project_state.md mentions "Architecture" or "Design"
- implementation_process/ has no in_progress tasks
```

If score >= 3: **Phase 2**

### Phase 3 Indicators
```
Score +1 for each:
- architecture/main.md is complete
- Component architectures exist
- implementation_process/in_progress/ has tasks
- implementation_process/completed/ has tasks
- project_state.md mentions "Implementation"
```

If score >= 3: **Phase 3**

## Analysis Process

1. **Check folder existence**
   ```
   ~/workspace/claude_memory/{project}/
   ├── project_state.md         # Required
   ├── architecture/            # Check contents
   └── implementation_process/  # Check contents
   ```

2. **Read project_state.md**
   - Look for explicit phase mention
   - Check status field
   - Review current focus

3. **Count files**
   - Research files
   - Architecture files
   - Task files (in_progress vs completed)

4. **Determine phase**
   - Apply scoring logic
   - Return phase with confidence

## Output Format

```markdown
## Phase Detection: {Project Name}

### Detected Phase: {1/2/3}
### Confidence: {High/Medium/Low}

### Evidence
| Indicator | Present | Phase Suggests |
|-----------|---------|----------------|
| project_state.md | Yes | - |
| architecture/main.md content | Yes | 2+ |
| research files | 2 | 1-2 |
| component architectures | 3 | 2+ |
| in_progress tasks | 1 | 3 |
| completed tasks | 2 | 3 |

### Phase Scores
- Phase 1 indicators: {X}/5
- Phase 2 indicators: {X}/5
- Phase 3 indicators: {X}/5

### Recommendation
Current phase is **{Phase}** based on {primary evidence}.

Next expected milestone: {what would advance to next phase}
```

## Edge Cases

**Empty project:** Default to Phase 1
**Mixed signals:** Use highest-scoring phase
**Unclear:** Ask user to clarify

## Human Control Points

- User can override detected phase
- User confirms phase assessment
