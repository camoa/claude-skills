# Testing Skills

How to validate skills work correctly before deployment.

## TDD for Skills

### RED Phase
1. Run pressure scenario WITHOUT skill
2. Document exact behavior verbatim
3. Identify failure patterns and rationalizations

### GREEN Phase
4. Write minimal skill addressing failures
5. Test again - verify improvement

### REFACTOR Phase
6. Identify new rationalizations
7. Add explicit counters
8. Re-test until bulletproof

## Testing by Skill Type

### Discipline-Enforcing Skills
- Test with academic understanding questions
- Test under pressure (time, sunk cost, authority)
- Test with combined pressures
- **Success**: Agent follows rule under maximum pressure

### Technique Skills
- Test application scenarios
- Test edge cases and variations
- Test with missing information
- **Success**: Agent applies technique correctly

### Reference Skills
- Test information retrieval
- Test application of information
- Test for coverage gaps
- **Success**: Agent finds and uses information correctly

## Validation Checklist

### Frontmatter
- [ ] Only `name` and `description` fields (plus optional: license, allowed-tools, metadata)
- [ ] Name: lowercase letters, numbers, hyphens only
- [ ] Name: max 64 characters
- [ ] Name: matches directory name
- [ ] Description: starts with "Use when..."
- [ ] Description: includes specific triggers
- [ ] Description: written in third person
- [ ] Description: under 1024 characters

### Content
- [ ] SKILL.md body under 500 lines
- [ ] No duplicate information
- [ ] All referenced files exist
- [ ] Scripts tested and working
- [ ] Examples are complete and runnable

### Discovery
- [ ] Description triggers correctly for intended tasks
- [ ] Doesn't trigger for unrelated tasks
- [ ] Keywords match likely searches

## Quick Validation Commands

```bash
# Check frontmatter format
head -20 SKILL.md

# Count lines (target: <500)
wc -l SKILL.md

# Find broken references
grep -o 'references/[^)]*' SKILL.md | while read f; do
  [ -f "$f" ] || echo "Missing: $f"
done

# Find broken script references
grep -o 'scripts/[^)]*' SKILL.md | while read f; do
  [ -f "$f" ] || echo "Missing: $f"
done

# Test scripts run
python scripts/*.py --help 2>/dev/null || echo "Check script syntax"

# Run validator
python scripts/validate_skill.py .
```

## Size Guidelines

| Component | Target | Maximum |
|-----------|--------|---------|
| Description | 200-500 chars | 1024 chars |
| SKILL.md body | <500 lines | 5000 words |
| Individual reference | <1000 lines | 10k words |
| Total skill files | <50 files | No limit |

## Success Criteria

A skill is ready when:

1. **Triggers correctly** - Loads for intended tasks, not unrelated ones
2. **Workflow works** - Claude follows the process correctly
3. **Output matches** - Results meet expectations
4. **No rationalization** - Claude doesn't skip or shortcut the skill
5. **Scripts execute** - All bundled scripts run without errors
6. **References exist** - All referenced files are present
