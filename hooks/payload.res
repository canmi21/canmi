/** A hook's payload as both harnesses send it: a field absent or misshapen is none, not a crash. */
type t = Dict.t<JSON.t>

let parse = (text): option<t> =>
  try {
    switch JSON.parseOrThrow(text) {
    | JSON.Object(fields) => Some(fields)
    | _ => None
    }
  } catch {
  | _ => None
  }

let text = (fields: t, key) =>
  switch fields->Dict.get(key) {
  | Some(JSON.String(value)) => Some(value)
  | _ => None
  }

let flag = (fields: t, key) =>
  switch fields->Dict.get(key) {
  | Some(JSON.Boolean(value)) => value
  | _ => false
  }

let object = (fields: t, key): option<t> =>
  switch fields->Dict.get(key) {
  | Some(JSON.Object(value)) => Some(value)
  | _ => None
  }

/** The shell command a Bash tool call ran, or nothing. */
let command = fields =>
  fields->object("tool_input")->Option.flatMap(input => input->text("command"))->Option.getOr("")

/** Where the agent stood, which every jj question is asked from. */
let cwd = fields => fields->text("cwd")->Option.filter(Node.existsSync)->Option.getOr(Node.cwd())

/** jj's answer from `cwd`, or nothing where it fails or takes over thirty seconds. */
let jj = (~cwd, args) => {
  let result = Node.spawnSync(
    "jj",
    args,
    {cwd, encoding: "utf8", maxBuffer: 268435456, timeout: 30000},
  )
  result.status->Nullable.toOption == Some(0) ? result.stdout->Nullable.getOr("") : ""
}
