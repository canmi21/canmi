/** Refuses a shell command that would hold the conversation, long-command-background. */
/** A loop that sleeps between its tests, the shape of a wait typed in the foreground. */
let pollingLoop = /\b(?:until|while|for|select)\b[\s\S]*?\bdo\b[\s\S]*?\bsleep\b[\s\S]*?\bdone\b/

/** The longest foreground timeout a call may ask for, in milliseconds. */
let longest =
  Delegation.foregroundSeconds->Int.toFloat *. 1000.

let timeout = (payload: Payload.t) =>
  switch payload
  ->Payload.object("tool_input")
  ->Option.flatMap(input => input->Dict.get("timeout")) {
  | Some(JSON.Number(milliseconds)) => Some(milliseconds)
  | _ => None
  }

let background = (payload: Payload.t) =>
  payload
  ->Payload.object("tool_input")
  ->Option.mapOr(false, input => input->Payload.flag("run_in_background"))

// Keep group boundaries until their background operator is known before splitting commands.
let foregroundText = (~keepBackground=false, command) => {
  let chars = command->Jj_command.withoutHeredocBodies->Node.codePoints
  let length = chars->Array.length
  let boundary = at =>
    [
      None,
      Some(" "),
      Some("\t"),
      Some("\r"),
      Some("\n"),
      Some(";"),
      Some("|"),
      Some("&"),
    ]->Array.includes(chars[at])
  let rec scan = (start, closing) => {
    let at = ref(start)
    let quote = ref("")
    let output = ref("")
    let piece = ref("")
    let closed = ref(false)
    let append = text => piece := piece.contents ++ text
    let flush = () => {
      output := output.contents ++ piece.contents
      piece := ""
    }
    while at.contents < length && !closed.contents {
      let char = chars->Array.getUnsafe(at.contents)
      let next = chars[at.contents + 1]
      if char == "\\" && quote.contents != "'" {
        append(char ++ next->Option.getOr(""))
        at := at.contents + 2
      } else if quote.contents == "'" {
        append(char)
        if char == "'" {
          quote := ""
        }
        at := at.contents + 1
      } else if char == "`" || (char == "$" && next == Some("(")) {
        let stop = Jj_command.substitutionEnd(chars, at.contents)->Option.getOr(length)
        append(chars->Array.slice(~start=at.contents, ~end=stop)->Array.join(""))
        at := stop
      } else if quote.contents == "\"" {
        append(char)
        if char == "\"" {
          quote := ""
        }
        at := at.contents + 1
      } else if char == "'" || char == "\"" {
        quote := char
        append(char)
        at := at.contents + 1
      } else if (
        char == "(" || (char == "{" && boundary(at.contents - 1) && boundary(at.contents + 1))
      ) {
        flush()
        let (inner, stop, balanced) = scan(at.contents + 1, char == "(" ? ")" : "}")
        append(";" ++ inner ++ ";")
        if !balanced {
          flush()
        }
        at := stop
      } else if char == closing && (char == ")" || boundary(at.contents - 1)) {
        closed := true
        at := at.contents + 1
      } else if char == "&" && next == Some("&") {
        append("&&")
        flush()
        at := at.contents + 2
      } else if char == "&" && next == Some(">") {
        append("&>")
        at := at.contents + 2
      } else if char == "|" && next == Some("&") {
        append("|")
        flush()
        at := at.contents + 2
      } else if (
        char == "&" &&
        at.contents > 0 &&
        [Some(">"), Some("<")]->Array.includes(chars[at.contents - 1])
      ) {
        append(char)
        at := at.contents + 1
      } else if char == "&" {
        keepBackground ? append(";") : piece := ";"
        flush()
        at := at.contents + 1
      } else {
        append(char)
        if [";", "\n", "|"]->Array.includes(char) {
          flush()
        }
        at := at.contents + 1
      }
    }
    flush()
    (output.contents, at.contents, closed.contents)
  }
  let (text, _, _) = scan(0, "")
  text
}

/** Whether a foreground command waits by polling outside a quoted argument or here-document. */
let polls = command =>
  pollingLoop->RegExp.test(
    foregroundText(command)->String.replaceRegExp(/'[^']*'|"(?:\\[\s\S]|[^"\\$`])*"/g, "\"\""),
  )

/** The seconds one literal sleep asks for, or nothing for a word that is not a plain number. */
let sleepSeconds = (word: string) =>
  switch word->String.match(/^(\d+(?:\.\d+)?)([smhd]?)$/) {
  | Some([_, Some(number), unit]) =>
    let scale = switch unit {
    | Some("m") => 60.
    | Some("h") => 3600.
    | Some("d") => 86400.
    | _ => 1.
    }
    Float.fromString(number)->Option.map(value => value *. scale)
  | _ => None
  }

/** The seconds every literal sleep in a foreground command adds up to. */
let rec sleepTotal = command =>
  Jj_command.segments(foregroundText(command))->Array.reduce(0., (total, piece) =>
    switch Jj_command.commandAt(piece) {
    | Some(at) if piece[at] == Some("sleep") =>
      total +.
      piece
      ->Array.slice(~start=at + 1)
      ->Array.reduce(0., (sum, word) => sum +. sleepSeconds(word)->Option.getOr(0.))
    | _ => total +. Jj_command.shellLine(piece)->Option.mapOr(0., sleepTotal)
    }
  )

let startsWith = (words, prefix) =>
  prefix->Array.everyWithIndex((word, at) => words[at] == Some(word))

/** The task a `mise run` names, past a `//repos/x:` path and the options before it. */
let taskOf = (words: array<string>) => {
  let at = ref(0)
  while (
    at.contents < words->Array.length && words->Array.getUnsafe(at.contents)->String.startsWith("-")
  ) {
    at :=
      at.contents + (
        ["-j", "--jobs", "-C", "--cd", "-E", "--env", "-o", "--output"]->Array.includes(
          words->Array.getUnsafe(at.contents),
        )
          ? 2
          : 1
      )
  }
  words[at.contents]->Option.map(name => {
    let bare =
      name->String.startsWith("//")
        ? name->String.split(":")->Array.slice(~start=1)->Array.join(":")
        : name
    bare
  })
}

/** Whether the words after `mise` run a task that is always long, or a long command under exec. */
let rec miseLong = (words: array<string>) => {
  let at = ref(0)
  while (
    at.contents < words->Array.length && words->Array.getUnsafe(at.contents)->String.startsWith("-")
  ) {
    at :=
      at.contents + (
        ["-C", "--cd", "-E", "--env"]->Array.includes(words->Array.getUnsafe(at.contents)) ? 2 : 1
      )
  }
  let rest = words->Array.slice(~start=at.contents + 1)
  switch words[at.contents] {
  | Some("run") | Some("r") =>
    switch taskOf(rest) {
    | None => false
    | Some(task) =>
      let head = task->String.split(":")->Array.getUnsafe(0)
      // What follows `--` is the command a task is given, as `job start -- mise run check`.
      let own = switch rest->Array.findIndex(word => word == "--") {
      | -1 => rest
      | dash => rest->Array.slice(~start=0, ~end=dash)
      }
      !(rest->Array.some(word => Delegation.shortFlags->Array.includes(word))) &&
      (Delegation.longTasks->Array.includes(head) ||
        Delegation.longTaskFlags->Array.some(((name, flag)) =>
          name == head && own->Array.includes(flag)
        ))
    }
  | Some("exec") | Some("x") =>
    switch rest->Array.findIndex(word => word == "--") {
    | -1 => false
    | dash => commandLong(rest->Array.slice(~start=dash + 1))
    }
  | _ => false
  }
}
/** Whether a program and its arguments are one of the always-long commands. */
and commandLong = (words: array<string>) =>
  switch words[0] {
  | None => false
  | Some(first) =>
    let program = Node.basename(first)
    let rest = words->Array.slice(~start=1)->Array.filter(word => !(word->String.startsWith("+")))
    if program == "mise" {
      miseLong(rest)
    } else if Delegation.shells->Array.includes(program) {
      switch rest->Array.findIndex(word =>
        word->String.startsWith("-") && word->String.includes("c")
      ) {
      | -1 => false
      | at => rest[at + 1]->Option.mapOr(false, text => lineLong(text))
      }
    } else {
      let named = Array.concat([program], rest)
      Delegation.longCommands->Array.some(long => named->startsWith(long))
    }
  }
/** Whether a command line runs an always-long command in the foreground in any segment. */
and lineLong = (command: string) =>
  Jj_command.segments(foregroundText(command))->Array.some(piece => {
    switch Jj_command.commandAt(piece) {
    | Some(at) => commandLong(piece->Array.slice(~start=at))
    | None => false
    }
  })

/** Whether a command line runs an always-long command in the foreground. */
let long = lineLong

/** Monitor may arrive as Bash but carries timeout_ms instead of Bash's timeout. */
let monitored = (payload: Payload.t) =>
  payload->Payload.text("tool_name") == Some("Monitor") ||
    payload
    ->Payload.object("tool_input")
    ->Option.mapOr(false, input => input->Dict.get("timeout_ms")->Option.isSome)

/** A tail following a job's output file, which runs on past the job until its monitor expires. */
let followsJob = command =>
  /\btail\b[^|;&]*\s-[A-Za-z]*[fF]/->RegExp.test(command) && /runs\/outputs\//->RegExp.test(command)

/** Why a foreground call would hold the conversation, or nothing where it would not. */
let held = (payload: Payload.t) =>
  if monitored(payload) && followsJob(Payload.command(payload)) {
    Some("it follows a job's output with tail, which runs on after the job ends")
  } else if background(payload) || monitored(payload) {
    None
  } else if polls(Payload.command(payload)) {
    Some("it waits in a loop that sleeps")
  } else if sleepTotal(Payload.command(payload)) > Delegation.foregroundSeconds->Int.toFloat {
    Some("it sleeps for longer than the foreground seconds")
  } else {
    switch timeout(payload) {
    | Some(milliseconds) if milliseconds > longest =>
      Some(`it asks for a timeout of ${Float.toString(milliseconds /. 1000.)} seconds`)
    | _ => long(Payload.command(payload)) ? Some("it runs a command that always runs long") : None
    }
  }

/** The tool name and field the gate judged, so a refusal shows the payload's shape. */
let judged = (payload: Payload.t) =>
  `tool_name ${payload->Payload.text("tool_name")->Option.getOr("(none)")}, field command`

/** The exit status the harness reads, 2 refusing the command with the reason on stderr. */
let refuse = (payload: Payload.t): int =>
  switch held(payload) {
  | None => 0
  | Some(why) =>
    Console.error(
      `Command refused by hooks/gates/background.res: ${why}, which holds the conversation.\n` ++
      `It judged ${judged(payload)}.\n` ++
      "Start it with `mise run //:job start -- <command>`, which returns at once and records it, then run `mise run //:watch <id>` under Monitor.\n" ++
      "`mise run //:job run -- <command>` with run_in_background waits and exits with its status.\n" ++
      "Read the result with `mise run //:job read <id>`.\n" ++ "The rule: long-command-background in model/rules/delegation.res, and docs/agents/agent-protocol.md",
    )
    2
  }
