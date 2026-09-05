---
name: check
description: Run every available check against a Claude Code plugin — the first-party validator, plugin-dev's linters, and three checks nothing else performs. Use when asked to validate, check, audit, or review a plugin, or before publishing one.
---

# Check a plugin

Run the checks. Read what came back. Do not summarise another tool's output into
your own words; the wording is theirs and so is the fix.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/run-checks.sh <plugin-dir>
```

Add `--strict` to fail on warnings as well as errors.

Exit codes: `0` everything was examined and clean, `1` at least one check found
something, `2` bad arguments, `3` nothing failed but something could not be
looked at. Three is not a soft pass: a machine without the `claude` CLI lands
there, because the first-party validator did not run.

## What runs

| Source | Notes |
|---|---|
| `claude plugin validate` | The first-party validator. It is the authority on the manifest. |
| `plugin-dev` hook linter | Once per hook script found. |
| `plugin-dev` agent validator | Once per agent file. See the caveat below. |
| `check.py` | Ours: containment, external component files, self-consistency. One program, `--only` to run a subset. |

The runner prints each tool's output verbatim and then a summary table. It does
not filter or rewrite anything.

**The agent validator has two known behaviours.** It stops at the first finding,
so a short report is not a clean file, and it reports a missing `model` or
`color` as an error when both are optional. Do not act on those two. After
fixing what it names, run it again rather than treating one pass as a full list.

**Two `plugin-dev` scripts are deliberately not run.** `validate-hook-schema.sh`
crashes on the standard `hooks.json` shape, and `validate-settings.sh` reads a
settings file rather than a plugin. The runner says so where they would have run.

## What our three checks are for, and what they refuse to do

They exist because of one test: **does the check encode a fact Anthropic can
change?** If it does, it is not here, however useful it looks. Hook event names,
model tiers, reserved marketplace names, manifest key allowlists, character caps
and enum members are all facts with an owner, and a check that writes one down is
wrong the day the owner changes it. That is what the plugin this replaced spent
54 rule identifiers and 121 checkable items doing.

What is left is structure and self-consistency, which cannot go stale:

- **E-series, external components.** The same defect that hard-errors inline in
  `plugin.json` passes clean in an external file. Three monitor entries with a
  repeated name inline give "Found 1 error"; the identical content at
  `./config/monitors.json` gives "Validation passed with warnings" and exit 0.
  So: does the declared path resolve, does it stay inside the plugin, does the
  file parse, does it repeat a key, do two entries collide on an identifier.
  Nothing about which fields belong in it.
- **S-series, self-consistency.** The same entry granted and denied in one
  frontmatter block. A frontmatter fence that is not on line one, so the whole
  block is inert. An execution line inside a fenced example, which the loader
  runs anyway — this is why `plugin-dev:command-development` cannot be invoked
  at all in a repository without an npm `test` script.
- **P-series, containment.** An absolute home path, a credential, a personal
  address, on their way to a public marketplace.

## When a check says UNCHECKED

That is not a pass. It means the check could not look: the CLI is absent,
`python3` or PyYAML is missing, or there was nothing of that kind to read. The
summary counts it separately from both PASS and FAIL, and the run exits 3 rather
than 0 when nothing ran at all. A false all-clear is worse than silence.

## Output

Prints to stdout. Writes nothing.
