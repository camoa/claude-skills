# Changelog

All notable changes to the code-paper-test plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
