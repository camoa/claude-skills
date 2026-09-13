# Changelog

All notable changes to this plugin are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [6.0.0-beta] - 2026-09-13

A rewrite of `ai-dev-assistant`, which this plugin replaces. Nothing from version 5 was
carried without being read, and most of it was not carried.

### Added

- Six stages as skills: scope, research, design, implement, review, completion. Each reads the
  records the stage before it wrote and writes its own, validated against a schema.
- A contract of criteria, written at scope and frozen at design close. Every later stage is
  checked against it, in both directions.
- Tests written before the code by a role that never sees the code, then frozen. A hook refuses a
  write to a frozen test. The build passes or it does not.
- Eight deciding checks per work order, run by script before any judgement. The tool rows come
  from the framework's process recipe in dev-guides.
- One review per task over sixteen checks: the contract, the tools at the final commit, one
  model pass over the whole change, and the surfaces when set up. Mutation testing runs under
  test coverage.
- Completion closes on the verdict or a person's reason, offers a follow-up task per open
  finding, and writes the pull request body from the records. It never calls a remote.
- Every action prints summary lines and paths. Record bodies, tool output and briefs stay in
  files that only a dispatched role reads.

### Removed

- Epics, playbooks, the work-order loop, the fourteen-check review battery, session save,
  maintainer mode, and the guardrail installer. The reasons are in the rewrite's own records.

### Not yet proved

- No skill has run inside a live conversation. This beta exists to run the first two tasks.
