# Changelog

All notable changes to the code-paper-test plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.10.1] - 2026-06-19

### Changed — docs
- **Evergreen catalog description + README.** Dropped the version-narration from the catalog description, and replaced the README's embedded `## Version` changelog with a pointer to this file (the history was duplicated). Kept the capability descriptions. No behavior change.

## [0.10.0] - 2026-06-16

### Added
- **Behavioral contract verification — the second pass after existence verification.** New `references/behavioral-verification.md` holds the canonical procedures: **B1** (code/library calls) enumerates every caller assumption about a return, locates the declared contract (type stub → OpenAPI → docs → docblock → changelog), diffs assumption vs contract, and applies a **chained-object rule** (trace every property/method invoked on a returned object, not just the first return type); **B2** (plugin/MCP/hook/skill references) checks that a referenced capability *produces* what the calling step consumes, not merely that the reference resolves. Closed-source / no-contract targets get a **taint stance** (assume the return could be null, hostile, or malformed; require a validation wrapper) and the explicit label `EXISTENCE VERIFIED / BEHAVIOR UNVERIFIED`.
- `references/dependency-verification.md` — renamed Option 3 to "Closed-Source / No-Contract — Taint Stance" and added a "Chained-Object Rule" section. The existence-layer `UNVERIFIED RISK` label is preserved; the behavioral-layer `BEHAVIOR UNVERIFIED` label is new and distinct.
- `references/skill-and-config-testing.md` — new "§8 Behavioral Output Verification (B2)" procedure and a `tool-reference-behavior` row in the JSON category table.
- `commands/test-team.md` — Happy Path Validator spawn gains a behavioral step 5b (B1) and a skill-mode B2 check.

### Changed
- **Report columns now distinguish existence from behavior** (the previous single `Verified?` column was a false-confidence trap). The Happy Path Analysis `## Dependency Verification` table gains `Behavior verified?` + `Contract source`; the lead synthesis splits its single Dependency Verification table into `## Existence Verification` and `## Behavioral Contract Verification` (the latter renamed from the rollout's `## Contract Verification` to avoid colliding with the pre-existing relational `## Contract Verification` table).
- **JSON schema 1.0 → 1.1 (additive only).** Optional `behavior_verified` boolean on dependency-type findings; `behaviors_verified` in the summary envelope; `tool-reference-behavior` category. CI gates pinning `^1\.` are unaffected.
- SKILL.md — new workflow step 6b, a behavioral distinction in "Critical: Never Assume", a skill-mode B2 note, and the new reference in the References list.

### Fixed (pre-existing)
- **Slash-command namespace corrected everywhere.** 21 references used `/code-paper:test-team`, but the plugin name is `code-paper-test`, so the command actually resolves as `/code-paper-test:test-team` — every documented invocation previously pointed at a non-existent command. Corrected across `SKILL.md` (incl. the routing table and `--json` examples), `commands/test-team.md`, `README.md`, `CHANGELOG.md`, and four `references/*.md`.
- **S14 (BUG-1) — `skills/paper-test/SKILL.md` frontmatter `model: sonnet` → `model: inherit`.** The skill runs inline with no context isolation, so a pinned sub-1M model overflows when the skill activates from a large conversation. `inherit` runs on the session model. The `**Model:** sonnet` markers in `commands/test-team.md` are fresh-context agent spawns and are intentionally left unchanged (S14 does not apply to spawns).

### Notes
- Existence-verification discipline is unchanged — behavioral verification is added on top, never a replacement.

## [0.9.0] - 2026-05-21

### Added
- **`${CLAUDE_EFFORT}` honored as a floor.** `/paper-test` (SKILL.md, "Effort-Adaptive Scenario Depth") scales scenarios per phase with the active effort level — `low` = happy path + one error case, `medium` = 2 per phase, `high`/`xhigh`/`max` = 3+. Effort never lowers the verification bar; every external call is still verified. `/code-paper-test:test-team` treats caller effort as a **floor-raiser**: each teammate runs at `max(${CLAUDE_EFFORT}, role floor)` — floors are `medium` (Happy Path Validator) and `high` (Edge Case Hunter, Red Team Attacker). A `low`/`medium` caller still gets the adversarial lenses at `high`; an `xhigh`/`max` caller bumps the whole team.
- README documentation for `teammateDefaultModel` / `teammateMode` settings as an alternative to the per-spawn `Model:` lines in `/test-team`.
- **`references/fork-vs-fresh.md`** — decision record for why `/code-paper-test:test-team` spawns its three testers in fresh contexts rather than forked subagents (`CLAUDE_CODE_FORK_SUBAGENT=1`): the fresh-vs-forked tradeoff table, why fresh is the default (independent reasoning is what makes the cross-challenge debate meaningful), the re-evaluation criteria, and how to opt in. Cross-linked from `references/ai-code-auditing.md` and the SKILL.md references list.

### Changed
- **SKILL.md conciseness pass** (494 → 126 body lines, no behavior change). The full 8-step workflow, verification procedures, flaw-catalog summary, module strategy, and output template moved to the new `references/workflow.md`; SKILL.md keeps the routing, the condensed workflow, the effort guidance, and the references list.
- SKILL.md frontmatter `version: 0.7.0` → `0.9.0` — realigns the skill version with the plugin version (the v0.8.0 doc-refresh bump left the skill at 0.7.0).

### Fixed (pre-existing)
- **`commands/test-team.md` FM01 error** — the `argument-hint` value (`[--json] <file-path> [file-path...]`) was unquoted, so YAML parsed `[--json]` as a flow sequence and the trailing scalar broke the **entire frontmatter block** — the command loaded with no `description` and no `allowed-tools` at runtime. Quoted the value. This defect predates this release; it surfaced under the v3.7.x validator's FM01 check.

### Hygiene
- Plugin-root `CLAUDE.md` renamed to `CONVENTIONS.md` (validator ST03).
- `$schema` added to `plugin.json`.
- PreCompact hook migrated to exec form (`"args": []`).
- marketplace.json description trimmed 604 → 547 chars (validator X02 cap).

## [0.8.0] - 2026-04-27

### 2026-04-25 doc-refresh deltas

Closes the 2026-04-25 Claude Code doc-refresh deltas affecting this plugin (snapshot pinned at upstream commit `c142d14`). Additive throughout — no behavior change.

### Added
- **Forked subagents (experimental)** documented in `skills/paper-test/references/ai-code-auditing.md` — Claude Code 2.1.117+'s `CLAUDE_CODE_FORK_SUBAGENT=1` opt-in is a strong fit for paper-test team mode (shared loaded codebase context across the 3 teammates). Marked experimental; **not enabled by default** — the cross-challenge debate phase relies on each agent reasoning independently from a fresh frame, so the current 3-agent fresh-context spawn is intentional, not a workaround. Re-evaluation criteria included.
- **Reading-strategy citation** in `skills/paper-test/references/ai-code-auditing.md` — paper-testing AI-generated code is **Type B** (full-read, no grep-first); inherited methods, decorators, and config-wired classes that an AI hallucinated are exactly the surface grep cannot see. Cites `https://camoa.github.io/dev-guides/development/reading-strategy/` via `dev-guides-navigator`.
- **`PostToolBatch` cross-link** in `commands/test-team.md` — Claude Code 2.1.118+'s `PostToolBatch` hook is the right primitive for users who want to aggregate per-teammate JSON outputs into a single batch summary. Plugin does not ship the hook; users copy it into their own project hooks if needed.

## [0.7.0] - 2026-04-22

### Added
- **`--json` output mode** on both `/paper-test` and `/code-paper-test:test-team` for CI integration and programmatic consumption. Versioned schema (`schema_version: "1.0"`) matching the camoa-skills ecosystem convention established by code-quality-tools. Severity rubric preserved (`CRITICAL`/`HIGH`/`MEDIUM`/`LOW`/`INFO`) — no new terms introduced.
- **New reference:** `skills/paper-test/references/json-output-schema.md` — full schema, finding-object shape, team-report extensions, skill/config category vocabulary, optional `rubric_score` block, CI gate patterns, and schema-versioning contract (match `^1\.`, never exact).
- **Deterministic + Agentic pairing section** in `skill-and-config-testing.md` — documents running `plugin-creation-tools:skill-quality-reviewer` before paper-test when testing skills/commands/agents, so mechanical issues (stale SDK refs, missing imperatives, frontmatter gaps) clear cheaply before semantic analysis.
- **SKILL.md trigger phrases** expanded: `"test this agent"`, `"walk through this code"`, `"step through this"`, `"dry run"`, `"sanity check"`, `"red team this"`, `"poke holes in this"` — cover natural phrasings the prior list missed.

### Changed
- **`/code-paper-test:test-team` command** — new `--json` argument handling. Each teammate writes `{role}-analysis.json` alongside the markdown report when the flag is set; the lead aggregates per the schema into `paper-test-team-report.json` with per-teammate breakdowns (`team.happy_path` / `team.edge_case` / `team.red_team`), cross-challenge outcomes (`confirmed_by_multiple`, `disputed`, `unanimous_clean_areas`), and per-finding `found_by` / `disputed` fields.
- **PreCompact hook** now surfaces both `.md` and `.json` reports in `.reports/`.
- **SKILL.md** frontmatter `version: 0.5.0` → `0.7.0` (corrects the intentional drift left during the v0.6.0 hook-only bump).

### Fixed
- SKILL.md / plugin.json version drift — both now `0.7.0`.
- SKILL.md frontmatter gained `model: sonnet` to match the plugin's own convention (`CLAUDE.md` lists `model` as required; previously missing).

## [0.6.0] - 2026-04-08

### Changed
- **PreCompact hook** — No longer dumps test report content into compaction. Now outputs instructions for Claude to read `.reports/` files on demand, reducing compaction bloat.

## [0.5.0] - 2026-03-20

### Added
- **Structured 3-Phase mode** in `/paper-test` for 50–300 line files — runs all 3 perspectives (happy path, edge cases, adversarial) sequentially in a single agent instead of spawning 3 separate agents. Same coverage, 1/3 the cost, no coordination overhead.
- **Smart routing** in `/paper-test` — reads target files, counts lines, and recommends the appropriate approach: quick trace (<50), structured 3-phase (50–300), or `/test-team` (300+ / security-critical / skills).
- **Self-review phase (Phase D)** in structured mode — after all 3 phases, the agent reviews its own findings for false positives, blind spots, and cross-phase confirmation.

### Changed
- **`/test-team` threshold raised** — now recommends itself for 300+ lines, security-critical code, or skill/command testing. For 50–300 lines, redirects to `/paper-test` structured 3-phase with explanation of cost savings. Under 50 lines, stops and redirects to `/paper-test` quick trace.
- **Skill/command routing preserved** in `/test-team` — the 3-agent team is still recommended for skill/command files regardless of line count, because perspective diversity (happy path vs edge case vs red team) genuinely finds different things for instruction-based testing.

## [0.4.3] - 2026-03-20

### Changed
- **`commands/test-team.md`**: Added `effort: high` to Edge Case Hunter and Red Team Attacker spawn specs — these agents perform exhaustive boundary and adversarial analysis and benefit from extended reasoning
- **`commands/test-team.md`**: Added dual-control completion pattern to all three teammate "WHEN DONE" blocks — agents can exit with code 2 (feedback loop) or output `{"continue": false}` (hard stop) to signal task completion to the lead
- **`hooks/pre-compact.sh`**: Fixed filename mismatch — hook was looking for `paper-test-synthesis.md` but the command writes `paper-test-team-report.md`; now correctly preserves the synthesis report on compaction

### Notes
- Frontmatter fields `hooks`, `mcpServers`, and `permissionMode` are silently ignored for plugin-packaged agents; spawn specs in this plugin use prose format only — no such fields are present

---

## [0.4.1] - 2026-03-15

### Added
- **PreCompact hook**: Preserves test team analysis reports (happy-path, edge-case, red-team, synthesis) before conversation compaction

## [0.4.0] - 2026-03-13

### Added

**Track A — Methodology Depth**
- **Data flow tracking** (Step 2b) — track type transformations across function boundaries
- **Error propagation tracing** — follow exceptions up the call stack, check for partial state
- **Untested path analysis** (Step 8) — identify code paths never exercised, assess risk
- **N+1 and performance pattern detection** — flag N+1 queries, nested loops, missing cache
- **Config validation** — verify YAML/JSON/services values match what code expects
- **State machine validation** — verify all state transitions valid, reachable, guarded (in advanced-techniques.md)
- **`references/severity-scoring.md`** — consistent severity rubric with 4-factor scoring (Reach, Impact, Reversibility, Exploitability)
- **`references/blind-ab-comparison.md`** — compare two implementations with shared scenarios and blind protocol
- **`references/rubric-scoring.md`** — structured grading system (Content + Structure, 50-point scale) with quality gate support

**Track B — Plugin Infrastructure**
- `maxTurns: 15` on all 3 test-team agents (cost control)
- `isolation: worktree` on all 3 test-team agents (independent repo access)
- `allowed-tools: Read, Glob, Grep, Bash` on paper-test skill
- `user-invocable: true` on paper-test skill
- Pushy descriptions with comprehensive trigger phrases on skill and command
- Quality gate enforcement on test-team agents (must complete ALL assigned categories)
- Model routing note: opus option for Red Team Attacker on complex security analysis

**Track C — Skill/Config Testing**
- **`references/skill-and-config-testing.md`** — extend paper testing to non-code artifacts
  - Trigger analysis, instruction tracing, frontmatter verification, context budget, fidelity testing, agent team coordination, config file testing
- Skill-mode auto-detection in test-team command (frontmatter → instruction tracing)
- Updated "When to Use" to include skills, commands, agents, configs

### Changed
- Removed experimental agent teams flag — agent teams are now GA
- SKILL.md version 0.2.0 → 0.4.0 (aligned with plugin)
- plugin.json description and keywords updated for skill/config testing
- CLAUDE.md expanded with "What This Plugin Tests" section
- README.md rewritten for v0.4.0

---

## [0.3.0] - 2026-02-11

### Added
- **NEW: `/test-team` command** — paper test code with competing agent team (3 perspectives)
  - **Happy Path Validator** (sonnet) — traces correct flow with ideal inputs, verifies dependencies and contracts
  - **Edge Case Hunter** (sonnet) — probes boundaries: nulls, empty, zero, large values, type mismatches
  - **Red Team Attacker** (sonnet) — adversarial inputs: injection, path traversal, race conditions, resource exhaustion
  - Cross-challenge debate resolves flaw severity and disputes false findings
  - Lead synthesizes prioritized flaw report next to target code
  - Scope gate: suggests standard paper test for <50 lines
  - Falls back to standard paper test skill when agent teams not available
  - Requires experimental flag: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`
- `commands/` directory — first command in this plugin
- `.claude/rules/command-conventions.md` for path-scoped command standards
- Command conventions section in `CLAUDE.md`

---

## [0.2.0] - 2026-02-09

### Added
- `model: sonnet` routing on paper-test skill for cost optimization
- `CLAUDE.md` plugin conventions file
- `.claude/rules/skill-conventions.md` for path-scoped skill standards
- Version bumped to 0.2.0 in SKILL.md frontmatter

### Changed
- Aligned with camoa-skills plugin standards (model routing, rules, conventions)

---

## [0.1.1] - 2025-12-26

### Added

**Advanced Testing Techniques** - New reference guide adapting security tabletop exercise methodologies

#### New Reference File
- `references/advanced-techniques.md` (938 lines) - Decision-focused advanced testing techniques

#### Techniques Covered
1. **Progressive Inject Testing**
   - Incrementally add complications to test scenarios
   - Test resilience under cascading failures
   - Template for designing inject sequences
   - Full authentication flow example with 5 injects

2. **Red Team Edge Case Discovery**
   - Adversarial mindset for finding edge cases
   - Security-focused attack questions
   - Payment processing red team analysis example
   - Attack surface ranking and prioritization

3. **Attack Surface Analysis**
   - Map all entry points to code
   - Rank by risk exposure
   - Prioritize testing effort
   - E-commerce checkout example

4. **Scenario-Based Workflow Testing**
   - End-to-end user workflows vs isolated functions
   - Integration bug detection
   - Complete purchase workflow example with 8 steps
   - Data handoff verification between components

5. **After-Action Report (AAR) Format**
   - Structured documentation of findings
   - Root cause analysis methodology
   - Improvement plan with owners and dates
   - Full AAR example with 4 critical gaps found

#### Design Philosophy
- **Decision-focused**: "When to use X vs Y" not tutorials
- **Concise**: One excellent example per technique
- **No duplication**: Assumes Claude knows security concepts
- **Under limits**: 938 lines (well under 1,000 line guideline)

#### Updated Files
- SKILL.md: Added reference to advanced-techniques.md
- CHANGELOG.md: This entry

### Value Proposition
Adapted proven security tabletop exercise methodologies to code testing, providing systematic approaches for complex scenarios that standard paper testing doesn't cover.

---

## [0.1.0] - 2025-12-26

### Added

**Initial Release** - Comprehensive paper testing plugin for mental code execution

#### Core Features
- Systematic line-by-line code tracing with concrete values
- External dependency verification (methods, signatures, return types)
- Code contract verification (8 patterns)
- AI-generated code auditing
- Hybrid testing strategy (flow-based + component edge cases)
- Common flaw catalog

#### Documentation Structure
- Main workflow in `SKILL.md` (352 lines)
- 6 detailed reference guides (2,934 lines total):
  - `core-method.md` (471 lines) - Complete testing methodology
  - `dependency-verification.md` (359 lines) - External call verification
  - `contract-patterns.md` (663 lines) - 8 code contract patterns
  - `ai-code-auditing.md` (351 lines) - AI code specific checks
  - `hybrid-testing.md` (452 lines) - Module testing strategy
  - `common-flaws.md` (638 lines) - Comprehensive bug catalog

#### Contract Pattern Coverage
Templates for 8 code relationship patterns:
1. Inheritance (abstract methods, parent calls)
2. Plugin Systems (Drupal, WordPress annotations)
3. Dependency Injection (service verification)
4. Interface Implementation (signature matching)
5. Traits (requirements, conflicts)
6. Event/Hook Systems (signatures, returns)
7. Middleware/Decorators (chain calls)
8. Service Collectors/Tagged Services (Drupal, Symfony)

#### AI-Specific Features
- Hallucinated method detection
- Mixed API version identification
- Wrong parameter order detection
- Return type assumption verification

#### Testing Methodology
- Flow-based testing (end-to-end integration)
- Component edge case testing
- Coverage-driven approach (all components in ≥1 flow)
- Parallel agent testing strategies

#### Value Proposition
Addresses AI code generation quality issues in 2025:
- 30-60% of code now AI-generated
- Traditional testing misses logic errors
- AI-powered paper testing verifies before deployment

### Files
```
code-paper-test/
├── .claude-plugin/plugin.json (v0.1.0)
├── skills/paper-test/
│   ├── SKILL.md
│   └── references/
│       ├── ai-code-auditing.md
│       ├── common-flaws.md
│       ├── contract-patterns.md
│       ├── core-method.md
│       ├── dependency-verification.md
│       └── hybrid-testing.md
├── CHANGELOG.md
├── LICENSE
└── README.md
```

### Marketplace
- Added to camoa-skills marketplace
- Keywords: testing, debugging, code-review, paper-testing, mental-execution, bug-detection, ai-code-auditing, contract-verification, dependency-verification
