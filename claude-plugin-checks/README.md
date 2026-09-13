# claude-plugin-checks

One command that runs every plugin check available on your machine, and three of
its own that nothing else performs.

```bash
bash scripts/run-checks.sh path/to/plugin          # or --strict to fail on warnings
```

That runs every check on the machine. For ours alone:

```bash
python3 scripts/check.py path/to/plugin [--only P,E01,S]
```

Or ask Claude to check a plugin and the `check` skill runs the same thing.

## Why it is this small

This plugin used to be `plugin-creation-tools`, and it taught plugin authoring:
a 56-file reference tree, scaffolding commands, two review agents, and a
validator carrying 54 rule identifiers over 121 separately checkable items, 46 of which
carried no identifier and no severity, so they could not be cited or blocked on.

Almost all of that was a fact about Claude Code written down somewhere Anthropic
cannot reach. Hook event names, model tiers, reserved marketplace names,
manifest key allowlists, character caps, enum members. Each one correct when it
was written and wrong the day the spec moved. Meanwhile `plugin-dev` and
`superpowers` ship the same teaching, maintained by people who change the spec
rather than chase it.

So the teaching went, and what stayed had to pass one test: **does this check
encode a fact somebody else owns?** If yes, it is not here. What survives is
structure and self-consistency, which cannot go stale.

## What runs

| Source | What we do |
|---|---|
| `claude plugin validate` | run it, print what it said |
| `plugin-dev` hook linter | run per hook script, print what it said |
| `plugin-dev` agent validator | run per agent file, print what it said, name its two quirks |
| `plugin-dev` hook-schema and settings validators | skipped: one crashes on the standard shape, the other reads a different file |
| superpowers | nothing to run; it ships no validator |
| our three scripts | run |

Nothing is filtered or reworded. If another tool is wrong about your plugin, its
maintainers can fix it, and re-running is usually faster than arguing with it.

## The checks

One program, `check.py`, over a rule module per family. Each module adds findings
and nothing else; the tree walk, the output shape, the outcome vocabulary and the
exit codes live in one shared place, so a defect in any of them is fixed once.
The previous version was three standalone scripts and the same blind-spot bug was
present in all three.

**Containment.** An absolute home path carrying a username, a credential, a
personal address, on their way to a public marketplace. An optional
`.containment-allow` file holds one regular expression per line for content a
plugin legitimately documents, and the run says how many patterns it loaded so a
silenced check stays visible.

**External components.** A defect that hard-errors inline in `plugin.json` passes
clean in an external file. Three monitor entries sharing a name, written inline,
give "Found 1 error"; the identical content at `./config/monitors.json` gives
"Validation passed with warnings" and exit 0. The same holds for `.lsp.json`,
`.mcp.json` and output-style files. This asks whether a declared path resolves,
whether it stays inside the plugin, whether the file parses, whether it repeats a
key, and whether two entries collide on an identifier. It says nothing about
which fields belong inside, because that is not ours to know.

**Self-consistency.** The same entry granted and denied in one frontmatter block.
A fence that is not on line one, so every field under it is inert. An execution
marker inside a fenced example in a file that is loaded as a component — the
shape that makes one shipped skill uninvocable in any repository without an npm
`test` script.

A finding names what it found and stops there. Where a collision exists but which
side wins is a fact about Claude Code nobody here has measured, the finding says
so rather than guessing. An earlier version guessed and called two working agents
in this marketplace broken.

## UNCHECKED is not a pass

Every check reports three outcomes, not two. `UNCHECKED` means it could not
look — the CLI is missing, `python3` or PyYAML is absent, or there was nothing
of that kind to read. The summary counts it apart from both PASS and FAIL, and
the run exits 3 rather than 0 when nothing ran. A check that cannot look must
never report that it looked.

## Requirements

`python3` and PyYAML for the checks themselves. `bash` for `run-checks.sh`, which
only launches things. The `claude` CLI and `plugin-dev` if you want theirs to run;
without them the run reports that they did not run rather than quietly skipping.
The `claude` CLI and `plugin-dev` if you want theirs to run; without them the
run says so instead of quietly skipping.

## Tests

```bash
pytest tests/                    # the rules, as functions
bash tests/exit-codes-spec.sh    # what a caller reading an exit code is told
```

Each rule has a test that fires on a fixture carrying the defect and one that
stays silent on a twin without it, so a rule that fires on everything fails the
same way a rule that fires on nothing does. Every rule is mutation-verified:
break its branch, the tests go red.

Two defects in this plugin's own history got past a green suite and were found by
running it against a real tree. That is now step five of `CONTRIBUTING.md`.
