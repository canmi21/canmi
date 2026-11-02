/** Refuses killing a process by name or by anything but a recorded pid, `kill-by-recorded-pid`. */
/** What finds its targets by a name, and what runs another program later in its own words. */
let byName = ["pkill", "killall"]
let wrappers = [
  "env",
  "sudo",
  "command",
  "exec",
  "nohup",
  "timeout",
  "time",
  "nice",
  "xargs",
  "find",
]

/** The variables a command itself set from `$!`. */
let capturedIn = (command: string) =>
  command
  ->String.split("$!")
  ->Array.slice(~start=0, ~end=-1)
  ->Array.filterMap(before =>
    before
    ->String.match(/([A-Za-z_][A-Za-z0-9_]*)=["']?$/)
    ->Option.flatMap(found => found[1]->Option.flatMap(x => x))
  )

/** Whether one operand of kill is a pid the agent recorded. */
let recorded = (word: string, ~captured) => {
  let bare = word->String.replaceRegExp(/^["']|["']$/g, "")
  if /^-?[0-9]+$/->RegExp.test(bare) || /^%[0-9]+$/->RegExp.test(bare) || bare == "$!" {
    true
  } else {
    switch bare->String.match(/^-?\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?$/) {
    | Some(found) =>
      found[1]->Option.flatMap(x => x)->Option.mapOr(false, name => captured->Array.includes(name))
    | None => false
    }
  }
}

/** The operands of a kill, past its signal and options. */
let operandsOf = (words: array<string>) => {
  let rec go = (rest: list<string>) =>
    switch rest {
    | list{"-s" | "-n", _, ...more} => go(more)
    | list{"--", ...more} => more
    | list{word, ...more} if /^-(?:[A-Za-z]+|[0-9]+)$/->RegExp.test(word) => go(more)
    | more => more
    }
  go(words->List.fromArray)->List.toArray
}

let rec why = command => {
  let captured = capturedIn(command)
  Jj_command.segments(
    ~keepQuotes=true,
    Background.foregroundText(~keepBackground=true, Push.withoutQuotedBodies(command)),
  )->Array.findMap(segment => {
    let raw = Codex_usage.dropOpeners(segment)
    let words = raw->Array.map(Rmvar.decoded)
    switch Jj_command.commandAt(words) {
    | None => None
    | Some(at) =>
      let rest = words->Array.slice(~start=at + 1)
      let program = words[at]->Option.map(Node.basename)->Option.getOr("")
      if byName->Array.includes(program) {
        Some(`${program} finds its targets by name`)
      } else if program == "kill" {
        let operands =
          raw
          ->Array.slice(~start=at + 1)
          ->operandsOf
          ->Array.filter(word => !(/^[0-9]*[<>]/->RegExp.test(word)))
        // No operand is what xargs fills in from what it found.
        operands == [] && rest->Array.includes("-l")
          ? None
          : operands == []
          ? Some("kill is given no pid, so what runs it finds them")
          : operands
            ->Array.find(word => !recorded(word, ~captured))
            ->Option.map(word => `kill is given ${word}, which this command did not record`)
      } else if program == "sudo" {
        why(rest->Array.filter(word => !(word->String.startsWith("-")))->Array.join(" "))
      } else if program == "find" {
        switch rest->Array.findIndex(word => word == "-exec" || word == "-execdir") {
        | -1 => None
        | flag => why(rest->Array.slice(~start=flag + 1)->Array.join(" "))
        }
      } else if Delegation.shells->Array.includes(program) {
        shellLine(rest)
      } else if program == "eval" {
        why(rest->Array.join(" "))
      } else {
        None
      }
    }
  })
}
// A shell given -c runs a line of its own, which is judged as one.
and shellLine = (rest: array<string>) =>
  switch rest->Array.findIndex(word => /^-[A-Za-z]*c[A-Za-z]*$/->RegExp.test(word)) {
  | -1 => None
  | flag => rest[flag + 1]->Option.flatMap(why)
  }

let refuse = (payload: Payload.t): int =>
  switch why(Payload.command(payload)) {
  | None => 0
  | Some(reason) =>
    Console.error(
      `Command refused by hooks/gates/kill_named.res: ${reason}.\n` ++
      "A process is killed only by a pid you recorded when you started it: start it with `cmd & P=$!` and `kill $P`, or a literal pid, or start it by `mise run //:job start` and end it by `mise run //:job stop <id>`.\n" ++ "The rule: kill-by-recorded-pid in model/rules/toolchain.res, and docs/agents/agent-protocol.md",
    )
    2
  }
