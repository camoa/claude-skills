# Changelog

All notable changes to the code-paper-test plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
