# Next.js Audit Operations

Quality audit operations for Next.js projects.

## Contents

- [Operation 14: Full Audit](#operation-14-full-audit)
- [Operation 15: Lint Check](#operation-15-lint-check)
- [Operation 16: Coverage Check](#operation-16-coverage-check)
- [Operation 17: DRY Check](#operation-17-dry-check)
- [Operation 19: SOLID Check](#operation-19-solid-check)

---

## Operation 14: Full Audit

When user says "run audit", "check code quality" in a Next.js project:

Run `scripts/core/full-audit.sh` (auto-detects Next.js) or manually:

1. Lint check (ESLint + TypeScript)
2. Coverage check (Jest)
3. DRY check (jscpd)
4. SOLID check (madge, complexity)
5. Aggregate results into `.reports/audit-report.json`

**Thresholds:**
| Metric | Pass | Warning | Fail |
|--------|------|---------|------|
| Coverage | >80% | 70-80% | <70% |
| ESLint errors | 0 | 1-10 | >10 |
| TypeScript errors | 0 | - | >0 |
| Duplication | <5% | 5-10% | >10% |

---

## Operation 15: Lint Check

When user says "lint code", "run eslint", "check types":

Run `scripts/nextjs/lint-check.sh` or:

### ESLint
```bash
npx eslint . --format json > .reports/lint-report.json
```

### TypeScript
```bash
npx tsc --noEmit
```

### Auto-fix Mode
```bash
scripts/nextjs/lint-check.sh --fix
# or: npx eslint . --fix
```

---

## Operation 16: Coverage Check

When user says "check coverage", "run jest coverage":

Run `scripts/nextjs/coverage-report.sh` or:

```bash
npx jest --coverage --coverageReporters=json-summary
```

Reports saved to `.reports/coverage/`

**Coverage Targets:**
| Code Type | Target |
|-----------|--------|
| Business logic | 90%+ |
| API routes | 85%+ |
| React components | 80%+ |
| Utility functions | 90%+ |
| Simple presentational | 60-70% |

---

## Operation 17: DRY Check

When user says "check duplication", "DRY check":

Run `scripts/nextjs/dry-check.sh` or:

```bash
npx jscpd src --reporters json --output .reports/dry/
```

**Rule of Three Guidance** (same as Drupal):

**Before extracting duplication:**
- Is this the 3rd+ occurrence? (If <3, duplication OK)
- Knowledge duplication or coincidental similarity?
- Will these change together? (Same reason to change?)
- Is the abstraction clear or would it be forced?

**Skip extraction when:**
- Test setup code (tests should be independent)
- Only 2 occurrences (wait for 3rd)
- Would need many parameters (wrong abstraction)
- Similar but different reasons to change

---

## Operation 19: SOLID Check

When user says "find SOLID violations", "check complexity", "check circular dependencies":

Run `scripts/nextjs/solid-check.sh` or:

### 1. Circular Dependencies (ISP, DIP)
```bash
npx madge --circular src
```

### 2. Complexity Analysis (SRP)
ESLint complexity rules check for functions with complexity >10

### 3. Large File Detection (SRP)
Find files >300 lines:
```bash
find src -name "*.ts" -o -name "*.tsx" | xargs wc -l | awk '$1 > 300'
```

### 4. TypeScript Strict Mode (LSP, DIP)
Check `tsconfig.json` for strict settings:
```json
{
  "compilerOptions": {
    "strict": true,
    "noImplicitAny": true,
    "strictNullChecks": true
  }
}
```

### Categorization by Principle

| Issue | Principle | Severity |
|-------|-----------|----------|
| Circular dependency | ISP, DIP | Critical |
| Complexity >10 | SRP | Warning |
| File >300 lines | SRP | Warning |
| strict mode disabled | LSP, DIP | Warning |

### Report Structure

Save `.reports/solid-report.json` with:
- Per-principle status (pass/warning/fail)
- Circular dependency chains
- Complexity violations
- Large files list

**Thresholds:**
| Metric | Pass | Warning | Fail |
|--------|------|---------|------|
| Circular deps | 0 | - | >0 |
| Complexity violations | 0 | 1-5 | >5 |
| Large files | 0 | 1-3 | >3 |
