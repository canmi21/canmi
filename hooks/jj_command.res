/** Every jj invocation inside the shell command a hook receives, split as POSIX shlex splits. */
let separators = ["&&", ";", "||", "|"]
let valued = ["-R", "--repository", "--at-operation", "--color", "--config", "--config-file"]

/** The words of a command line, or none where a quote is left open. */
let words = (command: string): option<array<string>> => {
  let found = []
  let word = ref("")
  let open_ = ref(false)
  let quote = ref("")
  let escaped = ref(false)
  let close = () =>
    if open_.contents {
      found->Array.push(word.contents)
      word := ""
      open_ := false
    }
  command
  ->Node.codePoints
  ->Array.forEach(char => {
    if escaped.contents {
      // Inside double quotes a backslash escapes only a quote or itself, as shlex has it.
      word :=
        word.contents ++
        (quote.contents == "\"" && char != "\"" && char != "\\" ? "\\" : "") ++
        char
      escaped := false
    } else if quote.contents == "'" {
      char == "'" ? quote := "" : word := word.contents ++ char
    } else if quote.contents == "\"" {
      if char == "\"" {
        quote := ""
      } else if char == "\\" {
        escaped := true
      } else {
        word := word.contents ++ char
      }
    } else if char == " " || char == "\t" || char == "\n" || char == "\r" {
      close()
    } else {
      open_ := true
      if char == "'" || char == "\"" {
        quote := char
      } else if char == "\\" {
        escaped := true
      } else {
        word := word.contents ++ char
      }
    }
  })
  if quote.contents != "" || escaped.contents {
    None
  } else {
    close()
    Some(found)
  }
}

/** The command line cut at each separator that stands as a word of its own. */
let segments = command =>
  switch words(command) {
  | None => []
  | Some(all) =>
    let cut = [[]]
    all->Array.forEach(word =>
      separators->Array.includes(word)
        ? cut->Array.push([])
        : cut[cut->Array.length - 1]->Option.forEach(last => last->Array.push(word))
    )
    cut->Array.filter(segment => segment != [])
  }

/** Whether the word at `at` is the command its segment runs, past assignments, env or command. */
let isCommand = (segment: array<string>, at) =>
  at == 0 || {
      let prefix = segment->Array.slice(~start=0, ~end=at)
      prefix[at - 1] == Some("--") ||
      prefix->Array.every(word => word->String.includes("=") && !(word->String.startsWith("="))) ||
      prefix[0]->Option.mapOr(false, first =>
        ["command", "env"]->Array.includes(Node.basename(first))
      )
    }

/** The jj subcommand one segment runs and the arguments after it, if it runs jj. */
let invocationOf = (segment: array<string>): option<(string, array<string>)> => {
  let at =
    segment->Array.findIndexWithIndex((word, index) =>
      Node.basename(word) == "jj" && isCommand(segment, index)
    )
  if at < 0 {
    None
  } else {
    let next = ref(at + 1)
    let found = ref(None)
    while found.contents == None && next.contents < segment->Array.length {
      let candidate = segment->Array.getUnsafe(next.contents)
      if valued->Array.includes(candidate) {
        next := next.contents + 2
      } else if candidate->String.startsWith("-") {
        next := next.contents + 1
      } else {
        found := Some((candidate, segment->Array.slice(~start=next.contents + 1)))
      }
    }
    found.contents
  }
}

/** Each jj subcommand and the arguments after it. */
let invocations = (command): array<(string, array<string>)> =>
  segments(command)->Array.filterMap(invocationOf)

/** The gates a jj invocation's own assignments skip, `SKIP=verify jj commit`, comma-separated. */
let skipped = (command): array<string> =>
  segments(command)->Array.flatMap(segment => {
    let at =
      segment->Array.findIndexWithIndex((word, index) =>
        Node.basename(word) == "jj" && isCommand(segment, index)
      )
    let prefix = `${Commits.skip}=`
    at < 0
      ? []
      : segment
        ->Array.slice(~start=0, ~end=at)
        ->Array.filter(word => word->String.startsWith(prefix))
        ->Array.flatMap(word =>
          word
          ->String.slice(~start=prefix->String.length)
          ->String.split(",")
          ->Array.map(String.trim)
        )
  })

/** The repository one segment's jj names with -R or --repository, if it names one. */
let repositoryOf = (segment: array<string>): option<string> => {
  let at =
    segment->Array.findIndexWithIndex((word, index) =>
      Node.basename(word) == "jj" && isCommand(segment, index)
    )
  let named = ref(None)
  if at >= 0 {
    segment
    ->Array.slice(~start=at + 1)
    ->Array.forEachWithIndex((word, index) =>
      if named.contents == None {
        if word == "-R" || word == "--repository" {
          named := segment[at + 2 + index]
        } else if word->String.startsWith("--repository=") {
          named := Some(word->String.slice(~start="--repository="->String.length))
        }
      }
    )
  }
  named.contents
}

/** The repository a jj invocation names with -R or --repository before its subcommand, if any. */
let repository = (command): option<string> => segments(command)->Array.findMap(repositoryOf)

/** Where each invocation of `subcommands` runs: `cwd`, moved by each `cd` before it, then by -R. */
let placed = (command, ~cwd, subcommands): array<string> => {
  let at = ref(cwd)
  let found = []
  segments(command)->Array.forEach(segment =>
    switch segment {
    | ["cd"] => at := Node.env->Dict.get("HOME")->Option.getOr(at.contents)
    | ["cd", target] => at := Node.resolve([at.contents, target])
    | _ =>
      switch invocationOf(segment) {
      | Some((subcommand, _)) if subcommands->Array.includes(subcommand) =>
        found->Array.push(
          repositoryOf(segment)->Option.mapOr(at.contents, named =>
            Node.resolve([at.contents, named])
          ),
        )
      | _ => ()
      }
    }
  )
  found
}
