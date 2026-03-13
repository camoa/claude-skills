# Blind A/B Comparison

Compare two implementations of the same functionality to determine which is better.

## When to Use

- Comparing AI-generated code vs human-written code
- Evaluating a refactored version against the original
- Choosing between two competing approaches
- Reviewing vendor code against internal implementation

---

## Method

### Step 1: Define the comparison scope

```
A/B COMPARISON: [what's being compared]

Implementation A: [source — file path or description]
Implementation B: [source — file path or description]

Same interface? YES/NO
Same inputs?     YES/NO
Same expected output? YES/NO
```

### Step 2: Design shared test scenarios

Use the SAME scenarios for both implementations:

```
SHARED SCENARIOS:
  1. Happy path:  [concrete inputs]
  2. Edge case 1: [empty/null/zero]
  3. Edge case 2: [boundary values]
  4. Error case:  [invalid input]
  5. Stress case: [large/concurrent]
```

### Step 3: Trace each implementation independently

Paper test A with all scenarios first. Then paper test B with the same scenarios. Do NOT compare during tracing — complete each independently.

### Step 4: Score each implementation

Use the rubric scoring template for each:

```
SCORECARD: Implementation [A/B]

| Category | Score (1-5) | Notes |
|----------|-------------|-------|
| Correctness | | All scenarios produce correct output? |
| Edge case handling | | How many edge cases handled gracefully? |
| Error handling | | Errors caught, reported, recovered? |
| Security | | Input validation, injection prevention? |
| Performance | | N+1 queries, unnecessary loops, caching? |
| Readability | | Clear naming, structure, comments? |
| Maintainability | | Easy to extend, modify, debug? |
| **Total** | **/35** | |
```

### Step 5: Compare and recommend

```
A/B COMPARISON RESULT:

Implementation A: [total]/35
Implementation B: [total]/35

Winner: [A/B]

Key differences:
  - A handles [X] better because [reason]
  - B handles [Y] better because [reason]

Recommendation: [Use A/B, or hybrid — take X from A and Y from B]
```

---

## Blind Protocol

For unbiased comparison:
1. Label implementations "A" and "B" without indicating which is "expected to be better"
2. Complete all tracing before comparing scores
3. If tracing both yourself, do A fully first, then B — don't interleave
4. With agent teams: assign A to one agent, B to another, synthesize only after both complete

---

## Example: AI-Generated vs Human Code

```
A/B COMPARISON: User authentication service

Implementation A: src/auth/AuthService.php (human-written, 6 months old)
Implementation B: src/auth/AuthServiceV2.php (AI-generated refactor)

SHARED SCENARIOS:
  1. Valid login (correct username + password)
  2. Wrong password
  3. Non-existent user
  4. Empty username
  5. SQL injection attempt: username = "admin' OR 1=1--"
  6. Concurrent login from 2 devices

RESULTS:
  Implementation A: 28/35
    - Handles SQL injection (parameterized queries) ✓
    - Missing: concurrent session handling
    - Missing: rate limiting on failed attempts

  Implementation B: 24/35
    - Better error messages to user ✓
    - FLAW: Uses string concatenation in query (SQL injection risk!)
    - FLAW: Calls $user->getFullName() which doesn't exist (AI hallucination)
    - Missing: concurrent session handling (same as A)

RECOMMENDATION: Keep A, adopt B's error messages, fix both for concurrent sessions
```
