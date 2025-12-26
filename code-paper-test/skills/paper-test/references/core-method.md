# Core Paper Testing Method

Complete methodology for testing code through mental execution.

## Contents

- [Purpose](#purpose)
- [Method Overview](#method-overview)
- [Step-by-Step Process](#step-by-step-process)
- [Scenario Selection](#scenario-selection)
- [Line-by-Line Tracing](#line-by-line-tracing)
- [Branch Handling](#branch-handling)
- [Loop Iteration](#loop-iteration)
- [Output Documentation](#output-documentation)

---

## Purpose

Follow code logic to find:
1. **Potential issues** - Bugs, wrong assumptions, edge cases
2. **Missing code** - What's needed but not written to achieve the intent

## Method Overview

- **Mentally execute** the code with concrete test cases (happy path, edge cases, errors)
- **Trace variable state** at each step
- **Verify external dependencies** - don't assume, confirm methods exist and behave as expected

Not just reading - actually running the code in your head with real values.

---

## When to Use

- Before deploying changes
- Debugging without a debugger
- Reviewing unfamiliar code
- Validating complex logic (loops, conditionals, recursion)
- Finding edge cases
- Auditing AI-generated code

---

## Step-by-Step Process

### 1. Define Test Scenario

Pick concrete input values. Start with the happy path, then edge cases.

```
SCENARIO: User submits form with email "test@example.com"
INPUT:
  $email = "test@example.com"
  $user = null
```

### 2. Trace Line by Line

Follow each line. Write the variable state after execution.

```
Line 10: $email = trim($email)
         → $email = "test@example.com"

Line 11: if (empty($email))
         → false, skip to line 15

Line 15: $user = loadUserByEmail($email)
         → assume returns User object with id=42

Line 16: if (!$user)
         → false (user exists), skip to line 20

Line 20: return $user->id
         → returns 42
```

### 3. Follow Every Branch

At each conditional, note which branch is taken and why.

```
Line 25: if ($count > 0 && $enabled)
         → $count=3, $enabled=true
         → true && true = true
         → TAKES: if branch (lines 26-30)
```

### 4. Track Loop Iterations

For loops, trace each iteration with index and values.

```
Line 30: foreach ($items as $key => $item)

Iteration 1: $key=0, $item="apple"
  Line 31: $result[] = strtoupper($item)
           → $result = ["APPLE"]

Iteration 2: $key=1, $item="banana"
  Line 31: $result[] = strtoupper($item)
           → $result = ["APPLE", "BANANA"]

Loop ends. $result = ["APPLE", "BANANA"]
```

### 5. Note the Output

What is returned? What state changed? What side effects occurred?

```
OUTPUT:
  Return value: 42
  Side effects: None
  Token/Session changes: None
```

---

## Scenario Selection

### Happy Path (Test 1)

The expected, normal case.

```
SCENARIO: Valid user login
INPUT:
  $username = "john_doe"
  $password = "correct_password"
  User exists in database with matching credentials
```

### Edge Cases (Tests 2-N)

Boundary conditions and special cases.

```
SCENARIO: Empty input
INPUT:
  $username = ""
  $password = ""

SCENARIO: Very long input
INPUT:
  $username = [string of 1000 characters]
  $password = [string of 1000 characters]

SCENARIO: Special characters
INPUT:
  $username = "user@domain.com"
  $password = "p@$$w0rd!"
```

### Error Cases (Final tests)

Things that should fail gracefully.

```
SCENARIO: User not found
INPUT:
  $username = "nonexistent"
  $password = "anything"
  User does NOT exist in database

SCENARIO: Wrong password
INPUT:
  $username = "john_doe"
  $password = "wrong_password"
  User exists but password doesn't match
```

---

## Line-by-Line Tracing

### Simple Assignments

```
Line 5: $total = $price * $quantity
        → $price = 10, $quantity = 3
        → $total = 30
```

### Method Calls

```
Line 10: $result = $this->calculate($value)
         → $value = 100
         → [Need to verify what calculate() does]
         → Assume returns: $result = 120
```

**CRITICAL**: Don't guess what methods do - verify them (see dependency-verification.md).

### Property Access

```
Line 15: $name = $user->getName()
         → $user = User{id: 1, name: "John"}
         → $name = "John"
```

### Conditionals

```
Line 20: if ($x > 5 && $y < 10)
         → $x = 7, $y = 3
         → 7 > 5 = true, 3 < 10 = true
         → true && true = true
         → TAKES if branch (lines 21-25)
```

---

## Branch Handling

### If/Else

```
Line 10: if ($status === 'active')
         → $status = 'inactive'
         → false
         → TAKES else branch (line 15)

Line 15: $message = "User is not active"
         → $message = "User is not active"
```

### Switch

```
Line 20: switch ($type)
         → $type = 'premium'

Line 21: case 'free':
         → no match, skip

Line 23: case 'premium':
         → MATCH, execute lines 24-25

Line 24: $price = 99.99
         → $price = 99.99

Line 25: break
         → EXIT switch
```

### Ternary

```
Line 30: $discount = $isPremium ? 0.20 : 0.10
         → $isPremium = true
         → takes first value
         → $discount = 0.20
```

---

## Loop Iteration

### Foreach

```
Line 40: foreach ($users as $user)
         → $users = [User{id:1}, User{id:2}]

Iteration 1:
  $user = User{id: 1, name: "Alice"}
  Line 41: $names[] = $user->name
           → $names = ["Alice"]

Iteration 2:
  $user = User{id: 2, name: "Bob"}
  Line 41: $names[] = $user->name
           → $names = ["Alice", "Bob"]

Loop ends.
Final state: $names = ["Alice", "Bob"]
```

### For

```
Line 50: for ($i = 0; $i < 3; $i++)

Iteration 1:
  $i = 0
  Line 51: $sum += $i
           → $sum = 0 (was 0)
  Increment: $i = 1

Iteration 2:
  $i = 1
  Line 51: $sum += $i
           → $sum = 1 (was 0)
  Increment: $i = 2

Iteration 3:
  $i = 2
  Line 51: $sum += $i
           → $sum = 3 (was 1)
  Increment: $i = 3

Check condition: $i < 3 → 3 < 3 = false
Loop ends. $sum = 3
```

### While

```
Line 60: while ($count < 10)

Check: $count = 0, 0 < 10 = true, ENTER loop

Iteration 1:
  Line 61: $count += 2
           → $count = 2
  Check: 2 < 10 = true, CONTINUE

Iteration 2:
  Line 61: $count += 2
           → $count = 4
  Check: 4 < 10 = true, CONTINUE

...

Iteration 5:
  Line 61: $count += 2
           → $count = 10
  Check: 10 < 10 = false, EXIT

Final: $count = 10
```

---

## Output Documentation

### Return Values

```
OUTPUT:
  Return value: [value and type]
  Return path: [which return statement, line number]
```

### Side Effects

```
OUTPUT:
  Side effects:
    - Database: INSERT into users (id: 123)
    - API call: POST to /api/notify
    - File system: Created /tmp/cache_abc.json
    - Email: Sent to user@example.com
```

### State Changes

```
OUTPUT:
  State changes:
    - Session: Set 'user_id' = 42
    - Cache: Stored 'user_42_profile'
    - Global: $GLOBALS['last_login'] = timestamp
    - Object: $this->isAuthenticated = true
```

---

## Complete Example

```php
function calculatePrice($items, $couponCode = null) {
  $total = 0;
  foreach ($items as $item) {
    $total += $item['price'] * $item['quantity'];
  }

  if ($couponCode === 'SAVE20') {
    $total *= 0.8;
  }

  return $total;
}
```

**Paper Test:**

```
SCENARIO: Two items with 20% coupon
INPUT:
  $items = [
    ['price' => 10, 'quantity' => 2],
    ['price' => 5, 'quantity' => 3]
  ]
  $couponCode = 'SAVE20'

TRACE:
Line 2: $total = 0
        → $total = 0

Line 3: foreach ($items as $item)
        → 2 items to process

Iteration 1:
  $item = ['price' => 10, 'quantity' => 2]
  Line 4: $total += $item['price'] * $item['quantity']
          → $total += 10 * 2
          → $total = 20

Iteration 2:
  $item = ['price' => 5, 'quantity' => 3]
  Line 4: $total += $item['price'] * $item['quantity']
          → $total += 5 * 3
          → $total = 35 (was 20)

Loop ends.

Line 7: if ($couponCode === 'SAVE20')
        → 'SAVE20' === 'SAVE20' = true
        → TAKES if branch (line 8)

Line 8: $total *= 0.8
        → $total = 35 * 0.8
        → $total = 28

Line 11: return $total
         → returns 28

OUTPUT:
  Return value: 28
  Side effects: None
  State changes: None

FLAWS FOUND:
  None - logic is correct
```

**Edge Case Test:**

```
SCENARIO: Empty items array
INPUT:
  $items = []
  $couponCode = null

TRACE:
Line 2: $total = 0
        → $total = 0

Line 3: foreach ($items as $item)
        → 0 items, loop never executes

Line 7: if ($couponCode === 'SAVE20')
        → null === 'SAVE20' = false
        → SKIP if branch

Line 11: return $total
         → returns 0

OUTPUT:
  Return value: 0
  Side effects: None

FLAWS FOUND:
  None - handles empty array correctly
```
