---
name: 'Roles and the Run Ledger'
title: One layer decides each thing, a program watches the long commands, and a target test keeps a thread on course
status: decided
supersedes: []
references: []
---

## Question

On 2026-11-02 one advisor held the author's conversation, dispatched seats, read check logs and ran
about six check rounds on main for faults seats could have caught. A passed check sat 29 minutes
unread until the advisor asked. Seats stopped for permission that was going to be given. Nothing but
an agent's memory noticed a job nobody was reading, and nothing measured whether the work still
served its goal. How is the top level split, how is a long command watched, and what keeps a thread
on course?

## Options

| The top level             | Against it                                                           |
| ------------------------- | -------------------------------------------------------------------- |
| One advisor doing it all  | The author's attention waits on check logs, which is what went wrong |
| Advisor and integrator    | Nobody between them holds a thread's order, so the advisor keeps it  |
| A layer for each decision | More sessions, paid for by each deciding only what is its own        |

| What watches a long command | Against it                                                       |
| --------------------------- | ---------------------------------------------------------------- |
| The agent that started it   | A job's notice never comes from a hung one, and a turn can end   |
| Another agent on a timer    | A model spent on reading a clock, and it too can go quiet        |
| A program under launchd     | It knows only what the ledger records, so the entry must be easy |

| What says a thread is on course | Against it                                              |
| ------------------------------- | ------------------------------------------------------- |
| A label on the work             | Tooling is always labeled as serving the goal           |
| A rank kept by some layer       | The ranker becomes the author without the author's word |
| A target test in steps          | A test must be written first, by those who own the goal |

## Decision

**A layer for each decision, with a test that needs no judgment of rank.** Is it reversible, and is it
inside what is decided? Both yes and the lowest layer with the right goes on, so a reversible choice
never waits for the author; either no and it goes up. A decision carrying its step, default and
reversibility can be parked or passed by whoever receives it, which is what keeps the author's queue
short. An order skipping a layer leaves the skipped layer working on a stale picture, so only a global
stop does.

**Thread state is files, a message only a nudge**, because a message has no reader after a reboot or a
compaction, and because the advisor must answer "where are we" without asking anyone.

**The watchdog is a program with no model in it**, since what it decides is a comparison of clocks, and
a model there costs tokens to be less reliable. It reports and never stops anything: a process it
killed by a wrong reading would cost more than a line nobody read. Its limits are starting values,
named so they can be tuned. The ledger gives timing as a by-product, so nothing else is timed.

**A process is stopped only by whoever started it**, by a recorded pid or through the ledger, because
the Mac is shared by sessions, and a kill by name reaches what another started.

**A seat checks what it can in its lane**, by parts named for what they catch: a fault found at the
landing costs a whole check and a round through the integrator, and a fast part costs seconds.

**A thread's goal is a target test in steps, its color the measure**, and the test belongs to the author
and the advisor, so nobody working toward it can move it. Figures warn and block nothing, since a
tooling share past a fifth may be right; the judgment is the advisor's and the decision the author's.
An auditor starts fresh with the charter and the commits alone, because a team's reasons are what make
its drift look reasonable. An idea from the author is never drift, since the goal is theirs to change.

**Decisions reach the author one at a time from a buffer**, because the cost of an interruption is the
author's, and a list answered at once is answered with less context than each deserves. This gives way
over the earlier practice of bringing one block's questions in one round.

Each rule is in `docs/agents/delegation.md`, `docs/agents/threads.md`, `docs/agents/runs.md`,
`docs/agents/advisor.md` and `Delegation` in the model.
