# Delegation

How work is split between the session the user is talking to, the top level, and the agents it
spawns. The split is shaped for the user's hands, not for an agent's throughput, and every rule
below follows from that. The rest of it is in four files beside this one: [briefs.md](briefs.md),
what a spawned agent is handed; [reading.md](reading.md), what a reader does; [lanes.md](lanes.md),
how the lanes are kept apart and merged; [checking.md](checking.md), how a wave is checked,
reviewed and committed.

## Whether a session delegates is the user's call, and the default is no

**A session works directly until the user says it delegates.** No spawned implementer, no read
sent out, no wave -- the session reads, edits, checks and commits on its own, under
[commits.md](../commits.md), "Completion", as any agent working directly does. The user decides per
session, and says so in words: "this session dispatches", "use agents", or the like.

**Once they have, every section below applies, and it holds until they say otherwise.** It is not
re-asked each turn, and it does not lapse into a judgment about which tasks seem worth an
implementer -- "When not to delegate" still governs the individual edit, but it never turns
delegation back on in a session that has not been told to, nor off in one that has.

**The agent does not propose it either.** A task that looks parallel is not a reason to ask; the
user knows this file exists and turns it on when they want it.

**Work that cannot run in parallel goes to one implementer**, decided by the author on 2026-10-24.
When the next step waits on the one before it -- a foundation being laid, one piece at a time --
the integrator dispatches a single implementer rather than idling while several wait on each
other. Implementers run side by side again once there are independent pieces; the user said so on
2026-10-14.

**No implementers run in parallel until the hooks holding their commands have landed**,
`implementer-commands` in [model/rules/delegation.res](../../model/rules/delegation.res). They
landed and were proven on 2026-10-24, for implementers spawned without a name.

**The integrator schedules the queue itself**, decided by the author on 2026-10-24: it judges what
is independent and runs those pieces side by side, neither all serial nor split hard. A piece waits
only on what it truly depends on; each implementer has a lane of its own and a declared set of
files no other lane touches, so two lanes never own one file. Review, verification and the check
once per wave stay as they are. How many run at once is `implementersAtOnce` in
[model/rules/delegation.res](../../model/rules/delegation.res).

**The command hooks guard against a slip, not against malice**, decided by the author on
2026-10-24: an implementer works with the integrator, so the hooks cover the common spellings of a
command and no more. **An implementer is refused four kinds of command alone**, decided by the
author on 2026-10-24, `implementer-commands`:

- **version control**, jj and git alike;
- **the machinery of a whole repository's check**: `check`, `verify`, `audit`, and `--pending`
  even beside one part, the one exception being a single part of the workspace's own check;
- **a task that deploys or releases**, `Delegation.releasing`;
- **`ssh`, `rsync` and `wrangler`.**

**A refactorer is refused the same four**, being a role that writes code as an implementer does,
with no part of the workspace's check excepted, `refactorer-commands`. That git, `--pending` and the
refactorer fall under these four was read from the author's decision by the advisor on 2026-10-24.

A list of what to refuse is never complete, and the completion protocol,
[implementer.md](implementer.md), leaves an implementer no reason to go around it. **Every other way
around the four is a known limit, and a review does not count it a defect.** Known to pass unseen:
`pnpm --filter <name> exec <command>`, an option before `exec`; a backtick span inside double
quotes, judged as a command where the shell would run it; and any spelling the hooks do not parse.

## A role is named by the user, and each has a file

**The user names a session's role in words at its start**, with no hook and no command to start
it, decided by the author on 2026-10-24. Each role has one file beside this one, and reading it is
enough to recover what the role does and where it stops: [advisor](advisor.md),
[integrator](integrator.md), [implementer](implementer.md), [reviewer](reviewer.md),
[refactorer](refactorer.md) and [reader](reader.md).

**The top level is split by what it decides**, decided by the author on 2026-10-24. Where an
advisor is named, the paraphrase, the judgment and the decisions belong to the user and the
advisor; the sequence, who owns which file, the commits, and writing what was decided into the
rules belong to the integrator, but for what the advisor writes and commits itself,
[advisor.md](advisor.md). **Where no role is named, one session holds both halves**, as it
always has, and where this file names the advisor or the integrator it then means that session.

**A subagent type is defined only where it truly differs in tools, model or permissions.**

- **The implementer** types no jj command, cannot deploy, cannot run `mise run check` and cannot
  spawn another agent.
- **The reviewer** only reads, in a fresh context, the diff and the rules, and is handed none of
  the reasoning behind the implementation.
- **The refactorer** runs alone, changes no behavior, and is held exactly as the implementer is.
- **Reading work goes first to the built-in Explore**, as a reader.

The implementer, the reviewer and the refactorer are defined in
[.claude/agents/](../../.claude/agents/), each definition's body pointing to its role file and
saying nothing more. **No subagent is given a `memory` field.**

**Deploying and rehearsing belong to the integrator alone**; no operator role exists.

**Work done live with the user, as a look tuned beside them, takes no role**: one session with no
role named does it directly, decided by the author on 2026-10-24.

**Who reads the code.** The advisor reads it itself or sends a reader; the integrator, where it
needs the code read to integrate, may send a reader too.

## The point is the user testing while the top level builds

**The user is the fastest test this project has.** They click in two seconds what a browser
round trip costs minutes, they are already looking at the thing, and they are the only party who
knows what "feels wrong" means. So the loop is not _finish, verify, report_. It is: hand back
something clickable, and go on working while it is being clicked.

Two obligations follow, and they are what actually saves the time.

**Never end a turn without something for the user to do.** A turn that ends in "still working"
spends their attention and returns nothing to spend it on.

**Never hold a turn to confirm what they would confirm faster.** This is the existing rule in
[agent-protocol.md](agent-protocol.md), "Checking your own work", and delegation does not soften
it -- it makes it load-bearing, because the cycles saved by not confirming are the cycles the
next wave is dispatched in.

**And an honest limit, so this is not sold as more than it is.** Parallelism pays only where
there are two or more independent concerns. A request with one causal chain stays serial however
many implementers exist: the table of contents indicator was one chain -- collapsed geometry, open
geometry, one element -- and no arrangement of agents would have made it two. What delegation
buys there is not wall-clock but **context**: a few hundred tokens of brief instead of twenty
thousand of reading and editing, and a top level that can still hold the whole task at the end of
it.

The wall-clock lever is elsewhere, and half of it is the user's. **A batch of requests in one
message becomes a wave of agents; one request at a time stays a queue however it is executed.**
The other half is the overlap: wave N is being clicked while wave N+1 is being dispatched. A top
level that goes quiet for ten minutes has failed at this even if every agent in it succeeded.

## A returning implementer is an event, not an instruction

An implementer that finishes sends a notification to the integrator, and it arrives wherever the
session happens to be -- which is usually in the middle of something else. **It does not get to
set the topic.** The default is to park the result and finish the exchange in progress.

This is not politeness, it is the point of the whole arrangement. A session that stops to report
every return has spent the freedom it delegated the work to buy: the user is back to waiting on an
implementer, through an intermediary, having gained nothing.

**Parked results surface at the seam between topics, never inside one.** "Right, that is
settled", "let us look at the other thing", a question that closes a thread -- those are where a
parked result comes out. Mid-idea is not.

**One turn, one topic.** Answering the idea, reporting a returned implementer and dispatching the
next one in a single message is the failure this rule exists to prevent: three things arrive at
once and none of them is legible.

**Three things break the thread, and each gets one line rather than a report.**

- **An implementer is blocked.** That is not a result, it is a stalled resource, and every
  exchange it waits through is the parallelism this arrangement was built for, idle.
- **What came back contradicts the premise of what is being discussed right now.** Designing on a
  fact that has just been disproved costs more than the interruption does.
- **The new idea touches a file an in-flight implementer owns.** This is not a report at all, it
  is [lanes.md](lanes.md), "File ownership is the whole of the concurrency control", doing its
  job. Say so before the idea is designed around a file that is being rewritten underneath it.

**Reading which of these applies is judgment, and nothing in the notification carries it.** If
the user's last message was about something else, they are on something else. If they ask how it
is going, they want the result. The signal is what they are doing, not what has arrived.

## What the top level keeps

Two lists, one for each half of the top level, and nothing on either can be handed to an agent that
starts cold.

### The user's and the advisor's, three things

**Paraphrase.** Turning what the user said into this project's terms is the whole of the top
level's value. The user says the indicator feels wrong; the brief says which function writes which
property, in which of the rail's two layouts, and which one it should have been reading. An
implementer handed the first sentence goes and rediscovers the codebase, and is paid for by the
token.

**Judgment.** Working out _why_ something is broken, and what the fix has to be, stays at the top
level. It is made on text an agent quoted back rather than on an agent's conclusion, which is the
subject of [reading.md](reading.md).

**Decisions.** Who decides what is [agent-protocol.md](agent-protocol.md), "Decision authority",
unchanged.

### The integrator's, three things

**Sequence and commits.** Who runs when, who owns which file, and what lands in which commit.

**The rules.** What delegation adds is that **a spawned agent never writes the rules or
`AGENTS.md`**: the rules are the shared decision record, two implementers editing them concurrently
conflict by construction, and a rule is a decision, which was never the implementer's to take. An
implementer that believes a rule is wrong says so in its report, which is the same thing it does
with a brief it believes is wrong.

**What it writes, and only that**, decided by the author on 2026-10-24: the model and its
interfaces; the files with one writer; the commit that merges a wave; a block's samples; the
registries, a module list, a route table, a workspace's member list; the lockfiles, written again at
a merge; the records of friction; the list of private identifiers; and a fix shorter than its brief
would be. **Shared code the model does not hold is written by one implementer in the wave
before**, and the next wave's implementers use what it landed. Where a project derives each block's
brief from its model and holds a block to it alone, as `monoflake/platform` does in its
`docs/code.md`, the interface is the model's, reviewed by the author before an implementer begins,
and the brief the project prints is the brief.

## What the user is shown

**Before a wave runs: one line per implementer** -- what it does, which files it owns, and which
model: Codex, or Claude because Codex is limited until about a time it names. Not the brief itself,
which is long enough to bury the thing worth checking. The cheapest place in the whole loop to
catch a misparaphrased intent is before three implementers have acted on it, and a line is cheap
enough to be read at a glance where a full brief is not.

**Codex comes first while it has quota**, decided by the author on 2026-10-29: an implementer is
dispatched on Codex whenever Codex still has quota, and on Claude only while it has none.

- **Quota is read at dispatch, and only then.** Before new work is dispatched the integrator reads
  Codex's remaining quota; work already running is never stopped or moved because of it.
- **It is read by the claude-dashboard plugin's check-usage**,
  `node ~/.claude/plugins/marketplaces/claude-dashboard/dist/check-usage.js --json`, whose `codex`
  entry gives the five-hour and seven-day windows' percentage used and when each resets. Codex's
  own CLI prints neither, and the last `token_count` event in its newest session under
  `~/.codex/sessions/` is only as fresh as the last Codex turn. Codex is limited while either
  window reads 100.
- **While Codex is limited, new work goes to Claude** rather than waiting, and the integrator notes
  about when the full window resets.
- **Around that time it reads the quota again**; once Codex has quota back, the next dispatch goes
  to Codex, and nothing in flight moves back.

**A Codex implementer is started from its lane's repository with its role in the environment**,
proven by a probe on 2026-10-29:

```sh
MONOFLAKE_ROLE=implementer codex exec -C <lane>/monoflake/<repository> -s workspace-write \
	--add-dir <lane> -o <scratchpad>/<lane>-report.txt - < <brief>
```

- **The role is what holds it.** Two entries in the author's `~/.codex/hooks.json` act only where
  `MONOFLAKE_ROLE=implementer`: the implementer's commands on `Bash`, refusing `git status` in the
  probe while a session without the role ran it, and the format of each file an `apply_patch`
  writes, [lint-format.md](../lint-format.md).
- **Its brief says first to read `/Users/canmi/workspace/AGENTS.md`**: in a lane Codex loads the
  repository's own `AGENTS.md` alone, a lane being a git worktree whose root stops its search.
- **`--add-dir <lane>`** lets ReScript write what it builds of a sibling into the sibling's own
  directory, as a lane's builds do; the brief is stdin, and `-o` keeps the last message as its
  report. A task that reads the lane's history, as `accept --from`, also needs
  `--add-dir repos/<repository>/.jj`, the store a lane's workspace shares with the main checkout,
  found on 2026-10-29 when an `accept` there answered nothing.
- **A lane is prepared before it is handed over**: `pnpm install` in each repository and, in
  monoflake/platform, `mise run prepare`, whose generated libraries a block's `built` reads, so the
  implementer meets no setup it may not write. The author's `config.toml` sets `danger-full-access`, which `-s workspace-write`
  overrides for the implementer alone.

**After a wave lands: what to click.** Named specifically -- which page, which interaction, what
should be true -- because "have a look" hands the user the job of working out what changed.

**A one-line status tail, on the turns where the state moved.** A reply that dispatched an
implementer, or in which one returned, ends with a line naming what is in flight and what is
parked -- `in flight: rail-fix (editing) - parked: toc-read (done, unreported)`. Turns where
nothing moved carry nothing; a status line on every message is noise, and noise is what stops it
being read.

It earns its place twice. It is the insurance against the parking rule's one real risk, which is
the integrator quietly losing track of its own outstanding work. And it is where the user says
"report that one first" -- the parked order is a default, and the line is what makes it
overridable without their having to ask what is outstanding.

## When not to delegate

**A look being shaped with the user is edited by a session with no role, even where others
delegate.** Styling a page the user is looking at is a loop of one change, one glance and the next
word, and an implementer puts a brief, a cold start and a diff read into every turn of it: the
user waits on all three to learn what one line would have shown. So a session with no role named
edits the page it and the user are tuning, looks at it itself, and hands it back. What runs beside
that loop goes as the roles have it: the part of a failing CI that needs code changed to an
implementer; a release and a deploy to the integrator, a release of our own code asked of the user
first; a read to a reader. Stated by the author on
2026-10-08, after two rounds of a sidebar went through implementers while they waited.

**If the brief would be as long as the edit, make the edit.** One line, one constant, a rename
already known, a comment. The overhead of a cold agent is real and it is not always smaller than
the work.

**A decision is never delegated**, to an agent or to the tree. It goes to the user, as one
focused question. See [agent-protocol.md](agent-protocol.md), "Decision authority".
