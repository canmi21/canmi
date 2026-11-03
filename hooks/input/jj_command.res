/** Every jj invocation inside the shell command a hook receives. */
let separators = ["&&", ";", "||", "|"]
let valued = ["-R", "--repository", "--at-operation", "--color", "--config", "--config-file"]

/** The position after a balanced command substitution, with its own quotes and nested spans. */
let rec substitutionEnd = (chars: array<string>, start): option<int> => {
  let backtick = chars[start] == Some("`")
  let at = ref(start + (backtick ? 1 : 2))
  let depth = ref(1)
  let quote = ref("")
  let balanced = ref(true)
  while at.contents < chars->Array.length && depth.contents > 0 && balanced.contents {
    let char = chars->Array.getUnsafe(at.contents)
    if char == "\\" && quote.contents != "'" {
      at := at.contents + 2
    } else if backtick {
      if char == "`" {
        depth := 0
      }
      at := at.contents + 1
    } else if quote.contents == "'" {
      if char == "'" {
        quote := ""
      }
      at := at.contents + 1
    } else if char == "`" || (char == "$" && chars[at.contents + 1] == Some("(")) {
      switch substitutionEnd(chars, at.contents) {
      | Some(stop) => at := stop
      | None => balanced := false
      }
    } else if quote.contents == "\"" {
      if char == "\"" {
        quote := ""
      }
      at := at.contents + 1
    } else {
      if char == "'" || char == "\"" {
        quote := char
      } else if char == "(" {
        depth := depth.contents + 1
      } else if char == ")" {
        depth := depth.contents - 1
      }
      at := at.contents + 1
    }
  }
  balanced.contents && depth.contents == 0 ? Some(at.contents) : None
}

/** Heredoc bodies stay data even when their delimiter permits expansion. */
let withoutHeredocBodies = command => {
  let chars = command->Node.codePoints
  let length = chars->Array.length
  let kept = []
  let pending = []
  let at = ref(0)
  let quote = ref("")
  while at.contents < length {
    let start = at.contents
    let char = chars->Array.getUnsafe(start)
    if char == "\\" && quote.contents != "'" {
      at := min(start + 2, length)
    } else if quote.contents != "" {
      if char == quote.contents {
        quote := ""
      }
      at := start + 1
    } else if char == "'" || char == "\"" {
      quote := char
      at := start + 1
    } else if char == "`" || (char == "$" && chars[start + 1] == Some("(")) {
      at := substitutionEnd(chars, start)->Option.getOr(length)
    } else if (
      char == "#" &&
        (start == 0 ||
          [Some(" "), Some("\t"), Some("\n"), Some(";"), Some("|")]->Array.includes(
            chars[start - 1],
          ))
    ) {
      while at.contents < length && chars[at.contents] != Some("\n") {
        at := at.contents + 1
      }
    } else if char == "<" && chars[start + 1] == Some("<") {
      if chars[start + 2] == Some("<") {
        at := start + 3
      } else {
        let tabs = chars[start + 2] == Some("-")
        at := start + (tabs ? 3 : 2)
        while [Some(" "), Some("\t")]->Array.includes(chars[at.contents]) {
          at := at.contents + 1
        }
        let delimiter = ref("")
        let quoted = ref("")
        let reading = ref(true)
        while at.contents < length && reading.contents {
          let current = chars->Array.getUnsafe(at.contents)
          if current == "\\" && quoted.contents != "'" {
            delimiter := delimiter.contents ++ chars[at.contents + 1]->Option.getOr("")
            at := min(at.contents + 2, length)
          } else if quoted.contents != "" {
            current == quoted.contents ? quoted := "" : delimiter := delimiter.contents ++ current
            at := at.contents + 1
          } else if current == "'" || current == "\"" {
            quoted := current
            at := at.contents + 1
          } else if (
            [" ", "\t", "\r", "\n", ";", "|", "&", "<", ">", "(", ")"]->Array.includes(current)
          ) {
            reading := false
          } else {
            delimiter := delimiter.contents ++ current
            at := at.contents + 1
          }
        }
        pending->Array.push((delimiter.contents, tabs))
      }
    } else {
      at := start + 1
    }
    kept->Array.push(chars->Array.slice(~start, ~end=at.contents)->Array.join(""))
    if char == "\n" && quote.contents == "" {
      pending->Array.forEach(((delimiter, tabs)) => {
        let ended = ref(false)
        while at.contents < length && !ended.contents {
          let lineStart = at.contents
          while at.contents < length && chars[at.contents] != Some("\n") {
            at := at.contents + 1
          }
          let line = chars->Array.slice(~start=lineStart, ~end=at.contents)->Array.join("")
          ended := (tabs ? line->String.replaceRegExp(/^\t+/, "") : line) == delimiter
          at := min(at.contents + 1, length)
        }
      })
      pending->Array.splice(~start=0, ~remove=pending->Array.length, ~insert=[])
    }
  }
  kept->Array.join("")
}

/** The words of a command line, or none where a quote or substitution is left open. */
let words = (~keepQuotes=false, command: string): option<array<string>> => {
  let found = []
  let word = ref("")
  let open_ = ref(false)
  let quote = ref("")
  let escaped = ref(false)
  let balanced = ref(true)
  let close = () =>
    if open_.contents {
      found->Array.push(word.contents)
      word := ""
      open_ := false
    }
  let chars = command->Node.codePoints
  let skip = ref(0)
  let operator = (text, ~pair) => {
    close()
    found->Array.push(text)
    skip := (pair ? 1 : 0)
  }
  chars->Array.forEachWithIndex((char, at) => {
    let next = chars[at + 1]
    if skip.contents > 0 {
      skip := skip.contents - 1
    } else if escaped.contents {
      // Inside double quotes a backslash escapes only a quote or itself, as shlex has it.
      word :=
        word.contents ++
        (keepQuotes || (quote.contents == "\"" && char != "\"" && char != "\\") ? "\\" : "") ++
        char
      escaped := false
    } else if quote.contents == "'" {
      if keepQuotes && char == "'" {
        word := word.contents ++ char
      }
      char == "'" ? quote := "" : word := word.contents ++ char
    } else if char == "`" || (char == "$" && next == Some("(")) {
      switch substitutionEnd(chars, at) {
      | Some(stop) =>
        word := word.contents ++ chars->Array.slice(~start=at, ~end=stop)->Array.join("")
        open_ := true
        skip := stop - at - 1
      | None => balanced := false
      }
    } else if quote.contents == "\"" {
      if char == "\"" {
        if keepQuotes {
          word := word.contents ++ char
        }
        quote := ""
      } else if char == "\\" {
        escaped := true
      } else {
        word := word.contents ++ char
      }
    } else if char == " " || char == "\t" || char == "\r" {
      close()
    } else if char == ";" || char == "\n" {
      operator(";", ~pair=false)
    } else if char == "|" {
      next == Some("|") ? operator("||", ~pair=true) : operator("|", ~pair=false)
    } else if char == "&" && next == Some("&") {
      operator("&&", ~pair=true)
    } else {
      open_ := true
      if char == "'" || char == "\"" {
        if keepQuotes {
          word := word.contents ++ char
        }
        quote := char
      } else if char == "\\" {
        escaped := true
      } else {
        word := word.contents ++ char
      }
    }
  })
  if quote.contents != "" || escaped.contents || !balanced.contents {
    None
  } else {
    close()
    Some(found)
  }
}

/** The text inside each outermost `$(...)` or backtick span, past single quotes. */
let substitutions = (command: string): array<string> => {
  let chars = command->Node.codePoints
  let length = chars->Array.length
  let found = []
  let single = ref(false)
  let double = ref(false)
  let at = ref(0)
  while at.contents < length {
    let char = chars->Array.getUnsafe(at.contents)
    if single.contents {
      single := char != "'"
      at := at.contents + 1
    } else if char == "'" && !double.contents {
      single := true
      at := at.contents + 1
    } else if char == "\"" {
      double := !double.contents
      at := at.contents + 1
    } else if char == "\\" {
      at := at.contents + 2
    } else if char == "`" || (char == "$" && chars[at.contents + 1] == Some("(")) {
      switch substitutionEnd(chars, at.contents) {
      | Some(stop) =>
        let start = at.contents + (char == "`" ? 1 : 2)
        found->Array.push(chars->Array.slice(~start, ~end=stop - 1)->Array.join(""))
        at := stop
      | None => at := length
      }
    } else {
      at := at.contents + 1
    }
  }
  found
}

/** The command line cut at each separator, then each command substitution's own segments. */
let rec segments = (~keepQuotes=false, command) =>
  switch words(~keepQuotes, command) {
  | None => []
  | Some(all) =>
    let cut = [[]]
    all->Array.forEach(word =>
      separators->Array.includes(word)
        ? cut->Array.push([])
        : cut[cut->Array.length - 1]->Option.forEach(last => last->Array.push(word))
    )
    cut
    ->Array.filter(segment => segment != [])
    ->Array.concat(substitutions(command)->Array.flatMap(inner => segments(~keepQuotes, inner)))
  }

/** Where the program of a segment sits, past assignments and the wrappers that run what follows. */
let commandAt = (segment: array<string>): option<int> => {
  let length = segment->Array.length
  let at = ref(0)
  let skipping = ref(true)
  let word = index => segment->Array.getUnsafe(index)
  // Dash words, and the word after each one that takes a value.
  let options = (~valued) =>
    while at.contents < length && word(at.contents)->String.startsWith("-") {
      at := at.contents + (valued->Array.includes(word(at.contents)) ? 2 : 1)
    }
  while skipping.contents && at.contents < length {
    let current = word(at.contents)
    if current->String.includes("=") && !(current->String.startsWith("=")) {
      at := at.contents + 1
    } else {
      switch Node.basename(current) {
      | "command" | "env" | "exec" | "nohup" | "time" | "setsid" =>
        at := at.contents + 1
        options(~valued=[])
      | "nice" =>
        at := at.contents + 1
        options(~valued=["-n", "--adjustment"])
      | "timeout" =>
        at := at.contents + 1
        options(~valued=["-s", "--signal", "-k", "--kill-after"])
        at := at.contents + 1
      | "xargs" =>
        at := at.contents + 1
        options(
          ~valued=["-I", "-n", "-P", "-L", "-E", "-d", "-s", "-a", "-J", "-R", "-S", "--max-args"],
        )
      | "npx" | "bunx" | "pnpx" =>
        at := at.contents + 1
        options(~valued=["-p", "--package"])
      | "pnpm" | "yarn" | "npm"
        if ["exec", "dlx"]->Array.includes(segment[at.contents + 1]->Option.getOr("")) =>
        at := at.contents + 2
        options(~valued=["-p", "--package"])
      | _ => skipping := false
      }
    }
  }
  at.contents < length ? Some(at.contents) : None
}

/** The line a shell given -c runs, which is a command like any typed. */
let shellLine = (segment: array<string>): option<string> =>
  commandAt(segment)->Option.flatMap(at => {
    let rest = segment->Array.slice(~start=at + 1)
    let flag = rest->Array.findIndex(word => /^-[A-Za-z]*c[A-Za-z]*$/->RegExp.test(word))
    let shell = Delegation.shells->Array.includes(Node.basename(segment->Array.getUnsafe(at)))
    shell && flag >= 0 ? rest[flag + 1] : None
  })

/** Each segment run in order, with a shell's line past here-documents and its assignments. */
let rec running = (command): array<array<string>> =>
  segments(withoutHeredocBodies(command))->Array.flatMap(segment =>
    switch (shellLine(segment), commandAt(segment)) {
    | (Some(line), Some(at)) =>
      let assigned =
        segment->Array.slice(~start=0, ~end=at)->Array.filter(word => word->String.includes("="))
      [segment, ...running(line)->Array.map(inner => assigned->Array.concat(inner))]
    | _ => [segment]
    }
  )

/** Whether the word at `at` is the command its segment runs, past assignments and wrappers. */
let isCommand = (segment: array<string>, at) =>
  at == 0 ||
  commandAt(segment) == Some(at) || {
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
  running(command)->Array.filterMap(invocationOf)

/** The gates a jj invocation's own assignments skip, `SKIP=verify jj commit`, comma-separated. */
let skipped = (command): array<string> =>
  running(command)->Array.flatMap(segment => {
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
let repository = (command): option<string> => running(command)->Array.findMap(repositoryOf)

/** Where each invocation of `subcommands` runs, `cwd` moved by each `cd` before it, then -R. */
let placed = (command, ~cwd, subcommands): array<string> => {
  let at = ref(cwd)
  let found = []
  running(command)->Array.forEach(segment =>
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

/** The program one segment runs and the words after it, past assignments and wrappers. */
let programOf = (segment: array<string>): option<(string, array<string>)> =>
  commandAt(segment)->Option.map(at => (
    Node.basename(segment->Array.getUnsafe(at)),
    segment->Array.slice(~start=at + 1),
  ))
