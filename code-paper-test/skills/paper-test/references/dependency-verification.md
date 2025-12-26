# External Dependency Verification

How to verify external calls during paper testing - don't assume, know.

## Contents

- [The Problem with Assumptions](#the-problem-with-assumptions)
- [What to Do](#what-to-do)
- [Common Dependency Questions](#common-dependency-questions)
- [Verification Methods](#verification-methods)
- [Dependency Types](#dependency-types)
- [Example - Dependency Bug](#example---dependency-bug)

---

## The Problem with Assumptions

When you hit a function call, API request, database query, or library method - **stop and understand what it actually does**.

```php
Line 15: $user = $userService->loadByEmail($email);
         → assume returns User object
```

This assumption could be wrong. The method might:
- Return `null` when not found
- Throw an exception when not found
- Return an empty array
- Return a different object type

**Paper testing rule:** For EVERY external call, verify actual behavior - don't guess.

---

## What to Do

### Option 1: Read the Source

Look at the actual implementation. Know the real behavior.

```php
// Checked UserService::loadByEmail()
// - Returns User object if found
// - Returns NULL if not found (does not throw)
// - Throws InvalidArgumentException if email is empty

Line 15: $user = $userService->loadByEmail($email);
         → KNOWN: returns User|null, throws on empty email
         → $email = "test@example.com" (not empty)
         → assume found: $user = User{id: 42}
```

### Option 2: Read the Documentation

If source isn't available, check official docs.

```
Line 15: $user = $userService->loadByEmail($email);
         → DOCS: "Returns User object or null if not found"
         → VERIFIED: Safe to assume User|null
```

### Option 3: Mark as Unknown Risk

If you can't verify, flag it as a potential flaw source.

```php
Line 15: $user = $userService->loadByEmail($email);
         → UNKNOWN: Need to verify return type when not found
         → RISK: Line 16 assumes $user is object, might be null
```

---

## Common Dependency Questions

Ask these for EVERY external call:

| Question | Why It Matters |
|----------|----------------|
| What does it return on success? | Know the exact type and structure |
| What does it return on "not found"? | null? empty array? false? |
| Does it throw exceptions? When? | Uncaught exceptions break flow |
| Does it have side effects? | Modifies database? Sends email? |
| Is it synchronous or async? | Might not have result immediately |
| What are the edge cases? | Empty input? Special characters? |

---

## Verification Methods

### Method 1: Read Implementation

```
DEPENDENCY CHECK: UserService::loadByEmail()

SOURCE REVIEW:
  File: src/Service/UserService.php:42

  Implementation:
    public function loadByEmail(string $email): ?User {
      if (empty($email)) {
        throw new InvalidArgumentException('Email cannot be empty');
      }

      $user = $this->repository->findOneBy(['email' => $email]);
      return $user;  // returns User or null
    }

VERIFIED BEHAVIOR:
  - Returns: User object if found
  - Returns: null if not found
  - Throws: InvalidArgumentException if empty string
  - Side effects: None (read-only query)
```

### Method 2: Read Interface/Contract

```
DEPENDENCY CHECK: LoggerInterface::info()

INTERFACE REVIEW:
  File: vendor/psr/log/src/LoggerInterface.php:25

  Signature:
    public function info(string $message, array $context = []): void

  Documentation:
    "Logs informational message. Does not throw exceptions."

VERIFIED BEHAVIOR:
  - Parameter 1: string $message (required)
  - Parameter 2: array $context (optional, defaults to [])
  - Returns: void (no return value)
  - Throws: None (guaranteed not to throw)
```

### Method 3: Read Documentation

```
DEPENDENCY CHECK: EntityTypeManagerInterface::getStorage()

OFFICIAL DOCS:
  URL: api.drupal.org/EntityTypeManagerInterface::getStorage

  Signature:
    public function getStorage(string $entity_type): EntityStorageInterface

  Documentation:
    "Gets the storage handler for an entity type."
    "Throws InvalidPluginDefinitionException if storage handler cannot be loaded."
    "Throws PluginNotFoundException if entity type does not exist."

VERIFIED BEHAVIOR:
  - Returns: EntityStorageInterface object (always)
  - Throws: InvalidPluginDefinitionException
  - Throws: PluginNotFoundException
  - Never returns null
```

### Method 4: Test/Inspect

If source and docs unavailable:

```
DEPENDENCY CHECK: $externalApi->fetchData()

INSPECTION METHOD:
  - Wrote test calling fetchData() with various inputs
  - Observed: Returns array on success
  - Observed: Returns empty array on not found
  - Observed: Throws HttpException on network error

VERIFIED BEHAVIOR:
  - Returns: array (always, never null)
  - Empty array: when no results
  - Throws: HttpException on failure
```

---

## Dependency Types

### Service Methods

```php
Line 10: $entity = $this->entityTypeManager->getStorage('node')->load($id);
```

**What to verify:**
- `getStorage()` - returns what? throws what?
- `load()` - returns what when ID doesn't exist?

**Verification:**
```
DEPENDENCY: EntityTypeManagerInterface::getStorage()
  Returns: EntityStorageInterface
  Throws: InvalidPluginDefinitionException, PluginNotFoundException

DEPENDENCY: EntityStorageInterface::load()
  Returns: EntityInterface|null
  Returns null when: ID doesn't exist
  Throws: None
```

### Database Queries

```php
Line 15: $user = $connection->query('SELECT * FROM users WHERE id = :id', [':id' => $id])->fetchObject();
```

**What to verify:**
- Does `query()` return a result object even if no rows?
- Does `fetchObject()` return null or false when no rows?

**Verification:**
```
DEPENDENCY: Connection::query()
  Returns: StatementInterface (always, even if 0 rows)
  Throws: DatabaseExceptionWrapper on SQL error

DEPENDENCY: StatementInterface::fetchObject()
  Returns: stdClass object if row exists
  Returns: FALSE if no rows (not null!)
  Note: Check with === false, not !
```

### API Calls

```php
Line 20: $response = $httpClient->get('https://api.example.com/users/' . $id);
```

**What to verify:**
- Does it throw on 404?
- What object does it return?
- What properties/methods on response object?

**Verification:**
```
DEPENDENCY: HttpClient::get()
  Returns: Response object on 2xx status
  Throws: ClientException on 4xx status (including 404)
  Throws: ServerException on 5xx status
  Throws: NetworkException on connection failure

DEPENDENCY: Response object
  Methods:
    - getStatusCode(): int
    - getBody(): StreamInterface
    - getBody()->getContents(): string (JSON or text)
```

### Framework/Library Functions

```php
Line 25: $decoded = json_decode($json, true);
```

**What to verify:**
- What does it return on malformed JSON?
- Does second parameter affect return type?

**Verification:**
```
DEPENDENCY: json_decode()
  Signature: json_decode(string $json, bool $assoc = false, ...)

  Returns when $assoc = true:
    - array if valid JSON object/array
    - null if malformed JSON
    - null if input is "null"

  Returns when $assoc = false:
    - stdClass object if valid JSON object
    - array if valid JSON array
    - null if malformed JSON

  Note: Cannot distinguish malformed from valid "null" without json_last_error()
```

### Plugin/Service Methods

```php
Line 30: $result = $this->myPlugin->process($data);
```

**What to verify:**
- Read the plugin base class or interface
- What does `process()` return?
- What parameters does it expect?

**Verification:**
```
DEPENDENCY: MyPluginInterface::process()
  Interface location: src/Plugin/MyPluginInterface.php

  Signature: public function process(array $data): ProcessResult

  Returns: ProcessResult object (always)
  Throws: ProcessException if $data invalid
  Side effects: May write to cache

  ProcessResult methods:
    - isSuccess(): bool
    - getData(): array
    - getErrors(): array
```

---

## Dependency Types

### 1. Internal Methods (Same Class)

```php
Line 5: $result = $this->calculateTotal($items);
```

**Verify:**
- Read `calculateTotal()` method in same class
- Check return type, exceptions, side effects

### 2. Injected Services

```php
Line 10: $user = $this->userService->loadByEmail($email);
```

**Verify:**
- Find service interface in constructor
- Read interface for method signature
- Read implementation if interface unclear

### 3. Static/Global Functions

```php
Line 15: $config = \Drupal::config('my_module.settings');
```

**Verify:**
- Read framework documentation
- Check what object type is returned
- Check what methods available on returned object

### 4. Database/ORM

```php
Line 20: $entity = Node::load($id);
```

**Verify:**
- Check ORM documentation
- Returns object or null?
- Throws exceptions?

### 5. External APIs

```php
Line 25: $data = $client->fetchData($endpoint);
```

**Verify:**
- API documentation
- Response structure
- Error handling (exceptions, status codes, null)

### 6. Library/Package Methods

```php
Line 30: $hash = password_hash($password, PASSWORD_BCRYPT);
```

**Verify:**
- PHP/library documentation
- Return type
- Failure modes (returns false? throws?)

---

## Example - Dependency Bug

```php
function findActiveUsers($emails) {
  $users = [];
  foreach ($emails as $email) {
    $user = $this->repository->findByEmail($email);
    if ($user->isActive()) {  // BUG: assumes $user is object
      $users[] = $user;
    }
  }
  return $users;
}
```

Paper test with dependency verification:

```
SCENARIO: One email doesn't exist in database
INPUT: $emails = ["exists@test.com", "notfound@test.com"]

DEPENDENCY CHECK: repository->findByEmail()
  File: src/Repository/UserRepository.php:50
  Signature: public function findByEmail(string $email): ?User
  Returns: User if found, NULL if not found
  Throws: None

TRACE:
Iteration 1: $email = "exists@test.com"
  Line 4: $user = repository->findByEmail("exists@test.com")
          → VERIFIED: returns User{id: 1, active: true}
  Line 5: if ($user->isActive())
          → true, adds to $users

Iteration 2: $email = "notfound@test.com"
  Line 4: $user = repository->findByEmail("notfound@test.com")
          → VERIFIED: returns NULL (not found)
  Line 5: if ($user->isActive())
          → FATAL ERROR: Calling isActive() on null

OUTPUT:
  Fatal error on line 5, iteration 2

FLAW FOUND:
  Line 5: No null check before calling method on $user
  FIX: Add null check:
    if ($user && $user->isActive()) {
```

**Without checking what `findByEmail` returns, this bug is invisible.**

---

## Verification Template

Use this for every external call:

```
DEPENDENCY CHECK: [ServiceName::methodName()]

LOCATION:
  File: [path to file]
  Line: [line number]
  Signature: [full method signature]

BEHAVIOR:
  Returns on success: [type and value]
  Returns on failure: [null | false | empty array | etc.]
  Throws: [exception types and when]
  Side effects: [database writes | API calls | cache | etc.]

EDGE CASES:
  - Empty input: [behavior]
  - Null input: [behavior]
  - Invalid input: [behavior]

VERIFICATION METHOD:
  [ ] Read source code
  [ ] Read interface/docs
  [ ] Tested manually
  [ ] Unable to verify (mark as RISK)

USAGE IN CODE:
  Line [N]: [how it's used]
  Handles null: [YES/NO]
  Handles exceptions: [YES/NO]
  Assumes: [what assumptions made]
```

---

## AI-Generated Code Risks

AI models often invent methods that don't exist. Always verify:

**Common AI inventions:**
- Methods with plausible names that don't exist
- Wrong parameter order (common in similar APIs)
- Wrong return types
- Mixing different framework versions

**Example:**
```php
// AI might generate:
$user = $userService->getByEmail($email);  // Method doesn't exist!

// Actual method:
$user = $userService->loadByEmail($email);  // Correct method name
```

**Protection:** Verify EVERY external method exists and has correct signature.

---

## Quick Checklist

For every external call in the code:

- [ ] What does it return on success?
- [ ] What does it return on failure/not found?
- [ ] Does it throw exceptions? Which ones?
- [ ] What are the side effects?
- [ ] Are parameter types correct?
- [ ] Is return type handled correctly in my code?
- [ ] Are edge cases (null, empty, invalid) handled?

**If you can't answer these, the code is untested.**
