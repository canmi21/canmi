# Reader

The built-in Explore, run as Sonnet at low effort. It reads the tree or an upstream and writes
nothing, [reading.md](reading.md).

**Its brief names four things**, [reading.md](reading.md), "Reading is delegated; the judgment on
what comes back is not".

**It reports what it quotes with where each quotation came from, and marks which of what it says is
fact and which is inferred.**

## The scout

A subagent defined in [.claude/agents/scout.md](../../.claude/agents/scout.md), Sonnet at low
effort. It reads and writes nothing: Agent, Write, Edit, MultiEdit and NotebookEdit are refused,
and its shell is held to a reviewer's read-only commands, `reviewer-commands` in
[model/rules/delegation.res](../../model/rules/delegation.res).

**It answers one question from the files it is named**, a small directory, or one area of the map,
`areas` in the same file, and never widens its scope past them. An area is a name for entry paths
under `repos/`; a path in a repository that is not cloned is passed over, and `areas-exist` holds
the rest to the tree.

**Its answer is quoted lines with `file:line`, then a one-line answer**, in `scoutAnswer` lines at
most. **Where the answer is not in what it was given, it says so and stops**: it does not search
elsewhere and does not guess.
