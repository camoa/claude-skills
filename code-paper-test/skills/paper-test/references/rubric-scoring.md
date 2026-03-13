# Rubric-Based Scoring

Structured grading system for overall code quality assessment during paper testing.

## When to Use

- Code reviews and PR assessments
- Vendor code evaluation
- Before/after refactoring comparison
- Quality gate decisions (pass/fail for deployment)
- Training — calibrate team on what "good" looks like

---

## Content Rubric (Does it work?)

| Category | 1 (Poor) | 3 (Adequate) | 5 (Excellent) |
|----------|----------|--------------|---------------|
| **Correctness** | Fails on happy path | Works for happy path, fails edge cases | Handles all scenarios correctly |
| **Completeness** | Missing major functionality | Core functionality present, gaps in edge cases | All requirements met, edge cases handled |
| **Edge cases** | No edge case handling | Some edge cases handled (null, empty) | Comprehensive (null, empty, zero, large, concurrent) |
| **Error handling** | No error handling, crashes | Basic try/catch, generic messages | Specific errors, recovery paths, user-friendly messages |
| **Security** | Obvious vulnerabilities (SQLi, XSS) | Basic sanitization, some gaps | Defense in depth, validated at all boundaries |

## Structure Rubric (Is it maintainable?)

| Category | 1 (Poor) | 3 (Adequate) | 5 (Excellent) |
|----------|----------|--------------|---------------|
| **Readability** | Cryptic names, no structure | Reasonable names, some structure | Self-documenting, clear intent |
| **Separation of concerns** | Business logic in controllers/forms | Some separation, some mixing | Clean layers, single responsibility |
| **DRY** | Copy-pasted blocks, duplicated logic | Minor duplication | No unnecessary duplication, good abstractions |
| **Testability** | Untestable (hardcoded deps, global state) | Partially testable | Fully injectable, pure functions where possible |
| **Extensibility** | Changes require rewriting | Can extend with moderate effort | Open for extension, closed for modification |

---

## Scoring Template

```
RUBRIC SCORE: [file/module name]

CONTENT (Does it work?):
  Correctness:      [1-5] — [notes]
  Completeness:     [1-5] — [notes]
  Edge cases:       [1-5] — [notes]
  Error handling:   [1-5] — [notes]
  Security:         [1-5] — [notes]
  Content subtotal: [sum]/25

STRUCTURE (Is it maintainable?):
  Readability:      [1-5] — [notes]
  Separation:       [1-5] — [notes]
  DRY:              [1-5] — [notes]
  Testability:      [1-5] — [notes]
  Extensibility:    [1-5] — [notes]
  Structure subtotal: [sum]/25

TOTAL: [sum]/50

GRADE:
  45-50: Excellent — production ready
  35-44: Good — minor improvements needed
  25-34: Adequate — several improvements needed before production
  15-24: Below standard — significant rework required
  <15:   Poor — fundamental issues, consider rewriting
```

---

## Quality Gate Usage

For deployment decisions:

```
QUALITY GATE: [module/feature name]

Minimum for deployment: 35/50 (Good)
Minimum per category:   2/5 (no category below Adequate)

Score: [X]/50
Below-minimum categories: [list any category scoring 1]

GATE: PASS / FAIL
Reason: [why]
```

---

## Example

```
RUBRIC SCORE: src/Service/PaymentProcessor.php

CONTENT:
  Correctness:      4 — Happy path works, one edge case wrong (negative amounts)
  Completeness:     3 — Missing refund flow, partial cancellation
  Edge cases:       2 — Handles null, misses empty cart and zero amount
  Error handling:   2 — Generic catch, user sees "Something went wrong"
  Security:         3 — Parameterized queries, missing rate limiting
  Content subtotal: 14/25

STRUCTURE:
  Readability:      4 — Clear names, good method length
  Separation:       3 — Some validation mixed into processing
  DRY:              4 — Minimal duplication
  Testability:      4 — Injectable dependencies, one static call
  Extensibility:    3 — New payment methods require modifying switch statement
  Structure subtotal: 18/25

TOTAL: 32/50

GRADE: Adequate — several improvements needed before production

QUALITY GATE: FAIL
  Below-minimum: Edge cases (2), Error handling (2)
  Action: Fix edge case handling and error messages before deployment
```
