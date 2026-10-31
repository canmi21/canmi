/** Refuses a push an agent runs past the verb, `jj git push` or `git push` typed directly. */
/** git's global options that take a value, so the word after them is not its subcommand. */
let gitValued = [
  "-C",
  "-c",
  "--git-dir",
  "--work-tree",
  "--namespace",
  "--exec-path",
  "--config-env",
]

/** The first word of `words` past options, those in `valued` taking the next word too. */
let firstOperand = (words: array<string>, ~valued) => {
  let at = ref(0)
  let found = ref(None)
  while found.contents == None && at.contents < words->Array.length {
    let word = words->Array.getUnsafe(at.contents)
    if valued->Array.includes(word) {
      at := at.contents + 2
    } else if word->String.startsWith("-") {
      at := at.contents + 1
    } else {
      found := Some(word)
    }
  }
  found.contents
}

/** Whether one segment of a command line pushes by jj or git directly. */
let pushes = (segment: array<string>) =>
  switch Jj_command.programOf(segment) {
  | Some(("jj", _)) =>
    switch Jj_command.invocationOf(segment) {
    | Some(("git", rest)) => firstOperand(rest, ~valued=[]) == Some("push")
    | _ => false
    }
  | Some(("git", words)) => firstOperand(words, ~valued=gitValued) == Some("push")
  | _ => false
  }

/** A here-document whose delimiter is quoted, whose body the shell never runs. */
let quotedHeredoc = /<<-?\s*(?:'([^']+)'|"([^"]+)"|\\([A-Za-z_][A-Za-z0-9_]*))/

/** The command line without the body of each quoted here-document, which is text and not run. */
let withoutQuotedBodies = command => {
  let kept = []
  let ending = ref(None)
  command
  ->String.split("\n")
  ->Array.forEach(line =>
    switch ending.contents {
    | Some(delimiter) => line->String.trim == delimiter ? ending := None : ()
    | None =>
      kept->Array.push(line)
      switch line->RegExp.exec(quotedHeredoc, _) {
      | Some(found) =>
        ending :=
          found
          ->RegExp.Result.matches
          ->Array.findMap(group => group)
      | None => ()
      }
    }
  )
  kept->Array.join("\n")
}

/** Whether a command line pushes past the verb anywhere in it. */
let bypasses = command => Jj_command.segments(withoutQuotedBodies(command))->Array.some(pushes)

/** The exit status the harness reads, 2 refusing the command with the reason on stderr. */
let refuse = (payload: Payload.t): int =>
  if bypasses(Payload.command(payload)) {
    Console.error(
      "Push refused by hooks/push.res: a push goes through `mise run push <repo>`, never `jj git push` or `git push` typed directly.\n" ++
      "Only the verb runs the form layer and the scan for private identifiers.\n" ++ "The rule: push-through-verb in model/rules/toolchain.res, and docs/agents/pushing.md",
    )
    2
  } else {
    0
  }
