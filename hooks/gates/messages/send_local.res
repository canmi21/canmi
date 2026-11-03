/** Refuses a message to a session not on this machine, `send-on-this-machine`. */
/** A name past a listing's ` [ref]`, which a listing may append to it. */
let bare = (to: string) =>
  switch to->String.match(/^(.*?) \[[^\]]+\]$/) {
  | Some(found) => found[1]->Option.flatMap(x => x)->Option.getOr(to)
  | None => to
  }

/** What is known here of who may be reached, each read apart so a test gives its own. */
type known = {sessions: array<string>, subagents: array<string>, socket: string => bool}

/** Why a message to `to` is refused, none where it stays on this machine. */
let why = (to: string, ~known: known) => {
  let name = bare(to)
  if (
    name == "main" || known.sessions->Array.includes(name) || known.subagents->Array.includes(name)
  ) {
    None
  } else if name->String.startsWith("uds:") {
    known.socket(name->String.slice(~start=4)) ? None : Some(`${to} is no socket on this machine`)
  } else {
    Some(`${to} is neither a session in ~/.claude/sessions/*.json nor a subagent of this session`)
  }
}

let home = () => Node.env->Dict.get("HOME")->Option.getOr("")

/** The name of each session this machine records, an unreadable record passed over. */
let sessionNames = () => {
  let directory = Node.join([home(), ".claude", "sessions"])
  Node.existsSync(directory)
    ? Node.readdir(directory)
      ->Array.filter(file => file->String.endsWith(".json"))
      ->Array.filterMap(file =>
        try Node.readFileSync(Node.join([directory, file]))
        ->Payload.parse
        ->Option.flatMap(fields => fields->Payload.text("name")) catch {
        | _ => None
        }
      )
    : []
}

/** Each subagent this session spawned by its id and its name, read beside its transcript. */
let subagentsOf = (payload: Payload.t) =>
  payload
  ->Payload.text("transcript_path")
  ->Option.mapOr([], transcript => {
    let directory = Node.join([transcript->String.slice(~start=0, ~end=-6), "subagents"])
    Node.existsSync(directory)
      ? Node.readdir(directory)
        ->Array.filter(file => file->String.endsWith(".meta.json"))
        ->Array.flatMap(file => {
          let id = file->String.slice(~start=6, ~end=-10)
          let named = try Node.readFileSync(Node.join([directory, file]))
          ->Payload.parse
          ->Option.flatMap(fields => fields->Payload.text("name")) catch {
          | _ => None
          }
          [id, ...named->Option.mapOr([], name => [name])]
        })
      : []
  })

/** A socket under the directory this machine's sessions listen in, and present. */
let localSocket = path =>
  path->String.startsWith("/tmp/cc-socks/") &&
  path->String.endsWith(".sock") &&
  Node.existsSync(path)

let refuse = (payload: Payload.t): int =>
  switch (
    payload->Payload.text("tool_name"),
    payload->Payload.object("tool_input")->Option.flatMap(input => input->Payload.text("to")),
  ) {
  | (Some("SendMessage"), Some(to)) =>
    switch why(
      to,
      ~known={
        sessions: sessionNames(),
        subagents: subagentsOf(payload),
        socket: localSocket,
      },
    ) {
    | None => 0
    | Some(reason) =>
      Console.error(
        `Message refused by hooks/gates/messages/send_local.res: ${reason}.\n` ++
        "Checked ~/.claude/sessions/*.json for its name, this session's subagents, and /tmp/cc-socks for a socket. A session just opened writes its record a moment later, so try again shortly; contacting another machine is only on the author's explicit word.\n" ++ "The rule: send-on-this-machine in model/rules/delegation.res, and docs/agents/delegation.md",
      )
      2
    }
  | _ => 0
  }
