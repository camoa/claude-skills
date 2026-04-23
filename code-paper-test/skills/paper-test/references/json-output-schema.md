# JSON Output Schema (`--json` mode)

Stable, versioned schema for CI integration, aggregation, and programmatic consumption. Emitted by `/paper-test --json <file>` and `/code-paper:test-team --json <file>`.

Shape follows the camoa-skills ecosystem convention established by `code-quality-tools/skills/code-quality-audit/references/json-schemas.md` — the same envelope fields (`schema_version`, `timestamp`, `target`, `status`, `summary`, `findings`) so downstream tooling can treat reports from both plugins uniformly.

## Invariants (CI pipelines rely on these)

1. **`findings` is always an array.** Zero findings = `[]`, never `null`, never omitted. Downstream `jq '.findings[]'` must never fail on "clean trace with no flaws."
2. **`status` reflects the gate verdict** — `fail` if any finding is `CRITICAL` or `HIGH`; `warning` if any finding is `MEDIUM`, `LOW`, or `INFO` but none are `CRITICAL` / `HIGH`; `pass` only when `findings` is empty. Untested, aborted, or prematurely stopped runs use `status: "warning"` (never `pass`).
3. **`schema_version` is semver on the schema itself**, independent of plugin version. Additive changes bump minor (`1.0` → `1.1`); breaking changes bump major (`1.0` → `2.0`).

   > **CI pinning:** match `^1\.` (`jq: test("^1\\.")`), NOT `== "1.0"` exactly — additive minor bumps are back-compat and should not break your gate.
   > ```bash
   > echo "$result" | jq -e '.schema_version | test("^1\\.")' >/dev/null || exit 1
   > ```
4. **String fields are JSON-escaped.** Newlines, quotes, and backslashes in `title`, `description`, `fix_suggestion`, and file excerpts must not corrupt the document. Validate with `echo "$OUTPUT" | jq .` before trusting it in a gate.
5. **Severity values match the existing rubric exactly** — `CRITICAL`, `HIGH`, `MEDIUM`, `LOW`, `INFO` (uppercase). Do not introduce new terms. See `severity-scoring.md`.

## Common envelope

All paper-test JSON reports share this shape:

```json
{
  "schema_version": "1.0",
  "tool": "paper-test | test-team",
  "mode": "quick | structured-3-phase | test-team",
  "target_type": "code | skill | config",
  "target_files": ["path/to/file.php"],
  "timestamp": "2026-04-22T12:00:00Z",
  "status": "pass | warning | fail",
  "summary": {
    "critical": 0,
    "high": 0,
    "medium": 0,
    "low": 0,
    "info": 0,
    "total_findings": 0,
    "scenarios_traced": 0,
    "dependencies_verified": 0,
    "contracts_verified": 0
  },
  "findings": []
}
```

## Finding object

Every entry in `findings[]`:

```json
{
  "severity": "CRITICAL",
  "category": "data-flow",
  "file": "src/Service/PaymentService.php",
  "line_start": 87,
  "line_end": 92,
  "title": "Unvalidated amount leaks to downstream charge call",
  "description": "User-controlled $amount is not bounds-checked before being passed to $gateway->charge(). Negative values pass type validation but reverse the transaction.",
  "fix_suggestion": "Add `if ($amount <= 0) throw new InvalidArgumentException()` before line 89.",
  "scoring_factors": {
    "reach": 3,
    "impact": 3,
    "reversibility": 3,
    "exploitability": 3
  }
}
```

### Field notes

- **`severity`** — one of `CRITICAL | HIGH | MEDIUM | LOW | INFO`. Derived from `scoring_factors` sum per the matrix in `severity-scoring.md`.
- **`category`** — short kebab-case string. Standard values for code targets: `data-flow`, `error-propagation`, `dependency-verification`, `contract-violation`, `null-access`, `edge-case`, `performance`, `security`, `ai-hallucination`, `state-issue`, `flow-issue`. Skill/config targets use the list in the "Skill/Config target_type" section below. Other values allowed — consumers should treat as opaque strings.
- **`line_end`** — equals `line_start` for single-line findings. Always present.
- **`fix_suggestion`** — one-line actionable fix. May include code snippets (remember invariant 4).
- **`scoring_factors`** — all four keys required (`reach`, `impact`, `reversibility`, `exploitability`), each `1`, `2`, or `3`. Omit the object only for `INFO` findings where scoring doesn't apply.

## `/paper-test --json` output

Quick-trace and structured-3-phase modes emit the common envelope directly. Write location: stdout (or `--output <path>` to write to a file sibling to the target).

Example for a passing trace with one low-severity finding:

```json
{
  "schema_version": "1.0",
  "tool": "paper-test",
  "mode": "structured-3-phase",
  "target_type": "code",
  "target_files": ["src/Service/UserService.php"],
  "timestamp": "2026-04-22T12:00:00Z",
  "status": "warning",
  "summary": {
    "critical": 0,
    "high": 0,
    "medium": 0,
    "low": 1,
    "info": 0,
    "total_findings": 1,
    "scenarios_traced": 7,
    "dependencies_verified": 4,
    "contracts_verified": 2
  },
  "findings": [
    {
      "severity": "LOW",
      "category": "null-access",
      "file": "src/Service/UserService.php",
      "line_start": 42,
      "line_end": 42,
      "title": "Missing null check on optional email lookup",
      "description": "loadByEmail() returns User|null but line 42 accesses ->getId() without guard.",
      "fix_suggestion": "Wrap in `if ($user !== null)` or use nullsafe `?->getId()`.",
      "scoring_factors": {"reach": 1, "impact": 2, "reversibility": 1, "exploitability": 1}
    }
  ]
}
```

## `/code-paper:test-team --json` output

Test-team mode emits the common envelope PLUS a `team` section holding per-teammate breakdowns and the cross-challenge debate outcome. Write location: `{target_dir}/paper-test-team-report.json` (sibling to the existing `paper-test-team-report.md`). Each teammate also writes `{role}-analysis.json` in `{target_dir}` so the lead can aggregate without re-parsing markdown.

The example below shows the shape only — the individual counts (`confirmed_by_multiple`, per-teammate `findings_count`, etc.) are illustrative and will not be cross-consistent with the single truncated finding shown.

```json
{
  "schema_version": "1.0",
  "tool": "test-team",
  "mode": "test-team",
  "target_type": "code",
  "target_files": ["src/Service/PaymentService.php"],
  "timestamp": "2026-04-22T12:00:00Z",
  "status": "fail",
  "summary": {
    "critical": 1,
    "high": 2,
    "medium": 3,
    "low": 4,
    "info": 0,
    "total_findings": 10,
    "scenarios_traced": 18,
    "dependencies_verified": 7,
    "contracts_verified": 3
  },
  "team": {
    "happy_path": {
      "scenarios": 5,
      "findings_count": 1,
      "source": "happy-path-analysis.json"
    },
    "edge_case": {
      "scenarios": 8,
      "categories_tested": 6,
      "findings_count": 5,
      "source": "edge-case-analysis.json"
    },
    "red_team": {
      "attack_categories_tested": 7,
      "exploitable": 2,
      "blocked": 3,
      "findings_count": 4,
      "source": "red-team-analysis.json"
    },
    "cross_challenge": {
      "confirmed_by_multiple": 6,
      "disputed": 2,
      "unanimous_clean_areas": ["src/Service/PaymentService.php:100-140"]
    }
  },
  "findings": [
    {
      "severity": "CRITICAL",
      "category": "security",
      "file": "src/Service/PaymentService.php",
      "line_start": 87,
      "line_end": 92,
      "title": "SQL injection via unescaped order_id",
      "description": "...",
      "fix_suggestion": "...",
      "scoring_factors": {"reach": 3, "impact": 3, "reversibility": 3, "exploitability": 3},
      "found_by": ["red_team", "edge_case"],
      "disputed": false
    }
  ]
}
```

### Team-specific finding fields

When `tool` is `"test-team"`, each finding gains:

- **`found_by`** — array of teammate roles that flagged this finding: any of `"happy_path"`, `"edge_case"`, `"red_team"`.
- **`disputed`** — boolean. `true` if another teammate challenged the finding during cross-challenge. Dispute resolution narrative lives in the markdown report; JSON only records whether dispute occurred.

## Skill/config `target_type`

When `target_type` is `"skill"` or `"config"`, `findings[].category` uses instruction-testing vocabulary instead of code-testing vocabulary:

- `trigger-analysis` — will Claude invoke this skill on the intended phrases? See `skill-and-config-testing.md` §1.
- `instruction-fidelity` — will Claude follow step N after executing step M? Step drift, missed conditionals.
- `frontmatter-verification` — declared `allowed-tools` / `model` / `description` match the body's actual tool use and claims.
- `context-budget` — instruction/reference size vs. likely context window at invocation time.
- `tool-reference-existence` — does every tool, file, skill, or agent named in the body actually exist?
- `dependency-verification` — for configs, do the keys the consuming code reads actually exist and have the expected types?

Example skill finding:

```json
{
  "severity": "MEDIUM",
  "category": "instruction-fidelity",
  "file": "skills/my-skill/SKILL.md",
  "line_start": 78,
  "line_end": 82,
  "title": "Step 5 references file that step 2 never wrote",
  "description": "Step 5 instructs Claude to Read `.reports/analysis.md` but no prior step writes that file.",
  "fix_suggestion": "Add explicit Write step before step 5, or change step 5 to conditional on file existence.",
  "scoring_factors": {"reach": 2, "impact": 2, "reversibility": 1, "exploitability": 1}
}
```

## Optional `rubric_score` block

When the rubric-scoring methodology runs (see `rubric-scoring.md`), the envelope gains a `rubric_score` field:

```json
{
  "rubric_score": {
    "content_total": 20,
    "structure_total": 22,
    "overall": 42,
    "grade": "Good",
    "quality_gate": "PASS",
    "content_breakdown": {
      "correctness": 5,
      "completeness": 4,
      "edge_cases": 3,
      "error_handling": 4,
      "security": 4
    },
    "structure_breakdown": {
      "readability": 5,
      "separation": 4,
      "dry": 4,
      "testability": 4,
      "extensibility": 5
    }
  }
}
```

`quality_gate` values: `"PASS"` (overall ≥ 35) | `"FAIL"` (< 35). See `rubric-scoring.md` for the full scoring rubric.

## CI gate patterns

**Fail the build on any HIGH or CRITICAL:**

```bash
result=$(/paper-test --json src/Service/PaymentService.php)
echo "$result" | jq -e '.status != "fail"' >/dev/null || exit 1
```

**Aggregate team report into a summary:**

```bash
jq '{
  target: .target_files[0],
  grade: (.rubric_score.grade // "ungraded"),
  critical: .summary.critical,
  high: .summary.high,
  disputed_count: [.findings[] | select(.disputed == true)] | length
}' paper-test-team-report.json
```

## Schema versioning contract

- **1.x** — current. Additive only. New optional fields, new category strings, new severity-neutral envelope fields. Consumers pinning `^1\.` stay safe.
- **2.0** — reserved for breaking changes. Examples of breaking: renaming `findings` to `issues`, changing severity casing to lowercase, removing `scoring_factors`. Any such change requires a new major and a migration note in the plugin CHANGELOG.
