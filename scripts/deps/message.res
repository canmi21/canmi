/**
 * The message a scheduled update is committed with, naming what moved by version from the files it
 * changed, as monoflake/machine's message does for its flake. See docs/ci.md.
 */
let width = 96
let lines = 5

/** What one name moved from and to, each side its versions as written. */
type moved = {name: string, before: array<string>, after: array<string>}

let unique = values =>
  values->Array.reduce([], (kept, value) => kept->Array.includes(value) ? kept : [...kept, value])

/** Each name's versions in a list of (name, version) pairs. */
let gathered = (pairs: array<(string, string)>): dict<array<string>> => {
  let all = Dict.make()
  pairs->Array.forEach(((name, version)) =>
    all->Dict.set(name, unique([...all->Dict.get(name)->Option.getOr([]), version]))
  )
  all
}

/** The names whose versions differ between two readings, in the order they first appear. */
let compared = (old: array<(string, string)>, now: array<(string, string)>): array<moved> => {
  let before = gathered(old)
  let after = gathered(now)
  unique([...now->Array.map(Pair.first), ...old->Array.map(Pair.first)])->Array.filterMap(name => {
    let was = before->Dict.get(name)->Option.getOr([])
    let is = after->Dict.get(name)->Option.getOr([])
    let gone = was->Array.filter(v => !(is->Array.includes(v)))
    let came = is->Array.filter(v => !(was->Array.includes(v)))
    gone == [] && came == [] ? None : Some({name, before: gone, after: came})
  })
}

let groups = (pattern, line) =>
  pattern
  ->RegExp.exec(line)
  ->Option.map(result => result->RegExp.Result.matches->Array.map(group => group->Option.getOr("")))

/** Every package Cargo.lock holds, by name and version. */
let cargo = text => {
  let name = ref(None)
  text
  ->String.split("\n")
  ->Array.filterMap(line =>
    switch (groups(/^name = "([^"]+)"$/, line), groups(/^version = "([^"]+)"$/, line)) {
    | (Some([found]), _) =>
      name := Some(found)
      None
    | (_, Some([version])) => name.contents->Option.map(found => (found, version))
    | _ => None
    }
  )
}

/** Every direct dependency each importer of pnpm-lock.yaml resolves, by name and version. */
let pnpm = text => {
  let inside = ref(false)
  let name = ref(None)
  text
  ->String.split("\n")
  ->Array.filterMap(line =>
    if line == "importers:" {
      inside := true
      None
    } else if inside.contents && /^\S/->RegExp.test(line) {
      inside := false
      None
    } else if !inside.contents {
      None
    } else {
      switch (groups(/^ {6}'?([^\s':]+)'?:$/, line), groups(/^ {8}version: (\S+)$/, line)) {
      | (Some([found]), _) =>
        name := Some(found)
        None
      | (_, Some([version])) =>
        name.contents->Option.map(found => (found, version->String.replaceRegExp(/\(.*$/, "")))
      | _ => None
      }
    }
  )
}

/** Every input flake.lock locks, by name and the first seven characters of its revision. */
let flake = text =>
  switch JSON.parseOrThrow(text)->JSON.Decode.object->Option.flatMap(o => o->Dict.get("nodes")) {
  | exception _ => []
  | None => []
  | Some(nodes) =>
    nodes
    ->JSON.Decode.object
    ->Option.getOr(Dict.make())
    ->Dict.toArray
    ->Array.filterMap(((name, node)) =>
      node
      ->JSON.Decode.object
      ->Option.flatMap(n => n->Dict.get("locked"))
      ->Option.flatMap(JSON.Decode.object)
      ->Option.flatMap(locked => locked->Dict.get("rev"))
      ->Option.flatMap(JSON.Decode.string)
      ->Option.map(rev => (name, rev->String.slice(~start=0, ~end=7)))
    )
  }

/** Every release and branch a workflow pins, by repository and the release or the commit. */
let workflow = text =>
  [
    ...Actions.pins(text)->Array.map(pin => (pin.repository, pin.current)),
    ...Actions.heads(text)->Array.map(head => (
      head.repository,
      head.current->String.slice(~start=0, ~end=7),
    )),
  ]

/** Every base a Dockerfile pins, by image and its tag, or its digest where the tag stayed. */
let dockerfile = text =>
  Images.bases(text)->Array.map(base => (
    base.image,
    `${base.tag}@${base.digest->String.slice(~start=7, ~end=19)}`,
  ))

/** How a changed file is read, by its path, or None for a file no reader knows. */
let reader = path => {
  let file = path->String.split("/")->Array.at(-1)->Option.getOr(path)
  if file == "Cargo.lock" {
    Some(cargo)
  } else if file == "pnpm-lock.yaml" {
    Some(pnpm)
  } else if file == "flake.lock" {
    Some(flake)
  } else if file == "Dockerfile" || file->String.endsWith(".Dockerfile") {
    Some(dockerfile)
  } else if path->String.startsWith(".github/") && /\.ya?ml$/->RegExp.test(file) {
    Some(workflow)
  } else {
    None
  }
}

/** What every changed file moved, a file no reader knows named by its path alone. */
let read = (changed: array<(string, string, string)>): (array<moved>, array<string>) => {
  let readings =
    changed->Array.map(((path, old, now)) => (
      path,
      reader(path)->Option.mapOr([], read => compared(read(old), read(now))),
    ))
  let unknown = readings->Array.filterMap(((path, moved)) => moved == [] ? Some(path) : None)
  let all = readings->Array.flatMap(((_, moved)) => moved)
  // A name two files move, as two machines' flakes do, is said once.
  let once =
    all->Array.reduce([], (kept: array<moved>, m) =>
      kept->Array.some(k => k.name == m.name) ? kept : [...kept, m]
    )
  (once, unknown)
}

let listed = words =>
  switch words {
  | [] => ""
  | [one] => one
  | _ =>
    `${words->Array.slice(~start=0, ~end=Array.length(words) - 1)->Array.join(", ")} and ${words
      ->Array.at(-1)
      ->Option.getOr("")}`
  }

let shown = versions => versions == [] ? "none" : versions->Array.join(", ")

/** The subject naming as many of what moved as fit, the rest counted. */
let subject = (moved: array<moved>, unknown: array<string>) => {
  let heads = [...moved->Array.map(m => `${m.name} ${shown(m.after)}`), ...unknown]
  let count = Array.length(heads)
  let line = taken => {
    let rest = count - taken
    let named = if taken == 0 {
      `${Int.toString(rest)} dependencies`
    } else if rest == 0 {
      listed(heads->Array.slice(~start=0, ~end=taken))
    } else {
      `${heads->Array.slice(~start=0, ~end=taken)->Array.join(", ")} and ${Int.toString(rest)} more`
    }
    `build: update ${named}`
  }
  Array.fromInitializer(~length=count + 1, i => count - i)
  ->Array.map(line)
  ->Array.find(text => String.length(text) <= width)
  ->Option.getOr(line(0))
}

/** The body, each move as old -> new, packed into at most `lines` lines of `width`. */
let body = (moved: array<moved>) => {
  let words = moved->Array.map(m => `${m.name} ${shown(m.before)} -> ${shown(m.after)}`)
  let pack = words =>
    words->Array.reduce([], (packed, word) =>
      switch packed->Array.at(-1) {
      | None => [word]
      | Some(last) if String.length(`${last}, ${word}`) <= width =>
        [...packed->Array.slice(~start=0, ~end=Array.length(packed) - 1), `${last}, ${word}`]
      | Some(_) => [...packed, word]
      }
    )
  let count = Array.length(words)
  Array.fromInitializer(~length=count + 1, i => count - i)
  ->Array.map(taken =>
    pack(
      [
        ...words->Array.slice(~start=0, ~end=taken),
        ...taken < count ? [`and ${Int.toString(count - taken)} more`] : [],
      ],
    )
  )
  ->Array.find(packed => Array.length(packed) <= lines)
  ->Option.getOr([])
}

/** The whole message for the files a run changed, each as (path, old text, new text). */
let message = changed => {
  let (moved, unknown) = read(changed)
  let lines = body(moved)
  `${subject(moved, unknown)}\n${lines == [] ? "" : `\n${lines->Array.join("\n")}\n`}`
}
