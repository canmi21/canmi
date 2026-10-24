/**
 * Holds the shell commands of a subagent, called from its definition's PreToolUse hook, and
 * formats each file it writes, called from its PostToolUse hook.
 */
type role = Implementer | Refactorer | Reviewer

let roleOf = name =>
  switch name {
  | "implementer" => Some(Implementer)
  | "refactorer" => Some(Refactorer)
  | "reviewer" => Some(Reviewer)
  | _ => None
  }

let firstWord = (words: array<string>) => words->Array.find(word => !(word->String.startsWith("-")))

// The mise options that take a value, global and of run.
let miseValued = [
  "-C",
  "--cd",
  "-E",
  "--env",
  "-j",
  "--jobs",
  "-o",
  "--output",
  "-s",
  "--shell",
  "-t",
  "--tool",
  "--secrets",
  "--allow-env",
  "--allow-net",
  "--allow-read",
  "--allow-write",
  "--task-cache",
  "--timeout",
  "--affected-base",
  "--affected-head",
]

/** What a mise invocation was given, its operands past options, the flags and the -C directory. */
type given = {operands: array<string>, flags: array<string>, directory: option<string>}

let givenOf = (words: array<string>) => {
  let operands = []
  let flags = []
  let directory = ref(None)
  let at = ref(0)
  while at.contents < words->Array.length {
    let word = words->Array.getUnsafe(at.contents)
    if miseValued->Array.includes(word) {
      if word == "-C" || word == "--cd" {
        directory := words[at.contents + 1]
      }
      at := at.contents + 2
    } else {
      if word->String.startsWith("--cd=") {
        directory := Some(word->String.slice(~start="--cd="->String.length))
      } else if word->String.startsWith("-") {
        flags->Array.push(word)
      } else {
        operands->Array.push(word)
      }
      at := at.contents + 1
    }
  }
  {operands, flags, directory: directory.contents}
}

/** The task a mise invocation runs, named as `run` or as the shorthand does, scoped by -C. */
let taskOf = (given: given) => {
  let {operands, directory} = given
  let (task, after) = switch (operands[0], operands[1], operands[2]) {
  | (Some("run" | "r"), task, _) => (task, 2)
  | (Some("tasks"), Some("run"), task) => (task, 3)
  | (Some("tasks"), _, _) => (None, 0)
  | (task, _, _) => (task, 1)
  }
  task->Option.map(task => (
    task->String.includes(":") ? task : directory->Option.mapOr(task, dir => `${dir}:${task}`),
    operands->Array.slice(~start=after),
  ))
}

/** Every task a mise invocation runs, those after a `:::` judged as the first is. */
let tasksOf = (given: given) => {
  let groups = [[]]
  given.operands->Array.forEach(operand =>
    if operand == ":::" {
      groups->Array.push([])
    } else {
      groups->Array.getUnsafe(groups->Array.length - 1)->Array.push(operand)
    }
  )
  groups->Array.mapWithIndex((group, at) =>
    taskOf({...given, operands: at == 0 ? group : ["run", ...group]})
  )
}

/** What `mise exec` or `mise x` runs, a segment after `--` or a line given -c. */
type inner =
  | Segment(array<string>)
  | Line(string)
  | Bare

let execOf = (given: given, words: array<string>) =>
  switch given.operands[0] {
  | Some("exec" | "x") =>
    let dashes = words->Array.findIndex(word => word == "--")
    let command = words->Array.findIndex(word => word == "-c" || word == "--command")
    Some(
      switch (dashes, command, words[command + 1]) {
      | (-1, -1, _) | (-1, _, None) => Bare
      | (-1, _, Some(line)) => Line(line)
      | (at, _, _) => Segment(words->Array.slice(~start=at + 1))
      },
    )
  | _ => None
  }

/** The rule that holds a role's commands, named in each refusal. */
let ruleOf = role =>
  switch role {
  | Implementer => "implementer-commands"
  | Refactorer => "refactorer-commands"
  | Reviewer => "reviewer-commands"
  }

/** The nearest directory at or above `directory` whose mise.toml declares a check task. */
let rec checkHolder = directory => {
  let file = Node.join([directory, "mise.toml"])
  if Node.existsSync(file) && Node.readFileSync(file)->String.includes("[tasks.check]") {
    Some(directory)
  } else if Node.dirname(directory) == directory {
    None
  } else {
    checkHolder(Node.dirname(directory))
  }
}

/** Whether a check task named by `scope` from `cwd` is the workspace's own, the dispatcher. */
let workspaceCheck = (scope, ~cwd) =>
  switch scope {
  | Some(path) if path->String.startsWith("//") =>
    Node.resolve([Registry.root, path->String.slice(~start=2)]) == Registry.root
  | Some(path) => checkHolder(Node.resolve([cwd, path])) == Some(Registry.root)
  | None => checkHolder(Node.resolve([cwd])) == Some(Registry.root)
  }

/** Why a role is refused a mise task, check or verify bar one part, --pending, audit or deploy. */
let taskReason = (role, (task: string, rest: array<string>), ~flags, ~cwd) => {
  let colon = task->String.lastIndexOf(":")
  let name = colon < 0 ? task : task->String.slice(~start=colon + 1)
  let scope = colon < 0 ? None : Some(task->String.slice(~start=0, ~end=colon))
  let repo = scope->Option.map(path => path == "//" ? "" : Node.basename(path))
  let tasks = switch repo {
  | Some(repo) if Delegation.releasing->Array.some(((known, _)) => known == repo) =>
    Delegation.releasing->Array.filter(((known, _)) => known == repo)
  | _ => Delegation.releasing
  }
  // A part is one part of the workspace's own check, docs/agents/checking.md.
  let aPart =
    role == Implementer &&
    workspaceCheck(scope, ~cwd) &&
    rest[0] == Some("workspace") &&
    rest->Array.length == 2 &&
    !(flags->Array.includes("--all"))
  if name == "check" && flags->Array.includes("--pending") {
    Some(`--pending is the integrator's, ${ruleOf(role)} holds it`)
  } else if name == "check" && !aPart {
    Some(
      role == Implementer
        ? `mise run check is the integrator's, bar parts of the workspace's, ${ruleOf(
              role,
            )} holds it`
        : `mise run check is the integrator's, ${ruleOf(role)} holds it`,
    )
  } else if name == "verify" {
    Some(`mise run verify is a whole check, which is the integrator's, ${ruleOf(role)} holds it`)
  } else if name == "audit" {
    Some(`mise run audit is the integrator's, ${ruleOf(role)} holds it`)
  } else if tasks->Array.some(((_, found)) => found->Array.includes(name)) {
    Some(
      `the task ${name} deploys or releases, which is the integrator's, ${ruleOf(role)} holds it`,
    )
  } else {
    None
  }
}

/** The letters a short flag is written with, `-n` as `n`, the long flags left out. */
let letters = flags =>
  flags
  ->Array.filter(flag => !(flag->String.startsWith("--")))
  ->Array.map(flag => flag->String.slice(~start=1))

// The sed short flags that take a value, the rest of the cluster or the next word.
// The l flag takes none on the sed macOS ships, so it is left out.
let sedValued = ["e", "f"]

/** Where the bracket expression opening at `at` in `chars` ends, past its last `]`. */
let bracketEnd = (chars: array<string>, at) => {
  let length = chars->Array.length
  let char = index => chars[index]->Option.getOr("")
  let next = ref(at + 1)
  if char(next.contents) == "^" {
    next := next.contents + 1
  }
  if char(next.contents) == "]" {
    next := next.contents + 1
  }
  let found = ref(None)
  while found.contents == None && next.contents < length {
    let current = char(next.contents)
    if current == "[" && [":", ".", "="]->Array.includes(char(next.contents + 1)) {
      let close = char(next.contents + 1) ++ "]"
      let stop = ref(next.contents + 2)
      while stop.contents < length && char(stop.contents) ++ char(stop.contents + 1) != close {
        stop := stop.contents + 1
      }
      next := stop.contents + 2
    } else if current == "]" {
      found := Some(next.contents + 1)
    } else {
      next := next.contents + 1
    }
  }
  found.contents->Option.getOr(length)
}

/** Whether a sed script might write a file or run a program, read as sed reads it, refusing what it cannot read. */
let sedScriptWrites = (script: string) => {
  let chars = script->Node.codePoints
  let length = chars->Array.length
  let at = ref(0)
  let unsafe = ref(false)
  let char = index => chars[index]->Option.getOr("")
  let isDigit = text => text >= "0" && text <= "9" && text != ""
  let skipDigits = () =>
    while at.contents < length && isDigit(char(at.contents)) {
      at := at.contents + 1
    }
  let skipBlank = () =>
    while char(at.contents) == " " || char(at.contents) == "\t" {
      at := at.contents + 1
    }
  // Moves past one part ending at an unescaped `delimiter`, false where the part is left open.
  let delimited = (delimiter, ~brackets) => {
    let closed = ref(false)
    let going = ref(true)
    while going.contents && at.contents < length {
      let current = char(at.contents)
      if current == "\\" {
        at := at.contents + 2
      } else if current == delimiter {
        at := at.contents + 1
        closed := true
        going := false
      } else if brackets && current == "[" {
        at := bracketEnd(chars, at.contents)
      } else if current == "\n" {
        going := false
      } else {
        at := at.contents + 1
      }
    }
    closed.contents
  }
  let regex = delimiter => {
    if !delimited(delimiter, ~brackets=true) {
      unsafe := true
    }
    while char(at.contents) == "I" || char(at.contents) == "M" {
      at := at.contents + 1
    }
  }
  let address = () =>
    switch char(at.contents) {
    | digit if isDigit(digit) =>
      skipDigits()
      if char(at.contents) == "~" {
        at := at.contents + 1
        skipDigits()
      }
      true
    | "$" =>
      at := at.contents + 1
      true
    | "/" =>
      at := at.contents + 1
      regex("/")
      true
    | "\\" =>
      let delimiter = char(at.contents + 1)
      at := at.contents + 2
      if delimiter == "" || delimiter == "\n" || delimiter == "\\" {
        unsafe := true
      } else {
        regex(delimiter)
      }
      true
    | _ => false
    }
  // Moves to the first of `stops` or the end, a backslash escaping the character after it.
  let skipTo = stops =>
    while at.contents < length && !(stops->Array.includes(char(at.contents))) {
      at := at.contents + (char(at.contents) == "\\" ? 2 : 1)
    }
  let substituted = (~brackets) =>
    switch char(at.contents) {
    | "" | "\n" | "\\" => unsafe := true
    | delimiter =>
      at := at.contents + 1
      if !(delimited(delimiter, ~brackets) && delimited(delimiter, ~brackets=false)) {
        unsafe := true
      }
    }
  while !unsafe.contents && at.contents < length {
    let current = char(at.contents)
    if [" ", "\t", ";", "\n", "}"]->Array.includes(current) {
      at := at.contents + 1
    } else {
      if address() {
        skipBlank()
        if char(at.contents) == "," {
          at := at.contents + 1
          skipBlank()
          if char(at.contents) == "+" || char(at.contents) == "~" {
            at := at.contents + 1
            skipDigits()
          } else if !address() {
            unsafe := true
          }
        }
      }
      skipBlank()
      while char(at.contents) == "!" {
        at := at.contents + 1
        skipBlank()
      }
      let command = char(at.contents)
      at := at.contents + 1
      if unsafe.contents || Delegation.sedWriting->Array.includes(command) {
        unsafe := true
      } else {
        switch command {
        | "{"
        | "="
        | "d"
        | "D"
        | "g"
        | "G"
        | "h"
        | "H"
        | "n"
        | "N"
        | "p"
        | "P"
        | "x"
        | "z"
        | "F" => ()
        | "s" =>
          substituted(~brackets=true)
          let going = ref(true)
          while !unsafe.contents && going.contents && at.contents < length {
            let flag = char(at.contents)
            if [";", "\n", "}"]->Array.includes(flag) {
              going := false
            } else if Delegation.sedWriting->Array.includes(flag) {
              unsafe := true
            } else if (
              isDigit(flag) || ["g", "p", "i", "I", "m", "M", " ", "\t"]->Array.includes(flag)
            ) {
              at := at.contents + 1
            } else {
              unsafe := true
            }
          }
        | "y" => substituted(~brackets=false)
        | "a" | "i" | "c" | "r" | "R" | "#" => skipTo(["\n"])
        | "b" | "t" | "T" | ":" | "v" => skipTo([";", "\n", "}"])
        | "q" | "Q" | "l" | "L" =>
          skipBlank()
          skipDigits()
        | _ => unsafe := true
        }
      }
    }
  }
  unsafe.contents
}

/** Why sed is refused a reviewer, not quiet, in place, given a script file or a script that might write, or none. */
let sedReason = (words: array<string>) => {
  let quiet = ref(false)
  let inPlace = ref(false)
  let fromFile = ref(false)
  let scripts = []
  let operands = []
  let options = ref(true)
  let at = ref(0)
  let valueAfter = () => {
    let value = words[at.contents]
    at := at.contents + 1
    value
  }
  while at.contents < words->Array.length {
    let word = words->Array.getUnsafe(at.contents)
    at := at.contents + 1
    if !options.contents || word == "-" || !(word->String.startsWith("-")) {
      operands->Array.push(word)
    } else if word == "--" {
      options := false
    } else if word->String.startsWith("--") {
      let name = word->String.split("=")->Array.getUnsafe(0)
      let given = word->String.includes("=")
      // sed takes a long flag by any prefix of it, so any prefix of a flag counts.
      let prefixOf = flag => name->String.length >= 3 && flag->String.startsWith(name)
      quiet := quiet.contents || Delegation.sedQuiet->Array.includes(name)
      inPlace :=
        inPlace.contents ||
        Delegation.sedInPlace->Array.some(flag => flag->String.startsWith("--") && prefixOf(flag))
      if prefixOf("--expression") {
        let value = given ? Some(word->String.slice(~start=name->String.length + 1)) : valueAfter()
        value->Option.forEach(value => scripts->Array.push(value))
      } else if prefixOf("--file") {
        fromFile := true
      } else if prefixOf("--line-length") && !given {
        at := at.contents + 1
      }
    } else {
      let chars = word->String.slice(~start=1)->String.split("")
      let scanning = ref(true)
      chars->Array.forEachWithIndex((char, index) =>
        if scanning.contents {
          if sedValued->Array.includes(char) {
            scanning := false
            let rest = chars->Array.slice(~start=index + 1)->Array.join("")
            let value = rest == "" ? valueAfter() : Some(rest)
            if char == "f" {
              fromFile := true
            } else {
              value->Option.forEach(value => scripts->Array.push(value))
            }
          } else if letters(Delegation.sedQuiet)->Array.includes(char) {
            quiet := true
          } else if letters(Delegation.sedInPlace)->Array.includes(char) {
            inPlace := true
          }
        }
      )
    }
  }
  let script = scripts->Array.length > 0 ? Some(scripts->Array.join("\n")) : operands[0]
  if inPlace.contents {
    Some("sed is never run in place")
  } else if !quiet.contents {
    Some("sed is run only quiet, given -n")
  } else if fromFile.contents {
    Some("sed is never given a script file, which cannot be read here")
  } else if script->Option.mapOr(false, sedScriptWrites) {
    Some(
      `sed is never given a script that might hold ${Delegation.sedWriting->Array.join(
          ", ",
        )} or a command it cannot read`,
    )
  } else {
    None
  }
}

/** The first of `words` naming a flag in `flags`, alone or given its value after `=`. */
let flagged = (words: array<string>, flags) =>
  words->Array.find(word =>
    flags->Array.some(flag => word == flag || word->String.startsWith(`${flag}=`))
  )

/** A reviewer's command line with each `&` that runs a command in the background made a `;`, or why it is refused, an output redirection to a file or a process substitution. */
let backgrounded = (command: string): result<string, string> => {
  let chars = command->Node.codePoints
  let length = chars->Array.length
  let char = index => chars[index]->Option.getOr("")
  let out = []
  let quote = ref("")
  let refusal = ref(None)
  let at = ref(0)
  let keep = (~until) => {
    chars->Array.slice(~start=at.contents, ~end=until)->Array.forEach(kept => out->Array.push(kept))
    at := until
  }
  // The target word of a redirection from `start`, its quotes taken off, and where it ends.
  let target = start => {
    let stop = ref(start)
    while char(stop.contents) == " " || char(stop.contents) == "\t" {
      stop := stop.contents + 1
    }
    let word = ref("")
    let inner = ref("")
    let going = ref(true)
    while going.contents && stop.contents < length {
      let current = char(stop.contents)
      if inner.contents != "" {
        current == inner.contents ? inner := "" : word := word.contents ++ current
        stop := stop.contents + 1
      } else if current == "'" || current == "\"" {
        inner := current
        stop := stop.contents + 1
      } else if current == "\\" {
        word := word.contents ++ char(stop.contents + 1)
        stop := stop.contents + 2
      } else if [" ", "\t", "\n", ";", "|", "&", "<", ">", "(", ")"]->Array.includes(current) {
        going := false
      } else {
        word := word.contents ++ current
        stop := stop.contents + 1
      }
    }
    (word.contents, stop.contents)
  }
  while refusal.contents == None && at.contents < length {
    let current = char(at.contents)
    let next = char(at.contents + 1)
    if quote.contents == "'" {
      if current == "'" {
        quote := ""
      }
      keep(~until=at.contents + 1)
    } else if quote.contents != "" {
      // Inside double quotes and $'' a backslash escapes the next character.
      if current == "\\" {
        keep(~until=at.contents + 2)
      } else {
        if current == (quote.contents == "\"" ? "\"" : "'") {
          quote := ""
        }
        keep(~until=at.contents + 1)
      }
    } else if current == "\\" {
      keep(~until=at.contents + 2)
    } else if current == "$" && next == "'" {
      quote := "$'"
      keep(~until=at.contents + 2)
    } else if current == "'" || current == "\"" {
      quote := current
      keep(~until=at.contents + 1)
    } else if (current == "<" || current == ">") && next == "(" {
      refusal := Some("a process substitution is never run")
    } else if current == ">" || ((current == "&" || current == "<") && next == ">") {
      let arrow = current == ">" ? at.contents : at.contents + 1
      let after = char(arrow + 1) == ">" || char(arrow + 1) == "|" ? arrow + 2 : arrow + 1
      let duplicated = current == ">" && char(after) == "&"
      let (word, stop) = target(duplicated ? after + 1 : after)
      let digits =
        word != "" && word->String.split("")->Array.every(digit => digit >= "0" && digit <= "9")
      if (duplicated && (digits || word == "-")) || Delegation.redirectedTo->Array.includes(word) {
        keep(~until=stop)
      } else {
        refusal :=
          Some(
            `output is redirected only to ${Delegation.redirectedTo->Array.join(
                " or ",
              )}, never to ${word == "" ? "nothing" : word}`,
          )
      }
    } else if current == "<" && next == "&" {
      keep(~until=at.contents + 2)
    } else if current == "&" && next == "&" {
      keep(~until=at.contents + 2)
    } else if current == "&" {
      out->Array.push(";")
      at := at.contents + 1
    } else {
      keep(~until=at.contents + 1)
    }
  }
  switch refusal.contents {
  | Some(why) => Error(why)
  | None => Ok(out->Array.join(""))
  }
}

/** Why one segment is refused a reviewer, which runs jj's reading and `Delegation.inspecting`. */
let readerReason = (segment: array<string>) =>
  switch Jj_command.programOf(segment) {
  | None => None
  | Some("jj", words) =>
    let rule = ruleOf(Reviewer)
    // A prefix counts, so a spelling such as `--config-toml` is refused with the rest.
    let running =
      words->Array.find(word =>
        Delegation.jjRunning->Array.some(flag => word->String.startsWith(flag))
      )
    switch (running, Jj_command.invocationOf(segment)) {
    | (Some(found), _) => Some(`jj is never given ${found}, ${rule} holds it`)
    | (_, Some("file", rest))
      if rest
      ->firstWord
      ->Option.mapOr(false, word => Delegation.readingFile->Array.includes(word)) =>
      None
    | (_, Some(subcommand, _)) if Delegation.reading->Array.includes(subcommand) => None
    | (_, Some(subcommand, _)) =>
      Some(`jj ${subcommand} is not a reader's command, ${rule} holds it`)
    | (_, None) => Some(`a bare jj is not a reader's command, ${rule} holds it`)
    }
  | Some(program, words) if Delegation.inspecting->Array.includes(program) =>
    let why = switch program {
    | "sed" => sedReason(words)
    | "rg" =>
      words
      ->flagged(Delegation.rgRunning)
      ->Option.map(found => `rg is never given ${found}`)
    | "find" =>
      words
      ->Array.find(word => Delegation.findWriting->Array.includes(word))
      ->Option.map(found => `find is never given ${found}`)
    | _ => None
    }
    why->Option.map(why => `${why}, ${ruleOf(Reviewer)} holds it`)
  | Some(program, _) => Some(`${program} is not a reader's command, ${ruleOf(Reviewer)} holds it`)
  }

/** Why a reviewer's command line is refused, its redirections read first, then each segment and each substitution judged as a command of its own. */
let rec readerLine = command =>
  switch backgrounded(command) {
  | Error(why) => Some(`${why}, ${ruleOf(Reviewer)} holds it`)
  | Ok(_) if Jj_command.words(command)->Option.isNone =>
    Some(`a command whose quotes are left open is not read, ${ruleOf(Reviewer)} holds it`)
  | Ok(line) =>
    Jj_command.segments(line)
    ->Array.findMap(readerReason)
    ->Option.orElse(Jj_command.substitutions(line)->Array.findMap(readerLine))
  }

/** Why one segment is refused to a role, or none. */
let rec segmentReason = (~directory=?, ~cwd=Registry.root, role, segment: array<string>) =>
  switch (role, Jj_command.programOf(segment)) {
  | (_, None) => None
  | (Reviewer, _) => readerReason(segment)
  | (_, Some(program, _)) if Delegation.versioning->Array.includes(program) =>
    Some("git is not typed here")
  | (_, Some("mise", words)) if execOf(givenOf(words), words) != None =>
    switch execOf(givenOf(words), words) {
    | Some(Segment(inner)) =>
      segmentReason(
        ~directory=?givenOf(words).directory->Option.orElse(directory),
        ~cwd,
        role,
        inner,
      )
    | Some(Line(line)) => reason(~cwd, role, line)
    | _ => None
    }
  | (_, Some("mise", words)) =>
    let given = givenOf(words)
    let given = {...given, directory: given.directory->Option.orElse(directory)}
    tasksOf(given)->Array.findMap(found =>
      found->Option.flatMap(found => taskReason(role, found, ~flags=given.flags, ~cwd))
    )
  | (_, Some("jj", _)) => Some("jj is not typed here")
  | (_, Some(program, _)) if Delegation.remote->Array.includes(program) =>
    Some(`${program} is the integrator's`)
  | (_, Some(program, words)) if Delegation.launchers->Array.includes(program) =>
    words
    ->Array.find(word => Delegation.remote->Array.includes(Node.basename(word)))
    ->Option.map(found => `${Node.basename(found)} is the integrator's`)
  | _ => shellReason(~cwd, role, segment)
  }
// A shell given -c runs a command line of its own, which is judged as one.
and shellReason = (~cwd, role, segment) =>
  switch Jj_command.programOf(segment) {
  | Some(program, words) if Delegation.shells->Array.includes(program) =>
    switch words->Array.findIndex(word => word == "-c") {
    | -1 => None
    | at => words[at + 1]->Option.flatMap(line => reason(~cwd, role, line))
    }
  | _ => None
  }
and reason = (~cwd=Registry.root, role, command) =>
  role == Reviewer
    ? readerLine(command)
    : Jj_command.segments(command)->Array.findMap(segment => segmentReason(~cwd, role, segment))

/** The exit status the harness reads, 2 refusing the command with the reason on stderr. */
let handle = (role, payload: Payload.t): int =>
  switch reason(~cwd=Payload.cwd(payload), role, Payload.command(payload)) {
  | None => 0
  | Some(why) =>
    Console.error(`Command refused by hooks/agent_commands.res: ${why}.`)
    2
  }

/** The nearest node_modules/.bin above `directory` holding `tool`, or the bare name for PATH. */
let rec binary = (directory, tool) => {
  let local = Node.join([directory, "node_modules", ".bin", tool])
  if Node.existsSync(local) {
    local
  } else if Node.dirname(directory) == directory {
    tool
  } else {
    binary(Node.dirname(directory), tool)
  }
}

/** The nearest directory above `directory` holding a workspace.toml, the repository's root. */
let rec holder = directory =>
  if Node.existsSync(Node.join([directory, "workspace.toml"])) {
    Some(directory)
  } else if Node.dirname(directory) == directory {
    None
  } else {
    holder(Node.dirname(directory))
  }

let nix = "/nix/var/nix/profiles/default/bin"

/** Runs nixfmt on `file` from a copy of the root's flake files, nothing where it has no lock. */
let nixfmt = (root, file) => {
  let flake = Node.join([root, "flake.nix"])
  let lock = Node.join([root, "flake.lock"])
  if Node.existsSync(flake) && Node.existsSync(lock) {
    let copy = Node.mkdtempSync(Node.join([Node.tmpdir(), "nixfmt-"]))
    Node.writeFileSync(Node.join([copy, "flake.nix"]), Node.readFileSync(flake))
    Node.writeFileSync(Node.join([copy, "flake.lock"]), Node.readFileSync(lock))
    let env = Node.envCopy(Node.env)
    env->Dict.set("PATH", `${nix}:${Node.env->Dict.get("PATH")->Option.getOr("")}`)
    Node.spawnWithEnv(
      "nix",
      ["run", "--inputs-from", `path:${copy}`, "nixpkgs#nixfmt", "--", file],
      {cwd: root, env, stdio: "ignore"},
    )->ignore
    Node.rmSync(copy, {recursive: true, force: true})
  }
}

/** Formats the file an Edit or a Write left by its suffix in `Format.owners`, failing nothing. */
let format = (payload: Payload.t): int => {
  let file = payload->Payload.object("tool_input")->Option.flatMap(Payload.text(_, "file_path"))
  let owner =
    file->Option.flatMap(file =>
      Format.owners->Array.find(((suffix, _)) => suffix == Node.extname(file))
    )
  let root = file->Option.flatMap(file => holder(Node.dirname(file)))
  let declared = root->Option.mapOr(Project.noFormat, Project.formatAt)
  let passed = switch (file, root) {
  | (Some(file), Some(root)) =>
    declared.unformatted->Array.includes(Node.extname(file)) ||
      Project.inTestData(declared, Node.relative(root, file))
  | _ => false
  }
  switch (file, owner) {
  | (Some(file), Some(_, Formats(tool))) if Node.existsSync(file) && !passed =>
    let directory = Node.dirname(file)
    switch (tool, root) {
    | ("nixfmt", Some(root)) => nixfmt(root, file)
    | ("nixfmt", None) => ()
    | ("shfmt", _) =>
      // mise pins shfmt for the workspace alone, so a file elsewhere goes through the workspace.
      Node.spawnSync(
        "mise",
        ["exec", "-C", Registry.root, "--", "shfmt", "-w", file],
        {cwd: directory, stdio: "ignore", timeout: 30000},
      )->ignore
    | _ =>
      let words = tool->String.split(" ")
      Node.spawnSync(
        binary(directory, words[0]->Option.getOr(tool)),
        Array.concat(words->Array.slice(~start=1), [file]),
        {cwd: directory, stdio: "ignore", timeout: 30000},
      )->ignore
    }
  | _ => ()
  }
  0
}

if Node.isMain {
  let read = try Node.readStdin() catch {
  | _ => ""
  }
  let given = Node.args()[0]
  let payload = Payload.parse(read)
  switch (given, given->Option.flatMap(roleOf), payload) {
  | (Some("format"), _, payload) => Node.exit(payload->Option.mapOr(0, format))
  | (_, Some(role), Some(payload)) => Node.exit(handle(role, payload))
  | (_, Some(_), None) => Node.exit(0)
  | _ =>
    Console.error(
      "hooks/agent_commands.res: name the role, implementer, refactorer or reviewer, or format.",
    )
    Node.exit(2)
  }
}
