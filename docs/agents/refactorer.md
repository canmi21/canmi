# Refactorer

A subagent the integrator dispatches, defined in
[.claude/agents/refactorer.md](../../.claude/agents/refactorer.md), Opus at medium effort. Decided
by the author on 2026-10-24.

**It tidies what an implementer wrote where the form layer warns**, [checking.md](checking.md), "The
form layer holds at gates, never while code is written"; a file with one writer the integrator
tidies itself. **It may split a file, move a directory, draw a module out, and rename a local
name.**

**It changes no behavior.** The tests and the samples answer exactly as they did before it began,
and that is what done means for it. **It changes no contract and no global name.** Where a split
shows that a new block or component belongs there, it reports that, and creates nothing.

**It runs alone, never beside another agent.** It is held exactly as the implementer is: it does not
use Agent, SendMessage, Workflow or Artifact, and runs no jj, no `mise run check`, no task that
deploys, and no `ssh`, `rsync` or `wrangler`, `refactorer-commands` in
[model/rules/delegation.res](../../model/rules/delegation.res).

**It escapes to the integrator**, [escapes.md](escapes.md), when a split would cut through a
boundary meant to stay whole, or when a comment cannot say what it must within the rules. **Its
report gives each change it made in the form of a record of friction**: the rule's id, where, and
what changed, which the integrator writes down as the record, [friction.md](friction.md).
