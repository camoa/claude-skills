# Common Code Flaws Catalog

Comprehensive list of bugs and issues paper testing frequently catches.

## Contents

- [Logic Errors](#logic-errors)
- [Null/Undefined Access](#nullundefined-access)
- [Edge Cases](#edge-cases)
- [State Issues](#state-issues)
- [Flow Issues](#flow-issues)
- [Contract Violations](#contract-violations)
- [Dependency Errors](#dependency-errors)
- [AI-Generated Code Specific](#ai-generated-code-specific)

---

## Logic Errors

### 1. Wrong Comparison Operator

```php
// FLAW: Assignment instead of comparison
if ($status = 'active') {  // Sets $status to 'active', always true
  // ...
}
// FIX: Use == or ===
if ($status === 'active') {
```

```php
// FLAW: Loose vs strict comparison
if ($count == '0') {  // true for 0, '0', '', false, null
  // ...
}
// FIX: Use strict comparison
if ($count === 0) {
```

### 2. Inverted Condition

```php
// FLAW: Logic backwards
if ($user) {
  return NULL;  // Returns null when user EXISTS
}
return $user;  // Returns user when user is NULL

// FIX: Invert the condition
if (!$user) {
  return NULL;
}
return $user;
```

### 3. Off-by-One in Loops

```php
// FLAW: Starts at 1, skips first item
for ($i = 1; $i < count($items); $i++) {
  process($items[$i]);
}
// FIX: Start at 0
for ($i = 0; $i < count($items); $i++) {
```

```php
// FLAW: Uses <=, processes one too many
for ($i = 0; $i <= count($items); $i++) {  // Array out of bounds!
  process($items[$i]);
}
// FIX: Use <
for ($i = 0; $i < count($items); $i++) {
```

### 4. Missing Break in Switch

```php
// FLAW: Falls through to next case
switch ($type) {
  case 'admin':
    $permissions = ['all'];
    // Missing break! Falls through to 'user' case
  case 'user':
    $permissions = ['read'];  // Overwrites 'all'!
    break;
}
// FIX: Add break
case 'admin':
  $permissions = ['all'];
  break;
```

### 5. Wrong Operator Precedence

```php
// FLAW: && binds tighter than ||
if ($status == 'active' || $status == 'pending' && $verified) {
  // Means: active OR (pending AND verified)
  // Not: (active OR pending) AND verified
}
// FIX: Use parentheses
if (($status == 'active' || $status == 'pending') && $verified) {
```

---

## Null/Undefined Access

### 1. Accessing Property on Null

```php
// FLAW: No null check
$user = loadUser($id);
$name = $user->getName();  // Fatal if $user is null

// FIX: Check for null
$user = loadUser($id);
if ($user) {
  $name = $user->getName();
}
```

### 2. Array Key That Might Not Exist

```php
// FLAW: Assumes key exists
$value = $config['api_key'];  // Notice/Warning if not set

// FIX: Check existence or use default
$value = $config['api_key'] ?? 'default';
// OR
$value = isset($config['api_key']) ? $config['api_key'] : 'default';
```

### 3. Uninitialized Variable

```php
// FLAW: Variable never set in some paths
if ($condition) {
  $result = calculateResult();
}
return $result;  // UNDEFINED if $condition is false

// FIX: Initialize before conditional
$result = null;
if ($condition) {
  $result = calculateResult();
}
return $result;
```

### 4. Null Propagation in Chains

```php
// FLAW: Any step could be null
$id = $entity->getMapping()->getSalesforceId()->getValue();

// If getMapping() returns null:
//   → Fatal: Call to member function getSalesforceId() on null

// FIX: Check each step or use null-safe operator
$mapping = $entity->getMapping();
if ($mapping) {
  $sfId = $mapping->getSalesforceId();
  if ($sfId) {
    $id = $sfId->getValue();
  }
}
// OR (PHP 8+)
$id = $entity->getMapping()?->getSalesforceId()?->getValue();
```

---

## Edge Cases

### 1. Empty Array

```php
// FLAW: Assumes array has items
$first = $items[0];  // Fatal if array is empty

// FIX: Check if array has items
if (!empty($items)) {
  $first = $items[0];
}
// OR
$first = $items[0] ?? null;
```

### 2. Empty String

```php
// FLAW: Empty string is falsy but not null
if ($email) {  // '' is falsy, skips validation
  validate($email);
}

// FIX: Explicit empty check
if ($email !== '' && $email !== null) {
  validate($email);
}
// OR check what empty means for your use case
if (strlen($email) > 0) {
```

### 3. Zero and Negative Numbers

```php
// FLAW: Treats 0 as invalid
if ($quantity) {  // 0 is falsy, but might be valid
  process($quantity);
}

// FIX: Explicit comparison
if ($quantity > 0) {
  process($quantity);
}
// OR if 0 is valid:
if ($quantity !== null) {
  process($quantity);
}
```

### 4. Very Large Inputs

```php
// FLAW: No limit on loop iterations
foreach ($items as $item) {  // What if $items has 1 million entries?
  expensiveOperation($item);
}

// FIX: Add limit or pagination
$max = 1000;
$count = 0;
foreach ($items as $item) {
  if (++$count > $max) break;
  expensiveOperation($item);
}
```

---

## State Issues

### 1. Variable Modified But Not Used

```php
// FLAW: Calculate but don't use
$total = 0;
foreach ($items as $item) {
  $total += $item->price;
}
return $items;  // BUG: Should return $total, not $items

// FIX: Return calculated value
return $total;
```

### 2. Variable Used Before Assignment

```php
// FLAW: Read before write
if ($status === 'active') {
  $count++;  // UNDEFINED: Never initialized
}

// FIX: Initialize first
$count = 0;
if ($status === 'active') {
  $count++;
}
```

### 3. Stale Data From Previous Iteration

```php
// FLAW: Variable persists across iterations
foreach ($items as $item) {
  if ($item->hasDiscount()) {
    $discount = $item->getDiscount();
  }
  $total += $item->price - $discount;  // Uses old $discount if current item has none!
}

// FIX: Reset or always assign
foreach ($items as $item) {
  $discount = 0;  // Reset each iteration
  if ($item->hasDiscount()) {
    $discount = $item->getDiscount();
  }
  $total += $item->price - $discount;
}
```

---

## Flow Issues

### 1. Unreachable Code

```php
// FLAW: Code after return never runs
function process($data) {
  if (empty($data)) {
    return false;
  }
  return true;

  logProcessing($data);  // NEVER EXECUTED
}

// FIX: Move logging before returns
```

### 2. Missing Return Statement

```php
// FLAW: Not all paths return value
function getStatus($user) {
  if ($user->isActive()) {
    return 'active';
  }
  // MISSING: No return for inactive users
}

// FIX: Ensure all paths return
function getStatus($user) {
  if ($user->isActive()) {
    return 'active';
  }
  return 'inactive';
}
```

### 3. Early Return Skips Cleanup

```php
// FLAW: Lock never released if error
function process($id) {
  acquireLock($id);

  if ($error) {
    return false;  // BUG: Lock still held!
  }

  $result = doWork($id);
  releaseLock($id);
  return $result;
}

// FIX: Release in all paths
function process($id) {
  acquireLock($id);

  if ($error) {
    releaseLock($id);
    return false;
  }

  $result = doWork($id);
  releaseLock($id);
  return $result;
}
// OR use try/finally
```

---

## Contract Violations

### 1. Missing Abstract Method Implementation

```php
// Parent class:
abstract class ActionBase {
  abstract public function execute(): void;
}

// FLAW: Doesn't implement required method
class MyAction extends ActionBase {
  // Missing execute() method - Fatal error!
}

// FIX: Implement all abstract methods
class MyAction extends ActionBase {
  public function execute(): void {
    // Implementation
  }
}
```

### 2. Wrong Interface Signature

```php
// Interface:
interface HandlerInterface {
  public function handle(Request $request): Response;
}

// FLAW: Wrong parameter type
class MyHandler implements HandlerInterface {
  public function handle(array $request): Response {
    //                    ^^^^^ Should be Request object
  }
}

// FIX: Match interface signature exactly
public function handle(Request $request): Response {
```

### 3. Missing Parent Constructor Call

```php
// Parent:
class ControllerBase {
  protected $logger;

  public function __construct(LoggerInterface $logger) {
    $this->logger = $logger;
  }
}

// FLAW: Doesn't call parent constructor
class MyController extends ControllerBase {
  public function __construct(LoggerInterface $logger, OtherService $other) {
    $this->other = $other;
    // BUG: $this->logger never set!
  }
}

// FIX: Call parent::__construct()
public function __construct(LoggerInterface $logger, OtherService $other) {
  parent::__construct($logger);
  $this->other = $other;
}
```

### 4. Plugin Missing Required Annotation Fields

```php
// FLAW: Missing required 'id' field
#[Action(
  label: new TranslatableMarkup("My Action")
)]
class MyAction extends ActionBase { }
// Plugin won't be discovered!

// FIX: Add all required fields
#[Action(
  id: "my_action",
  label: new TranslatableMarkup("My Action")
)]
```

---

## Dependency Errors

### 1. Method Doesn't Exist

```php
// FLAW: AI invented method name
$storage->loadMultipleByProperties(['status' => 1]);
// Method doesn't exist!

// FIX: Check actual interface
$storage->loadByProperties(['status' => 1]);
```

### 2. Wrong Return Type Assumption

```php
// FLAW: Assumes returns single entity
$mapping = $storage->loadByProperties(['id' => $id]);
$name = $mapping->label();
// FATAL: loadByProperties returns ARRAY, not entity

// FIX: Handle array return
$mappings = $storage->loadByProperties(['id' => $id]);
$mapping = reset($mappings);
if ($mapping) {
  $name = $mapping->label();
}
```

### 3. Service Doesn't Exist

```php
// FLAW: Service not registered
public function __construct(
  private CustomApiClient $apiClient  // Not in container!
) {}

// FIX: Verify service exists in services.yml
// OR use correct service name
```

### 4. Missing Exception Handling

```php
// FLAW: External call can throw
$result = $httpClient->get($url);
$data = json_decode($result->getBody());
// If request fails: Uncaught exception crashes

// FIX: Wrap in try/catch
try {
  $result = $httpClient->get($url);
  $data = json_decode($result->getBody());
} catch (RequestException $e) {
  // Handle error
}
```

---

## AI-Generated Code Specific

### 1. Hallucinated Methods

```php
// AI invents plausible method names:
$entity->getFieldValue('field_name');  // Doesn't exist
$user->getFullName();  // Doesn't exist
$service->fetchAllActive();  // Doesn't exist

// Actual methods:
$entity->get('field_name')->value;
$user->get('field_first_name')->value . ' ' . $user->get('field_last_name')->value;
$service->loadByProperties(['active' => TRUE]);
```

### 2. Mixed API Versions

```php
// AI uses Drupal 7 in Drupal 10 code:
$node = node_load($nid);  // Old API!
$account = user_load($uid);  // Old API!

// Correct D10:
$node = Node::load($nid);
$account = User::load($uid);
```

### 3. Wrong Parameter Order

```php
// AI guesses parameter order:
$url = Url::fromRoute($params, 'route.name');  // WRONG order

// Actual signature:
$url = Url::fromRoute('route.name', $params);
```

---

## Quick Flaw Detection Checklist

When tracing code, watch for:

**Variables:**
- [ ] Initialized before use?
- [ ] Used after assignment?
- [ ] Correct type?

**Conditionals:**
- [ ] Right comparison operator (=, ==, ===)?
- [ ] Logic correct (not inverted)?
- [ ] All branches return/handle?

**Loops:**
- [ ] Start/end indices correct?
- [ ] Variables reset each iteration?
- [ ] Handles empty collection?

**Function Calls:**
- [ ] Method exists?
- [ ] Parameters correct order/type?
- [ ] Return type handled correctly?
- [ ] Null/error cases handled?

**Objects:**
- [ ] Null check before property access?
- [ ] Object exists before method call?

**Arrays:**
- [ ] Key exists before access?
- [ ] Handles empty array?

**Contracts:**
- [ ] All abstract methods implemented?
- [ ] Interface signatures match?
- [ ] Parent constructors called?

---

## Flaw Documentation Template

```
FLAW FOUND:
  Line [N]: [Description of issue]

  Current behavior:
    [What happens now]

  Expected behavior:
    [What should happen]

  Root cause:
    [Why the bug exists]

  Impact:
    [What breaks - fatal error? Wrong data? Security issue?]

  FIX:
    [Specific code change needed]

  Test case to verify:
    INPUT: [values that trigger bug]
    EXPECTED: [correct output after fix]
```
