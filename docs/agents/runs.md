# The run ledger and the watchdog

Two programs with no model in them, in [scripts/workspace/runs/](../../scripts/workspace/runs/),
`run-ledger`, `watchdog-reports` in [model/rules/delegation.res](../../model/rules/delegation.res),
which holds every limit here; why they exist is RFC ml1m6. A job nobody is reading looks exactly like a
job going well.

## One entry starts a long command

**These tasks are the workspace's, reached as `//:job` and `//:watch` from anywhere below it**: a bare
`mise run job` inside a repository or a lane looks for that repository's own.

**`mise run //:job start [--by <who>] [--limit <seconds>] [--quiet] -- <command>` returns at once**,
printing an id, and the ledger under `Delegation.runs` records who started it, its pid, its start, its
output file, and at its end its status and duration. The command runs in the directory the call was
made from, in a process group of its own, and outlives the call. `--quiet` is a job meant to go
silent. **`mise run //:job run -- <command>` waits and exits with its status**, for the Bash tool's
`run_in_background`.

- **`mise run //:watch <id>` under Monitor** wakes its session only at the end, at failures gathered and
  at a stall once, and reaching the end records the read.
- **`mise run //:job read <id>`** prints its status and the end of its output, and records the read. A
  Read or a shell command naming its output file records it too, by a hook.
- **`mise run //:job stop <id> [--by <who>]`** ends its process group, and a watch of it: only a job
  of the session and the `--by` name that started it, `job-stop-own`, as a process is killed only by
  a pid its agent recorded. A seat starts its jobs `--by <its lane>` and stops them the same way. `list` shows the last ones.
- **`mise run //:job table [--since <yyyy-mm-dd>]`** is duration times count by command, the top one the
  bottleneck. Timing comes free of the ledger, and nothing else is timed specially; `--by-class`
  gathers it by class, with Claude seats, reviews, landings, recurring work and pieces past the limit
  from `Delegation.pieceMinutes`, `job-classes`.

## The watchdog reports what nobody is looking at

**launchd runs it each `Delegation.watchdogSeconds`, and each report is one line in the event file**,
whose path `mise run //:job events` prints, said once:

- **`unread`**: a job that ended and whose result nobody read;
- **`died`**: a job whose process is gone with no end written;
- **`silent`**: a live job whose output has not moved, `--quiet` exempt;
- **`over`**: one past its `--limit`, or twice its command's p95 once it has history;
- **`idle`**: an integrator of a thread with no job, no seat, one left unreported counting up to
  `Delegation.seatOpenSeconds`, and no turn past `Delegation.idleSeconds`
  while a step is ready by the charter's `after`, to the supervisor, and past
  `Delegation.idleSupervisorSeconds` more with ready steps outnumbering busy integrators, to the
  advisor, a supervisor's transcript moving by every Monitor notice and so saying nothing. A charter
  with a reference to no step, or none readable, says `charter`;
- **`quiet`**: a registered role with no turn for its limit in `Delegation.silentTurns`, to its
  superior. Past a supervisor's, the author gets a notification;
- **`figures`**: a thread's, [threads.md](threads.md), "Staying on course", with each registered
  session's context size and compactions in the thread's `figures.txt`, or `contexts.txt` beside the
  event file; a read that fails says so and never says zero;
- **`context`**: an advisor past `Delegation.advisorReplacedFrom`, to itself,
  [advisor.md](advisor.md).

**A session with no transcript to read is said once, `unwatched`, rather than passed over in silence.**
**A session registers once**, `mise run //:job register <role> <name> [--thread <name>]`, a hook naming its transcript,
whose growth is its turn; `--transcript <file>` names it where no hook runs. `mise run //:job unregister
<name>` ends that. A Codex seat is started by `mise run //:job start`, its silence being a job's.

The supervisor keeps a Monitor on the event file: `tail -n 0 -F` of that path.

**It is installed once by the author**: `mise run //:job install` from the workspace, which writes a
plist under `~/Library/LaunchAgents` and loads it in the user's own launchd domain with no sudo;
`--dry-run` prints both.
