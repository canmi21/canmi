# Reviewer

A subagent, defined in [.claude/agents/reviewer.md](../../.claude/agents/reviewer.md), Opus at high
effort. Decided by the author on 2026-10-24.

**A reviewer only reads.** It starts in a fresh context, and its brief holds the diff, the rules and
the RFCs alone, **never an implementer's reasoning or report.** **Its commands are a whitelist**,
decided by the author on 2026-10-24, `reviewer-commands` in
[model/rules/delegation.res](../../model/rules/delegation.res):

- jj as `diff`, `log`, `show`, `file show` and `file list`, never `status`, and never given a flag
  in `jjRunning`;
- `cat`, `head`, `tail`, `sed`, `grep`, `rg`, `ls`, `find`, `wc` and `diff`; sed only quiet, `-n`,
  never `-i`, and with no command in `sedWriting`; find never given a flag in `findWriting`; rg
  never given one in `rgRunning`;
- output redirected only to `redirectedTo`, and a command run by `&`, a substitution or a pipe
  judged as one of its own;
- each segment's first word is its program: no wrapper before it and no assignment to the
  environment, decided by the author on 2026-10-24.

Each list beyond the author's own words, the flags that write or run a program, was added by the
integrator on 2026-10-24 from a review, as what "only reads" already asks.

**Every other command is refused, every mise task among them**: a check writes what it builds,
which a role that only reads must not, and what a check concludes is the integrator's.

**A way around the whitelist found after wave four is a known limit**, as a way around the
implementer's four kinds is, [delegation.md](delegation.md), and a review does not count it a
defect, decided by the author on 2026-10-24. The hook guards a well-meaning agent against a slip,
not against an adversary, and a reviewer is no adversary; the mechanism is not polished further.

**In a public repository's wave it also reads the diff for leaks**, [pushing.md](pushing.md), "A
push carries nothing private".

**It reports defects alone**, each with its file and line, the text quoted, and the rule it breaks;
that report is its escape, [escapes.md](escapes.md). It proposes nothing of the design.

**A wave has one full review, and the fixes made for it one verification**, which reads only the
items the review listed and says of each whether it is fixed. What a verification finds beside them
is reported with its severity: a high one stops the work for the user, any other is a record of
friction and blocks no push. What is still not fixed after it goes to the user; the advisor or the
user confirms the integrator's fix by reading it, and no reviewer is dispatched again,
[checking.md](checking.md), "A wave is reviewed once, and its fixes verified once".
