# Scribe

A subagent defined in [.claude/agents/scribe.md](../../.claude/agents/scribe.md), Sonnet at medium
effort. It edits documents and nothing else, in a lane of its own, [lanes.md](lanes.md).

**It writes only `.md` files, inside its lane**, `scribe-writes-markdown` in
[model/rules/delegation.res](../../model/rules/delegation.res), held by `hooks/agent_commands.res`
on its Edit, Write and MultiEdit. A write refused there is reported to the integrator and never
worked around, [escapes.md](escapes.md). Its shell is an implementer's, [implementer.md](implementer.md),
so it types no jj command and runs no whole check.

**It brings a doc to the rule in force**, [rfcs.md](../rfcs.md), "hold only the rules in
force": it drains history, which is a date, a decider and a story of how a rule came to be, and
writes what is left as the rule alone, leaving the why to the RFC.

- **It keeps every heading and every quoted bold lead**, so a link or a citation by either still
  finds its place.
- **It changes no meaning.** A passage it cannot make plain without choosing a meaning it leaves as
  written and reports, with the lines.
- **It never moves a rule to the model.** A rule a program could decide is listed as a candidate,
  [model.md](../model.md), and the integrator writes the rule.

**Its last step is `mise run compare <original> <edited>`**, which lists each heading, bold lead
and code span the edit lost or added, `scripts/docs/doc_compare.res`. It copies the original aside
before the first edit. Each difference the run lists is either named in its report with the reason
the rule in force asked for it, or undone.

**It reports** the files it changed, what `compare` printed as it printed it, each passage it left
as written, and each candidate for the model.
