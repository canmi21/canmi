let decoded = word => Jj_command.words(word)->Option.flatMap(words => words[0])->Option.getOr(word)

let unguarded = word =>
  word
  ->String.replaceRegExpBy0Unsafe(/'[^']*'|"(?:\\[\s\S]|[^"\\])*"|\\[\s\S]/g, (
    ~match,
    ~offset as _,
    ~input as _,
  ) => match->String.startsWith("\"") ? match->String.replaceRegExp(/\\[\s\S]/g, "") : "")
  ->String.replaceRegExp(/\$\{[A-Za-z_][A-Za-z0-9_]*:\?[^}]*\}/g, "")
  ->String.match(/\$(?:[A-Za-z_0-9@*#?$!\-]|\{)/)
  ->Option.isSome

let rec unsafe = command =>
  Jj_command.segments(
    ~keepQuotes=true,
    Background.foregroundText(~keepBackground=true, Push.withoutQuotedBodies(command)),
  )->Array.some(segment => {
    let raw = Codex_usage.dropOpeners(segment)
    let words = raw->Array.map(decoded)
    switch Jj_command.commandAt(words) {
    | None => false
    | Some(at) =>
      let rest = words->Array.slice(~start=at + 1)
      switch words[at]->Option.map(Node.basename) {
      | Some("rm") =>
        let operands = ref(false)
        let redirected = ref(false)
        raw
        ->Array.slice(~start=at + 1)
        ->Array.some(word => {
          let value = decoded(word)
          if redirected.contents {
            redirected := false
            false
          } else if /^(?:[0-9]*[<>]|&>)/->RegExp.test(word) {
            redirected := /[<>]$|[<>]&$|<<-$/->RegExp.test(word)
            false
          } else if !operands.contents && value == "--" {
            operands := true
            false
          } else if !operands.contents && value->String.startsWith("-") {
            false
          } else {
            unguarded(word)
          }
        })
      | Some(program) if Delegation.shells->Array.includes(program) =>
        switch rest->Array.findIndex(word => /^-[A-Za-z]*c[A-Za-z]*$/->RegExp.test(word)) {
        | -1 => false
        | flag => rest[flag + 1]->Option.mapOr(false, unsafe)
        }
      | _ => false
      }
    }
  })

let refuse = (payload: Payload.t): int =>
  if payload->Payload.text("tool_name") == Some("Bash") && unsafe(Payload.command(payload)) {
    Console.error(
      "Command refused by hooks/gates/rmvar.res: an rm path contains an unguarded shell variable.\n" ++
      "Rewrite the path as \"${S:?}\"/name with your variable name, or use the literal path.\n" ++ "The rule: rm-variable-guarded",
    )
    2
  } else {
    0
  }
