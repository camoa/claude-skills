# Auditing AI-Generated Code

AI (LLMs) generates code based on patterns, not actual knowledge of your codebase. This creates specific risks that paper testing helps catch.

## Contents

- [Common AI Code Problems](#common-ai-code-problems)
- [How to Catch AI Assumptions](#how-to-catch-ai-assumptions)
- [Paper Test Notation for AI Code](#paper-test-notation-for-ai-code)
- [Red Flags in AI Code](#red-flags-in-ai-code)
- [Verification Checklist](#verification-checklist-for-ai-code)
- [Example - Catching AI Hallucination](#example---catching-ai-hallucination)

---

## Common AI Code Problems

| Problem | Example |
|---------|---------|
| **Invented methods** | Calls `$entity->getFieldValue()` but method is actually `$entity->get()` |
| **Wrong return types** | Assumes method returns array, actually returns object |
| **Wrong parameters** | Passes `(id, type)` but signature is `(type, id)` |
| **Mixed APIs** | Uses Drupal 7 pattern in Drupal 10 code |
| **Assumed existence** | Calls service that doesn't exist in the container |
| **Wrong namespace** | Imports class from wrong module |

---

## How to Catch AI Assumptions

During paper test, for every external call AI wrote:

1. **Verify the method exists** - Check the actual class
2. **Verify the signature** - Parameters in right order? Right types?
3. **Verify return type** - What does it actually return?
4. **Verify the import** - Is the namespace correct?

**NEVER trust AI code without verification** - AI generates plausible code, not necessarily correct code.

---

## Paper Test Notation for AI Code

Mark AI assumptions explicitly during tracing:

```
Line 15: $mapping = $this->mappingStorage->loadByProperties(['status' => 1]);

AI ASSUMPTION CHECK:
  - Method exists? → CHECK: Yes, from ConfigEntityStorage
  - Parameters? → CHECK: Takes array of conditions
  - Returns? → PROBLEM: AI assumes returns single entity
                ACTUAL: Returns array of entities

FLAW: AI assumed loadByProperties returns one entity, returns array.
FIX: Use reset($mapping) or loop through results.
```

This makes assumptions visible and catchable.

---

## Red Flags in AI Code

Watch for these patterns that often indicate AI assumptions:

### 1. Chained Method Calls

```php
// Red flag: Did AI verify each method exists?
$value = $entity->getMapping()->getSalesforceId()->getValue();
```

**What to check:**
- Does `getMapping()` exist?
- Does it return an object with `getSalesforceId()`?
- Does that return an object with `getValue()`?
- What if any step returns null?

### 2. Specific Method Names

```php
// Red flag: Might be invented
$result = $service->fetchAllActiveRecords();

// Red flag: Very specific helper
$user = $userRepository->findByEmailAndStatus($email, 'active');
```

**What to check:**
- Does this exact method name exist?
- Or did AI invent a plausible-sounding name?

### 3. Assumed Data Structures

```php
// Red flag: Assumed nested array structure
$name = $response['data']['user']['name'];

// Red flag: Assumed object property
$id = $result->data->id;
```

**What to check:**
- Is this the actual structure returned?
- What if keys don't exist?
- What if nesting is different?

### 4. Framework-Specific Helpers

```php
// Red flag: Right version? Right parameters?
$url = Url::fromRoute('entity.node.canonical', ['node' => $nid]);

// Red flag: D7 pattern in D10 code
$node = node_load($nid);  // Old API!
```

**What to check:**
- Is this the current API version?
- Are parameters in correct order?
- Does route name exist?

### 5. Assumed Constants/Enums

```php
// Red flag: Does this constant exist?
if ($status === Node::STATUS_PUBLISHED) { }

// Red flag: Right enum value?
$entity->setStatus(EntityStatus::ACTIVE);
```

**What to check:**
- Does constant exist on that class?
- Is the value correct?

### 6. Service Assumptions

```php
// Red flag: Does this service exist in container?
$this->customApiClient->send($data);

// Red flag: Right service method?
$this->logger->logError($message);  // Might be error(), not logError()
```

**What to check:**
- Is service registered?
- Is method name correct?
- Is interface imported?

---

## Verification Checklist for AI Code

For each external dependency in AI-generated code:

- [ ] Class/service exists in codebase
- [ ] Method exists on that class
- [ ] Method signature matches (parameter order, types)
- [ ] Return type matches AI's usage
- [ ] Namespace/import is correct
- [ ] API version matches project (D10 vs D9, React 18 vs 17, etc.)
- [ ] Null/error cases handled
- [ ] Data structure assumptions verified

---

## Example - Catching AI Hallucination

### AI Generated Code:

```php
public function execute($entity = NULL): void {
  $fields = $this->salesforceClient->describeObject('Contact')->getFields();

  foreach ($fields as $field) {
    $value = $entity->getFieldValue($field->name);
    $this->salesforceClient->updateField('Contact', $entity->id(), $field->name, $value);
  }
}
```

### Paper Test with Verification:

```
PAPER TEST: AI-generated Salesforce field sync

SCENARIO: Update Contact fields
INPUT: $entity = Node{id: 123, type: 'contact'}

---

LINE 2: $fields = $this->salesforceClient->describeObject('Contact')->getFields();

AI ASSUMPTION CHECK:
  Method: describeObject()

  Verify method exists:
    → Checked RestClientInterface
    → PROBLEM: Method is objectDescribe(), not describeObject()
    → AI HALLUCINATION: Invented plausible method name

  Verify return:
    → objectDescribe() returns RestResponseDescribe object
    → Has getFields() method? → YES, verified exists
    → getFields() returns: array of field descriptor objects

FLAW FOUND #1:
  Line 2: AI invented method name "describeObject"
  ACTUAL: Method is "objectDescribe"
  FIX: $this->salesforceClient->objectDescribe('Contact')->getFields()

---

LINE 4: $value = $entity->getFieldValue($field->name);

AI ASSUMPTION CHECK:
  Method: getFieldValue()

  Verify method exists:
    → Checked EntityInterface
    → PROBLEM: Method does not exist
    → ACTUAL: Method is get($field_name)->value or $entity->get($field_name)->getString()
    → AI HALLUCINATION: Invented convenient method

  Verify field name handling:
    → $field->name might be Salesforce field (e.g., "FirstName")
    → Need to map to Drupal field (e.g., "field_first_name")
    → AI missed mapping step entirely

FLAW FOUND #2:
  Line 4: Method getFieldValue() doesn't exist
  FIX: Use $entity->get($drupal_field_name)->value

FLAW FOUND #3:
  Line 4: No field mapping from Salesforce to Drupal
  FIX: Add mapping lookup before get()

---

LINE 5: $this->salesforceClient->updateField('Contact', $entity->id(), $field->name, $value);

AI ASSUMPTION CHECK:
  Method: updateField()

  Verify method exists:
    → Checked RestClientInterface
    → PROBLEM: No updateField() method exists
    → ACTUAL: Must use objectUpdate() with full object data
    → AI HALLUCINATION: Invented granular update method

  Verify parameters:
    → Even if method existed, parameter order seems wrong
    → Usually: (object_type, object_id, data) not individual fields

FLAW FOUND #4:
  Line 5: Method updateField() doesn't exist
  ACTUAL API: objectUpdate(string $name, array $data)
  FIX: Collect all field values, then call objectUpdate() once

---

FLAWS SUMMARY:
1. describeObject() → objectDescribe() (hallucinated method name)
2. getFieldValue() doesn't exist (hallucinated convenience method)
3. Missing Salesforce-to-Drupal field mapping
4. updateField() doesn't exist (hallucinated granular update)
5. Should batch update, not update field-by-field

CORRECTED CODE:
```php
public function execute($entity = NULL): void {
  // Get Salesforce field definitions
  $sf_fields = $this->salesforceClient->objectDescribe('Contact')->getFields();

  // Build update data
  $data = [];
  foreach ($sf_fields as $sf_field) {
    // Map Salesforce field to Drupal field
    $drupal_field = $this->fieldMapping->toDrupalField($sf_field->name);

    if ($entity->hasField($drupal_field)) {
      $field = $entity->get($drupal_field);
      if (!$field->isEmpty()) {
        $data[$sf_field->name] = $field->value;
      }
    }
  }

  // Single update call with all fields
  $salesforce_id = $this->getSalesforceId($entity);
  $this->salesforceClient->objectUpdate('Contact', $salesforce_id, $data);
}
```

---

## Common AI Hallucination Patterns

### Pattern 1: Convenience Methods

AI invents methods that "should" exist but don't:

```php
// AI generates:
$user->getFullName();  // Doesn't exist
// Actual:
$user->get('field_first_name')->value . ' ' . $user->get('field_last_name')->value;

// AI generates:
$entity->setFieldValue('field_name', $value);  // Doesn't exist
// Actual:
$entity->set('field_name', $value);
```

### Pattern 2: Wrong API Version

AI mixes patterns from different versions:

```php
// AI generates (Drupal 7 in D10):
$node = node_load($nid);
// D10 actual:
$node = Node::load($nid);

// AI generates (old Symfony):
$request->get('param');
// Current:
$request->query->get('param');
```

### Pattern 3: Plausible Names

AI generates method names that sound right:

```php
// AI generates:
$storage->findByStatus('published');  // Sounds right, doesn't exist
// Actual:
$storage->loadByProperties(['status' => 'published']);

// AI generates:
$repository->getAllActive();  // Sounds right, doesn't exist
// Actual:
$repository->findBy(['active' => true]);
```

### Pattern 4: Wrong Return Assumptions

AI assumes convenient return types:

```php
// AI assumes:
$user = $repository->find($id);  // Assumes single User
// Actually returns:
$users = $repository->find($id);  // Returns array!

// AI assumes:
$result = $service->process($data);  // Assumes direct value
// Actually:
$result = $service->process($data);  // Returns Result object with ->getData()
```

---

## AI Code Testing Strategy

### Phase 1: Syntax Check

Run linter/static analysis:
- Catches undefined methods immediately
- Catches wrong parameter counts
- Catches type mismatches

### Phase 2: Paper Test with Verification

For each external call:
1. Find actual class/service
2. Verify method exists
3. Verify signature
4. Verify return type
5. Verify error handling

### Phase 3: Run Tests

After paper test fixes:
- Unit tests catch remaining issues
- Integration tests catch API mismatches
- But paper test catches 80% before running

---

## Quick Verification Template

```
LINE [N]: [AI-generated code]

AI VERIFICATION:
  Class/Service: [name]
    → Exists? [YES/NO]
    → Imported from: [correct namespace?]

  Method: [name]
    → Exists? [YES/NO]
    → Signature: [actual signature]
    → AI used: [what AI assumed]
    → Match? [YES/NO]

  Return type:
    → Actually returns: [type]
    → AI assumes: [type]
    → Match? [YES/NO]

  Edge cases:
    → Handles null? [YES/NO]
    → Handles empty? [YES/NO]
    → Handles errors? [YES/NO]

RESULT:
  [ ] VERIFIED - code is correct
  [ ] FLAW FOUND - [description]
        FIX: [correction]
```

---

## Summary

**AI code is plausible, not verified.**

Every external call in AI-generated code is an assumption that needs verification:
- Method names (might be invented)
- Parameter order (might be wrong)
- Return types (might be assumed)
- API versions (might be mixed)
- Error handling (might be missing)

**Paper testing with verification catches these before deployment.**
