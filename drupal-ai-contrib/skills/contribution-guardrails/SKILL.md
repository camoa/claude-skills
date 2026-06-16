---
name: contribution-guardrails
description: "Enforces the development discipline for AI-assisted Drupal contributions — evidence over assertion, the no-guessing rule for external facts, the verification-gate artifact contracts, and re-verification on post-gate change. Use PROACTIVELY during any development between claiming an issue and verifying it. Use when user says 'guardrails', 'evidence over assertion', 'no guessing', 'verify this fact', 'is this actually tested', or whenever AI-assisted code is being written for a Drupal contribution. MUST apply before claiming any gate passed."
version: 0.1.0
model: inherit
user-invocable: true
allowed-tools: Read, Grep, Glob, Task
disallowed-tools: Edit, Write
---

# Contribution Guardrails

The cross-cutting discipline for AI-assisted Drupal contribution development. The
recurring failure this prevents: AI claiming correctness it never verified. Drupal
treats this as an existential review-cost problem — AI makes contributing cheap but
makes *reviewing* expensive.

## When to Use

- During any development between `/drupal-ai-contrib:issue` and `/drupal-ai-contrib:verify`
- Before stating that anything "passes", "works", "is done", or "is secure"
- When about to use an SDK symbol, API parameter, or version-specific behavior
- NOT for: running the gates themselves (that is `contribution-verify`)

## Rule 1 — Evidence over assertion

A gate passes **only on a produced artifact**. Never on the model stating a verdict.

For each gate, *produce → capture → check the artifact*:

| Gate | Pass artifact |
|------|---------------|
| Research | Cited findings — each claim traced to a source (dev-guide slug, vendor doc, source file) |
| Implementation | TDD evidence — a failing test, then the same test passing (red → green) |
| Static analysis | Clean **captured** `phpcs` / `phpstan` output — the actual command output, pasted |
| Test | The core `phpunit.xml.dist` run with **zero** failures, warnings, deprecations |
| Live behavior | Real API / command output — captured, not described |
| Review | A fresh-context agent's verdict (`fresh-context-reviewer`) |
| Completion | A green **real** drupalci pipeline (`contribution-pipeline`) |

If you cannot show the artifact, the gate has **not** passed — say so plainly.

## Rule 2 — No guessing external facts

Any external fact — an SDK symbol, an API header or parameter, a beta-feature slug, a
library-version behavior — is **verified against vendor source or a live probe**.

- Model memory and changelog lines are **leads, never facts**.
- An unverified external fact is a **blocker** — not a caveat, not a "should".
- Hand the claim to the `drupal-ai-contrib:external-fact-verifier` agent (Task tool);
  act only on a `verified` result.

## Rule 3 — Re-verification on post-gate change

Any code edited **after** its gate passed re-fires that gate for the touched path.
Features added after a green test run are the classic escape hatch for unverified code.
The `PostToolUse` re-verification hook marks a changed path's gate **stale**; `verify`
re-runs every stale gate. Never treat a pre-edit green as still valid.

## Rule 4 — Proportionality, justified not assumed

Full gates for features. A light path is allowed for trivial changes — but "trivial"
must be **explicitly justified and recorded** (what makes it trivial, in writing),
never assumed. An unrecorded "this is trivial" is the bypass that hides unverified work.

## Rule 5 — Scope discipline

Deliver exactly the agreed scope contract — goal / expected result / success criteria /
non-goals. AI over-delivers, and every extra line is review burden a maintainer did not
ask for. Out-of-scope work is a guardrail violation, not a bonus.

## Anti-patterns this skill blocks

- Guessing an API/SDK fact from model memory instead of verifying against source.
- Reporting "tests pass locally" without disclosing local tool versions vs. CI's.
- Dismissing a warning as "noise" without tracing it to its source.
- Entering design or implementation without consulting the relevant dev-guides.
- Delivering beyond the agreed scope contract.
- Marking a task done on local-green before the real drupalci pipeline is green.
- Undisclosed AI use above the policy's "significant portion" threshold.

## Examples

### Example 1: an unverified "passes"
**User says:** "The phpcs job should pass now."
**Actions:**
1. "Should" is an assertion, not an artifact (Rule 1).
2. Require the captured `phpcs` output; if it has not been run, run it and capture it.
**Result:** The gate's verdict is the pasted command output, not a prediction.

### Example 2: an SDK symbol from memory
**User says:** "Use the `Client::stream()` method from the SDK."
**Actions:**
1. `Client::stream()` is an external fact recalled from memory (Rule 2).
2. Hand the claim to the `drupal-ai-contrib:external-fact-verifier` agent — verify
   against vendor source.
**Result:** Code uses the symbol only after a `verified` result; otherwise it is blocked.

## Troubleshooting

| Situation | Handling |
|-----------|----------|
| Asked to call something "trivial" to skip gates | Allowed only if the justification is written down (Rule 4). No record → full gates. |
| A warning is dismissed as "noise" | Trace it to its source before dismissing — undismissed by default. |
| Builder explains why the work is fine | Explanation is narrative, not evidence. Require the artifact. |
| Extra work delivered beyond scope | Flag as a Rule 5 violation; it is review burden, not a bonus. |

## Knowledge layer

Load via `dev-guides-navigator`: `drupal/contributing-with-ai/evidence-over-assertion`,
`drupal/contributing-with-ai/supervised-ai-workflow`,
`drupal/contributing-with-ai/human-review-requirements`.
