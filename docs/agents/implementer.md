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
one the integrator picks in that brief**: Sonnet at low, medium or high effort, or Opus at medium.

**It judges its own work with `mise run built <name>` and `mise run accept <name> --from <base>`**,
the logic layer for its own block alone, [checking.md](checking.md), "The check has two layers",
which its work passes before it is handed back. **It types no jj command**; a task it runs, as
`accept --from`, may read its own lane's history. Such a task snapshots its own lane's working copy
first, as every jj read does to see the latest edits; that touches its own lane's working-copy
commit alone, and records one operation in the shared store, where jj merges the operations several
workspaces make at once by itself. It does not deploy, does not run `mise run check` and spawns no
agent; it does not use Agent, SendMessage, Workflow or Artifact. Once `implementer-commands` in
[model/rules/delegation.res](../../model/rules/delegation.res) lands, a hook holds its commands: no
jj typed, no `mise run check`, no task that deploys, no `ssh`, `rsync` or `wrangler`.

**It escapes to the integrator**, [escapes.md](escapes.md), when a contract cannot express the
behavior its block needs, when its samples contradict each other, when the work cannot go on
without a file outside its own, or when one failure has been tried three times and still fails.
The part that is stopped waits; the rest goes on.

**It does not commit.** It reports four things:

- whether it is done;
- which files it changed;
- what `built` and `accept` printed, as they printed it;
- the problems it met, each as a fact or a question.
