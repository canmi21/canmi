/** A rule the workspace can decide, its why in `doc`, and what holds it, or what is owed. */
type held =
  | Check(string)
  | Hook(string)
  | Gate(string)
  | Pending(string)

type t = {name: string, says: string, doc: string, held: held}
