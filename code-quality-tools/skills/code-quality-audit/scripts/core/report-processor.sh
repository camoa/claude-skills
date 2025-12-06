#!/bin/bash
# report-processor.sh - Convert JSON audit reports to Markdown
# Part of code-quality-audit skill

set -e

REPORT_DIR="${REPORT_DIR:-./reports/quality}"
INPUT_FILE="${1:-${REPORT_DIR}/audit-report.json}"
OUTPUT_FILE="${2:-${REPORT_DIR}/audit-report.md}"

# Check for jq
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required for JSON processing"
    echo "Install with: apt-get install jq (Linux) or brew install jq (Mac)"
    exit 1
fi

# Check input file
if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file not found: $INPUT_FILE"
    exit 1
fi

# Status icons
icon_pass="✅"
icon_warn="⚠️"
icon_fail="❌"

# Get icon for status
get_icon() {
    case "$1" in
        pass) echo "$icon_pass" ;;
        warning) echo "$icon_warn" ;;
        fail) echo "$icon_fail" ;;
        *) echo "❓" ;;
    esac
}

# Generate Markdown report
generate_markdown() {
    local json="$INPUT_FILE"

    # Extract data
    local project_type=$(jq -r '.meta.project_type // "unknown"' "$json")
    local project_path=$(jq -r '.meta.project_path // "."' "$json")
    local timestamp=$(jq -r '.meta.timestamp // "unknown"' "$json")
    local overall_score=$(jq -r '.summary.overall_score // "unknown"' "$json")

    # Summary scores
    local coverage_score=$(jq -r '.summary.coverage_score // "unknown"' "$json")
    local solid_score=$(jq -r '.summary.solid_score // "unknown"' "$json")
    local dry_score=$(jq -r '.summary.dry_score // "unknown"' "$json")

    # Counts
    local critical_count=$(jq -r '.summary.critical_issues // 0' "$json")
    local warning_count=$(jq -r '.summary.warnings // 0' "$json")
    local suggestion_count=$(jq -r '.summary.suggestions // 0' "$json")

    # Coverage data
    local line_coverage=$(jq -r '.coverage.line_coverage // "N/A"' "$json")
    local coverage_min=$(jq -r '.meta.thresholds.coverage_minimum // 70' "$json")
    local coverage_target=$(jq -r '.meta.thresholds.coverage_target // 80' "$json")

    # DRY data
    local duplication_pct=$(jq -r '.dry.duplication_percentage // "N/A"' "$json")
    local duplication_max=$(jq -r '.meta.thresholds.duplication_max // 5' "$json")

    # Generate markdown
    cat > "$OUTPUT_FILE" << EOF
# Code Quality Audit Report

**Project**: ${project_path} (${project_type})
**Date**: ${timestamp}
**Overall Score**: $(get_icon "$overall_score") ${overall_score^^}

## Summary

| Metric | Score | Status |
|--------|-------|--------|
| Test Coverage | ${line_coverage}% | $(get_icon "$coverage_score") ${coverage_score} |
| SOLID Compliance | - | $(get_icon "$solid_score") ${solid_score} |
| DRY (Duplication) | ${duplication_pct}% | $(get_icon "$dry_score") ${dry_score} |

**Issues**: ${critical_count} Critical, ${warning_count} Warnings, ${suggestion_count} Suggestions

---

## Coverage Analysis

**Line Coverage**: ${line_coverage}% (target: ${coverage_target}%, minimum: ${coverage_min}%)

EOF

    # Add uncovered files if available
    local uncovered_count=$(jq '.coverage.uncovered_files | length' "$json" 2>/dev/null || echo "0")
    if [ "$uncovered_count" -gt 0 ]; then
        echo "### Uncovered Files (lowest coverage)" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        echo "| File | Coverage |" >> "$OUTPUT_FILE"
        echo "|------|----------|" >> "$OUTPUT_FILE"
        jq -r '.coverage.uncovered_files[] | "| \(.file) | \(.coverage)% |"' "$json" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
    fi

    cat >> "$OUTPUT_FILE" << EOF
---

## SOLID Violations

EOF

    # Critical violations
    local critical_violations=$(jq '[.solid.violations[] | select(.severity == "critical")] | length' "$json" 2>/dev/null || echo "0")
    echo "### Critical (${critical_violations})" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    if [ "$critical_violations" -gt 0 ]; then
        jq -r '.solid.violations[] | select(.severity == "critical") | "- **\(.principle)** in `\(.file):\(.line)`: \(.message)"' "$json" >> "$OUTPUT_FILE"
    else
        echo "_No critical violations_" >> "$OUTPUT_FILE"
    fi
    echo "" >> "$OUTPUT_FILE"

    # Warnings
    local warning_violations=$(jq '[.solid.violations[] | select(.severity == "warning")] | length' "$json" 2>/dev/null || echo "0")
    echo "### Warnings (${warning_violations})" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    if [ "$warning_violations" -gt 0 ]; then
        jq -r '.solid.violations[] | select(.severity == "warning") | "- **\(.principle)** in `\(.file):\(.line)`: \(.message)"' "$json" >> "$OUTPUT_FILE"
    else
        echo "_No warnings_" >> "$OUTPUT_FILE"
    fi
    echo "" >> "$OUTPUT_FILE"

    cat >> "$OUTPUT_FILE" << EOF
---

## DRY Analysis

**Duplication**: ${duplication_pct}% (threshold: <${duplication_max}%)

EOF

    # Add clones if available
    local clone_count=$(jq '.dry.clones | length' "$json" 2>/dev/null || echo "0")
    if [ "$clone_count" -gt 0 ]; then
        echo "### Detected Clones (${clone_count})" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        jq -r '.dry.clones[] | "- **\(.lines) lines** duplicated between:\n  - `\(.files[0].file):\(.files[0].start_line)-\(.files[0].end_line)`\n  - `\(.files[1].file):\(.files[1].start_line)-\(.files[1].end_line)`"' "$json" >> "$OUTPUT_FILE" 2>/dev/null || true
    else
        echo "_No significant duplication detected_" >> "$OUTPUT_FILE"
    fi

    cat >> "$OUTPUT_FILE" << EOF

---

## Recommendations

EOF

    # High priority
    echo "### High Priority" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    local high_count=$(jq '[.recommendations[] | select(.priority == "high")] | length' "$json" 2>/dev/null || echo "0")
    if [ "$high_count" -gt 0 ]; then
        jq -r '.recommendations[] | select(.priority == "high") | "- [\(.category)] \(.message)\n  - Action: \(.action)"' "$json" >> "$OUTPUT_FILE"
    else
        echo "_No high priority recommendations_" >> "$OUTPUT_FILE"
    fi
    echo "" >> "$OUTPUT_FILE"

    # Medium priority
    echo "### Medium Priority" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    local med_count=$(jq '[.recommendations[] | select(.priority == "medium")] | length' "$json" 2>/dev/null || echo "0")
    if [ "$med_count" -gt 0 ]; then
        jq -r '.recommendations[] | select(.priority == "medium") | "- [\(.category)] \(.message)"' "$json" >> "$OUTPUT_FILE"
    else
        echo "_No medium priority recommendations_" >> "$OUTPUT_FILE"
    fi

    cat >> "$OUTPUT_FILE" << EOF

---

## Tool Versions

EOF

    # Tool versions table
    jq -r '.meta.tool_versions | to_entries | .[] | "| \(.key) | \(.value) |"' "$json" 2>/dev/null | {
        echo "| Tool | Version |"
        echo "|------|---------|"
        cat
    } >> "$OUTPUT_FILE"

    cat >> "$OUTPUT_FILE" << EOF

---

*Generated by code-quality-audit skill*
EOF

    echo "Markdown report generated: $OUTPUT_FILE"
}

# Main
generate_markdown
