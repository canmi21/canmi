/** Refuses killing a process by name or by anything but a recorded pid, `kill-by-recorded-pid`. */
/** What finds its targets by a name. */
let byName = ["pkill", "killall"]

/** The options of sudo and ssh that take a value, so their program can be found. */
let sudoValued = ["-u", "-g", "-h", "-p", "-C", "-T", "-U", "-r", "-t"]
let sshValued = ["-o", "-i", "-p", "-J", "-l", "-F", "-b", "-c", "-D", "-E", "-e", "-L", "-R", "-S"]

/** A killing line piped to a shell, which judges nothing word by word. */
let pipedToShell = /\bkill\b[^|]*\|\s*(?:\/[^\s]*\/)?(?:sh|bash|zsh|fish)\b/

/** What follows a program's options, those of `valued` taking the next word. */
let rec pastOptions = (words: list<string>, ~valued) =>
  switch words {
  | list{word, _, ...more} if valued->Array.includes(word) => pastOptions(more, ~valued)
  | list{word, ...more} if word->String.startsWith("-") => pastOptions(more, ~valued)
  | more => more
  }

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

/** The operands of a kill, past its one signal, its options and any redirection. */
let operandsOf = (words: array<string>) => {
  let rec plain = (rest: list<string>) =>
    switch rest {
    | list{word, _, ...more} if /^(?:[0-9]*|&)[<>]+&?$/->RegExp.test(word) => plain(more)
    | list{word, ...more} if /^(?:[0-9]*|&)[<>]/->RegExp.test(word) => plain(more)
    | list{word, ...more} => list{word, ...plain(more)}
    | list{} => list{}
    }
  let rec operands = (rest: list<string>, ~signalled) =>
    switch rest {
    | list{"-s" | "-n", _, ...more} => operands(more, ~signalled=true)
    | list{"--", ...more} => more
    | list{word, ...more} if !signalled && /^-(?:[A-Za-z]+|[0-9]+)$/->RegExp.test(word) =>
      operands(more, ~signalled=true)
    | more => more
    }
  operands(plain(words->List.fromArray), ~signalled=false)->List.toArray
}

let rec why = command => {
  let captured = capturedIn(command)
  let shown = Background.foregroundText(~keepBackground=true, Push.withoutQuotedBodies(command))

  (
    pipedToShell->RegExp.test(shown) ? Some("a killing line is piped to a shell") : None
  )->Option.orElse(segmentsWhy(shown, ~captured))
}
and segmentsWhy = (shown, ~captured) =>
  Jj_command.segments(~keepQuotes=true, shown)->Array.findMap(segment => {
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
        // No operand is what xargs fills in from what it found.
        operands == [] && rest->Array.includes("-l")
          ? None
          : operands == []
          ? Some("kill is given no pid, so what runs it finds them")
          : operands
            ->Array.find(word => !recorded(word, ~captured))
            ->Option.map(word => `kill is given ${word}, which this command did not record`)
      } else if program == "sudo" {
        why(rest->List.fromArray->pastOptions(~valued=sudoValued)->List.toArray->Array.join(" "))
      } else if program == "builtin" {
        why(rest->Array.join(" "))
      } else if program == "mise" {
        switch rest->Array.findIndex(word => word == "--") {
        | -1 => None
        | dash => why(rest->Array.slice(~start=dash + 1)->Array.join(" "))
        }
      } else if program == "ssh" {
        // The first word past its options is the host, and the rest runs there.
        switch rest->List.fromArray->pastOptions(~valued=sshValued) {
        | list{_, ...line} => why(line->List.toArray->Array.join(" "))
        | list{} => None
        }
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
