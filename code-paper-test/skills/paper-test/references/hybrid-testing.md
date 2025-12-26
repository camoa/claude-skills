# Hybrid Testing Strategy

For modules with multiple components (events, conditions, actions, services), use a **coverage-driven hybrid** approach that combines flow-based and component testing.

## Contents

- [Two Levels of Testing](#two-levels-of-testing)
- [Why Both?](#why-both)
- [Coverage-Driven Method](#coverage-driven-method)
- [Coverage Matrix Example](#coverage-matrix-example)
- [Minimum Coverage Requirements](#minimum-coverage-requirements)
- [Flow Testing Template](#flow-testing-template)
- [Component Edge Case Template](#component-edge-case-template)
- [Using Agents for Parallel Testing](#using-agents-for-parallel-testing)

---

## Two Levels of Testing

| Level | What | Purpose | Catches |
|-------|------|---------|---------|
| **Flow-based** | Real user workflows end-to-end | Test integration, data handoffs | Data format mismatches, token issues, missing handoffs |
| **Component** | Each component with edge cases | Test individual logic thoroughly | Implementation bugs, null handling, error cases |

---

## Why Both?

### Flow-based Testing Alone Misses:
- Edge cases within components (empty results, null inputs)
- Error handling paths that don't occur in happy-path flows
- Component-specific logic bugs

### Component-only Testing Misses:
- Data format incompatibilities between components
- Token/state handoff issues
- Real-world usage patterns

**Both together = comprehensive coverage with minimal redundancy**

---

## Coverage-Driven Method

```
Step 1: Map all components
        - List every event, condition, action, service
        - Example: 7 events, 2 conditions, 7 actions = 16 components

Step 2: Design flows that COVER all components
        - Each component must appear in at least one flow
        - Flows represent real user workflows
        - 3-5 flows typically cover a module

Step 3: Add component edge cases
        - For each component, identify scenarios NOT covered by flows
        - Error cases, empty inputs, boundary conditions
        - 2-4 edge cases per component
```

This ensures:
- Every component tested in realistic integration (flows)
- Every component tested with edge cases (components)
- No redundant testing

---

## Coverage Matrix Example

For an ECA integration module:

```
FLOWS:
┌─────────────────────────────────────────────────────────────────┐
│ Flow 1: "Push on entity save"                                   │
│   Event: entity_presave → Condition: has_mapping →              │
│   Action: trigger_push → (uses: push result tokens)             │
├─────────────────────────────────────────────────────────────────┤
│ Flow 2: "Query and process"                                     │
│   Event: custom_trigger → Action: execute_soql →                │
│   Action: get_field_value (loop through results)                │
├─────────────────────────────────────────────────────────────────┤
│ Flow 3: "Handle pull event"                                     │
│   Event: pull_success → Condition: check_object_type →          │
│   Action: get_mapped_object → Action: update_entity             │
└─────────────────────────────────────────────────────────────────┘

COMPONENT EDGE CASES:
┌─────────────────────────────────────────────────────────────────┐
│ execute_soql:                                                   │
│   - Empty result set (0 records)                                │
│   - API error / connection failure                              │
│   - Malformed SOQL query                                        │
├─────────────────────────────────────────────────────────────────┤
│ trigger_push:                                                   │
│   - Entity has no mapping                                       │
│   - Multiple mappings for same entity                           │
│   - Push fails due to validation                                │
├─────────────────────────────────────────────────────────────────┤
│ has_mapping condition:                                          │
│   - Entity type not supported                                   │
│   - Null entity passed                                          │
└─────────────────────────────────────────────────────────────────┘
```

Result:
- All 16 components appear in at least one flow
- Each component has 2-4 edge case tests
- Total scenarios: 3 flows + ~30 edge cases = 33 tests

---

## Minimum Coverage Requirements

| Component Type | In Flows | Edge Cases | Total Scenarios |
|----------------|----------|------------|-----------------|
| Events | 1+ flow each | 1-2 (error events) | 2-3 per event |
| Conditions | 1+ flow each | 2-3 (true, false, edge) | 3-4 per condition |
| Actions | 1+ flow each | 2-4 (error, empty, edge) | 3-5 per action |

---

## Flow Testing Template

```
FLOW: [Name - what user is trying to accomplish]

TRIGGER: [What starts this flow]
EXPECTED OUTCOME: [What should happen when complete]

COMPONENTS INVOLVED:
  - Event: [event_id]
  - Condition: [condition_id] (optional)
  - Action: [action_id]
  - Action: [action_id]

SCENARIO: [Concrete example]
INPUT:
  [Initial state - entity values, configuration, etc.]

TRACE:
1. EVENT FIRES: [event_id]
   Data provided: [what data/tokens are available]
   Configuration: [event configuration]

   Token data stored:
     - [token_name]: [token_value]
     - [token_name]: [token_value]

2. CONDITION EVALUATES: [condition_id]
   Input received:
     - From tokens: [what tokens it reads]
     - Configuration: [condition configuration]

   Processing:
     Line X: [condition logic traced]
     Line Y: [...]

   Result: [true/false and why]
   Action: [CONTINUE to action / STOP execution]

3. ACTION EXECUTES: [action_id]
   Input received:
     - From tokens: [which tokens from event/previous actions]
     - Configuration: [action configuration values]

   Processing:
     Line X: [action logic traced]
     Line Y: [external call - verified behavior]
     Line Z: [...]

   Output:
     Token data stored:
       - [token_name]: [value]
     Side effects: [database changes, API calls, etc.]

4. NEXT ACTION: [action_id]
   Input received:
     - From tokens: [uses tokens from step 3]
     - Configuration: [...]

   Processing:
     Line X: [...]

   Output:
     Return value: [...]
     Side effects: [...]

INTEGRATION CHECKS:
  - [ ] Event provides data action expects?
  - [ ] Token names consistent between components?
  - [ ] Data types compatible (string vs array vs object)?
  - [ ] Error from one component handled by next?
  - [ ] Missing null checks between handoffs?

FLAWS FOUND:
  - [Integration issue description]
    Component A outputs: [format]
    Component B expects: [format]
    FIX: [how to resolve]

  - [Token mismatch]
    Event stores token: "entity_id"
    Action reads token: "entity.id"
    FIX: Standardize token names
```

---

## Component Edge Case Template

```
COMPONENT: [component_id]
TYPE: [Event | Condition | Action]
BASE CLASS: [ConfigurableActionBase, etc.]

COVERED IN FLOWS:
  - Flow 1: [scenario name] - happy path

SCENARIOS NOT COVERED BY FLOWS:
  1. [edge case description]
  2. [edge case description]
  3. [error case description]

---

SCENARIO 1: [Description - e.g., "Empty result set"]
INPUT:
  Configuration:
    - soql_query: "SELECT Id FROM Contact WHERE Email = 'notfound@example.com'"
    - result_token: "query_result"

  Token data available:
    - entity: Node{id: 123}

TRACE:
Line 5: $query = $this->getConfigWithTokens('soql_query')
        → $query = "SELECT Id FROM Contact WHERE Email = 'notfound@example.com'"

Line 6: $result = $this->salesforceClient->query($query)

        DEPENDENCY CHECK: salesforceClient->query()
          Returns: SelectQueryResult object
          When no results: result->size() = 0, result->records() = []

        → $result = SelectQueryResult{size: 0, records: []}

Line 7: $records = $result->records()
        → $records = [] (empty array)

Line 8: $this->tokenService->addTokenData('query_result', $records)
        → Stores empty array in token

OUTPUT:
  Token data stored:
    - query_result: [] (empty array)

  Side effects: None

FLAW CHECK:
  - [ ] Handles empty array correctly?
  - [ ] Should set a "no_results" flag?
  - [ ] Next action expects array or specific format?

FLAW FOUND: None - correctly handles empty results

---

SCENARIO 2: [Description - e.g., "API connection failure"]
INPUT:
  Configuration: [same as scenario 1]

TRACE:
Line 6: $result = $this->salesforceClient->query($query)

        DEPENDENCY CHECK:
          Throws: RestException on connection failure

        → THROWS RestException("Connection timeout")

Line 7: NOT REACHED (exception thrown)

OUTPUT:
  Exception thrown: RestException
  No token data stored
  Flow stops

FLAW FOUND:
  - Line 6: No try/catch for connection failures
  - Flow crashes instead of graceful failure
  - FIX: Wrap in try/catch, log error, set error token

---

SCENARIO 3: [Description - e.g., "Malformed SOQL query"]
INPUT:
  Configuration:
    - soql_query: "SELECTT Id FROM Contact"  # Typo: SELECTT

TRACE:
Line 5: $query = $this->getConfigWithTokens('soql_query')
        → $query = "SELECTT Id FROM Contact"

Line 6: $result = $this->salesforceClient->query($query)

        DEPENDENCY CHECK:
          Throws: RestException on SOQL syntax error

        → THROWS RestException("Invalid SOQL syntax")

OUTPUT:
  Exception thrown: RestException
  No token data stored

FLAW FOUND:
  - Same as scenario 2 - needs error handling
  - FIX: try/catch + error token
```

---

## Using Agents for Parallel Testing

For large modules, spawn agents to test in parallel:

### Option 1: Agent per Component Type
```
- Agent 1: Test all events (7 events × 2 scenarios each = 14 tests)
- Agent 2: Test all conditions (2 conditions × 3 scenarios each = 6 tests)
- Agent 3: Test all actions (7 actions × 3 scenarios each = 21 tests)
```

**When to use:** Small-to-medium modules, clear component separation

### Option 2: Agent per Component
```
- Agent 1: execute_soql action (4 scenarios)
- Agent 2: trigger_push action (4 scenarios)
- Agent 3: get_field_value action (3 scenarios)
- Agent 4: entity_presave event (2 scenarios)
- Agent 5: has_mapping condition (3 scenarios)
- ...
```

**When to use:** Large modules with complex components

### Option 3: Agent per Flow + Edge Case Agents
```
Integration Testing:
- Agent 1: Flow 1 - Push on entity save
- Agent 2: Flow 2 - Query and process
- Agent 3: Flow 3 - Handle pull event

Edge Case Testing (parallel):
- Agent 4: execute_soql edge cases
- Agent 5: trigger_push edge cases
- Agent 6: All condition edge cases
- Agent 7: All event edge cases
```

**When to use:** When flows are complex and need focused attention

---

## Coverage Checklist

Before finishing paper testing:

### Flow Coverage
- [ ] Every component appears in at least one flow
- [ ] Every flow represents a real user workflow
- [ ] Integration between components tested (token handoffs, data formats)

### Component Coverage
- [ ] Each component has edge case scenarios
- [ ] Error cases covered (API failures, null inputs, empty results)
- [ ] Boundary conditions tested (first/last item, min/max values)

### Quality Checks
- [ ] No redundant scenarios (each test adds unique coverage)
- [ ] Realistic test data (not contrived examples)
- [ ] External dependencies verified (not assumed)

---

## Example: Complete Coverage Plan

**Module:** Salesforce ECA Integration (16 components)

### Flow Tests (3 flows):
1. "Push entity on save" (4 components)
2. "Query and process results" (3 components)
3. "Handle pull event" (5 components)

**Coverage:** 12/16 components in flows

### Missing from Flows:
- authenticate action
- disconnect action
- get_api_version action
- connection_status event

### Edge Case Tests (32 scenarios):
- 7 events × 2 edge cases = 14 scenarios
- 2 conditions × 3 edge cases = 6 scenarios
- 7 actions × 3 edge cases = 21 scenarios
- Missing components: 4 × 2 = 8 scenarios (added to flows or edge cases)

**Total:** 3 flows + 40 edge cases = 43 total test scenarios

**Estimated time:**
- Flows: 30 min each × 3 = 1.5 hours
- Edge cases: 5 min each × 40 = 3.3 hours
- Total: ~5 hours for complete module testing

**vs. Component-only:**
- 16 components × 5 scenarios each = 80 tests
- Time: ~7 hours with significant redundancy

**Hybrid saves time while improving coverage.**
