/** Refuses a message to a session not on this machine, `send-on-this-machine`. */
/** What is known here of who may be reached, each read apart so a test gives its own. */
type known = {sessions: array<string>, subagents: array<string>, socket: string => bool}

/** Why a message to `to` is refused, none where it stays on this machine. */
let why = (to: string, ~known: known) => {
  if / \[[^\]]+\]$/->RegExp.test(to) {
    Some(
      `${to} carries a ref that does not identify this machine; use uds:/tmp/cc-socks/<pid>.sock`,
    )
  } else if (
    to == "main" ||
    to == "team-lead" ||
    known.sessions->Array.includes(to) ||
    known.subagents->Array.includes(to)
  ) {
    None
  } else if to->String.startsWith("uds:") {
    known.socket(to->String.slice(~start=4)) ? None : Some(`${to} is no socket on this machine`)
  } else {
    Some(`${to} is neither a session in ~/.claude/sessions/*.json nor a subagent of this session`)
  }
}

@module("node:os") external userInfo: unit => {"homedir": string} = "userInfo"

let home = () =>
  switch Node.env->Dict.get("HOME") {
  | Some(value) if value != "" => value
  | _ => userInfo()["homedir"]
  }

/** The name of each live session this machine records, an unreadable record passed over. */
let sessionNames = () =>
  try {
    let directory = Node.join([home(), ".claude", "sessions"])
    Node.existsSync(directory)
      ? Node.readdir(directory)
        ->Array.filter(file => file->String.endsWith(".json"))
        ->Array.filterMap(file =>
          try Node.readFileSync(Node.join([directory, file]))
          ->Payload.parse
          ->Option.flatMap(fields =>
            Ledger.numberOf(fields, "pid")
            ->Option.filter(pid => pid == Math.floor(pid) && Watchdog.alive(pid->Float.toInt))
            ->Option.flatMap(_ => fields->Payload.text("name"))
          ) catch {
          | _ => None
          }
        )
      : []
  } catch {
  | _ => []
  }

/** Each subagent this session spawned by its id and its name, read beside its transcript. */
let subagentsOf = (payload: Payload.t) =>
  payload
  ->Payload.text("transcript_path")
  ->Option.mapOr([], transcript =>
    try {
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
    } catch {
    | _ => []
    }
  )

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
        "Checked live processes in ~/.claude/sessions/*.json, this session's subagents, and /tmp/cc-socks for a socket. A destination with a ref is refused; use uds:/tmp/cc-socks/<pid>.sock. A session just opened writes its record a moment later, so try again shortly; contacting another machine is only on the author's explicit word.\n" ++ "The rule: send-on-this-machine in model/rules/delegation.res, and docs/agents/delegation.md",
      )
      2
    }
  | _ => 0
  }
