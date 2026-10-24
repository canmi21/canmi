# Friction

Where the rules rubbed, kept so it can be read back, decided by the author on 2026-10-24.

**A record of friction is written for every escape, [escapes.md](escapes.md); for every change the
refactorer makes; and for an observation of the user's, once the user and the advisor have reached
a conclusion on it.** A leak a push's scan finds is one too, [pushing.md](pushing.md).

**The records live at `Delegation.friction`**, in
[model/rules/delegation.res](../../model/rules/delegation.res), local to the machine and in no
repository. **One record
is one file**, named for its date and the id of the rule it concerns. **Only the integrator writes
them.**

**The refactorer's report gives each change in that form**, the rule's id, where, and what changed,
and the integrator writes each down as a record, [refactorer.md](refactorer.md).

**`mise run friction` sums them by rule id**, a task not written yet. Once they are dealt with, the
user decides whether all of them are deleted, some, or none. What they teach is written into the
rules, the model or a script of the repository they concern.
