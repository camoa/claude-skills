---
name: paper-test
description: Use when testing code through mental execution - trace code line-by-line with concrete input values to find bugs, logic errors, missing code, edge cases, and contract violations before deployment
version: 0.1.0
---

# Paper Test

Systematically test code by mentally executing it line-by-line with concrete values.

## When to Use

- "Paper test this code" / "Trace this code" / "Test without running"
- "Find bugs in this code" / "Check for edge cases"
- "Validate this implementation" / "Review this logic"
- Before deploying changes
- Debugging without a debugger
- Reviewing unfamiliar or AI-generated code
- Validating complex logic (loops, conditionals, recursion)

## Method

Follow code logic with concrete test cases to find:
1. **Potential issues** - Bugs, wrong assumptions, edge cases
2. **Missing code** - What's needed but not written to achieve intent

NOT just reading - actually run the code in your head with real values.

## Critical: How AI Should Verify

**NEVER assume or guess** - Use your tools to verify every claim:

### Verifying External Dependencies

When code calls external methods/services:

1. **Use Read tool** to check actual source files:
   ```
   Read: src/Service/UserService.php
   → Find loadByEmail() method
   → Note: Returns User|null, throws InvalidArgumentException if empty
   ```

2. **Use Grep tool** to find method definitions:
   ```
   Grep: "public function loadByEmail" in src/
   → Verify method exists and signature
   ```

3. **Check interfaces** for injected services:
   ```
   Read: vendor/.../LoggerInterface.php
   → Verify info() method signature
   ```

**DO NOT** write "Assume method exists" - Actually verify or mark as UNVERIFIED RISK.

### Verifying Code Contracts

When code has relationships (extends, implements, uses):

1. **Read parent/base classes**:
   ```
   Read: src/Plugin/ActionBase.php
   → Check for abstract methods
   → Verify parent constructor signature
   ```

2. **Read interfaces**:
   ```
   Read: src/Handler/HandlerInterface.php
   → List all required methods
   → Note exact signatures
   ```

3. **Check service definitions**:
   ```
   Read: config/services.yml
   Read: modulename.services.yml
   → Verify service ID exists
   → Check tags if using service collectors
   ```

### When You Cannot Verify

If source is unavailable (external package, closed-source):

```
DEPENDENCY CHECK: $externalApi->fetchData()
  VERIFICATION: Unable to read source
  RISK: Cannot verify method exists or return type
  RECOMMENDATION: Add runtime checks for null/exceptions
```

Mark as risk - don't assume it works.

---

## Quick Reference

| Test Type | When | Output |
|-----------|------|--------|
| Happy Path | First test | Verify correct flow |
| Edge Cases | After happy path | Find boundary issues |
| Error Cases | Last | Verify error handling |
| Contract Verification | Always | Check dependencies |

---

## Paper Testing Workflow

When user provides code to test:

### Step 1: Define Test Scenarios

Pick concrete input values. Start with happy path, then edge cases.

```
SCENARIO: [Description of what we're testing]
INPUT:
  $variable1 = [concrete value]
  $variable2 = [concrete value]
  [initial state]
```

### Step 2: Trace Line by Line

Follow each line. Write the variable state after execution.

```
Line [N]: [code statement]
         → [variable] = [new value]
         → [state change description]
```

### Step 3: Follow Every Branch

At each conditional, note which branch is taken and why.

```
Line [N]: if ([condition])
         → [variable1]=[value], [variable2]=[value]
         → [evaluation] = [true/false]
         → TAKES: [if branch / else branch] (lines X-Y)
```

### Step 4: Track Loop Iterations

For loops, trace EACH iteration with index and values.

```
Line [N]: foreach ([collection] as [item])

Iteration 1: $key=[value], $item=[value]
  Line [N+1]: [statement]
           → [state change]

Iteration 2: $key=[value], $item=[value]
  Line [N+1]: [statement]
           → [state change]

Loop ends. Final state: [describe]
```

### Step 5: Verify External Dependencies

For EVERY external call (methods, services, APIs), verify:

```
DEPENDENCY CHECK: [service/method name]

Location: [file path or interface]
Method signature: [actual signature]
Returns: [actual return type and values]
Throws: [exceptions, when]
Side effects: [what it modifies]

VERIFICATION:
  - [ ] Method exists
  - [ ] Parameters correct (type, order)
  - [ ] Return type handled correctly
  - [ ] Edge cases considered
```

**DO NOT ASSUME** - Read the actual source code or documentation.

### Step 6: Verify Code Contracts

For classes with relationships (extends, implements, uses, injects):

```
CONTRACT VERIFICATION: [Class name]

Extends: [Parent class]
  - [ ] All abstract methods implemented
  - [ ] Parent constructor called (if required)
  - [ ] Parent methods called when needed

Implements: [Interface]
  - [ ] All interface methods present
  - [ ] Signatures match exactly
  - [ ] Return types correct

Injected Services:
  - [ ] Service exists in container
  - [ ] Interface methods verified
  - [ ] Return types handled

Tagged Service (if applicable):
  - [ ] Tag name matches collector
  - [ ] Implements required interface
  - [ ] Priority appropriate
```

See reference guide for complete contract patterns.

### Step 7: Note Output and Flaws

```
OUTPUT:
  Return value: [what's returned]
  Side effects: [database changes, API calls, etc.]
  State changes: [session, cache, variables]

FLAWS FOUND:
  - Line [N]: [description of issue]
    FIX: [how to resolve]
  - Line [N]: [description of issue]
    FIX: [how to resolve]
```

---

## What to Look For

### Logic Errors
- Wrong comparison (`=` vs `==` vs `===`)
- Inverted condition (`if ($x)` should be `if (!$x)`)
- Off-by-one in loops
- Missing break in switch

### Null/Undefined Access
- Accessing property on null object
- Array key that might not exist
- Uninitialized variable

### Edge Cases
- Empty array/string
- Zero, negative numbers
- Null values
- Very large inputs

### State Issues
- Variable modified but not used
- Variable used before assignment
- Stale data from previous iteration

### Flow Issues
- Unreachable code
- Missing return statement
- Early return skips cleanup

### AI Code Issues
- Invented methods that don't exist
- Wrong return types assumed
- Wrong parameter order
- Mixed API versions
- Assumed service existence
- Wrong namespace imports

---

## Testing Strategy for Modules

For modules with multiple components (ECA plugins, form systems, etc.), use coverage-driven hybrid approach.

### Two Levels

**Flow-based**: Real user workflows end-to-end
- Tests integration and data handoffs
- Catches format mismatches, token issues

**Component**: Each component with edge cases
- Tests individual logic thoroughly
- Catches implementation bugs, null handling

### Coverage Method

```
Step 1: Map all components
  - List every event, condition, action, service

Step 2: Design flows covering all components
  - Each component in at least one flow
  - 3-5 flows typically cover a module

Step 3: Add component edge cases
  - For each component: scenarios NOT in flows
  - Error cases, empty inputs, boundaries
  - 2-4 edge cases per component
```

---

## Output Format

Use this template for all paper tests:

```
PAPER TEST: [File/Function name]

SCENARIO: [Description]
INPUT:
  [variable] = [value]
  [variable] = [value]

TRACE:
Line [N]: [code]
         → [variable] = [new value]

Line [N]: [conditional]
         → [evaluation] = [result]
         → TAKES: [branch]

Line [N]: [loop start]
Iteration [N]: [values]
  Line [N]: [code]
           → [state]

OUTPUT:
  Return: [value]
  Side effects: [list]
  State changes: [list]

DEPENDENCY CHECKS:
  [method/service]: VERIFIED / ISSUE FOUND
    Issue: [description]

CONTRACT CHECKS:
  [pattern]: VERIFIED / VIOLATION
    Issue: [description]

FLAWS FOUND:
  - [Line N]: [issue]
    FIX: [solution]
  - [Line N]: [issue]
    FIX: [solution]

EDGE CASES TO TEST:
  1. [scenario]
  2. [scenario]
```

---

## References

All detailed guides are in `references/` directory:

- `references/core-method.md` - Complete paper testing method
- `references/dependency-verification.md` - How to verify external calls
- `references/contract-patterns.md` - All code contract types
- `references/ai-code-auditing.md` - Testing AI-generated code
- `references/hybrid-testing.md` - Module-level testing strategy
- `references/common-flaws.md` - Catalog of frequent bugs
- `references/advanced-techniques.md` - Progressive injects, red team testing, attack surface analysis, AAR format

---

## Example

```php
function getDiscount($total, $coupon) {
  if ($coupon == 'SAVE10') {
    $discount = $total * 0.10;
  }
  if ($coupon == 'SAVE20') {
    $discount = $total * 0.20;
  }
  return $discount;
}
```

Paper test:

```
SCENARIO: No coupon provided
INPUT: $total = 100, $coupon = null

TRACE:
Line 2: if ($coupon == 'SAVE10')
        → null == 'SAVE10' = false
        → SKIP

Line 5: if ($coupon == 'SAVE20')
        → null == 'SAVE20' = false
        → SKIP

Line 8: return $discount
        → $discount is UNDEFINED

OUTPUT:
  Return: PHP Warning - undefined variable

FLAWS FOUND:
  - Line 8: Returns undefined variable when no coupon matches
    FIX: Initialize $discount = 0 at start of function
```

---

## Progressive Disclosure

The SKILL.md provides the core workflow. For detailed guidance:

- Complete methodology → `references/core-method.md`
- Dependency verification patterns → `references/dependency-verification.md`
- Contract verification (extends, implements, DI, plugins, etc.) → `references/contract-patterns.md`
- AI code specific checks → `references/ai-code-auditing.md`
- Module testing strategy → `references/hybrid-testing.md`
