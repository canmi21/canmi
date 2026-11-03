/** Refuses a jj restore or abandon that would lose changes nobody has committed. */
/** The flags of `jj restore` that take a value, besides jj's global ones. */
let restoreValued = ["--from", "-f", "--to", "-t", "--into", "-c", "--changes-in"]

/** The words past flags and the values they take, those after `--` included. */
let operands = (arguments: array<string>, ~valued) => {
  let kept = []
  let at = ref(0)
  let bare = ref(false)
  while at.contents < arguments->Array.length {
    let word = arguments->Array.getUnsafe(at.contents)
    if !bare.contents && word == "--" {
      bare := true
      at := at.contents + 1
    } else if !bare.contents && valued->Array.includes(word) {
      at := at.contents + 2
    } else if !bare.contents && word->String.startsWith("-") {
      at := at.contents + 1
    } else {
      kept->Array.push(word)
      at := at.contents + 1
    }
  }
  kept
}

/** The value a flag carries, as `--to x` or `--to=x`, the last one given. */
let flagValue = (arguments: array<string>, names: array<string>) => {
  let found = ref(None)
  arguments->Array.forEachWithIndex((word, at) =>
    names->Array.forEach(name => {
      if word == name {
        found := arguments[at + 1]
      } else if name->String.startsWith("--") && word->String.startsWith(name ++ "=") {
        found := Some(word->String.slice(~start=name->String.length + 1))
      }
    })
  )
  found.contents
}

/** The revsets whose changes a command would lose, none where it names a path or loses nothing. */
let targets = (subcommand, arguments: array<string>): array<string> =>
  switch subcommand {
  | "restore" =>
    operands(arguments, ~valued=Array.concat(restoreValued, Jj_command.valued)) == []
      ? [flagValue(arguments, ["--to", "-t", "--into", "-c", "--changes-in"])->Option.getOr("@")]
      : []
  | _ =>
    switch operands(arguments, ~valued=Jj_command.valued) {
    | [] => ["@"]
    | revsets => revsets
    }
  }

/** Whether a revset holds a commit with changes, or why jj could not say. */
let holds = (place, revset): result<bool, string> => {
  let answer = Node.spawnSync(
    "jj",
    ["log", "--no-graph", "-r", `(${revset}) & ~empty()`, "-T", "change_id ++ \"\\n\""],
    {cwd: place, encoding: "utf8", maxBuffer: 268435456, timeout: 10000},
  )
  answer.status->Nullable.toOption == Some(0)
    ? Ok(answer.stdout->Nullable.getOr("")->String.trim != "")
    : Error(answer.stderr->Nullable.getOr("")->String.trim)
}

/** jj's stdout from `place`, or why it could not answer. */
let ask = (place, args): result<string, string> => {
  let answer = Node.spawnSync(
    "jj",
    args,
    {cwd: place, encoding: "utf8", maxBuffer: 268435456, timeout: 10000},
  )
  answer.status->Nullable.toOption == Some(0)
    ? Ok(answer.stdout->Nullable.getOr(""))
    : Error(answer.stderr->Nullable.getOr("")->String.trim)
}

/** A path as a quoted fileset that jj reads relative to where it runs. */
let quoted = path =>
  `cwd:"${path->String.replaceAll("\\", "\\\\")->String.replaceAll("\"", "\\\"")}"`

/** Whether every change in the commits of a revset is already in main, path by path. */
let landed = (place, revset): result<bool, string> =>
  switch ask(
    place,
    ["log", "--no-graph", "-r", `(${revset}) & ~empty()`, "-T", "commit_id ++ \"\\n\""],
  ) {
  | Error(why) => Error(why)
  | Ok(found) =>
    found
    ->String.split("\n")
    ->Array.map(String.trim)
    ->Array.filter(id => id != "")
    ->Array.reduce(Ok(true), (all, id) =>
      switch (all, ask(place, ["diff", "-r", id, "--name-only"])) {
      | (Ok(false), _) => Ok(false)
      | (Error(why), _) | (_, Error(why)) => Error(why)
      | (Ok(true), Ok(names)) =>
        let paths = names->String.split("\n")->Array.filter(line => line != "")
        paths == []
          ? Ok(true)
          : ask(
              place,
              ["diff", "--from", "main", "--to", id, "--name-only", ...paths->Array.map(quoted)],
            )
            // No main to compare with means nothing of it is on main.
            ->Result.mapOr(false, left => left->String.trim == "")
            ->Ok
      }
    )
  }

/** The exit status the harness reads, 2 refusing the command with the reason on stderr. */
let handle = (payload: Payload.t, ~holds=holds, ~landed=landed): int =>
  try {
    // Jj_command.running reads past a here-document body, text the shell never runs.
    let command = Payload.command(payload)
    let guarded = ["restore", "abandon"]
    if Jj_command.skipped(command)->Array.includes("restore") {
      0
    } else {
      let places = Jj_command.placed(command, ~cwd=Payload.cwd(payload), guarded)
      let calls =
        Jj_command.invocations(command)->Array.filter(((subcommand, _)) =>
          guarded->Array.includes(subcommand)
        )
      let refused = ref(None)
      calls->Array.forEachWithIndex(((subcommand, rest), index) =>
        places[index]->Option.forEach(place =>
          targets(subcommand, rest)->Array.forEach(
            revset =>
              if refused.contents == None {
                switch holds(place, revset) {
                | Ok(true) =>
                  switch subcommand == "abandon" ? landed(place, revset) : Ok(false) {
                  | Ok(true) => ()
                  | Ok(false) => refused := Some((subcommand, revset))
                  | Error(why) =>
                    Console.error(
                      `hooks/gates/lose.res could not compare ${revset} with main, so the command passes: ${why}`,
                    )
                  }
                | Ok(false) => ()
                | Error(why) =>
                  Console.error(
                    `hooks/gates/lose.res could not ask jj about ${revset}, so the command passes: ${why}`,
                  )
                }
              },
          )
        )
      )
      switch refused.contents {
      | None => 0
      | Some((subcommand, revset)) =>
        Console.error(
          `jj ${subcommand} refused by hooks/gates/lose.res: ${revset} holds changes that main does not have, and this would lose them.\n` ++
          `Name the paths to restore, or commit or snapshot the changes first. To lose them anyway, name the gate: \`SKIP=restore jj ${subcommand} ...\`.`,
        )
        2
      }
    }
  } catch {
  | _ => 0
  }
