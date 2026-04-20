# Parse Claude Code Review Check-Run JSON

Claude Code's managed Code Review posts inline PR comments AND populates a **Claude Code Review** check run alongside your CI checks. The check run's Details text ends with a machine-readable JSON line you can parse with `gh` + `jq` to gate merges on severity counts.

## Output shape

```json
{"normal": 2, "nit": 1, "pre_existing": 0}
```

| Key | What it counts |
|---|---|
| `normal` | **Important** findings (🔴) — the severity was renamed in the UI but the JSON key stays `normal` for backwards compatibility |
| `nit` | Nit findings (🟡) — minor issues, worth fixing but not blocking |
| `pre_existing` | Pre-existing bugs (🟣) — present in the codebase but not introduced by this PR |

A non-zero `normal` count means Claude found at least one bug worth fixing before merge. The check run itself always completes with a neutral conclusion (never blocks merge via branch protection), so enforcement is on you.

## Fetch and parse

One-liner (current PR check-run). Use `[-1]` (last occurrence) to defend against the slim-but-real risk that PR content quoted back into the Details text contains a literal `bughunter-severity:` marker earlier in the output:

```bash
gh api repos/OWNER/REPO/check-runs/CHECK_RUN_ID \
  --jq '.output.text | split("bughunter-severity: ") | last | split(" -->")[0] | fromjson'
```

**Defensive pattern** (recommended for CI gates — fails safely on missing marker or malformed JSON):

```bash
JSON=$(gh api "repos/$REPO/check-runs/$CHECK_RUN_ID" \
  --jq '.output.text | split("bughunter-severity: ") | last | split(" -->")[0] | fromjson' \
  2>/dev/null || echo '{}')
# Treat absent marker OR malformed JSON as "gate indeterminate — block merge"
NORMAL=$(echo "$JSON" | jq -r '.normal // null')
if [ "$NORMAL" = "null" ]; then
  echo "::error::Could not parse Claude Code Review severity — blocking merge out of caution"
  exit 1
fi
```

Discover the check-run ID for a PR:

```bash
PR=1234
CHECK_RUN_ID=$(
  gh api "repos/$OWNER/$REPO/commits/$(gh pr view "$PR" --json headRefOid -q .headRefOid)/check-runs" \
    --jq '.check_runs[] | select(.name == "Claude Code Review") | .id' \
    | tail -1
)
```

## GitHub Actions — fail merge on Important findings

Drop into `.github/workflows/quality-gate.yml`. Waits for the Claude Code Review check run to finish, then parses its JSON and fails if `normal > 0`.

```yaml
name: Quality Gate
on:
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
  gate-on-review:
    runs-on: ubuntu-latest
    permissions:
      checks: read
      pull-requests: read
    steps:
      - name: Wait for Claude Code Review to finish
        id: wait
        env:
          GH_TOKEN: ${{ github.token }}
          REPO: ${{ github.repository }}
          SHA: ${{ github.event.pull_request.head.sha }}
        run: |
          for _ in $(seq 1 60); do
            STATE=$(gh api "repos/$REPO/commits/$SHA/check-runs" \
              --jq '.check_runs[] | select(.name=="Claude Code Review") | .status' \
              | tail -1)
            if [ "$STATE" = "completed" ]; then
              echo "done=1" >> "$GITHUB_OUTPUT"
              break
            fi
            sleep 30
          done
          if [ "${{ steps.wait.outputs.done }}" != "1" ]; then
            echo "::error::Claude Code Review did not complete within 30 min — gate indeterminate, blocking merge"
            exit 1
          fi

      - name: Parse severity counts
        if: steps.wait.outputs.done == '1'
        env:
          GH_TOKEN: ${{ github.token }}
          REPO: ${{ github.repository }}
          SHA: ${{ github.event.pull_request.head.sha }}
        run: |
          CHECK_ID=$(gh api "repos/$REPO/commits/$SHA/check-runs" \
            --jq '.check_runs[] | select(.name=="Claude Code Review") | .id' \
            | tail -1)
          if [ -z "$CHECK_ID" ]; then
            echo "::error::No Claude Code Review check run found — gate indeterminate, blocking merge"
            exit 1
          fi
          # `last` defends against PR content echoing a fake marker earlier in the output
          JSON=$(gh api "repos/$REPO/check-runs/$CHECK_ID" \
            --jq '.output.text | split("bughunter-severity: ") | last | split(" -->")[0] | fromjson' \
            2>/dev/null || echo '{}')
          NORMAL=$(echo "$JSON" | jq -r '.normal // null')
          if [ "$NORMAL" = "null" ]; then
            echo "::error::Could not parse check-run severity marker — blocking merge"
            exit 1
          fi
          echo "Severity counts: $JSON"
          if [ "$NORMAL" -gt 0 ]; then
            echo "::error::Claude Code Review found $NORMAL Important finding(s). Block merge."
            exit 1
          fi
```

## GitLab CI pattern

```yaml
quality-gate:
  stage: verify
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
  script:
    - |
      # Use the GitHub mirror commit SHA mapped into GitLab, or use the
      # Claude session ID if your pipeline uses a routine callback instead.
      # GitLab CI consuming GitHub check runs requires a GitHub token.
      NORMAL=$(gh api "repos/$GITHUB_REPO/check-runs/$CHECK_ID" \
        --jq '.output.text | split("bughunter-severity: ")[1] | split(" -->")[0] | fromjson | .normal')
      test "$NORMAL" -eq 0 || { echo "Merge blocked: $NORMAL Important findings"; exit 1; }
```

## Backwards-compat note

The JSON `normal` key corresponds to the UI's **Important** severity. The rename was UI-only; the JSON shape stayed stable so existing parsers don't break. When writing your own tooling:

- Read the count from the `normal` key
- Display it to humans as "Important" (match the UI)
- Don't rename the key in downstream pipelines — other tools may expect `normal`

## See also

- `review-md-v2.md` — author REVIEW.md to control what gets flagged as Important
- `premerge-gate-routine.md` — alternative enforcement path via Cloud Routine when managed Code Review isn't available
- Upstream: [`/en/code-review`](https://docs.claude.com/en/code-review)
