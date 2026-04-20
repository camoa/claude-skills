# REVIEW.md for Plugin Repositories

Claude Code's managed Code Review service reads two files from the repo it's reviewing: `CLAUDE.md` (general project context) and `REVIEW.md` (review-only instructions). For plugin-repo maintainers, `REVIEW.md` is the right place to scope reviews to plugin-specific concerns.

## The two-file model

| File | Scope | Priority in review pipeline |
|------|-------|-----------------------------|
| `CLAUDE.md` | All Claude Code tasks, not just reviews. Context for how code should look | Read as project context; newly introduced violations flagged as nits |
| `REVIEW.md` | Review-only instructions | Injected into every review-agent system prompt as the **highest-priority** block |

`REVIEW.md` wins every conflict during reviews. Use it to reshape severity calibration, skip paths, and enforce repo-specific checks that shouldn't apply to interactive sessions.

**`@` import syntax is not expanded** in `REVIEW.md`. Anything you want enforced must be written inline.

## What to tune

| Lever | What it does | Example |
|-------|--------------|---------|
| **Severity** | Redefine what "Important" vs "Nit" means for your repo | "Treat missing frontmatter as Important; treat style suggestions as Nit at most." |
| **Nit volume** | Cap how many yellow/nit comments a single review posts | "Post at most 5 nits inline; mention the rest as a count." |
| **Skip rules** | Paths, branches, or categories to skip entirely | "Skip `examples/**` and `*.lock`; skip anything CI already enforces." |
| **Repo-specific checks** | Must-flag-on-every-PR rules | "Every new skill must have valid YAML frontmatter and `description` under 1,536 chars." |
| **Verification bar** | Require evidence before a class of finding is posted | "Behavior claims need a `file:line` citation, not inference from naming." |
| **Re-review convergence** | How to behave after round 1 | "After the first review, suppress new nits; post Important findings only." |
| **Summary shape** | Opening tally / TL;DR format | "Open with a one-line tally: `X factual, Y style`. Lead with 'no factual issues' when true." |

## Starter REVIEW.md for a plugin repo

```markdown
# Review instructions

## What Important means here

Important is reserved for findings that:
- Break plugin loading (malformed `plugin.json`, missing frontmatter)
- Violate the Claude Code plugin schema (unknown keys, invalid event names,
  broken hook matcher syntax)
- Introduce a security regression (hooks auto-approving in `auto` mode,
  shell injection in hook scripts, path traversal in marketplace sources)
- Break dependency resolution (semver ranges, tag convention violations)

Style, naming, and refactoring suggestions are Nit at most.

## Cap the nits

Report at most 5 nits inline. If there are more, say "plus N similar items"
in the summary. If everything is a Nit, open with "No blocking issues."

## Do not report

- Anything the `/plugin-creation-tools:validate` command already catches
  (the PR pipeline runs it — no point duplicating)
- Lockfiles, generated JSON schemas, and vendored dependencies
- Files under `examples/**` that intentionally demonstrate anti-patterns
- Style/formatting checks run by the lint step

## Always check

- Every new skill/agent/command file has a `version` frontmatter field
- Skill descriptions stay under 1,536 characters combined with `when_to_use`
- Hook examples using broad matchers include an `if` field where tool-event
  applicable
- Any `Claude Code SDK` mention has been updated to `Agent SDK` (link:
  `references/11-agent-sdk/migration.md`)
- Plugin-version bumps touch **both** `plugin.json` AND the repo-root
  `marketplace.json`
- New dependencies use the `{name}--v{version}` tag convention

## Verification bar

For behavior claims in a new skill description, require a test or a clear
runtime signal. Inferring from the name is not enough.

## Re-review convergence

After the first review, suppress new nits. Post Important findings only.
A one-line fix should not reach round three on style.

## Summary shape

Open the summary with a one-line tally:
`N factual, M style` — or `No factual issues` when that's the case.
Lead with the shape before the details.
```

**Keep it focused.** A 300-line `REVIEW.md` dilutes the rules that matter. The example above is ~40 lines of actionable instruction. If your repo grows beyond that, split project context into `CLAUDE.md` and keep `REVIEW.md` for rules that should only fire during review.

## `/ultrareview` for pre-merge deep review

`REVIEW.md` runs automatically on every PR (configurable). For a deeper, multi-agent review before a risky merge, the `/ultrareview` slash command runs a browser-based review session with a dedicated agent team. Use it when:

- Merging a large plugin version bump (major release, schema changes)
- A PR touches multiple plugins in a shared marketplace
- A contributor outside the core team is opening their first PR

`/ultrareview` is additive to `REVIEW.md` — it inherits the same rules. The dedicated review agents just work the diff more thoroughly.

## Cross-links

- [`packaging.md`](packaging.md) — how your plugin is packaged before distribution
- [`routines-auto-validate.md`](routines-auto-validate.md) — auto-run `/plugin-creation-tools:validate` on every PR via a Routine
- Upstream: [Code Review](https://docs.claude.com/en/code-review), [Ultrareview](https://docs.claude.com/en/ultrareview)
