---
# Routing block, first and in this order. Whoever is resolving reads to here and decides.
name: <framework>_<tool>_tooling
capability: <tool>
description: Use when a <framework> project needs <tool>. Says how to install it and how to run it.
# Metadata, read only after a match.
label: <Tool> (<Framework>)
recipe_schema_version: 1.0.0
version: 0.1.0
recipe_class: tooling
framework: <framework>
authors:
  - name: <author>
license: <license>
---

## Goal

One paragraph. What this tool is and what a project gets by having it.

## Install

The commands that add the tool, in order. One per line, in the first fenced block under this
heading. A script reads that block, so nothing else here is read.

```
<first command>
<second command>
```

Each one runs as arguments, never through a shell, so a shell metacharacter is refused rather than
run to mean something its author did not intend. Write two steps instead of joining them with `&&`.

Every step is safe to run twice, because a project may already have part of what this tool needs.

If a step fails because something it depends on is absent, let it fail. The tool's own message is
better than anything written here in advance.

## Run

The command that invokes the tool. One command, in the first fenced block under this heading.

```
<command>
```

Say below the block where the result appears, for a person reading it.

This is also the check. Whoever needs the tool runs this command, and a "not found" is the answer
that the tool is missing. Install, then run it again. Nothing records whether the tool is present,
because running it answers that every time.

Invoke the tool to find out. Do not match its error text: error text changes between versions and
is not a contract.
