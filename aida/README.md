<div align="center">

# AIDA, the AI Dev Assistant

**Six stages, script checks, and stack recipes for AI coding work.**

**[Documentation](docs/README.md) · [Installing](#installing-it) · [Changelog](CHANGELOG.md)**

[![Version](https://img.shields.io/github/package-json/v/camoa/claude-skills?filename=aida%2F.claude-plugin%2Fplugin.json&label=version)](#status)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](#license)

[![Tested: bash](https://img.shields.io/badge/tested-bash-blue.svg)](#status)

[![Claude Code](https://img.shields.io/badge/Claude_Code-supported-blueviolet.svg)](#installing-it)
[![Copilot CLI](https://img.shields.io/badge/Copilot_CLI-unsupported-lightgrey.svg)](#status)
[![Codex](https://img.shields.io/badge/Codex-unsupported-lightgrey.svg)](#status)
[![Cursor](https://img.shields.io/badge/Cursor-unsupported-lightgrey.svg)](#status)
[![OpenCode](https://img.shields.io/badge/OpenCode-unsupported-lightgrey.svg)](#status)
[![Antigravity](https://img.shields.io/badge/Antigravity-unsupported-lightgrey.svg)](#status)

</div>

A Claude Code plugin. AIDA keeps AI coding work inside a process that produces better code for
your project.

Every task runs through six stages. Scope writes a contract: the goals, the non-goals, and the
criteria that prove each goal was met. Research looks for prior art in your own code first, then
outside, and reads current documentation rather than the model's memory. Design writes a spec
detailed enough to build from. Implementation writes the tests first. Review runs the blocking
checks and compares the result against the contract. Completion closes the task on that verdict
and writes the pull request body from the records.

Two things hold the process together.

**The checks are scripts.** A model judging its own work is not a check. Where an answer is
decidable, a script decides it. A step that could not run says so, instead of reporting a pass
over nothing it looked at.

**The stack knowledge is not in AIDA.** Each stage fetches a recipe for your language or
framework and follows it. The same six stages work for PHP, Python, Go, Drupal, or a Claude
plugin, because AIDA holds the process and the recipe holds the stack.

AIDA also remembers. A new window, or the same window after its context is compacted, knows which
task is active, which stage it is in, what the contract says, and what was already decided. You
make a decision once.

## The six stages

| Stage | What it produces |
|---|---|
| Scope | the contract: goals, non-goals, and the criteria that prove them |
| Research | prior art, the guides to read, and how this is done today |
| Design | the spec: what to build, where the logic lives, which pattern each part follows |
| Implementation | the code, written test first, reviewed as it lands |
| Review | the blocking checks, and the result held against the contract |
| Completion | the pull request body, and the task closed on the review's verdict |

## Status

Version 6. A rewrite of `ai-dev-assistant`, which it replaces in the marketplace. Every stage is
built against behaviour fixtures. On every pull request, continuous integration runs the structure
specs and the behaviour suite in `tests/behaviour`, under bash on Linux. The suite runs each stage
end to end, and tests the hooks that guard commands, writes, reads, stops and compaction. The
plugin's scripts run under bash, whatever shell the session uses. Live tasks on real projects have
run since the betas, and each release fixes the defects they found. Copilot CLI, Codex, Cursor,
OpenCode and Antigravity are not supported yet. A task to support them is open.

## Installing it

```text
/plugin marketplace add camoa/claude-skills
/plugin install aida@camoa-skills
```

To run it from a clone for one session, load the plugin folder:

```bash
claude --plugin-dir /path/to/claude-skills/aida
```

To see what actually registered, rather than what the files claim, put the flag before the
subcommand:

```bash
claude --plugin-dir /path/to/claude-skills/aida plugin list
claude --plugin-dir /path/to/claude-skills/aida plugin details aida
```

`plugin list` shows whether the plugin loaded. `plugin details` lists the components it
registered. `claude --debug` shows the load itself, including manifest errors.

## Documentation

The documentation lives in `docs/`. Start at `docs/README.md`, then `docs/start/`. Each folder
has an index, and each page answers one question: how to do a thing, what AIDA does, and briefly
why it works that way. When AIDA refuses or stops, `docs/when-it-stops/` says what to do.

## License

MIT.
