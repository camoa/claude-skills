# The commands you type

Each AIDA skill is one command, `/aida:<skill>`. You can also say what you want in plain words,
such as "create a task", and Claude runs the matching skill.

## Every day

| Type | What it does |
|---|---|
| `/aida:next` | Lists the open tasks and the stage each is at, or loads the task you name. |
| `/aida:project` | Says which project owns this folder, and runs the project check. |
| `/aida:task create` | Makes a new task and its worktree. |
| `/cd <path>` | A Claude Code command: moves this session into a task's worktree. |

## The six stages, in order

| Type | What it does |
|---|---|
| `/aida:scope` | Writes the contract in a conversation with you. |
| `/aida:scope approve` | Your yes on the contract. |
| `/aida:research` | Grounds each criterion in your code, outside sources and recipes. |
| `/aida:design` | Writes the work orders. `/aida:design close` closes the design. |
| `/aida:implement` | Builds each work order, tests first. |
| `/aida:review` | Runs the checks over the whole task and records one verdict. |
| `/aida:completion` | Writes the pull request body and closes the task. |

Each stage takes a task id at the end, such as `/aida:review add-search-page`. Without one, it
acts on the task active in this conversation.

## The project

| Type | What it does |
|---|---|
| `/aida:project create` | Makes a project for your code. |
| `/aida:project switch <name>` | Moves to another project. |
| `/aida:project list` | Lists every registered project. |
| `/aida:project state <name> <state>` | Marks a project active, complete or archived. |
| `/aida:project set-frameworks <name> <framework>...` | Names the stack when AIDA did not detect it. |
| `/aida:project add-source <name> <kind> <folder>` | Uses your own folder of guides, recipes or playbooks. |
| `/aida:project task-rule <name>` | Adds the task rule to your repository's `CLAUDE.md`. |
| `/aida:project check-machine` | Checks this machine can reach a task's worktree. |
| `/aida:project uninstall <name>` | Takes AIDA's own instructions out of your repository. |
| `/aida:project set-mutation <name> <on\|off>` | Turns mutation testing at review on or off. |

## The task

| Type | What it does |
|---|---|
| `/aida:task split <task-id>` | Splits a task into a parent and children. |
| `/aida:task set-run-mode <task-id> <mode>` | Sets the run mode: `autonomous`, `light` or `interactive`. |
| `/aida:task set-budget <task-id>` | Sets a ceiling on one build, in dispatches or minutes. |
| `/aida:task save <task-id>` | Saves a decision made mid-stage as a note. |
| `/aida:task environment <task-id> up` | Brings up the worktree's own site. |
| `/aida:task prune` | Removes the worktrees of complete tasks. |

## Tools, tests and playbooks

| Type | What it does |
|---|---|
| `/aida:tool install <tool>` | Installs a tool, such as `phpunit` or `playwright`, from your stack's recipe. |
| `/aida:tool run <tool>` | Runs a tool from its recipe. |
| `/aida:surfaces` | Sets up end to end and visual regression tests. |
| `/aida:surfaces unregister <id>` | Removes one surface you decided goes. |
| `/aida:test-cleanup` | Sorts a grown test suite, asks you what goes, and hands the cleanup to a task. |
| `/aida:playbooks list` | Lists the plays that apply to this project. |
| `/aida:playbooks capture` | Saves a rule you want followed as a play. |

For the details of each, see [the project](../project/README.md), [the task](../task/README.md),
[the stages](../stages/README.md) and [sources](../sources/README.md).

## Why it works this way

- **One skill per question.** Each command answers one thing, so its name tells you where to go.

Source: skills/*/SKILL.md
