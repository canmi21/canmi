/**
 * A workflow's or composite action's jobs and steps, and a step's shell cut into commands, for the
 * ci rules in docs/ci.md.
 */
type step = {
  name: string,
  uses: option<string>,
  run: option<string>,
  condition: string,
  inputs: Dict.t<JSON.t>,
}
type job = {id: string, runsOn: string, steps: array<step>}
type document = {file: string, action: bool, jobs: array<job>}

let field = (value, key) =>
  value->JSON.Decode.object->Option.flatMap(fields => fields->Dict.get(key))
let text = value => value->Option.flatMap(JSON.Decode.string)

let step = value => {
  name: field(value, "name")->text->Option.getOr(""),
  uses: field(value, "uses")->text,
  run: field(value, "run")->text,
  condition: field(value, "if")->Option.mapOr("", value => JSON.stringify(value)),
  inputs: field(value, "with")->Option.flatMap(JSON.Decode.object)->Option.getOr(Dict.make()),
}

let stepsOf = value =>
  value
  ->Option.flatMap(value => field(value, "steps"))
  ->Option.flatMap(JSON.Decode.array)
  ->Option.getOr([])
  ->Array.map(step)

/** The jobs of one file's text, a composite action being one, and none where it is unreadable. */
let read = (source, ~action) =>
  try {
    let document = Yaml.parse(source)
    if action {
      [{id: "action", runsOn: "", steps: stepsOf(field(document, "runs"))}]
    } else {
      field(document, "jobs")
      ->Option.flatMap(JSON.Decode.object)
      ->Option.mapOr([], jobs => jobs->Dict.toArray)
      ->Array.map(((id, job)) => {
        id,
        runsOn: field(job, "runs-on")->Option.mapOr("", value => JSON.stringify(value)),
        steps: stepsOf(Some(job)),
      })
    }
  } catch {
  | JsExn(_) => []
  }

let workflow = /^\.github\/workflows\/[^\/]+\.ya?ml$/
let composite = /^\.github\/actions\/.+\/action\.ya?ml$/

/** Every workflow and composite action of the repository at `root`. */
let documents = (~root): array<document> =>
  Lines.tracked(root)->Array.filterMap(path => {
    let action = composite->RegExp.test(path)
    action || workflow->RegExp.test(path)
      ? Some({
          file: path,
          action,
          jobs: read(Node.readFileSync(Node.join([root, path])), ~action),
        })
      : None
  })

/** One piece of a command line, and whether a pipe fed it. */
type segment = {text: string, piped: bool}

/** A run's lines with comments dropped and a trailing backslash or operator joined to the next. */
let logical = (run): array<string> =>
  run
  ->String.split("\n")
  ->Array.map(String.trim)
  ->Array.filter(line => line != "" && !(line->String.startsWith("#")))
  ->Array.reduce([], (found, line) => {
    let last = found->Array.length - 1
    let open_ = found->Array.get(last)->Option.getOr("")
    let continues = ["\\", "&&", "||", "|"]->Array.some(end => open_->String.endsWith(end))
    if continues {
      let joined = open_->String.endsWith("\\") ? open_->String.slice(~start=0, ~end=-1) : open_
      found->Array.setUnsafe(last, `${joined} ${line}`)
      found
    } else {
      [...found, line]
    }
  })

/** A command line cut at `&&`, `||`, `|` and `;` outside quotes. */
let segments = (line): array<segment> => {
  let found = []
  let current = ref("")
  let quote = ref("")
  let piped = ref(false)
  let chars = line->String.split("")
  let flush = next => {
    found->Array.push({text: current.contents->String.trim, piped: piped.contents})
    current := ""
    piped := next
  }
  let index = ref(0)
  while index.contents < chars->Array.length {
    let char = chars->Array.getUnsafe(index.contents)
    let after = chars->Array.get(index.contents + 1)->Option.getOr("")
    if quote.contents != "" {
      current := current.contents ++ char
      quote := (char == quote.contents ? "" : quote.contents)
    } else if char == "'" || char == "\"" {
      quote := char
      current := current.contents ++ char
    } else if (char == "&" || char == "|") && after == char {
      flush(false)
      index := index.contents + 1
    } else if char == "|" {
      flush(true)
    } else if char == ";" {
      flush(false)
    } else {
      current := current.contents ++ char
    }
    index := index.contents + 1
  }
  flush(false)
  found->Array.filter(segment => segment.text != "")
}

let keywords = ["if", "elif", "then", "else", "do", "while", "until", "!"]

/** A segment with its grouping, `!` and assignment prefix off, leaving the command or none. */
let rec bare = text => {
  let text = text->String.trim
  let first = text->String.split(" ")->Array.getUnsafe(0)
  if text->String.startsWith("$(") {
    bare(text->String.slice(~start=2))
  } else if text->String.startsWith("(") || text->String.startsWith("{ ") {
    bare(text->String.slice(~start=1))
  } else if keywords->Array.includes(first) && first != text {
    bare(text->String.slice(~start=first->String.length))
  } else {
    switch /^[A-Za-z_]\w*=(\$\()?/->RegExp.exec(text) {
    | Some(found) =>
      switch found->RegExp.Result.matches {
      | [Some(_), Some(_)] =>
        bare(text->String.slice(~start=found->RegExp.Result.fullMatch->String.length))
      | _ => ""
      }
    | None => text
    }
  }
}

/** The command a segment runs, its first word, or none where it only assigns or closes a block. */
let head = segment => bare(segment.text)->String.split(" ")->Array.getUnsafe(0)

/** The first word of a segment as written, before a keyword like `for` or `if` is dropped. */
let opening = segment =>
  segment.text->String.replaceRegExp(/^[({!\s]+/, "")->String.split(" ")->Array.getUnsafe(0)

/** Each segment of a run block. */
let commands = (run): array<segment> => run->logical->Array.flatMap(segments)
