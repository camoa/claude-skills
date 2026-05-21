# Paper Testing Workflow

The full step-by-step workflow, verification detail, flaw catalog summary,
module strategy, and output template. `SKILL.md` carries the condensed version;
this file is the complete reference. For even deeper methodology see
`core-method.md`, `dependency-verification.md`, `contract-patterns.md`,
`common-flaws.md`, and `hybrid-testing.md`.

## Critical: How AI Should Verify

**NEVER assume or guess** — use your tools to verify every claim.

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

**DO NOT** write "Assume method exists" — actually verify or mark as UNVERIFIED RISK.

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

Mark as risk — don't assume it works.

### Verifying Configuration Dependencies

When code reads config values (YAML, JSON, .env, services):

1. **Find the config source** — Read the actual file
2. **Verify key exists** — Does the key the code reads actually exist?
3. **Verify value type** — Does the value match what code expects?
4. **Verify defaults** — If config missing, is there a sensible fallback?

```
CONFIG CHECK: $this->config('my_module.settings')->get('api_timeout')
  Source: config/install/my_module.settings.yml
  Key exists?  YES / NO
  Value:       30
  Type match:  integer (code expects int) — MATCH / MISMATCH
  Default:     NULL if missing — RISK: no fallback
```

Also check: services.yml (service IDs, arguments), routing.yml (route names),
schema.yml (structure matches config).

## Quick Reference

| Test Type | When | Output |
|-----------|------|--------|
| Happy Path | First test | Verify correct flow |
| Edge Cases | After happy path | Find boundary issues |
| Error Cases | Last | Verify error handling |
| Contract Verification | Always | Check dependencies |

## Paper Testing Workflow

When user provides code to test:

### Step 1: Define Test Scenarios

Pick concrete input values. Start with happy path, then edge cases. The number
of scenarios per phase scales with effort — see SKILL.md "Effort-Adaptive
Scenario Depth".

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

### Step 2b: Track Data Flow Across Boundaries

At every function call, method return, or data handoff, track type transformations:

```
DATA FLOW: [source] → [destination]
  Input type:  [what was passed]
  Output type: [what was returned]
  Coercion:    [any implicit type change]
  Risk:        [what breaks if type is wrong]
```

Watch for:
- **Implicit coercion** — string "30" used as int, null used as empty string
- **Container types** — method returns array but code treats as single object
- **Serialization boundaries** — object → JSON → object (properties may change case, nulls may disappear)
- **Framework wrapping** — raw value wrapped in Response, FieldItemList, Result objects

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

**DO NOT ASSUME** — Read the actual source code or documentation.

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

See `contract-patterns.md` for complete contract patterns.

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

### Step 8: Untested Path Analysis

After all scenarios, review for paths NOT exercised:

```
UNTESTED PATHS:
  - Line [N]-[M]: [else branch / catch block / default case] — never triggered
    Risk: [what this path handles]
    Scenario needed: [input that would trigger it]

Coverage: [X of Y branches exercised]
Recommendation: [add scenario for critical untested paths / accept risk]
```

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

### Error Propagation
- Exception thrown but caught too high (wrong handler)
- Exception swallowed silently (empty catch block)
- Partial state left behind (DB row inserted, email not sent)
- Wrong error code/status returned to caller
- User retries after error — causes duplicates?

### Performance Patterns
- N+1 query — database call inside a loop
- Nested loops on collections — O(n²) or worse
- Same expensive call repeated — missing cache/variable
- Unbounded collection growth — no size limit in loop
- Missing pagination — loads entire table into memory

### AI Code Issues
- Invented methods that don't exist
- Wrong return types assumed
- Wrong parameter order
- Mixed API versions
- Assumed service existence
- Wrong namespace imports

Full catalog with examples and fixes: `common-flaws.md`.

## Testing Strategy for Modules

For modules with multiple components (ECA plugins, form systems, etc.), use a
coverage-driven hybrid approach.

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

Full method, coverage matrix, and templates: `hybrid-testing.md`.

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
