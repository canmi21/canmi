/** A rule the workspace can decide, its why in `doc`, and what holds it, or what is owed. */
type held =
  | Check(string)
  | Hook(string)
  | Gate(string)
  | Pending(string)

/** The layer of the check a rule belongs to, docs/agents/checking.md, a rule marked none Logic. */
type layer =
  | Logic
  | Form

/** Whether an escape may ask a rule to change, docs/agents/escapes.md, unmarked Escapable. */
type escape =
  | Escapable
  | ByTool

/** Where a decision lets a rule not hold, why, and the decision that made it. */
type exempt = {where: string, why: string, decided: string}

type t = {
  name: string,
  says: string,
  doc: string,
  held: held,
  layer?: layer,
  escape?: escape,
  exempts?: array<exempt>,
}
