# How to read a process recipe

The catalog publishes these rules with its recipes. The research, design, implement and review
skills and `scripts/lib/recipes.sh` read recipes by these rules. The plugin's verdicts must match them.

## The three blocks

Each block is fenced YAML under one H2 heading, opened by one key. The catalog fails a recipe that
lacks a heading or a row, so a consumer never meets a partial block.

| Heading | Recipe | Key | Ids, in this order |
|---|---|---|---|
| `## Check commands` | `checks.md` | `check_commands` | `coding-standards`, `static-analysis`, `security`, `duplication`, `design-metrics` |
| `## Surface commands` | `checks.md` | `surface_commands` | `e2e-preflight`, `e2e`, `visual-regression`, `visual-regression-accept`, `visual-parity`, `visual-parity-accept` |
| `## Test commands` | `test-execution.md` | `test_commands` | `suite`, `file`, `test`, `changed`, `smoke`, `mutation` |

A row carries `id`, then `argv` or `absent`, never both. An `absent` row carries no other key,
except `nearest` on a test row. Optional keys: `extensions`, `signal`, `silent_pass` on a surface
row that runs a suite, and `cost` and `trap` on a test row. `argv` is a list of tokens, and a
placeholder is always a whole token.

The id list is closed. It grows only when the catalog validator and its index change together.
Address a row by an id you already know. Never run a row whose id you do not know.

## The verdicts

A row ends in one of six words: `met`, `unmet`, `not run`, `not applicable`, `undeclared`, `unknown`.

- Exit 0 is `met` and any other exit is `unmet`, unless the row says otherwise.
- `signal: empty-stdout` marks a tool that cannot fail by exit status. Exit 0 with anything on
  standard output is `unmet`. A reader that does not read the key records `not run`, never
  `met`, because the exit status of such a tool decides nothing.
- `{paths}` expands to one token per file in the caller's list, relative to the project root.
- `{dirs}` expands to one token per distinct directory that directly contains a listed file,
  relative to the project root. A directory inside another listed one is dropped, so no file is
  scanned twice.
- `extensions:` narrows `{paths}` to those extensions. An empty expansion is `not applicable`,
  never `met`, because nothing ran.
- An `absent` row is `undeclared`. Its text is what a person reads when they ask why.
- A row with no placeholder runs whole, over whatever scope its own tool takes.
- The `mutation` row is a report, and never blocks. Every catalog tool exits 0 with survivors, so read the
  score and the survivors from the output text, as the row's `trap:` says.
- `unknown` means nothing ran or nothing was decided: a command not found, or a placeholder
  with no value. A non-zero mutation exit is `unknown` too, a run fault and never a survivor count.
- Surface rows on Drupal run on the host, not through `ddev exec`, because the e2e recipe
  installs Playwright on the host.

## A missing heading

The catalog fails closed on these blocks, so a resolved body never lacks a heading. A missing
heading therefore means you hold the wrong document, not an empty block. Stop, report the path,
and do not read the row as `undeclared`. `scripts/recipe-lint.sh <recipe.md>` names each missing
heading and each malformed row before a stage resolves the recipe.
