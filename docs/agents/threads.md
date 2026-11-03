# Threads

A thread is one goal carried to its target test, RFC ml1m6. What a thread is in the record is its RFC,
[agent-protocol.md](agent-protocol.md), "A thread runs on its own between a charter and a ledger".
What it is day to day is four files in one place, a message being only a nudge.

## Where a thread's files are

**`mise run //:thread new <name>` writes them under `Delegation.threads`**, in
[model/rules/delegation.res](../../model/rules/delegation.res), private and in no repository: its
`charter.md`, `decisions.md`, `buffer.md`, `ledger.md` and `status.md`, each starting from the small template
[scripts/workspace/runs/thread.res](../../scripts/workspace/runs/thread.res) holds. **The thread's
RFC keeps what is the record**, its goal and its `### Ledger` at the end. The advisor answers "where
are we" from these files alone.

- **`charter.md`**: the goal, its target test in steps, the bounds, the values to fix. **Each step
  says `after:`, what must be green first, never an order**, and the supervisor opens every step whose
  `after` is met, [delegation.md](delegation.md), "Work without a dependency runs in parallel by default".
- **`decisions.md`**: the queue, each decision carrying the step of the path it stands on, a
  recommended default and whether it can be undone, [delegation.md](delegation.md), "Decision
  rights".
- **`buffer.md`**: what waits to reach the author, the advisor's, [advisor.md](advisor.md), "Decisions
  reach the author one at a time".
- **`ledger.md`**: what any layer chose under its right, one line each, the working copy of the RFC's
  `### Ledger`, into which the supervisor gathers it at the thread's end.
- **`status.md`**: where the thread stands, kept by the supervisor.

## Staying on course

**The author holds what is to be done and what is next and urgent.** The advisor brings candidates
and evidence; no layer ranks across goals.

**A thread's goal is a target test in steps, and whether a step is green is the measure**, never a
label on the work. Its test belongs to the author and the advisor; the supervisor and everyone below
do not change it.

**The advisor owns staying on course; the supervisor gives the figures and no judgment.** The
watchdog says each thread's seat time and landings since a step last went green, and the share of its
seat time that is tooling, flagged past `Delegation.toolingShare`, `thread-figures` in
[model/rules/delegation.res](../../model/rules/delegation.res), and writes them to the thread's
`figures.txt`. **They warn and never block, and no check fails on them.** A figure that helps in
neither of two threads is removed.

They are read from what the integrators and the supervisor record as the thread goes:

- `mise run //:thread green <name> <step>`, by the supervisor, when the target test turns a step green;
- `mise run //:thread seat <name> <seat> [--tooling]` and `seated <name> <seat>`, by the integrator, at a
  seat's dispatch and its report, `--tooling` where the seat builds the means and not the goal;
- `mise run //:thread landed <name> <repository> <commit> <subject>`, by the integrator, at a landing.

**At each checkpoint an auditor answers**, [auditor.md](auditor.md), **and the advisor asks the
author three things**: is this still the goal; have you used what runs now; what finished without
feeling closer.

**An idea from the author is never drift.** The advisor asks at once whether it changes the goal or
joins the plan. Joining the plan, with its `waits`, touches no one; changing the goal is a charter
change, recorded, and the supervisor reorders.

## At a thread's end

**`mise run //:job table --since <day>` is its timing**: duration times count by command, the top one
the bottleneck, [runs.md](runs.md). Nothing else is timed specially.
