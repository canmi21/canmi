/** Refuses dispatching an implementer whose brief does not name one result and one verification. */
let roles = ["implementer", "refactorer"]

let pointer = /brief is the file\s+(\/[^\s"'`]+)/i

let linesOf = (text, prefix) =>
  text->String.split("\n")->Array.filter(line => line->String.startsWith(prefix))->Array.length

/** What a brief lacks or repeats, one sentence each, none where it holds exactly one of both. */
let faults = (brief: string): array<string> =>
  [("Result:", "result"), ("Verify:", "verification")]->Array.filterMap(((prefix, noun)) =>
    switch linesOf(brief, prefix) {
    | 1 => None
    | 0 => Some(`it holds no line starting \`${prefix}\``)
    | count =>
      Some(`it holds ${Int.toString(count)} lines starting \`${prefix}\`, and ${noun}s are seats`)
    }
  )

let unreadable = (path, ~why) => [`its brief file ${path} ${why}`]

let readFile = path =>
  try Some(Node.readFileSync(path)) catch {
  | _ => None
  }

/** The faults of a Claude implementer's prompt, or of the file it names where it only points. */
let promptFaults = (prompt: string): array<string> =>
  switch (
    linesOf(prompt, "Result:") + linesOf(prompt, "Verify:"),
    pointer
    ->RegExp.exec(prompt)
    ->Option.flatMap(found => found->Array.get(1))
    ->Option.flatMap(x => x),
  ) {
  | (0, Some(path)) =>
    let path = path->String.replaceRegExp(/[.,;:)]+$/, "")
    switch readFile(path) {
    | Some(brief) => faults(brief)
    | None => unreadable(path, ~why="cannot be read")
    }
  | _ => faults(prompt)
  }

/** The lanes a text names by their directory, each once, none that is not on disk. */
let lanesIn = (text: string, ~exists=Node.existsSync) =>
  text
  ->String.split(`${Delegation.lanes}/`)
  ->Array.slice(~start=1)
  ->Array.filterMap(rest =>
    rest
    ->String.match(/^[a-z][a-z0-9-]*/)
    ->Option.flatMap(found => found[0]->Option.flatMap(x => x))
  )
  ->Array.filter(name => exists(Node.join([Lane_state.lanes(Lane.baseOf(Registry.root)), name])))
  ->Set.fromArray
  ->Set.values
  ->Array.fromIterator

/** A lane a brief names that is stale, `lane-not-stale`, its seat otherwise on the old tree. */
let staleFaults = (text: string, ~exists=Node.existsSync, ~stale=Lane_check.stale) =>
  lanesIn(text, ~exists)->Array.flatMap(name =>
    Lane_state.workspacesOf(
      ~root=Lane.baseOf(Registry.root),
      ~subdirs=Lane_state.realSubdirs,
      ~isWorkspace=Lane_state.realIsWorkspace,
      name,
    )
    ->Array.filter(one => stale(one.path))
    ->Array.map(one => `lanes/${name}/${one.rel} is stale, so open a fresh lane`)
  )

/** The file a segment's stdin is redirected from, `< path` or `<path`. */
let redirected = (words: array<string>) =>
  words
  ->Array.flatMapWithIndex((word, at) =>
    if word == "<" {
      words[at + 1]->Option.mapOr([], file => [file])
    } else if word->String.startsWith("<") && !(word->String.startsWith("<<")) {
      [word->String.slice(~start=1)]
    } else {
      []
    }
  )
  ->Array.get(0)

/** The role an implementer's codex exec names in its own assignments, or nothing. */
let roleOf = (prefix: array<string>) =>
  roles->Array.find(role => prefix->Array.includes(`MONOFLAKE_ROLE=${role}`))

/** Whether the words after `codex` run `exec`. */
let execs = (rest: array<string>) => {
  let at = ref(0)
  let outcome = ref(None)
  while outcome.contents == None && at.contents < rest->Array.length {
    let word = rest->Array.getUnsafe(at.contents)
    if Codex_usage.valued->Array.includes(word) {
      at := at.contents + 2
    } else if word->String.startsWith("-") {
      at := at.contents + 1
    } else {
      outcome := Some(word == "exec" || word == "e")
    }
  }
  outcome.contents->Option.getOr(false)
}

/** The faults of each implementer's codex exec in a command line, with the segment's own SKIP. */
let rec commandFaults = (command: string, ~cwd): array<string> =>
  Jj_command.segments(Codex_usage.flattened(command))->Array.flatMap(segment =>
    segmentFaults(Codex_usage.dropOpeners(segment), ~cwd)
  )
and segmentFaults = (segment: array<string>, ~cwd): array<string> =>
  switch Jj_command.commandAt(segment) {
  | None => []
  | Some(at) =>
    let prefix = segment->Array.slice(~start=0, ~end=at)
    let argv = segment->Array.slice(~start=at)
    switch argv[0]->Option.map(Node.basename) {
    | Some("codex") =>
      if (
        execs(argv->Array.slice(~start=1)) &&
        roleOf(prefix)->Option.isSome &&
        !(prefix->Array.includes(`${Commits.skip}=seat`))
      ) {
        switch redirected(segment) {
        | None => ["it has no brief file redirected to stdin, as `- < <path>`"]
        | Some(file) =>
          let path = Node.resolve([cwd, file])
          let stale = staleFaults(segment->Array.join(" "))
          switch readFile(path) {
          | Some(brief) => Array.concat(faults(brief), Array.concat(stale, staleFaults(brief)))
          | None => unreadable(path, ~why="cannot be read")
          }
        }
      } else {
        []
      }
    | Some(program) if Delegation.shells->Array.includes(program) =>
      let rest = argv->Array.slice(~start=1)
      switch rest->Array.findIndex(word => /^-[A-Za-z]*c[A-Za-z]*$/->RegExp.test(word)) {
      | -1 => []
      | flag =>
        rest[flag + 1]->Option.mapOr([], inner => {
          // An assignment before the shell reaches the codex inside it.
          let inherited = prefix->Array.filter(word => word->String.startsWith("MONOFLAKE_ROLE="))
          commandFaults(inherited->Array.concat([inner])->Array.join(" "), ~cwd)
        })
      }
    | _ => []
    }
  }

let subagent = (payload: Payload.t) =>
  payload
  ->Payload.object("tool_input")
  ->Option.flatMap(input => input->Payload.text("subagent_type"))

/** The exit status the harness reads, 2 refusing the dispatch with the reason on stderr. */
let refuse = (payload: Payload.t): int => {
  let found = switch payload->Payload.text("tool_name") {
  | Some("Agent") | Some("Task") =>
    switch subagent(payload) {
    | Some(kind) if roles->Array.includes(kind) =>
      Some(
        payload
        ->Payload.object("tool_input")
        ->Option.flatMap(input => input->Payload.text("prompt"))
        ->Option.getOr("")
        ->(prompt => Array.concat(promptFaults(prompt), staleFaults(prompt))),
      )
    | _ => None
    }
  | _ => Some(commandFaults(Payload.command(payload), ~cwd=Payload.cwd(payload)))
  }
  switch found {
  | Some(faults) if faults != [] =>
    Console.error(
      `Dispatch refused by hooks/gates/seat.res: ${faults->Array.join("; ")}.\n` ++
      "A brief holds exactly one line starting `Result:` and exactly one starting `Verify:`; two results are two seats, so split them and dispatch each. A stale lane is left for a fresh one.\n" ++ "The rules: seat-one-result and lane-not-stale in model/rules/delegation.res, and docs/agents/delegation.md, \"The integrator schedules the queue itself\"",
    )
    2
  | _ => 0
  }
}
