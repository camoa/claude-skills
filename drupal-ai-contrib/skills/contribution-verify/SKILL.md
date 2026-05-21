---
name: contribution-verify
description: "Runs the local verification inner loop for a Drupal contribution — the drupalci-parity gate set at CI strictness, the AI-policy gate, and the eval gate, every gate passing only on a captured artifact. Use when the user runs /drupal-ai-contrib:verify or asks to verify, check, or locally test a Drupal contribution before submitting. This is the centerpiece — evidence over assertion, never a bare 'passes'."
version: 0.1.0
model: sonnet
user-invocable: false
---

# Contribution Verify (worker skill)

The fast inner loop. Mirrors the **real drupalci jobs** locally at their **real
strictness**, plus the AI-policy and eval gates. Every gate passes **only on a produced
artifact** — a captured command output, a diff, a real result. **Never** report a bare
"passes".

Backs `/drupal-ai-contrib:verify`. Load the knowledge layer via `dev-guides-navigator`:
`drupal/contributing/drupalci-pipeline-gitlab-templates`,
`drupal/contributing/drupal-coding-standards-ci-parity`,
`drupal/contributing/reproducing-drupalci-failures-locally`,
`drupal/contributing-with-ai/coding-standards`,
`drupal/contributing-with-ai/testing-ai-code`,
`drupal/contributing-with-ai/drupal-ai-policy`,
`drupal/contributing-with-ai/ai-best-practices-and-evals`.

## Procedure

### 1. Environment match — before any gate

Read from `.gitlab-ci.yml`: `_TARGET_CORE`, `_TARGET_PHP`, `_GITLAB_TEMPLATES_REF`,
`_PHPUNIT_CONCURRENT`, `SKIP_*`, `OPT_IN_TEST_*`. Install the **target core version** +
`drupal/core-dev` so `phpunit` / `phpstan` resolve to the releases CI uses. Versions
are **resolved, never baked in**. If the environment is not matched, say so — local
green on mismatched versions is not evidence.

### 2. Parse the enabled gate set

`.gitlab-ci.yml` `include`s the `gitlab_templates` files. Determine which jobs are
enabled and each job's **actual blocking status** (`allow_failure`, `SKIP_*`). Report
each gate's real blocking status — not a uniform pass/fail.

### 3. Run the drupalci-parity gate set

Run each enabled job locally at CI strictness; capture each one's output as the artifact:

| Gate | How to run at CI strictness |
|------|------------------------------|
| `composer` | `composer validate` + install with the project's constraints |
| `phpcs` | `phpcs` against the project's `phpcs.xml.dist` (`Drupal` + `DrupalPractice`); `drupal/coder` ^8.3.x. **Blocking by default.** |
| `phpstan` | `phpstan analyse` with the project's `phpstan.neon` (`phpstan-drupal`). **`allow_failure: true` by default** — report it, flagged non-blocking. |
| `phpunit` | Run with the **core config**: `vendor/bin/phpunit -c web/core/phpunit.xml.dist --webroot=web`, switching to `core/scripts/run-tests.sh` when `_PHPUNIT_CONCURRENT: 1`. The core `phpunit.xml.dist` carries `failOnWarning` / `failOnPhpunitWarning` — that is what fails on warnings. Pass = zero failures, zero warnings, zero deprecations. |
| `cspell` | `cspell` with the project's `.cspell-project-words.txt` loaded |
| `eslint` / `stylelint` | only when JS/CSS present and not `SKIP_ESLINT` / `SKIP_STYLELINT` |

**Opt-in variants** — `OPT_IN_TEST_PREVIOUS_MAJOR` / `_PREVIOUS_MINOR` / `_NEXT_MINOR` /
`_MAX_PHP`. `gitlab_templates` v1.15.0+ moved these to **manual trigger** — they do not
auto-run. Report opt-in variants **explicitly as unrun**; never imply coverage. Defer
locally-impossible combinations to `contribution-pipeline`.

**Parity, not philosophy.** These gates assert "does the drupalci job pass". Delegate
the philosophy / standards review (SOLID, DRY) to `code-quality-tools` — parity gates
stay here and are authoritative for "code correctly done".

### 4. The AI-policy gate — every contribution

Runs every time. Dispatch the `drupal-ai-contrib:ai-policy-checker` agent (Task tool)
to fetch the **current** state of the adopted *Policy on the use of AI when
contributing to Drupal* and `ai_best_practices` — never hard-code policy text. The
gate's pass artifact is:
- a **disclosure decision recorded** — does AI use cross the "significant portion"
  threshold (whole functions / classes / scaffolding / extensive docblocks; single-line
  autocomplete is exempt)? If yes, the `AI-Generated: Yes (...)` disclosure is prepared.
- the **verification checklist confirmed for this contribution** — dependencies, logic,
  and security verified (not assumed); full contributor responsibility acknowledged.
- the policy state fetched **live** and attached.

### 5. The eval gate — best-effort

`ai_best_practices` ships `evals/evals.json` (offline grader — PHP lint / phpcs / diff /
security-pattern / report-structure checks). Run the eval set locally as a quality gate
**if available**; degrade silently if not. Never hard-depend on the eval registry,
never pin its schema, never adopt `promptfoo`. When guidance fails in practice, capture
an expert correction (correction → fix → eval passes; agent-agnostic JSONL) and offer
to file it upstream.

### 6. Re-verification

Any path edited after its gate last passed is **stale**. The `PostToolUse`
re-verification hook records every edited contribution file in a ledger. Read the stale
set by running `${CLAUDE_PLUGIN_ROOT}/scripts/reverify-list.sh` — it prints one path per
line (nothing if no gate is stale). Re-run the gate for **every** stale path before
reporting; a pre-edit green is not valid. After all gates report green, clear the
ledger: `${CLAUDE_PLUGIN_ROOT}/scripts/reverify-list.sh --clear`.

### 7. Report — evidence, never assertion

For each gate report: the gate, its **actual blocking status**, PASS / FAIL / UNRUN,
and the **captured artifact** (the command output). Never report a verdict without its
artifact. List opt-in variants as UNRUN. State the environment-match status. If a gate
cannot be run locally, say so and defer it to `contribution-pipeline` — do not imply it
passed.

## Examples

### Example 1: a clean inner-loop run
**Trigger:** `/drupal-ai-contrib:verify`
**Actions:**
1. Environment-match the target core; parse the enabled gate set.
2. Run `composer`, `phpcs`, `phpstan`, `phpunit`, `cspell`; run the AI-policy + eval gates.
3. Report each with its captured output and real blocking status.
**Result:** Every gate's verdict is backed by a pasted artifact; opt-in variants UNRUN.

### Example 2: a warning surfaced by the core config
**Trigger:** `/drupal-ai-contrib:verify` after adding a deprecated API call.
**Actions:**
1. `phpunit` runs with the core `phpunit.xml.dist` (`failOnWarning`).
2. The deprecation fails the gate — capture the output, do not dismiss it as noise.
**Result:** FAIL reported with the deprecation trace; routed back to development.

## Troubleshooting

| Situation | Handling |
|-----------|----------|
| No `.gitlab-ci.yml` found | Report the gap; point at `/drupal-ai-contrib:setup` for that gap only — do not refuse. |
| Local core version ≠ `_TARGET_CORE` | Environment-match first; a green on mismatched versions is not evidence. |
| `evals.json` absent or schema changed | Degrade silently — the eval gate is best-effort, never a hard dependency. |
| A gate cannot run locally (e.g. `_MAX_PHP`) | Report UNRUN and defer to `contribution-pipeline`; never imply it passed. |
| `phpstan` reports errors | It is `allow_failure: true` by default — report FAIL flagged non-blocking, per the project's config. |
