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

/** Each jj subcommand and the arguments after it. */
let invocations = (command): array<(string, array<string>)> =>
  segments(command)->Array.filterMap(segment => {
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
  })
