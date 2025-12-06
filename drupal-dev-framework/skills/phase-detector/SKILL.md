---
name: phase-detector
description: Use when determining project phase - analyzes memory folder structure to identify Phase 1, 2, or 3
version: 1.1.0
---

# Phase Detector

Analyze project memory to determine current development phase.

## Activation

Activate when:
- Invoked by `project-orchestrator` agent
- Session start on existing project
- Phase is unclear
- "What phase am I in?"

## Phase Definitions

| Phase | Focus | Code? |
|-------|-------|-------|
| 1 - Research | Requirements, existing solutions | NO |
| 2 - Architecture | Design, patterns, decisions | NO |
| 3 - Implementation | Build with TDD, interactive | YES |

## Workflow

### 1. Load Project Path

Use `Read` on `project_state.md` to get `{project_path}`.

### 2. Scan Folder Structure

Use `Glob` to check these locations:

```
{project_path}/project_state.md
{project_path}/architecture/main.md
{project_path}/architecture/research_*.md
{project_path}/architecture/*.md (excluding main.md and research_*)
{project_path}/implementation_process/in_progress/*.md
{project_path}/implementation_process/completed/*.md
```

### 3. Apply Scoring

**Phase 1 Indicators (score each +1):**
- [ ] project_state.md exists but minimal (<50 lines)
- [ ] architecture/main.md empty or missing
- [ ] No research_*.md files
- [ ] No component architecture files
- [ ] implementation_process/ is empty

**Phase 2 Indicators (score each +1):**
- [ ] architecture/main.md has content (>20 lines)
- [ ] research_*.md files exist
- [ ] Component architecture files exist
- [ ] project_state.md mentions "Architecture" or "Design"
- [ ] No in_progress tasks yet

**Phase 3 Indicators (score each +1):**
- [ ] architecture/main.md is complete
- [ ] Component architectures exist
- [ ] in_progress/ has task files
- [ ] completed/ has task files
- [ ] project_state.md mentions "Implementation"

### 4. Determine Phase

```
If Phase 1 score >= 3: Phase 1
Else if Phase 2 score >= 3: Phase 2
Else if Phase 3 score >= 3: Phase 3
Else: Ask user to clarify
```

### 5. Check project_state.md Explicit Phase

Use `Read` on project_state.md and look for:
```
**Phase:** X - Name
```

If explicit phase conflicts with detected phase, report discrepancy.

### 6. Return Result

Format output as:
```
## Phase Detection: {Project Name}

**Detected Phase:** {1/2/3} - {Research/Architecture/Implementation}
**Confidence:** {High/Medium/Low}

### Evidence
| Indicator | Found | Suggests |
|-----------|-------|----------|
| project_state.md | Yes, 45 lines | Phase 1 |
| architecture/main.md | Yes, 120 lines | Phase 2+ |
| research files | 2 found | Phase 2+ |
| component architectures | 3 found | Phase 2+ |
| in_progress tasks | 1 found | Phase 3 |
| completed tasks | 2 found | Phase 3 |

### Scores
- Phase 1: {X}/5
- Phase 2: {X}/5
- Phase 3: {X}/5

### Conclusion
Project is in **Phase {N}** based on {primary evidence}.

### Next Milestone
{What would advance to next phase}
```

## Edge Cases

| Situation | Handling |
|-----------|----------|
| Empty project | Default to Phase 1 |
| Mixed signals | Use highest-scoring phase |
| Tie between phases | Ask user to confirm |
| Explicit phase in file | Trust file if reasonable |

## Stop Points

STOP if:
- Scores are tied (ask user)
- Detected phase conflicts with explicit phase in project_state.md
- Project structure is unexpected
