---
max_turns: 40
allowed_tools:
  - Skill
  - Bash
  - Read
  - Agent
---
Scope the task `volunteer-role-pull` in the active AIDA project with `/aida:scope`. The task
exists and has no contract yet. The run mode is interactive. Start from this line: "simplify
how a volunteer's role is pulled from the roster".

Draft the whole contract and show it once. Then apply these five corrections one at a time, in
this order, replying after each one as you would to a person who typed it:

1. Drop role assignment. It is not this task.
2. Keep blocking as an option, not a requirement.
3. Add a boundary: nothing in this task touches the roster import.
4. Add a working rule: a pull that finds no role returns the default, never an error.
5. Keep the other criteria as they are.

After the fifth reply, treat this line as typed by the person: "That is the contract." Close
the stage the way the skill says a person's yes is handled, and stop.
