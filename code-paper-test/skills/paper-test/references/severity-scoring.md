# Severity Scoring Rubric

Consistent criteria for rating flaw severity during paper testing.

## Severity Levels

| Severity | Criteria | Action |
|----------|----------|--------|
| **CRITICAL** | Data loss, security breach, financial impact, crash on main path | Fix immediately — blocks deployment |
| **HIGH** | Feature broken for common use case, data corruption possible, auth bypass | Fix before release |
| **MEDIUM** | Edge case failure, degraded UX, workaround exists | Fix in current sprint |
| **LOW** | Code quality issue, minor UX issue, theoretical risk | Fix when convenient |
| **INFO** | Observation, not a bug — code smell, future concern | Document only |

---

## Scoring Factors

Rate each factor 1-3, then use the matrix:

### 1. Reach — How many users/requests hit this path?

| Score | Description |
|-------|-------------|
| 3 | Every request / main flow |
| 2 | Common but not universal (10-50% of requests) |
| 1 | Rare edge case (<10% of requests) |

### 2. Impact — What happens when triggered?

| Score | Description |
|-------|-------------|
| 3 | Crash, data loss, security breach, financial loss |
| 2 | Feature broken, wrong data returned, silent failure |
| 1 | Wrong message, cosmetic issue, minor inconvenience |

### 3. Reversibility — Can the damage be undone?

| Score | Description |
|-------|-------------|
| 3 | Irreversible (data deleted, money sent, security exposed) |
| 2 | Recoverable with effort (restore backup, manual fix) |
| 1 | Self-correcting or trivially fixable |

### 4. Exploitability — Can an attacker trigger this intentionally?

| Score | Description |
|-------|-------------|
| 3 | Public input, no auth required |
| 2 | Authenticated user can trigger |
| 1 | Requires system access or unlikely conditions |

### Severity Matrix

| Total Score (4-12) | Severity |
|-------------------|----------|
| 10-12 | CRITICAL |
| 7-9 | HIGH |
| 4-6 | MEDIUM |
| 2-3 | LOW |

---

## Template

```
FLAW: [description]
  Line: [N]
  Reach:         [1-3] — [reason]
  Impact:        [1-3] — [reason]
  Reversibility: [1-3] — [reason]
  Exploitability:[1-3] — [reason]
  Total:         [sum] → SEVERITY: [level]
```

---

## Example

```
FLAW: No input validation on payment amount — negative values process as refunds
  Line: 15
  Reach:         3 — every payment request hits this
  Impact:        3 — financial loss, attacker receives money
  Reversibility: 3 — money transferred, hard to recover
  Exploitability:3 — public API, no auth needed beyond login
  Total:         12 → SEVERITY: CRITICAL

FLAW: Error message reveals stack trace to user
  Line: 88
  Reach:         1 — only on unhandled exceptions
  Impact:        2 — information disclosure, no direct exploit
  Reversibility: 1 — no lasting damage
  Exploitability:2 — authenticated user can trigger with bad input
  Total:         6 → SEVERITY: MEDIUM
```

---

## When to Use

- **Always** for security-related flaws
- **Team reports** from test-team command (consistent cross-tester scoring)
- **Prioritization** when multiple flaws found (fix highest severity first)
- **Communication** with stakeholders (objective severity, not opinion)

For quick paper tests of simple code, informal CRITICAL/HIGH/MEDIUM/LOW labels without scoring are acceptable.
