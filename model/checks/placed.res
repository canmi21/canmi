/**
 * Each D1 database and R2 bucket a repository's scripts and tasks make, against
 * `cloudflare-placed`. A make by REST, a jurisdiction, a Durable Object's hint and a Worker's
 * placement go unread, the rule `cloudflare-placed-rest` waiting for them. A regex literal
 * holding the opening of a block comment still starts one where it stands.
 */
/** What a create is told to name. */
let told =
  Toolchain.places->Array.join(" or ")

/** Whether `value` is a place a create may name. */
let passes = value => Toolchain.places->Array.includes(value)

/** A create in a shell line, its words apart by space, or quoted apart as an argv is. */
let creating = /\b(d1[\s\x22\x27,]+create|r2[\s\x22\x27,]+bucket[\s\x22\x27,]+create)\b/

/** A create in a source, its consecutive strings in an array or a list. */
let created = /([\x22\x27\x60])(?:d1\1\s*,\s*\1create|r2\1\s*,\s*\1bucket\1\s*,\s*\1create)\1/g

/** The endings of a test file, each read as a `tests/` directory is not. */
let tested = ["_test.res", ".test.ts", ".spec.ts", ".test.js", ".spec.js", ".test.mjs", ".spec.mjs"]

/** Whether a tracked `path` is read, in no package's own, build's or tests' directory, no test. */
let read = path =>
  !(
    path
    ->Node.dirname
    ->String.split("/")
    ->Array.some(part => part == "node_modules" || part == "tests")
  ) &&
  !(/(?:^|\/)lib\/(?:bs|ocaml)\//->RegExp.test(path)) &&
  !(tested->Array.some(suffix => path->String.endsWith(suffix)))

/** Whether `path` is a source the array scan reads, compiled output never. */
let coded = path =>
  [".res", ".mjs", ".js", ".ts"]->Array.some(suffix => path->String.endsWith(suffix)) &&
    !(path->String.endsWith(".res.mjs"))

/** Whether `path` lies under `.mise/tasks/`, where an executable file is a task. */
let tasked = path => /(?:^|\/)\.mise\/tasks\//->RegExp.test(path)

/** The quotes a source's strings open with, ReScript's own lacking the single one. */
let quotesOf = file => file->String.endsWith(".res") ? "\"`" : "\"'`"

/** A name bound by `let` or `const`, its value where a string literal alone gives it. */
type binding = {file: string, name: string, value: option<string>}

/** Where a create is placed, by a literal, by a name bound to one, or by what a run decides. */
type place = Literal(string) | Bound(string, binding) | Open

/** The finding on a create, by the place it names, or that it names none. */
let named = (~value=?, ~bound=?, what) =>
  switch (value, bound) {
  | (None, _) => `${what} names no --location; add --location ${told}`
  | (Some(value), None) => `${what} names --location ${value}; ${told} alone`
  | (Some(value), Some((name, file))) =>
    `${what} names --location ${name}, bound to ${value} in ${file}; ${told} alone`
  }

/** The finding on a create placed at `place`, none where it may be. */
let judged = (place, ~what) =>
  switch place {
  | Literal(value) => passes(value) ? None : Some(named(what, ~value))
  | Bound(name, {file, value: Some(value)}) =>
    passes(value) ? None : Some(named(what, ~value, ~bound=(name, file)))
  | Bound(_, _) | Open => None
  }

/** Each match of a global `pattern` in `text`. */
let all = (pattern, text): array<RegExp.Result.t> => {
  let rec next = found =>
    switch pattern->RegExp.exec(text) {
    | Some(result) => next([...found, result])
    | None => found
    }
  next([])
}

/** The line `at` lies on, counted from one. */
let lineOf = (text, at) => text->String.slice(~start=0, ~end=at)->String.split("\n")->Array.length

/** `text` with each comment turned to spaces, its strings and its lines kept where they were. */
let blanked = (text, ~quotes) => {
  let length = text->String.length
  let rec walk = (at, ~quote, ~out) =>
    if at >= length {
      out
    } else {
      let char = text->String.charAt(at)
      let next = text->String.charAt(at + 1)
      switch quote {
      | Some(_) if char == "\\" => walk(at + 2, ~quote, ~out=`${out}${char}${next}`)
      | Some(mark) =>
        let shut = char == mark || (char == "\n" && mark != "`")
        walk(at + 1, ~quote=shut ? None : quote, ~out=`${out}${char}`)
      | None if char == "/" && (next == "/" || next == "*") =>
        let found =
          next == "/" ? text->String.indexOfFrom("\n", at) : text->String.indexOfFrom("*/", at + 2)
        let stop = found < 0 ? length : next == "/" ? found : found + 2
        let spaces = text->String.slice(~start=at, ~end=stop)->String.replaceRegExp(/[^\n]/g, " ")
        walk(stop, ~quote, ~out=`${out}${spaces}`)
      | None =>
        let quote = quotes->String.includes(char) ? Some(char) : None
        walk(at + 1, ~quote, ~out=`${out}${char}`)
      }
    }
  walk(0, ~quote=None, ~out="")
}

/** Where the quote closing at `at` opened, read backward. */
let rec quoteStart = (text, at, ~mark) =>
  if at < 0 {
    -1
  } else if text->String.charAt(at) == mark && text->String.charAt(at - 1) != "\\" {
    at
  } else {
    quoteStart(text, at - 1, ~mark)
  }

/** Where the array or list holding `at` opens, if one and not a call or a block holds it. */
let rec opening = (text, at, ~quotes, ~depth=0) =>
  if at < 0 {
    None
  } else {
    let char = text->String.charAt(at)
    if quotes->String.includes(char) {
      opening(text, quoteStart(text, at - 1, ~mark=char) - 1, ~quotes, ~depth)
    } else if "])}"->String.includes(char) {
      opening(text, at - 1, ~quotes, ~depth=depth + 1)
    } else if "[({"->String.includes(char) {
      switch depth {
      | 0 =>
        let listed = char == "{" && at >= 4 && text->String.slice(~start=at - 4, ~end=at) == "list"
        char == "[" || listed ? Some(at) : None
      | _ => opening(text, at - 1, ~quotes, ~depth=depth - 1)
      }
    } else {
      opening(text, at - 1, ~quotes, ~depth)
    }
  }

/** Where the quote opening before `at` closes, read forward. */
let rec quoteEnd = (text, at, ~mark) =>
  if at >= text->String.length {
    at
  } else if text->String.charAt(at) == "\\" {
    quoteEnd(text, at + 2, ~mark)
  } else if text->String.charAt(at) == mark {
    at
  } else {
    quoteEnd(text, at + 1, ~mark)
  }

/** Where the array or list holding `at` closes, at its last bracket. */
let rec closing = (text, at, ~quotes, ~depth=0) =>
  if at >= text->String.length {
    at
  } else {
    let char = text->String.charAt(at)
    if quotes->String.includes(char) {
      closing(text, quoteEnd(text, at + 1, ~mark=char) + 1, ~quotes, ~depth)
    } else if "[({"->String.includes(char) {
      closing(text, at + 1, ~quotes, ~depth=depth + 1)
    } else if "])}"->String.includes(char) {
      depth == 0 ? at : closing(text, at + 1, ~quotes, ~depth=depth - 1)
    } else {
      closing(text, at + 1, ~quotes, ~depth)
    }
  }

/** The elements between `start` and `stop`, split at their own commas, each trimmed. */
let elements = (text, ~start, ~stop, ~quotes): array<string> => {
  let rec walk = (at, ~depth, ~from, ~found) =>
    if at >= stop {
      [...found, text->String.slice(~start=from, ~end=stop)]
    } else {
      let char = text->String.charAt(at)
      if quotes->String.includes(char) {
        walk(quoteEnd(text, at + 1, ~mark=char) + 1, ~depth, ~from, ~found)
      } else if "[({"->String.includes(char) {
        walk(at + 1, ~depth=depth + 1, ~from, ~found)
      } else if "])}"->String.includes(char) {
        walk(at + 1, ~depth=depth - 1, ~from, ~found)
      } else if char == "," && depth == 0 {
        walk(
          at + 1,
          ~depth,
          ~from=at + 1,
          ~found=[...found, text->String.slice(~start=from, ~end=at)],
        )
      } else {
        walk(at + 1, ~depth, ~from, ~found)
      }
    }
  walk(start, ~depth=0, ~from=start, ~found=[])
  ->Array.map(String.trim)
  ->Array.filter(element => element != "")
}

/** The elements of the array or list holding `at` in a blanked source. */
let containerAt = (text, at, ~quotes) =>
  opening(text, at - 1, ~quotes)->Option.map(start =>
    elements(text, ~start=start + 1, ~stop=closing(text, at, ~quotes), ~quotes)
  )

/** Each string literal of a blanked source, by where it opens and what it holds. */
let literals = (text, ~quotes): array<(int, string)> => {
  let rec walk = (at, ~found) =>
    if at >= text->String.length {
      found
    } else {
      let char = text->String.charAt(at)
      if quotes->String.includes(char) {
        let stop = quoteEnd(text, at + 1, ~mark=char)
        walk(stop + 1, ~found=[...found, (at, text->String.slice(~start=at + 1, ~end=stop))])
      } else {
        walk(at + 1, ~found)
      }
    }
  walk(0, ~found=[])
}

/** The quote and the text of an element that is one string literal and nothing more. */
let quoted = element =>
  switch /^([\x22\x27\x60])((?:\\.|(?!\1)[^\\])*)\1$/s->RegExp.exec(element) {
  | Some(result) =>
    switch result->RegExp.Result.matches {
    | [Some(mark), Some(inner)] => Some((mark, inner))
    | _ => None
    }
  | None => None
  }

/** What a literal says, a backtick's with an interpolation saying nothing fixed. */
let fixed = ((mark, inner)) => mark == "`" && inner->String.includes("${") ? None : Some(inner)

/** A `let`, `const` or `var`, its name and what it binds. */
let binds = /^\s*(?:export\s+)?(?:let|const|var)\s+([\w$][\w$']*)\s*(?::[^=\n]*)?=(.*)$/gm

/** Each `let`, `const` or `var` a blanked source holds, by its name and any literal it binds. */
let bindings = (text, ~file): array<binding> =>
  all(binds, text)->Array.filterMap(result =>
    switch result->RegExp.Result.matches {
    | [Some(name), Some(bound)] =>
      let bound = bound->String.trim->String.replaceRegExp(/;$/, "")->String.trim
      Some({file, name, value: quoted(bound)->Option.flatMap(fixed)})
    | _ => None
    }
  )

/** The module a source `file` is, as another names it. */
let moduleOf = file => {
  let base = Node.basename(file)->String.replaceRegExp(/\.(?:res|mjs|js|ts)$/, "")
  `${base->String.charAt(0)->String.toUpperCase}${base->String.slice(~start=1)}`
}

/** The modules a blanked source opens, each by its last name. */
let opens = text =>
  all(/^[ \t]*open!?\s+([A-Z][\w.]*)/gm, text)->Array.filterMap(result =>
    switch result->RegExp.Result.matches {
    | [Some(path)] => path->String.split(".")->Array.at(-1)
    | _ => None
    }
  )

/** What `id` is bound to, in `file` and then the modules it opens, or `Mod.x` in mod's file. */
let resolved = (id, ~file, ~modules, ~bound: array<binding>): option<binding> => {
  let parts = id->String.split(".")
  let name = parts->Array.at(-1)->Option.getOr(id)
  let within = owns => bound->Array.find(binding => binding.name == name && owns(binding.file))
  switch parts->Array.at(-2) {
  | Some(owner) => within(other => moduleOf(other) == owner)
  | None =>
    switch within(other => other == file) {
    | Some(binding) => Some(binding)
    | None => modules->Array.findMap(owner => within(other => moduleOf(other) == owner))
    }
  }
}

/** Where one element after `--location` places a create, a name by what it is bound to. */
let valueOf = (element, ~resolve) =>
  switch quoted(element) {
  | Some(literal) => fixed(literal)->Option.mapOr(Open, value => Literal(value))
  | None if /^[A-Za-z_$][\w$.']*$/->RegExp.test(element) =>
    switch resolve(element) {
    | Some({value: Some(_)} as binding) => Bound(element, binding)
    | _ => Open
    }
  | None => Open
  }

/** Where the elements of one array place a create, if they name `--location` at all. */
let placeIn = (held: array<string>, ~resolve): option<place> =>
  switch held->Array.findIndex(element =>
    quoted(element)->Option.map(((_, inner)) => inner) == Some("--location")
  ) {
  | -1 =>
    held->Array.findMap(element =>
      switch quoted(element) {
      | Some((mark, inner)) if inner->String.startsWith("--location=") =>
        let value = (mark, inner->String.slice(~start=String.length("--location=")))
        Some(fixed(value)->Option.mapOr(Open, value => Literal(value)))
      | _ => None
      }
    )
  | at => Some(held->Array.get(at + 1)->Option.mapOr(Open, element => valueOf(element, ~resolve)))
  }

/** The line after a definition, where the next one begins. */
let defined = /\n(?=(?:let|const|function|export|type|module|open|include|external)\b|@)/

/** Where the function `name` a blanked source defines places what it spreads, if it does. */
let spreadPlace = (text, name, ~quotes, ~resolve) => {
  let escaped = name->String.replaceAll("$", "\\$")
  let definition = RegExp.fromString(
    `^[ \\t]*(?:export\\s+)?(?:let|const|function)\\s+(?:rec\\s+)?${escaped}\\b`,
    ~flags="m",
  )
  definition
  ->RegExp.exec(text)
  ->Option.flatMap(result => {
    let begins = result->RegExp.Result.index
    let rest = text->String.slice(~start=begins)
    let body = switch defined->RegExp.exec(rest) {
    | Some(found) => rest->String.slice(~start=0, ~end=found->RegExp.Result.index)
    | None => rest
    }
    let flagged = /[\x22\x27\x60]--location[=\x22\x27\x60]/
    flagged
    ->RegExp.exec(body)
    ->Option.flatMap(flag => containerAt(text, begins + flag->RegExp.Result.index, ~quotes))
    ->Option.flatMap(held => placeIn(held, ~resolve))
  })
}

/** What one array or list of a create leaves unplaced, a spread placing it as its function does. */
let unplaced = (held, ~what, ~text, ~quotes, ~resolve) =>
  switch placeIn(held, ~resolve) {
  | Some(place) => judged(place, ~what)
  | None =>
    let spread = held->Array.filterMap(element =>
      switch /^\.\.\.\s*([A-Za-z_$][\w$.]*)\s*\(/->RegExp.exec(element) {
      | Some(result) =>
        switch result->RegExp.Result.matches {
        | [Some(call)] =>
          let name = call->String.split(".")->Array.at(-1)->Option.getOr(call)
          spreadPlace(text, name, ~quotes, ~resolve)
        | _ => None
        }
      | None => None
      }
    )
    spread == [] ? Some(named(what)) : spread->Array.findMap(place => judged(place, ~what))
  }

/** The lines of a shell `text`, one a trailing backslash continues joined, by its first line. */
let logical = (text): array<(int, string)> => {
  let (found, carried) =
    text
    ->String.split("\n")
    ->Array.reduceWithIndex(([], None), ((found, carried), line, index) => {
      let (begins, held) = switch carried {
      | Some((begins, held)) => (begins, `${held} ${line}`)
      | None => (index + 1, line)
      }
      let ends = held->String.trimEnd
      ends->String.endsWith("\\")
        ? (found, Some((begins, ends->String.slice(~start=0, ~end=-1))))
        : ([...found, (begins, held)], None)
    })
  switch carried {
  | Some(last) => [...found, last]
  | None => found
  }
}

/** A word with its outer quotes taken off. */
let unquoted = word => word->String.replaceRegExp(/^[\x22\x27]|[\x22\x27]$/g, "")

/** Where a shell word after `--location` places a create, `earlier` the assignments before it. */
let shellPlace = (word, ~earlier: array<binding>) => {
  let word = unquoted(word)
  switch /^\$\{?([A-Za-z_]\w*)(?::?[-=]([^}]*))?\}?$/->RegExp.exec(word) {
  | _ if word->String.startsWith("{{") => Open
  | Some(result) =>
    let (name, default) = switch result->RegExp.Result.matches {
    | [Some(name), default] => (name, default->Option.map(unquoted))
    | _ => ("", None)
    }
    let binding = earlier->Array.findLast(binding => binding.name == name)
    switch (binding, default) {
    | (Some({value: Some(value)} as binding), _) if !passes(value) => Bound(word, binding)
    | (_, Some(value)) => Literal(value)
    | (Some({value: Some(_)} as binding), None) => Bound(word, binding)
    | _ => Open
    }
  | None => word->String.includes("$") || word->String.includes("{{") ? Open : Literal(word)
  }
}

/** A `--location` a shell line names, its value where a quote or a comma ends it. */
let flagged = /--location[\x22\x27]?(=|\s*,\s*|\s+)([\x22\x27]?)([^\s\x22\x27,]+)/

/** Each create a shell `text` makes, `file` naming it, by its line and what it leaves unplaced. */
let shellJudged = (text, ~file): array<(int, option<string>)> => {
  let segments =
    logical(text)
    ->Array.filter(((_, held)) => !(held->String.trim->String.startsWith("#")))
    ->Array.flatMap(((line, held)) =>
      held
      ->String.splitByRegExp(/&&|\|\||;|\|/)
      ->Array.filterMap(segment => segment->Option.map(segment => (line, segment)))
    )
  let assignment = /^\s*(?:export\s+|local\s+|readonly\s+)?([A-Za-z_]\w*)=(\S*)\s*$/
  let (_, found) = segments->Array.reduce(([], []), ((earlier, found), (line, segment)) =>
    switch (assignment->RegExp.exec(segment), creating->RegExp.exec(segment)) {
    | (Some(result), _) =>
      switch result->RegExp.Result.matches {
      | [Some(name), Some(word)] =>
        let word = unquoted(word)
        let value = /[$`(]/->RegExp.test(word) ? None : Some(word)
        ([...earlier, {file, name, value}], found)
      | _ => (earlier, found)
      }
    | (None, Some(result)) =>
      let what = switch result->RegExp.Result.matches {
      | [Some(create)] => create->String.replaceRegExp(/[\s\x22\x27,]+/g, " ")
      | _ => "a create"
      }
      let place = switch flagged->RegExp.exec(segment) {
      | Some(flag) =>
        switch flag->RegExp.Result.matches {
        | [Some(apart), quote, Some(word)] =>
          let argv = apart->String.includes(",") && quote->Option.getOr("") == ""
          Some(argv ? Open : shellPlace(word, ~earlier))
        | _ => None
        }
      | None => /--location[\x22\x27=\s,]*$/->RegExp.test(segment) ? Some(Open) : None
      }
      let said = place->Option.mapOr(Some(named(what)), place => judged(place, ~what))
      (earlier, [...found, (line, said)])
    | (None, None) => (earlier, found)
    }
  )
  found
}

/** The findings among `judged`, `file` naming them and `from` the line they begin on. */
let shown = (~from=1, judged: array<(int, option<string>)>, ~file): array<string> =>
  judged->Array.filterMap(((line, said)) =>
    said->Option.map(said => `${file}:${Int.toString(from + line - 1)}: ${said}`)
  )

/** Each create in a shell script, `file` naming it, that names no place it may name. */
let script = (text, ~file): array<string> => shellJudged(text, ~file)->shown(~file)

/** Each create in one blanked source, `file` naming it, by its line and what it leaves unplaced. */
let codeJudged = (text, ~file, ~bound): array<(int, option<string>)> => {
  let quotes = quotesOf(file)
  let modules = opens(text)
  let own = bindings(text, ~file)
  let bound = Array.concat(own, bound->Array.filter(binding => binding.file != file))
  let resolve = id => resolved(id, ~file, ~modules, ~bound)
  let arrays = all(created, text)->Array.filterMap(result => {
    let at = result->RegExp.Result.index
    let what = result->RegExp.Result.fullMatch->String.replaceRegExp(/\W+/g, " ")->String.trim
    containerAt(text, at, ~quotes)->Option.map(held => (
      lineOf(text, at),
      unplaced(held, ~what, ~text, ~quotes, ~resolve),
    ))
  })
  let lines =
    literals(text, ~quotes)->Array.flatMap(((at, inner)) =>
      creating->RegExp.test(inner)
        ? shellJudged(inner, ~file)->Array.map(((line, said)) => (
            lineOf(text, at) + line - 1,
            said,
          ))
        : []
    )
  Array.concat(arrays, lines)
}

/** Each create in one source, `file` naming it, that names no place it may name. */
let source = (text, ~file, ~bound) =>
  codeJudged(blanked(text, ~quotes=quotesOf(file)), ~file, ~bound)->shown(~file)

/** What each task of one mise.toml's text runs, a step of a list a script of its own. */
let runs = (text): array<string> => {
  let steps = run =>
    switch run {
    | JSON.String(text) => [text]
    | JSON.Array(steps) =>
      steps->Array.filterMap(step =>
        switch step {
        | JSON.String(text) => Some(text)
        | _ => None
        }
      )
    | _ => []
    }
  let tasks = switch Toml.parse(text) {
  | JSON.Object(config) =>
    switch config->Dict.get("tasks") {
    | Some(JSON.Object(tasks)) => tasks->Dict.valuesToArray
    | _ => []
    }
  | _ => []
  | exception _ => []
  }
  tasks->Array.flatMap(task =>
    switch task {
    | JSON.Object(fields) => fields->Dict.get("run")->Option.mapOr([], steps)
    | run => steps(run)
    }
  )
}

/** Each create a task in one mise.toml runs, `file` naming it, that names no place it may name. */
let tasks = (text, ~file): array<string> => {
  let raw = text->String.split("\n")
  runs(text)->Array.flatMap(run => {
    let held = run->String.split("\n")
    shellJudged(run, ~file)->Array.filterMap(((line, said)) =>
      said->Option.map(
        said => {
          let first = held->Array.get(line - 1)->Option.getOr("")->String.trim
          let at = first == "" ? -1 : raw->Array.findIndex(kept => kept->String.includes(first))
          `${file}:${Int.toString(at < 0 ? 1 : at + 1)}: ${said}`
        },
      )
    )
  })
}

/** How a tracked file is read, as a source, as a shell script or as a mise.toml. */
type kind = Code | Shell | Toml

/** How `path` is read, its `stats` saying whether a file under `.mise/tasks/` runs. */
let kindsOf = (path, ~stats): array<kind> =>
  if Node.basename(path) == "mise.toml" {
    [Toml]
  } else {
    let runs = tasked(path) && Int.bitwiseAnd(Tasks.mode(stats), 0o111) != 0
    let shell = path->String.endsWith(".sh") || runs
    Array.concat(shell ? [Shell] : [], coded(path) ? [Code] : [])
  }

/** The file at `path` under `root`, how it is read and its text, none where it cannot be. */
let loaded = (path, ~root) => {
  let file = Node.join([root, path])
  let stats = switch Node.stat(file) {
  | Some(stats) if stats->Node.statsIsFile => Some(stats)
  | _ => None
  | exception _ => None
  }
  stats->Option.flatMap(stats =>
    switch kindsOf(path, ~stats) {
    | [] => None
    | kinds =>
      switch Node.readFileSync(file) {
      | text => Some((path, kinds, text))
      | exception _ => None
      }
    }
  )
}

/**
 * What the tracked `paths` under `root` make with no place it may name. Where a file is read both
 * as a source and as a shell script, the source's reading of a line is the one kept.
 */
let within = (~root, ~paths): array<string> => {
  let texts =
    paths
    ->Array.filter(path =>
      read(path) &&
      (coded(path) ||
      tasked(path) ||
      path->String.endsWith(".sh") ||
      Node.basename(path) == "mise.toml")
    )
    ->Array.filterMap(path => loaded(path, ~root))
  let sources =
    texts->Array.filterMap(((path, kinds, text)) =>
      kinds->Array.includes(Code) ? Some((path, blanked(text, ~quotes=quotesOf(path)))) : None
    )
  let bound = sources->Array.flatMap(((file, text)) => bindings(text, ~file))
  let judged = sources->Array.map(((file, text)) => (file, codeJudged(text, ~file, ~bound)))
  Array.concat(
    judged->Array.flatMap(((file, creates)) => creates->shown(~file)),
    texts->Array.flatMap(((file, kinds, text)) =>
      if kinds->Array.includes(Toml) {
        tasks(text, ~file)
      } else if kinds->Array.includes(Shell) {
        let read =
          judged
          ->Array.find(((other, _)) => other == file)
          ->Option.mapOr([], ((_, creates)) => creates->Array.map(((line, _)) => line))
        shellJudged(text, ~file)
        ->Array.filter(((line, _)) => !(read->Array.includes(line)))
        ->shown(~file)
      } else {
        []
      }
    ),
  )
}

/** What `root`'s tracked scripts and tasks make with no place it may name. */
let found = (~root): array<string> => within(~root, ~paths=Lines.tracked(root))
