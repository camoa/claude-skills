---
name: contribution-verify
description: "Runs the local verification inner loop for a Drupal contribution — the drupalci-parity gate set at CI strictness, the AI-policy gate, and the eval gate, every gate passing only on a captured artifact. Use when the user runs /drupal-ai-contrib:verify or asks to verify, check, or locally test a Drupal contribution before submitting. This is the centerpiece — evidence over assertion, never a bare 'passes'."
version: 0.1.0
model: inherit
user-invocable: false
disallowed-tools: Edit, Write
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
`drupal/contributing/contrib-project-scaffolding`,
`drupal/contributing-with-ai/coding-standards`,
`drupal/contributing-with-ai/testing-ai-code`,
`drupal/contributing-with-ai/drupal-ai-policy`,
`drupal/contributing-with-ai/disclosure-checkboxes`,
`drupal/contributing-with-ai/ai-best-practices-and-evals`.

## Procedure

### 1. Environment match — before any gate

Read from `.gitlab-ci.yml`: `_TARGET_CORE`, `_TARGET_PHP`, `_GITLAB_TEMPLATES_REF`,
`_PHPUNIT_CONCURRENT`, `SKIP_*`, `OPT_IN_TEST_*`. Install the **target core version** +
`drupal/core-dev` so `phpunit` / `phpstan` resolve to the releases CI uses. Versions
are **resolved, never baked in**. If the environment is not matched, say so — local
green on mismatched versions is not evidence.

JS/CSS tooling needs the same discipline — as a command, not just a principle.
Prettier resolves its own config independently of ESLint's `--config` / `--no-eslintrc`
flags, so pointing `eslint` at core's linked config is not enough by itself: a run that
never resolves the project's (or core's) `.prettierrc.json` still executes cleanly and
reports a verdict — it just silently falls back to Prettier's own default
(`singleQuote: false`), the **opposite** of core's convention, and flags the **opposite**
set of quote violations from CI's real one. Reproduce what the shared `gitlab_templates`
job actually does before running `eslint`:

    ln -sfv <core>/.eslintrc.passing.json <project>/../.eslintrc.json
    ln -sfv <core>/.eslintrc.jquery.json <project>/../.eslintrc.jquery.json
    test -e <project>/.prettierrc.json || ln -sfv <core>/.prettierrc.json <project>/.prettierrc.json

The first two land **above** the contribution repo, so they never enter the MR. The third
lands **inside** it: remove it when you are done, or it will show up in `git status` and can
be committed by accident. `-f` so a re-run does not fail on an existing link.

CI also writes a `.prettierignore` when the project has none, which exempts YAML from
Prettier's rules:

    test -e <project>/.prettierignore || echo '*.yml' > <project>/.prettierignore

Then run the job's **own** invocation, not a shortened one. Missing flags reproduce the
config and lose the scope, which is the same false clean in a different place:

    <core>/node_modules/.bin/eslint --no-error-on-unmatched-pattern \
      --ignore-pattern="*.es6.js" --resolve-plugins-relative-to=<core> \
      --ext=.js,.yml .

`--ext=.js,.yml` is the one that matters most: given a directory, ESLint lints `.js` only by
default, while CI also lints `*.info.yml`, `*.libraries.yml` and `*.services.yml`. Drop it and
the local run reports clean on files CI checks. `--ignore-pattern="*.es6.js"` skips legacy
files CI skips, so dropping it produces a false red instead. Same binary, same merged config,
same scope. `stylelint` resolves differently: it uses the project's own
`.stylelintrc*` when present and core's only when absent, so there is no merged cascade to
reproduce — confirm which single config applies before assuming either. That is a statement
about the config cascade, not about Prettier, which stylelint does not involve.

### 2. Parse the enabled gate set

`.gitlab-ci.yml` `include`s the `gitlab_templates` files. Determine which jobs are
enabled and each job's **actual blocking status** (`allow_failure`, `SKIP_*`). Report
each gate's real blocking status — not a uniform pass/fail.

### 3. Run the drupalci-parity gate set

Run each enabled job locally at CI strictness; capture each one's output as the artifact:

| Gate | How to run at CI strictness |
|------|------------------------------|
| `composer` | `composer validate` + install with the project's constraints |
| `phpcs` | `phpcs` against the project's `phpcs.xml.dist` (`Drupal` + `DrupalPractice`); `drupal/coder` `^8.3`, deliberately — see below. **Blocking by default.** |
| `phpstan` | `phpstan analyse` with the project's `phpstan.neon` (`phpstan-drupal`). **`allow_failure: true` by default** — report it, flagged non-blocking. |
| `phpunit` | Run with the **core config**: `vendor/bin/phpunit -c web/core/phpunit.xml.dist --webroot=web`, switching to `core/scripts/run-tests.sh` when `_PHPUNIT_CONCURRENT: 1`. The core `phpunit.xml.dist` carries `failOnWarning` / `failOnPhpunitWarning` — that is what fails on warnings. Pass = zero failures, zero warnings, zero deprecations. |
| `cspell` | `cspell` with the project's `.cspell-project-words.txt` loaded |
| `eslint` / `stylelint` | only when JS/CSS present and not `SKIP_ESLINT` / `SKIP_STYLELINT`; resolve the project's own merged config, never a rebuilt command (§1) |

**Why `drupal/coder` is pinned `^8.3` here, and `^8.3.30||^9.0` in
`code-quality-tools`.** Same package, two profiles, one stated reason each. This skill
exists to reproduce drupal.org's own pipeline locally, and that pipeline installs coder
through `drupal/core-dev`, which pins `^8.3.30` on 11.x and 11.3.x and `^8.3.10` on 10.6.x
— no core branch has moved to `^9`. Pinning `^8.3` is therefore the only pin that
reproduces the CI that judges the patch; tracking the current major here would run a
stricter phpcs than the one the gate is imitating, and fail a patch core's CI would have
passed.

`code-quality-tools` audits custom site code rather than a patch, so it is free to accept
coder 9 where a project can resolve it — but it is not free to REQUIRE it. It pins the
range `^8.3.30||^9.0` and lets Composer take the newest version the project can actually
install. This corrects what this page said until 2026-08-30, that the sibling plugin
"tracks the current major at `^9.0`": a bare `^9.0` cannot install alongside
`drupal/core-dev` on either supported major, because core-dev requires coder `^8.3.10` on
Drupal 10 and `^8.3.30` on Drupal 11, and core-dev is present on most Drupal development
sites. The reasoning was right about intent and wrong about the fact underneath it.

Verified against core-dev's `composer.json` and `gitlab_templates`'
`include.drupalci.main.yml` on 2026-08-27; the range and its reason are recorded in
`code-quality-tools/skills/code-quality-audit/schema/tool-catalog.json` under
`constraint_reason` and `resolves_against`, checked 2026-08-30.

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
  threshold (illustrative examples: whole functions / classes / scaffolding / extensive
  docblocks; single-line autocomplete exempt — the live policy the agent returns is
  authoritative over these examples)? If yes, the `AI-Generated: Yes (...)` disclosure
  is prepared.
- the **verification checklist confirmed for this contribution** — dependencies, logic,
  and security verified (not assumed); full contributor responsibility acknowledged.
- the policy state fetched **live** and attached.

If the `ai-policy-checker` agent reports a policy source **unreachable**, the AI-policy
gate is **UNRUN** — report it as UNRUN, never as passed. The contribution cannot clear
this gate on an unconfirmed policy state.

### 5. The eval gate — best-effort

`ai_best_practices` ships `evals/evals.json` (offline grader — PHP lint / phpcs / diff /
security-pattern / report-structure checks). Run the eval set locally as a quality gate
**if available**; degrade silently if not. Never hard-depend on the eval registry,
never pin its schema, never adopt `promptfoo`. When guidance fails in practice, capture
an expert correction (correction → fix → eval passes; agent-agnostic JSONL) and offer
to file it upstream.

When **3 or more** captured corrections cluster on the **same subsystem**, surface a
recommendation to propose a dedicated skill section or eval suite for it — a recurring
failure cluster is a signal the guidance itself has a gap, not just one bad output.

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

## Sandbox users — untrusted code execution

`verify` runs the **contributor's own code** at CI strictness — `composer install`,
`phpunit`, `eslint`, `phpstan` — which is untrusted-code execution against an unreviewed
contribution (Composer scripts and a test suite both run arbitrary PHP). When verifying
a contribution you have not yet reviewed, run it under the process-level sandbox runtime
(`@anthropic-ai/sandbox-runtime`): unlike the built-in Bash sandbox, it wraps the
**whole Claude Code process** — Bash, file tools, MCP servers, and hooks — in the same
Seatbelt / bubblewrap isolation, so a malicious `composer.json` script or test fixture
cannot reach beyond the workspace. (The attack surface here is PHPUnit / Composer,
parallel to the `npx`-trojan risk in JS tooling.) For a *fully* untrusted repository,
the guide steers stronger isolation — a dedicated VM or Claude Code on the web. See the
**Sandbox Environments** guide.

## Large host codebases

For Drupal **core** or large-suite contributions, scope `verify` to the contribution's
**changed subtree** rather than the entire host codebase — point the gates at the paths
the diff actually touches so a multi-gigabyte monorepo does not dilute the signal or
blow the time budget. See the **Large Codebases and Monorepos** guide.
