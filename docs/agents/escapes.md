# Escapes

What an agent does when a rule stands in the way of the work, decided by the author on
2026-10-24. How the work is split is [delegation.md](delegation.md).

## An escape asks for the model to change

**An escape is a request that the model be changed, never a way past a rule.** While it waits,
every rule still holds: the part of the work it stopped waits for the decision, and the rest goes
on. **The decision has one of three outcomes**:

- the rule is followed, and the decision says how;
- the rule is changed;
- the rule gains an exception in the model, typed, saying where it holds, why, and which decision
  made it, `Rule.exempts` in [model/rule.res](../../model/rule.res).

So the model is always whole: what is allowed is what it says.

**Each rule says whether it can be escaped**, `Rule.escape`, and **a rule that says nothing can
be.** Only a rule a formatter satisfies on its own is marked `ByTool` and cannot be:
`formatted-on-write`, and `tabs`, since the formatter writes the indentation `.editorconfig` sets.

## Who escapes to whom

- **An implementer escapes to the integrator** when a contract cannot express the behavior the
  block needs; when its samples contradict each other; when the work cannot go on without a file
  outside its own; or when one failure has been tried three times and still fails.
- **The refactorer escapes to the integrator** when a split would cut through a boundary meant to
  stay whole, or when a comment cannot say what it must within the rules.
- **A reviewer's report of a defect is its escape.**
- **The integrator escapes to the user and the advisor.**

Each escape is also a record of friction, [friction.md](friction.md).
