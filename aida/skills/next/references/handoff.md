# The handoff at a stage's close

Every stage ends the same way. The stage that closes names the next stage.

Interactive: stop here. Name the next command for the person, `/aida:<next stage> <task-id>`, and
never invoke it yourself.

Autonomous: invoke `aida:<next stage>` through the Skill tool, once, with the task id. Stop if it
refuses. Invoke it only when the run mode covers the next stage too. Otherwise end as interactive
does, and name the command.

Each stage but design refuses to start without the previous stage's record. Design starts without
research, because research is optional, and writes a warning. So no stage runs before scope, and
the chain is safe.
