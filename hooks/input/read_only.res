// Judges a reviewer's command line, which runs jj's reading and `Delegation.inspecting` alone.

/** The rule that holds a reviewer's commands, named in each refusal. */
let rule = "reviewer-commands"

let firstWord = (words: array<string>) => words->Array.find(word => !(word->String.startsWith("-")))

/** The first of `words` naming a flag in `flags`, alone or given its value after `=`. */
let flagged = (words: array<string>, flags) =>
  words->Array.find(word =>
    flags->Array.some(flag => word == flag || word->String.startsWith(`${flag}=`))
  )

/**
 * A reviewer's command line with each `&` that runs a command in the background made a `;`, or
 * why it is refused, an output redirection to a file or a process substitution.
 */
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

/** Why a program is refused a reviewer, which runs jj's reading and `Delegation.inspecting`. */
let programReason = (segment: array<string>) =>
  switch Jj_command.programOf(segment) {
  | None => None
  | Some("jj", words) =>
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
    | "sed" => Sed_script.reason(words)
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
    why->Option.map(why => `${why}, ${rule} holds it`)
  | Some(program, _) => Some(`${program} is not a reader's command, ${rule} holds it`)
  }

/** Why one segment is refused a reviewer, a wrapper or an assignment before it, or its program. */
let segmentReason = (segment: array<string>) => {
  let before =
    segment->Array.slice(
      ~start=0,
      ~end=Jj_command.commandAt(segment)->Option.getOr(segment->Array.length),
    )
  let wrapped =
    before->Array.find(word =>
      Delegation.wrapping->Array.includes(Node.basename(word)) ||
        (word->String.includes("=") && !(word->String.startsWith("=")))
    )
  switch wrapped {
  | Some(found) => Some(`${found} never stands before a reviewer's command, ${rule} holds it`)
  | None => programReason(segment)
  }
}

/**
 * Why a reviewer's command line is refused, its redirections read first, then each segment and
 * each substitution judged as a command of its own.
 */
let rec reason = command =>
  switch backgrounded(command) {
  | Error(why) => Some(`${why}, ${rule} holds it`)
  | Ok(_) if Jj_command.words(command)->Option.isNone =>
    Some(`a command whose quotes are left open is not read, ${rule} holds it`)
  | Ok(line) =>
    Jj_command.segments(line)
    ->Array.findMap(segmentReason)
    ->Option.orElse(Jj_command.substitutions(line)->Array.findMap(reason))
  }
