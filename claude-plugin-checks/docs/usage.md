# Usage

## Check a plugin

```bash
bash scripts/run-checks.sh path/to/plugin
bash scripts/run-checks.sh path/to/plugin --strict   # warnings fail too
```

That runs everything on the machine: the first-party validator, plugin-dev's
linters, and our own checks. With the plugin installed, ask Claude to check or
validate a plugin and the `check` skill runs the same command.

## Run only our checks

```bash
python3 scripts/check.py path/to/plugin [--strict] [--only P,E01,S] [--json]
```

`--only` takes rule prefixes or full identifiers, so `--only P` runs the
containment rules and `--only E01,S` runs the path-containment rule plus every
self-consistency rule.

## Exit codes

The same four everywhere, from `check.py` and from `run-checks.sh`:

| Code | Means |
|---|---|
| 0 | everything was examined and everything was clean |
| 1 | at least one finding, or a warning under `--strict` |
| 2 | the arguments were wrong |
| 3 | nothing failed, but something could not be looked at |

**Three is not a soft pass.** A run lands there when a dependency is missing, a
directory could not be read, or there was nothing of that kind to examine. A
machine without the `claude` CLI never gets a zero from the runner, because the
first-party validator did not run and calling that clean would be a false
all-clear.

## The output

One JSON object on stdout, a readable summary on stderr. `--json` suppresses the
summary.

```json
{
  "schema_version": "2.0",
  "dir": "...",
  "strict": false,
  "subjects": 29,
  "findings": [
    {"rule": "S01", "severity": "error", "kind": "tool-granted-and-denied",
     "file": "agents/a.md", "line": 1, "note": "..."}
  ],
  "errors": 0,
  "warnings": 0,
  "could_not_look": [{"where": "...", "reason": "..."}],
  "result": "PASS",
  "counters": {"declared_paths": 4, "rules_run": 3}
}
```

`result` is `PASS`, `FAIL` or `UNCHECKED`. `subjects` is how many things were
actually examined, and `could_not_look` is every place a check was blind, so a
clean-looking result that covered nothing is visible rather than implied.

## Rules

| Rule | Severity | What it means |
|---|---|---|
| `P01` | error | An absolute home path, carrying a username |
| `P02` | error | Something shaped like a credential, reported redacted |
| `P03` | warn | A personal address outside the author or owner manifest fields |
| `E01` | error | A component path resolving outside the plugin directory |
| `E02` | error | A declared path with nothing at it |
| `E03` | error | A declared JSON file that does not parse |
| `E04` | error | A repeated JSON key; the last one wins and the rest vanish |
| `E05` | warn | A declared component that parses to an empty container |
| `E06` | error | Two entries colliding on the same identifier |
| `S01` | error | The same entry in a grant list and a denial list |
| `S02` | error | A frontmatter fence that is not on line one, or does not parse |
| `S02` | warn | A byte-order mark before the fence |
| `S03` | error | An execution marker inside a fenced example, in a component body |
| `S04` | error | A frontmatter fence that opens and never closes |

The frontmatter rules are in the self-consistency module rather than with the
component-file rules, because those only see files a manifest declares by path.
No plugin in this marketplace declares any, so a rule placed there fires on
nothing.

## Suppressing a containment finding

Put one extended regular expression per line in `.containment-allow` at the
plugin root. A finding whose `path:line:content` matches any of them is dropped,
and the run reports how many patterns were loaded so a silenced gate is visible.
This is for content a plugin legitimately documents, such as a fixture that has
to look like a leak to exercise a check.

## Layout

```
scripts/check.py              the entry point
scripts/cpc/result.py         the output shape, the outcome vocabulary, exit codes
scripts/cpc/walk.py           one tree walk, one exclusion list
scripts/cpc/manifest.py       manifest reading and declared-path resolution
scripts/cpc/rules/*.py        one module per rule family, each returning findings
scripts/run-checks.sh         launches the foreign tools, then check.py
```

A rule module adds findings to the report it is handed. It does not decide an
outcome, an exit code or an output shape; those live in `result.py`, once. That
is why a rule has unit tests that call a function rather than a spec that drives
a subprocess.

## Output

Everything prints to stdout and stderr. Nothing is written to disk.
