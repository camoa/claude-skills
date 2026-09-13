# AIDA, the AI Dev Assistant

A Claude Code plugin. AIDA keeps AI coding work inside a process that produces better code for
your project.

Every task runs through five stages. Scope writes a contract: the goals, the non-goals, and the
criteria that prove each goal was met. Research looks for prior art in your own code first, then
outside, and reads current documentation rather than the model's memory. Design writes a spec
detailed enough to build from. Implementation writes the tests first. Review runs the blocking
checks and compares the result against the contract.

Two things hold the process together.

**The checks are scripts.** A model judging its own work is not a check. Where an answer is
decidable, a script decides it. A step that could not run says so, instead of reporting a pass
over nothing it looked at.

**The stack knowledge is not in AIDA.** Each stage fetches a recipe for your language or
framework and follows it. The same five stages work for PHP, Python, Go, Drupal, or a Claude
plugin, because AIDA holds the process and the recipe holds the stack.

AIDA also remembers. A new window, or the same window after its context is compacted, knows which
task is active, which stage it is in, what the contract says, and what was already decided. You
make a decision once.

## The five stages

| Stage | What it produces |
|---|---|
| Scope | the contract: goals, non-goals, and the criteria that prove them |
| Research | prior art, the guides to read, and how this is done today |
| Design | the spec: what to build, where the logic lives, which pattern each part follows |
| Implementation | the code, written test first, reviewed as it lands |
| Review | the blocking checks, and the result held against the contract |

## Status

Version 6.0.0-beta. A rewrite of `ai-dev-assistant`, which it replaces in the marketplace. Every
stage is built and proved against fixtures under bash and zsh. The beta exists to run the first
live tasks: one started under version 5, one from scratch. Defects come from those runs.

## Running it while it is built

Load it for one session, from wherever you cloned it:

```bash
claude --plugin-dir /path/to/aida-v6-code/aida
```

The flag loads the plugin for that session only. A session started without it does not see
version 6, so version 5 keeps working.

To see what actually registered, rather than what the files claim, put the flag before the
subcommand:

```bash
claude --plugin-dir /path/to/aida-v6-code/aida plugin list
claude --plugin-dir /path/to/aida-v6-code/aida plugin details aida
```

`plugin list` shows whether the plugin loaded. `plugin details` lists the components it
registered. `claude --debug` shows the load itself, including manifest errors.

## Documentation

The documentation is written stage by stage, as each one closes. It will live in `docs/`, as an
overview with a page per topic. It covers the process and every variant of it: each entry point,
both run modes, every task shape, every build path, the optional test harnesses, and what to do
for a stack that has no recipe.

## License

MIT.
