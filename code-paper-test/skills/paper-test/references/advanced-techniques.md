# Advanced Paper Testing Techniques

Decision-focused techniques adapted from security tabletop exercises for complex code testing.

## Contents

- [When to Use Advanced Techniques](#when-to-use-advanced-techniques)
- [Progressive Inject Testing](#progressive-inject-testing)
- [Red Team Edge Case Discovery](#red-team-edge-case-discovery)
- [Attack Surface Analysis](#attack-surface-analysis)
- [Scenario-Based Workflow Testing](#scenario-based-workflow-testing)
- [After-Action Report Format](#after-action-report-format)

---

## When to Use Advanced Techniques

| Technique | Use When | Skip When | Benefit |
|-----------|----------|-----------|---------|
| **Progressive Injects** | Complex workflows, multiple dependencies, cascading failures | Simple functions, isolated logic | Finds interaction bugs, tests resilience |
| **Red Team Testing** | Security-critical code, public APIs, user input handling | Internal utilities, trusted inputs | Discovers edge cases developers miss |
| **Attack Surface** | Multiple entry points, prioritizing test effort | Single entry point | Focuses testing on highest risk |
| **Scenario Workflows** | End-to-end features, multi-step processes | Single operations | Tests realistic usage patterns |
| **AAR Format** | Complex findings, multiple issues, team review | Simple bugs | Structured documentation, root cause analysis |

**Decision Rule**: Use standard paper testing for simple code. Use advanced techniques when:
- Code has 3+ external dependencies
- Multiple components interact
- Security or reliability critical
- Complex business logic
- Real-world usage requires multi-step flows

---

## Progressive Inject Testing

### Concept

Test scenarios progressively increase in complexity through "inject cards" - each inject adds complications that force code to adapt.

Adapted from security tabletop exercises where facilitators inject new developments to test team adaptability.

### When to Use

- **Multi-step workflows**: Authentication, checkout, data processing pipelines
- **Dependency chains**: Service A calls Service B calls Service C
- **Resource constraints**: Memory, time, connections
- **Failure scenarios**: What happens when step 3 fails after steps 1-2 succeeded?

### Template

```
BASE SCENARIO: [Happy path]
INPUT: [Ideal conditions]

INJECT 1: [Edge case data]
  What changes: [Describe complication]
  Expected behavior: [How code should adapt]

INJECT 2: [Resource constraint]
  What changes: [Describe limitation]
  Expected behavior: [Graceful degradation]

INJECT 3: [Concurrent access]
  What changes: [Race condition, timing]
  Expected behavior: [Atomicity, locks]

INJECT 4: [Infrastructure failure]
  What changes: [Service down, timeout]
  Expected behavior: [Fallback, retry, error]

INJECT 5: [Requirement change]
  What changes: [New validation rule]
  Expected behavior: [Code flexibility]
```

### Example: User Authentication Flow

```
BASE SCENARIO: Valid user login
INPUT:
  $username = "john_doe"
  $password = "correct_password"
  Database: Available, user exists
  Session store: Available, empty

TRACE:
Line 10: $user = $userRepository->findByUsername($username)
         → Returns User{id: 42, password_hash: "$2y$..."}

Line 12: if (password_verify($password, $user->password_hash))
         → TRUE, password matches

Line 15: $sessionId = $sessionService->create($user->id)
         → Returns "sess_abc123"

Line 17: return new LoginResponse(success: true, sessionId: "sess_abc123")

OUTPUT: Successful login
FLAWS: None in base scenario

---

INJECT 1: Database is slow (3-second query time)

What changes: Database query takes 3 seconds
Expected: Timeout handling, user feedback

TRACE:
Line 10: $user = $userRepository->findByUsername($username)
         → Takes 3 seconds to return

DEPENDENCY CHECK: userRepository->findByUsername()
  - Has timeout configured? [Need to verify]
  - Read UserRepository.php

VERIFICATION:
  - [ ] Query timeout set
  - [ ] User shown loading state
  - [ ] Timeout doesn't cause crash

FLAW FOUND:
  No query timeout configured - could hang indefinitely
  FIX: Add 5-second database query timeout

---

INJECT 2: Session store is full

What changes: $sessionService->create() fails
Expected: Error handling, user notification

TRACE:
Line 15: $sessionId = $sessionService->create($user->id)
         → THROWS SessionStorageException("Storage full")

Line 17: NOT REACHED (exception thrown)

FLAW FOUND:
  No try/catch around session creation
  User sees generic error page instead of helpful message
  FIX: Wrap in try/catch, return LoginResponse(success: false, error: "Service unavailable")

---

INJECT 3: Concurrent login from different device

What changes: User logs in twice simultaneously
Expected: Invalidate old session or allow multiple sessions?

SCENARIO:
  Request A: Login from laptop (started)
  Request B: Login from phone (started 100ms later)

TRACE Request A:
Line 15: $sessionId = $sessionService->create($user->id)
         → Creates "sess_laptop_xyz"

TRACE Request B (concurrent):
Line 15: $sessionId = $sessionService->create($user->id)
         → Creates "sess_phone_abc"

RESULT: Both sessions active simultaneously

SECURITY CHECK:
  - Is concurrent session allowed by policy? [Need business rule]
  - Should old session be invalidated?
  - Session hijacking risk if not tracked?

FLAW FOUND (POTENTIAL):
  No policy enforcement on concurrent sessions
  RECOMMENDATION: Define business rule, implement session limit or invalidation

---

INJECT 4: Password verification is timing-attackable

What changes: password_verify() takes different times for wrong vs. right password
Expected: Constant-time comparison

SECURITY ANALYSIS:
Line 12: if (password_verify($password, $user->password_hash))

password_verify() is DESIGNED to be constant-time (bcrypt property)
VERIFIED: Not vulnerable to timing attack

FLAW: None

---

INJECT 5: Requirement change: Now needs 2FA

What changes: After password verification, must check 2FA token
Expected: Code can be extended without major refactor

ANALYSIS:
Current code: password verify → create session → return

To add 2FA:
  - Need to check if user has 2FA enabled
  - If enabled, verify token before creating session
  - Return different response if 2FA required

FLEXIBILITY CHECK:
  - Can insert 2FA check between lines 12 and 15? YES
  - Clean extension point or major refactor? CLEAN

FLAW: None - code structure allows clean extension
```

### Progressive Testing Findings Summary

```
PROGRESSIVE TEST RESULTS: User Authentication

Inject 1 (Slow Database):
  ❌ No query timeout - could hang indefinitely
  FIX: Add 5-second timeout

Inject 2 (Session Storage Full):
  ❌ No exception handling - user sees generic error
  FIX: Try/catch with user-friendly message

Inject 3 (Concurrent Login):
  ⚠️  No concurrent session policy
  FIX: Define business rule, implement enforcement

Inject 4 (Timing Attack):
  ✅ password_verify() already constant-time

Inject 5 (2FA Requirement):
  ✅ Code structure allows clean extension

OVERALL: Found 2 bugs, 1 policy gap that wouldn't be found in basic testing.
```

---

## Red Team Edge Case Discovery

### Concept

Adversarial mindset: Think like an attacker trying to break code. Ask "What if I intentionally do the WRONG thing?"

Adapted from security red team exercises where attackers identify vulnerabilities.

### When to Use

- **Public APIs**: External input, untrusted sources
- **Security boundaries**: Authentication, authorization, payment
- **Resource management**: Memory, connections, files
- **State machines**: Can I force invalid state transitions?

### Red Team Questions

**Input Validation:**
- "What if I send null instead of object?"
- "What if I send empty string instead of required field?"
- "What if I send 1 billion characters?"
- "What if I send special characters: `<>\"'&;`?"
- "What if I send negative number for positive field?"
- "What if I send SQL injection: `'; DROP TABLE users;--`?"
- "What if I send script injection: `<script>alert('xss')</script>`?"

**Resource Exhaustion:**
- "What if I call this 10,000 times per second?"
- "What if I upload 10GB file?"
- "What if I create infinite loop by making entity reference itself?"
- "What if I exhaust database connections?"
- "What if I fill all available memory?"

**Race Conditions:**
- "What if I call this twice simultaneously?"
- "What if I modify data while it's being read?"
- "What if I delete object while another process uses it?"

**State Manipulation:**
- "What if I skip step 2 and go directly to step 3?"
- "What if I call finalize() before initialize()?"
- "What if I access object before it's fully constructed?"
- "What if I trigger the same state transition twice?"

**Privilege Escalation:**
- "What if I modify my user ID in the request?"
- "What if I access admin endpoint as regular user?"
- "What if I modify permission check to always return true?"

### Example: Red Team Testing Payment Processing

```
RED TEAM ANALYSIS: Payment Processing

CODE UNDER TEST:
```php
function processPayment($userId, $amount, $paymentMethod) {
  $user = loadUser($userId);
  $charge = $paymentGateway->charge($amount, $paymentMethod);

  if ($charge->success) {
    $order = createOrder($userId, $amount);
    sendConfirmation($user->email);
    return $order;
  }

  return null;
}
```

---

RED TEAM QUESTION 1: "What if I send negative amount?"

TRACE:
Line 2: $user = loadUser($userId)
        → Returns User{id: 42}

Line 3: $charge = $paymentGateway->charge(-100.00, $paymentMethod)
        → What does gateway do with negative amount?

DEPENDENCY CHECK: paymentGateway->charge()
  Need to verify: Does it reject negative amounts or process as refund?

ASSUMPTION RISK:
  If gateway processes -$100 as refund, attacker gets money!

FLAW FOUND:
  No input validation on $amount
  FIX: Add validation before line 3:
    if ($amount <= 0) { throw new InvalidArgumentException(); }

---

RED TEAM QUESTION 2: "What if I send someone else's user ID?"

SCENARIO:
  Attacker is user_id=999
  Sends request with $userId=42 (different user)

TRACE:
Line 2: $user = loadUser(42)
        → Returns victim's user object

Line 3: $charge = $paymentGateway->charge($amount, $paymentMethod)
        → Whose payment method? Function parameter (attacker's)

Line 6: $order = createOrder(42, $amount)
        → Order assigned to user_id=42 (victim)

RESULT: Attacker pays with their card, victim gets the order!

FLAW FOUND:
  No authorization check - userId from untrusted input
  FIX: Verify $userId matches authenticated user session

---

RED TEAM QUESTION 3: "What if payment succeeds but email fails?"

TRACE:
Line 6: $order = createOrder($userId, $amount)
        → Order created, database committed

Line 7: sendConfirmation($user->email)
        → THROWS EmailServiceException

Line 8: NOT REACHED (exception thrown)

RESULT:
  User charged, order created, but no confirmation sent
  User doesn't know purchase succeeded

FLAW FOUND:
  Email failure causes exception, user thinks payment failed
  Could result in duplicate charges if user retries

FIX:
  - Wrap email in try/catch, log failure but return success
  - OR use async email queue with retry logic
  - OR return order even if email fails, show success to user

---

RED TEAM QUESTION 4: "What if I call this twice simultaneously?"

SCENARIO:
  Request A: processPayment(userId=42, amount=100)
  Request B: processPayment(userId=42, amount=100) [100ms later]

BOTH TRACE:
Line 3: $charge = $paymentGateway->charge($amount, $paymentMethod)

Request A: Charges card $100, creates order
Request B: Charges card $100 AGAIN, creates DUPLICATE order

RESULT: User charged twice!

FLAW FOUND:
  No idempotency key - duplicate requests process separately
  FIX: Add idempotency check using request ID/nonce

---

RED TEAM SUMMARY:

ATTACK SURFACE: processPayment()
  Entry points: 3 parameters (userId, amount, paymentMethod)
  External dependencies: 4 (loadUser, paymentGateway, createOrder, sendConfirmation)

VULNERABILITIES FOUND:
1. Negative amount (input validation)
2. Arbitrary user ID (authorization)
3. Email failure causes user confusion (error handling)
4. Duplicate charges (idempotency)

SEVERITY:
  CRITICAL: #1, #2 (financial impact, security)
  MEDIUM: #4 (reliability)
  LOW: #3 (user experience)

FIXES REQUIRED: 4
```

---

## Attack Surface Analysis

### Concept

Map all entry points to code, rank by risk exposure, prioritize testing effort.

Adapted from security attack surface analysis for threat modeling.

### When to Use

- **Multiple entry points**: APIs, forms, file uploads, message queues
- **Limited testing time**: Need to prioritize highest-risk areas
- **Security-critical systems**: Must identify exposed attack surface
- **Complex codebases**: Unclear where to focus testing effort

### Process

```
1. IDENTIFY ENTRY POINTS
   - All inputs: user input, API calls, file reads, database queries, external services
   - List every way data enters the system

2. RANK BY EXPOSURE
   - External > Internal
   - User-controlled > System-controlled
   - Direct input > Derived data

3. PRIORITIZE TESTING
   - HIGH: Public APIs, user forms, file uploads
   - MEDIUM: Database queries, config files
   - LOW: Internal service calls, hardcoded values

4. DOCUMENT ATTACK SURFACE
   Entry point → Input type → Validation → Risk level

5. FOCUS PAPER TESTING
   Test HIGH/MEDIUM entry points first with red team mindset
```

### Example

```
ATTACK SURFACE ANALYSIS: E-commerce Checkout

ENTRY POINTS IDENTIFIED:

1. POST /api/checkout
   Input: {userId, cartItems[], shippingAddress, paymentMethod}
   Validation: Schema validation only
   Risk: HIGH (external, user-controlled, financial)

2. Database query: loadCart($userId)
   Input: $userId from session
   Validation: Integer type check
   Risk: MEDIUM (internal but could be tampered session)

3. External API: paymentGateway->charge()
   Input: amount, paymentMethod
   Validation: Gateway's validation
   Risk: MEDIUM (external dependency, financial)

4. File read: config/shipping_rates.yml
   Input: File path (hardcoded)
   Validation: None (trusted source)
   Risk: LOW (internal, system-controlled)

RISK RANKING:
  HIGH: /api/checkout endpoint
  MEDIUM: loadCart query, paymentGateway call
  LOW: config file read

TESTING PRIORITY:
1. Paper test /api/checkout with red team questions (highest risk)
2. Paper test loadCart with session tampering scenarios
3. Paper test paymentGateway error handling
4. Skip detailed testing of config file (low risk)

FOCUSED TESTING EFFORT:
  Spend 60% of time on /api/checkout
  Spend 30% on database/gateway interactions
  Spend 10% on everything else
```

---

## Scenario-Based Workflow Testing

### Concept

Test complete user workflows end-to-end, not isolated functions. Catch integration bugs that unit tests miss.

### When to Use vs. Standard Testing

| Use Scenario Testing | Use Standard Testing |
|---------------------|---------------------|
| Multi-step workflows | Single operations |
| Component integration | Isolated logic |
| Realistic user behavior | Edge cases within function |
| Data handoff between services | Pure calculations |

### Template

```
SCENARIO: [User story - what user is trying to accomplish]

WORKFLOW STEPS:
1. [User action]
2. [System response]
3. [User action]
4. [System response]
...

TRACE COMPLETE FLOW:
Step 1: [Component A]
  Line X: [code]
  Output: [data passed to next component]

Step 2: [Component B receives data from A]
  Line Y: [code]
  Check: Does data format match expectations?
  Output: [data passed to next component]

Step 3: [Component C receives data from B]
  ...

INTEGRATION CHECKS:
  - [ ] Data format compatible between components?
  - [ ] State consistent across steps?
  - [ ] Error in step N handled by step N+1?
  - [ ] Transaction boundaries correct?

FLAWS: [Issues found in integration, not individual components]
```

### Example

```
SCENARIO: User purchases item with discount coupon

WORKFLOW:
1. User adds item to cart
2. User enters coupon code
3. System validates coupon
4. System recalculates total
5. User proceeds to payment
6. Payment processes
7. Inventory updates
8. Order confirmation sent

---

STEP 1: Add item to cart (CartService)

Line 42: $cart = $this->getOrCreateCart($sessionId)
         → Returns Cart{id: 1, items: []}

Line 43: $cart->addItem($productId, $quantity)
         → Adds Product{id: 100, price: 50.00, qty: 2}

OUTPUT TO NEXT STEP:
  Cart state: {items: [{productId: 100, price: 50.00, qty: 2}]}

---

STEP 2: Enter coupon code (CouponController)

INPUT FROM USER: "SAVE20"

Line 55: $coupon = $couponRepository->findByCode("SAVE20")
         → Returns Coupon{code: "SAVE20", discount: 20%, validUntil: "2025-12-31"}

OUTPUT TO NEXT STEP:
  Coupon object passed to validation

---

STEP 3: Validate coupon (CouponValidator)

INPUT: Coupon{code: "SAVE20"}, Cart{items: [...]}

Line 67: if ($coupon->isExpired())
         → validUntil: 2025-12-31, today: 2025-12-26
         → FALSE, not expired

Line 69: if ($coupon->minimumPurchase > $cart->getSubtotal())
         → minimumPurchase: 25, subtotal: 100
         → FALSE, meets minimum

Line 71: $coupon->markAsUsed($userId)
         → Updates database: usage_count++

OUTPUT TO NEXT STEP:
  Valid coupon, ready for discount calculation

---

STEP 4: Recalculate total (PriceCalculator)

INPUT: Cart{subtotal: 100}, Coupon{discount: 20%}

Line 80: $subtotal = $cart->getSubtotal()
         → $subtotal = 100.00

Line 81: $discount = $subtotal * ($coupon->discount / 100)
         → $discount = 100 * 0.20 = 20.00

Line 82: $total = $subtotal - $discount
         → $total = 80.00

OUTPUT TO NEXT STEP:
  Final total: 80.00

INTEGRATION CHECK:
  - [ ] Is $cart->getSubtotal() cached or recalculated?
  - [ ] What if items added AFTER coupon applied?

POTENTIAL FLAW:
  If user adds items after applying coupon, is discount recalculated?
  Need to verify discount persists correctly.

---

STEP 5: Process payment (PaymentService)

INPUT: Total: 80.00, PaymentMethod: {...}

Line 95: $charge = $gateway->charge(80.00, $paymentMethod)
         → Returns Charge{success: true, chargeId: "ch_abc"}

OUTPUT TO NEXT STEP:
  Successful charge, ready to create order

---

STEP 6: Create order (OrderService)

INPUT: Cart{items: [...]}, Charge{chargeId: "ch_abc"}

Line 110: $order = new Order()
Line 111: $order->setItems($cart->getItems())
Line 112: $order->setTotal(80.00)
Line 113: $order->setChargeId("ch_abc")
Line 114: $order->save()

OUTPUT TO NEXT STEP:
  Order{id: 5001, status: "pending"}

---

STEP 7: Update inventory (InventoryService)

INPUT: Order{items: [{productId: 100, qty: 2}]}

Line 125: foreach ($order->getItems() as $item)
Line 126:   $product = $productRepository->find($item->productId)
            → Product{id: 100, stock: 50}

Line 127:   $product->decrementStock($item->quantity)
            → stock: 50 - 2 = 48

Line 128:   $product->save()

OUTPUT TO NEXT STEP:
  Inventory updated, ready to send confirmation

---

STEP 8: Send confirmation (EmailService)

INPUT: Order{id: 5001}, User{email: "user@example.com"}

Line 140: $email = new OrderConfirmationEmail($order, $user)
Line 141: $this->mailer->send($email)
          → Email sent successfully

OUTPUT: Workflow complete

---

INTEGRATION FLAWS FOUND:

1. Coupon discount persistence (Step 4):
   If user adds items after applying coupon, discount might not recalculate
   FIX: Recalculate discount on every cart change

2. Transaction boundaries:
   Payment succeeds (Step 5) but inventory update could fail (Step 7)
   User charged but order not fulfilled
   FIX: Wrap Steps 5-7 in database transaction

3. Email failure (Step 8):
   If email fails, user doesn't know order succeeded
   Could lead to duplicate orders if user retries
   FIX: Return success even if email fails, retry email async

SCENARIO TEST RESULT:
  Found 3 integration bugs that wouldn't appear in unit tests of individual components.
```

---

## After-Action Report Format

### Concept

Structured documentation of paper test findings with root cause analysis and improvement plan.

Adapted from security exercise after-action reports (AAR).

### When to Use

- **Complex findings**: Multiple issues found
- **Team review**: Sharing results with team
- **Root cause analysis**: Need to understand why bugs exist
- **Improvement tracking**: Assign owners and due dates

### Template

```
PAPER TEST AFTER-ACTION REPORT

Date: [YYYY-MM-DD]
Tester: [Name]
Code: [File/Function/Feature tested]

---

OBJECTIVES:
  What capabilities were being validated:
  - [ ] Objective 1
  - [ ] Objective 2
  - [ ] Objective 3

---

TEST SCENARIOS EXECUTED:
  1. [Scenario name] - [Result: PASS/FAIL]
  2. [Scenario name] - [Result: PASS/FAIL]
  3. [Scenario name] - [Result: PASS/FAIL]

---

STRENGTHS IDENTIFIED:
  ✅ [What worked well]
  ✅ [Effective patterns found]
  ✅ [Good practices observed]

---

GAPS IDENTIFIED:
  ❌ [Gap 1]: [Description]
     Impact: [What breaks, severity]
     Location: [File:Line]

  ❌ [Gap 2]: [Description]
     Impact: [What breaks, severity]
     Location: [File:Line]

---

ROOT CAUSE ANALYSIS:
  Gap 1:
    Why it exists: [Developer didn't know requirement | Oversight | Time pressure]
    Pattern: [Is this a repeated mistake?]

  Gap 2:
    Why it exists: [...]
    Pattern: [...]

---

IMPROVEMENT PLAN:

| Issue | Fix | Owner | Due Date | Status |
|-------|-----|-------|----------|--------|
| Gap 1 | [Specific code change] | Dev A | 2025-12-30 | Open |
| Gap 2 | [Specific code change] | Dev B | 2025-12-31 | Open |

---

LESSONS LEARNED:
  - [Pattern to avoid in future]
  - [Best practice to adopt]
  - [Testing approach to use]

---

FOLLOW-UP ACTIONS:
  - [ ] Update coding standards document
  - [ ] Add validation rule to checklist
  - [ ] Schedule follow-up review on [date]
```

### Example AAR

```
PAPER TEST AFTER-ACTION REPORT

Date: 2025-12-26
Tester: Senior Developer
Code: src/Payment/PaymentProcessor.php::processPayment()

---

OBJECTIVES:
  Validate payment processing security and reliability:
  ✅ Input validation prevents malicious inputs
  ✅ Error handling prevents user confusion
  ✅ Concurrency handled correctly
  ❌ Authorization checks prevent unauthorized payments

---

TEST SCENARIOS EXECUTED:
  1. Happy path (valid payment) - PASS
  2. Negative amount attack - FAIL
  3. Unauthorized user ID - FAIL
  4. Email service failure - FAIL
  5. Concurrent duplicate requests - FAIL

---

STRENGTHS IDENTIFIED:
  ✅ Payment gateway integration is clean and testable
  ✅ Order creation logic is atomic with proper transactions
  ✅ Code structure allows clean extension for new payment methods

---

GAPS IDENTIFIED:
  ❌ Gap 1: No input validation on payment amount
     Impact: Attacker could send negative amount, potentially receive money (CRITICAL)
     Location: PaymentProcessor.php:15

  ❌ Gap 2: No authorization check on user ID
     Impact: Attacker could purchase for different user (CRITICAL)
     Location: PaymentProcessor.php:12

  ❌ Gap 3: Email failure causes exception that confuses user
     Impact: User thinks payment failed, might retry and get charged twice (MEDIUM)
     Location: PaymentProcessor.php:25

  ❌ Gap 4: No idempotency protection
     Impact: Duplicate requests process separately, double charge (HIGH)
     Location: PaymentProcessor.php:15-28 (entire function)

---

ROOT CAUSE ANALYSIS:
  Gap 1 (Input validation):
    Why: Developer assumed frontend validates input
    Pattern: Repeated mistake - trusting client-side validation
    Systemic issue: Missing security requirement in specs

  Gap 2 (Authorization):
    Why: Developer didn't consider attack scenario
    Pattern: First occurrence - payment processing is new feature
    Systemic issue: No security review process

  Gap 3 (Email error handling):
    Why: Time pressure - shipped without complete error handling
    Pattern: Repeated - other features also have poor error handling
    Systemic issue: Need better error handling patterns

  Gap 4 (Idempotency):
    Why: Developer unaware of idempotency requirement
    Pattern: First occurrence
    Systemic issue: Payment processing best practices not documented

---

IMPROVEMENT PLAN:

| Issue | Fix | Owner | Due Date | Status |
|-------|-----|-------|----------|--------|
| Gap 1 | Add amount validation: if ($amount <= 0) throw InvalidArgumentException | Alice | 2025-12-27 | Open |
| Gap 2 | Add auth check: if ($userId !== $authenticatedUserId) throw UnauthorizedException | Alice | 2025-12-27 | Open |
| Gap 3 | Wrap email in try/catch, log error but return success | Bob | 2025-12-28 | Open |
| Gap 4 | Add idempotency key check using Redis cache | Charlie | 2025-12-30 | Open |
| Pattern | Document payment processing security checklist | Alice | 2026-01-05 | Open |
| Pattern | Implement security review for all payment features | Team Lead | 2026-01-10 | Open |

---

LESSONS LEARNED:
  - NEVER trust client-side validation - always validate server-side
  - Payment processing requires security review before deployment
  - Error handling must not confuse users into duplicate actions
  - Idempotency is critical for financial operations
  - Paper testing with red team mindset found 4 critical issues before production

---

FOLLOW-UP ACTIONS:
  - [x] Create GitHub issues for all gaps
  - [ ] Update payment processing documentation with security requirements
  - [ ] Add payment security checklist to code review template
  - [ ] Schedule security training session on financial transaction best practices
  - [ ] Re-test after fixes implemented (scheduled: 2025-12-31)
```

---

## Summary

These advanced techniques complement standard paper testing for complex scenarios:

**Progressive Injects**: Add complications incrementally to test resilience
**Red Team**: Adversarial mindset finds edge cases developers miss
**Attack Surface**: Prioritize testing effort on highest-risk entry points
**Scenario Workflows**: Test end-to-end integration, not isolated components
**AAR Format**: Structure findings for team review and improvement tracking

Use when code complexity, security criticality, or multi-component integration demands more rigorous analysis than standard paper testing provides.
