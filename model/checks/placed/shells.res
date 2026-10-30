/** The judgment of a create in a shell line and in a mise task, for `Placed`. */
open Placing

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
let shellJudged = (
  text,
  ~file,
  ~repo="",
  ~exceptions=Toolchain.placedExceptions,
  ~runtime=None,
): array<(int, option<string>)> => {
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
      let said =
        place->Option.mapOr(Some(named(what)), place =>
          judged(place, ~what, ~repo, ~file, ~exceptions, ~runtime)
        )
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
let script = (text, ~file, ~repo="", ~exceptions=Toolchain.placedExceptions): array<string> =>
  shellJudged(text, ~file, ~repo, ~exceptions)->shown(~file)

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
let tasks = (text, ~file, ~repo="", ~exceptions=Toolchain.placedExceptions): array<string> => {
  let raw = text->String.split("\n")
  runs(text)->Array.flatMap(run => {
    let held = run->String.split("\n")
    shellJudged(run, ~file, ~repo, ~exceptions)->Array.filterMap(((line, said)) =>
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
