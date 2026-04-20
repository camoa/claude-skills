# Authoring REVIEW.md (v2 injection model)

`REVIEW.md` lives at the repository root and is read by Claude Code's managed Code Review service on every PR review. Its contents are pasted **verbatim into the system prompt of every agent in the review pipeline as the highest-priority instruction block** — above the default review guidance, not alongside it. This is the single most important thing to know when authoring one.

## What changed

| Previous semantics | Current semantics |
|---|---|
| Additive guidance — merged with default review rules | Highest-priority system-prompt injection — overrides default rules where they conflict |
| Severity label "Normal" | Severity label "Important" (JSON key still `normal`) |
| `@import` syntax expanded | Pasted verbatim — `@` imports are NOT expanded |
| Minor influence on behavior | Load-bearing — authors control what gets flagged, at what severity, and how findings are reported |

## Authoring patterns with real impact

### Severity overrides

Redefine what "Important" (🔴) means for this repo. The default calibration targets production code. Override it explicitly for docs repos, config repos, prototypes, or infrastructure.

```markdown
## What Important means here

Reserve Important for findings that would break behavior, leak data,
or block a rollback: incorrect logic, unscoped database queries, PII
in logs, migrations that aren't backward compatible. Everything else
is Nit at most.
```

You can also **escalate**:

```markdown
## Escalations

Treat any CLAUDE.md violation as Important (default is Nit).
Treat missing integration tests on new API routes as Important.
```

### Nit caps

Prose, config, and style-heavy code can be polished forever. Cap explicitly:

```markdown
## Cap the nits

Report at most five Nits per review. If more were found, say
"plus N similar items" in the summary. If everything found is
a Nit, lead the summary with "No blocking issues."
```

### Path-skip directives

List paths, branch patterns, and finding categories Claude should skip entirely:

```markdown
## Do not report

- Anything CI already enforces: lint, formatting, type errors
- Generated files under `src/gen/` and `*.lock`
- Test-only code that intentionally violates production rules
- Findings in `scripts/` unless near-certain and severe
```

For "review but with a higher bar" use the last pattern — set the threshold, don't skip.

### Mandatory-check lists

Add repo-specific rules to flag on every PR. These land more reliably here than in a long `CLAUDE.md`:

```markdown
## Always check

- New API routes have an integration test
- Log lines don't include email addresses, user IDs, request bodies
- Database queries are scoped to the caller's tenant
- Migrations are backward-compatible for one release cycle
```

### Verification bar

Require evidence before a finding posts — cuts false positives:

```markdown
## Verification

Behavior claims need a `file:line` citation in the source, not an
inference from naming. If Claude cannot cite, don't post.
```

### Re-review convergence

Control what happens on repeat reviews of the same PR:

```markdown
## After the first review

Suppress new Nits. Post Important findings only. Do not re-flag
anything already dismissed via 👎 reaction.
```

### Summary shape

Shape the review body opener:

```markdown
## Summary format

Open with a one-line tally: "N factual, M style".
Lead with "No factual issues" when that's the case.
```

## What doesn't work

- `@import` / `@file` references — pasted verbatim, not parsed
- References to other files — contents are not read; put rules inline
- Length for its own sake — a long `REVIEW.md` dilutes the rules that matter most

## Starter: Drupal

```markdown
# Review instructions

## What Important means here

Reserve Important for: SQL injection, XSS via unsanitized `#markup`, missing access checks on routes or entity operations, `\Drupal::service()` in new code (should use DI), hook implementations that break backward compatibility, config that leaks to export without being intentional.

Style, naming, coding-standards violations are Nit at most.

## Cap the nits

Report at most five Nits per review. If more found, summarize as "plus N style/naming items".

## Do not report

- Anything `phpcs --standard=Drupal` catches (CI runs it)
- Findings in `vendor/`, `core/`, `contrib/`
- Generated config in `config/sync/` — review the code that produced it instead
- `.module` hook docblocks — Drupal convention, not a bug

## Always check

- New routes declare `_permission`, `_access`, or `_custom_access`
- Forms validate and sanitize `$form_state->getValue()` before use
- Database queries use placeholders, not string concatenation
- Entity API used over direct database queries for content entities
- Services injected via constructor, not `\Drupal::service()`
- Render arrays with `#markup` use `Xss::filter()` or `t()` for user input

## Verification

For security findings, cite the file:line where user input flows to the sink.
For DI violations, cite the static call in new code (not pre-existing).
```

## Starter: Next.js

```markdown
# Review instructions

## What Important means here

Reserve Important for: secrets leaked to client bundle, API routes without auth/authz, unvalidated user input reaching database or shell, `dangerouslySetInnerHTML` with untrusted data, `getServerSideProps` exposing server secrets, open redirects, missing CSRF on state-changing routes.

TypeScript strictness, React key warnings, and component structure are Nit at most.

## Cap the nits

Report at most five Nits per review.

## Do not report

- Anything ESLint catches (CI runs `next lint`)
- Findings in `node_modules/`, `.next/`, `__generated__/`
- `any` in test files
- Missing `useMemo`/`useCallback` unless profiling shows an actual issue

## Always check

- API routes validate `req.body` with zod/valibot/yup before use
- `NEXT_PUBLIC_` prefix is correct — server-only vars never prefixed
- Auth checks run before database reads on authenticated routes
- Rate limiting on public unauthenticated endpoints
- `useState` holding secrets never serialized to HTML (check `getServerSideProps` returns)

## Verification

For secrets-in-bundle findings, cite the import path that pulls server code into a client component.
For missing auth, cite the route handler and the absence of the auth helper.
```

## See also

- `commands/generate-review-md.md` — generator that emits a starter REVIEW.md tailored to project type
- `commands/review.md` — local rubric review; reads REVIEW.md for project-specific standards
- `references/check-run-json.md` — parsing the check-run JSON output (`normal` key = Important count)
