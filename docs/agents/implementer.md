# Implementer

A subagent the integrator spawns, defined in
[.claude/agents/implementer.md](../../.claude/agents/implementer.md). Decided by the author on
2026-10-24.

**An implementer writes only its own block's directory**, in a lane of its own,
[lanes.md](lanes.md), "A lane is a directory beside `repos/`". It names what is local to its block,
and only that, choosing the most exact and most technically neutral word,
[naming.md](../naming.md), "A global name is the model's".

**Its brief is what `mise run brief <name>` prints**, with its lane's path, the files it owns and
the dependencies still waiting, [briefs.md](briefs.md), "What a brief holds". **Its model is the
one the integrator picks in that brief**: Codex while it has quota, else Sonnet at low, medium or
high effort, or Opus at medium, [delegation.md](delegation.md), "Codex comes first while it has
quota".

**It works by a completion protocol**, decided by the author on 2026-10-24, which the end of every
brief `mise run brief` prints says again, written by monoflake/platform's model:

- **while writing, it runs `mise run built <name>`**, as often as it likes;
- **once written, it runs `mise run accept <name> --from <base>` once**, and when both pass it stops
  and hands back;
- **it writes unit tests only for logic inside its block that the samples do not reach**; the
  samples are not its to write or to change;
- **it never needs a whole repository's check, `fmt`, a deploy, a rehearsal or jj**, and where it
  believes it does it escapes, [escapes.md](escapes.md).

Its own block's tests alone cost little and their scope is plain; running none would leave a failure
to the merge, where several blocks are already mixed. That is the logic layer for its own block
alone, [checking.md](checking.md), "The check has two layers". **It types no jj command**; a task it runs, as
`accept --from`, may read its own lane's history. Such a task snapshots its own lane's working copy
first, as every jj read does to see the latest edits; that touches its own lane's working-copy
commit alone, and records one operation in the shared store, where jj merges the operations several
workspaces make at once by itself. It does not deploy, does not run the whole of `mise run check`
and spawns no agent; **where what it writes is one part of the workspace's check, it may run that
part alone**, `mise run check workspace <part>`, and in any other repository it runs its block's
`built` and `accept`, [checking.md](checking.md); it does not use Agent,
SendMessage, Workflow or Artifact. A hook in its definition holds its commands, four kinds alone,
`implementer-commands` in [model/rules/delegation.res](../../model/rules/delegation.res) and
[delegation.md](delegation.md); it was proven to run in a subagent on 2026-10-24. Beside it,
`secrets-unprinted` refuses every role a command that prints the environment or a decrypted
secret, [briefs.md](briefs.md), "Every brief carries these". **It runs only in
an implementer spawned without a name**: one spawned by name, as a teammate a message can reach, ran
`git status` unrefused where one spawned plainly beside it was refused, a probe of 2026-10-24, so an
implementer is spawned plainly and a later word reaches it by its id.

**It escapes to the integrator**, [escapes.md](escapes.md), when a contract cannot express the
behavior its block needs, when its samples contradict each other, when the work cannot go on
without a file outside its own, or when one failure has been tried three times and still fails.
The part that is stopped waits; the rest goes on.

**It does not commit.** It reports four things:

- whether it is done;
- which files it changed;
- what `built` and `accept` printed, as they printed it;
- the problems it met, each as a fact or a question.
