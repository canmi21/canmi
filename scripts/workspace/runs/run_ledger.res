/**
 * What a tool call tells the run ledger, docs/agents/runs.md. An output read is a job's result
 * read, and a registering command names the session's transcript, whose growth is its turn.
 */
let registering = /\bmise\s+run\s+(?:\/\/:)?job\s+register\s+([a-z]+)\s+([A-Za-z0-9_.-]+)(?![A-Za-z0-9_.-])/
let namedThread = /--thread\s+([a-z][a-z0-9-]*)/

/** The output paths of the ledger a call's text names. */
let outputsIn = (text: string) => {
  let prefix = Ledger.outputs() ++ Node.sep
  let user = Node.env->Dict.get("HOME")->Option.getOr("")
  let prefixes =
    user != "" && prefix->String.startsWith(user ++ Node.sep)
      ? [
          prefix,
          "~" ++ prefix->String.slice(~start=user->String.length),
          "$HOME" ++ prefix->String.slice(~start=user->String.length),
        ]
      : [prefix]
  prefixes->Array.flatMap(named =>
    text
    ->String.split(named)
    ->Array.slice(~start=1)
    ->Array.filterMap(rest =>
      rest
      ->String.match(/^[0-9a-f-]+\.log/)
      ->Option.flatMap(found => found[0]->Option.flatMap(x => x))
      ->Option.map(file => prefix ++ file)
    )
  )
}

/** The text of a call that may read a job's output, its file or its command. */
let readText = (payload: Payload.t) => {
  let input = payload->Payload.object("tool_input")
  [
    input->Option.flatMap(fields => fields->Payload.text("file_path")),
    input->Option.flatMap(fields => fields->Payload.text("command")),
  ]
  ->Array.filterMap(x => x)
  ->Array.join("\n")
}

/** The session's own transcript, a subagent's where it is one. */
let transcriptOf = (payload: Payload.t) =>
  payload
  ->Payload.text("agent_transcript_path")
  ->Option.orElse(payload->Payload.text("transcript_path"))

let observe = (payload: Payload.t, ~at=Date.now()) => {
  let text = readText(payload)

  outputsIn(text)->Array.forEach(path =>
    Ledger.idOfOutput(path)->Option.forEach(id =>
      if Ledger.find(id)->Option.mapOr(false, job => job.ended != None) {
        Ledger.markRead(~id, ~at)
      }
    )
  )

  switch (RegExp.exec(registering, Payload.command(payload)), transcriptOf(payload)) {
  | (Some(found), Some(transcript)) =>
    switch (found[1]->Option.flatMap(x => x), found[2]->Option.flatMap(x => x)) {
    | (Some(role), Some(name))
      if Delegation.registeredRoles->Array.includes(role) &&
        !(Payload.command(payload)->String.includes("--transcript")) =>
      let thread =
        RegExp.exec(namedThread, Payload.command(payload))->Option.flatMap(found =>
          found[1]->Option.flatMap(x => x)
        )
      Ledger.registerSession(~role, ~name, ~transcript=Some(transcript), ~thread)
    | _ => ()
    }
  | _ => ()
  }
}
