/**
 * What a tool call tells the run ledger, docs/agents/runs.md. An output read is a job's result
 * read, and a registering command names the session's transcript, whose growth is its turn.
 */
/** A command's own words, up to its first redirection. */
let pastRedirects = (words: array<string>) =>
  switch words->Array.findIndex(word => /^\d*[<>]/->RegExp.test(word)) {
  | -1 => words
  | at => words->Array.slice(~start=0, ~end=at)
  }

let registration = segment =>
  switch Jj_command.programOf(segment)->Option.map(((program, words)) => (
    program,
    pastRedirects(words)->List.fromArray,
  )) {
  | Some(("mise", list{"run", "job" | "//:job", "register", role, name, ...flags}))
    if Delegation.registeredRoles->Array.includes(role) && /^[A-Za-z0-9_.-]+$/->RegExp.test(name) =>
    switch flags {
    | list{} => Some((role, name, None))
    | list{"--thread", thread} => Some((role, name, Some(thread)))
    | _ => None
    }
  | _ => None
  }

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

/** The command as typed, so a here-document that only names a registration registers nobody. */
let typed = payload => Jj_command.withoutHeredocBodies(Payload.command(payload))

let observe = (payload: Payload.t, ~at=Date.now()) => {
  let text = readText(payload)

  outputsIn(text)->Array.forEach(path =>
    Ledger.idOfOutput(path)->Option.forEach(id =>
      if Ledger.find(id)->Option.mapOr(false, job => job.ended != None) {
        Ledger.markRead(~id, ~at)
      }
    )
  )

  transcriptOf(payload)->Option.forEach(transcript =>
    typed(payload)
    ->Jj_command.segments
    ->Array.filterMap(registration)
    ->Array.forEach(((role, name, thread)) =>
      Ledger.registerSession(~role, ~name, ~transcript=Some(transcript), ~thread)
    )
  )
}
