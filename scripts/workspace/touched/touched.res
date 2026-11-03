type touched =
  | Every
  | Blocks(array<string>)

let inside = (path, directory) => path->String.startsWith(`${directory}/`)

let of_ = (~paths, ~blocks, ~full) => {
  let shared =
    paths->Array.some(path => !(blocks->Array.some(((_, directory)) => inside(path, directory))))
  if full || paths == [] || shared {
    Every
  } else {
    Blocks(
      blocks
      ->Array.filter(((_, directory)) => paths->Array.some(path => inside(path, directory)))
      ->Array.map(((name, _)) => name),
    )
  }
}

let changed = repo => {
  let result = Node.spawnSync(
    "jj",
    ["diff", "--name-only", "--from", "main@origin", "--to", "@"],
    {cwd: repo, encoding: "utf8", maxBuffer: 268435456},
  )
  if result.status->Nullable.getOr(1) != 0 {
    []
  } else {
    result.stdout
    ->Nullable.getOr("")
    ->String.split("\n")
    ->Array.map(String.trim)
    ->Array.filter(line => line != "")
  }
}

/** Each package under `code/` by its name, its scope dropped, and its directory. */
let blocksOf = repo => {
  let code = Node.join([repo, "code"])
  let found = []
  let rec walk = (directory, depth) =>
    if depth <= 3 {
      let manifest = Node.join([directory, "package.json"])
      if directory != code && Node.existsSync(manifest) {
        switch JSON.parseOrThrow(Node.readFileSync(manifest))
        ->JSON.Decode.object
        ->Option.flatMap(fields => fields->Dict.get("name"))
        ->Option.flatMap(JSON.Decode.string) {
        | Some(name) =>
          let short = name->String.replaceRegExp(/^@[^\/]+\//, "")
          let relative =
            directory->String.slice(~start=String.length(repo) + 1, ~end=String.length(directory))
          found->Array.push((short, relative))
        | None => ()
        }
      } else {
        Node.entries(directory)->Array.forEach(entry => {
          let name = entry->Node.name
          if name != "node_modules" && !(name->String.startsWith(".")) && entry->Node.isDirectory {
            walk(Node.join([directory, name]), depth + 1)
          }
        })
      }
    }
  if Node.existsSync(code) {
    walk(code, 0)
  }
  found
}

/** Whether a repository's verify takes `--blocks`, as its mise.toml declares the flag. */
let takesBlocks = repo => {
  let config = Node.join([repo, "mise.toml"])
  Node.existsSync(config) && Node.readFileSync(config)->String.includes(`flag "--blocks`)
}

/** Each block by its name and the blocks it uses, its `@`-scoped dependencies of the same scope. */
let usesOf = repo =>
  blocksOf(repo)->Array.map(((name, directory)) => {
    let fields =
      JSON.parseOrThrow(Node.readFileSync(Node.join([repo, directory, "package.json"])))
      ->JSON.Decode.object
      ->Option.getOr(dict{})
    let named = key =>
      fields
      ->Dict.get(key)
      ->Option.flatMap(JSON.Decode.object)
      ->Option.mapOr([], deps => deps->Dict.keysToArray)
    let used =
      Array.concat(named("dependencies"), named("devDependencies"))
      ->Array.filter(dep => dep->String.startsWith("@monoflake/"))
      ->Array.map(dep => dep->String.replaceRegExp(/^@[^\/]+\//, ""))
    (name, used)
  })

let withDependents = (names, ~uses) => {
  let held = Set.fromArray(names)
  let grew = ref(true)
  while grew.contents {
    grew := false
    uses->Array.forEach(((name, used)) =>
      if !(held->Set.has(name)) && used->Array.some(one => held->Set.has(one)) {
        held->Set.add(name)
        grew := true
      }
    )
  }
  uses->Array.filterMap(((name, _)) => held->Set.has(name) ? Some(name) : None)
}

let arguments = repo =>
  if !takesBlocks(repo) {
    []
  } else {
    switch of_(~paths=changed(repo), ~blocks=blocksOf(repo), ~full=false) {
    | Every | Blocks([]) => []
    | Blocks(names) => ["--blocks", withDependents(names, ~uses=usesOf(repo))->Array.join(",")]
    }
  }

let tableOf = repo => {
  let strings = value =>
    value
    ->JSON.Decode.array
    ->Option.flatMap(values => {
      let decoded = values->Array.filterMap(JSON.Decode.string)
      Array.length(decoded) == Array.length(values) ? Some(decoded) : None
    })
  try {
    Toml.parse(Node.readFileSync(Node.join([repo, "workspace.toml"])))
    ->JSON.Decode.object
    ->Option.flatMap(fields => fields->Dict.get("check"))
    ->Option.flatMap(JSON.Decode.object)
    ->Option.flatMap(fields => fields->Dict.get("touched"))
    ->Option.flatMap(JSON.Decode.array)
    ->Option.flatMap(rows => {
      let table = rows->Array.filterMap(row =>
        row
        ->JSON.Decode.object
        ->Option.flatMap(
          fields => {
            let paths = fields->Dict.get("paths")->Option.flatMap(strings)
            let parts = fields->Dict.get("parts")->Option.flatMap(strings)
            switch (paths, parts) {
            | (Some(paths), Some(parts)) => Some((paths, parts))
            | _ => None
            }
          },
        )
      )
      table == [] ? None : Some(table)
    })
  } catch {
  | _ => None
  }
}

let parts = (~paths, ~table) => {
  let matches = (path, glob) => {
    let characters = path->String.split("")
    let pattern = glob->String.split("")
    let length = Array.length(characters)
    let previous = ref(Array.make(~length=length + 1, false))
    previous.contents[0] = true
    let index = ref(0)
    while index.contents < Array.length(pattern) {
      let character = pattern[index.contents]
      let star = character == Some("*")
      let crosses = star && pattern->Array.get(index.contents + 1) == Some("*")
      let current = Array.make(~length=length + 1, false)
      current[0] = star && previous.contents->Array.get(0)->Option.getOr(false)
      for position in 1 to length {
        current[position] = if star {
          previous.contents->Array.get(position)->Option.getOr(false) ||
            (current->Array.get(position - 1)->Option.getOr(false) &&
              (crosses || characters[position - 1] != Some("/")))
        } else {
          previous.contents->Array.get(position - 1)->Option.getOr(false) &&
            characters[position - 1] == character
        }
      }
      previous := current
      index := index.contents + (crosses ? 2 : 1)
    }
    previous.contents->Array.get(length)->Option.getOr(false)
  }
  let selected = Set.make()
  let covered = paths->Array.every(path => {
    let found = ref(false)
    table->Array.forEach(((globs, names)) => {
      if globs->Array.some(glob => matches(path, glob)) {
        found := true
        names->Array.forEach(name => selected->Set.add(name))
      }
    })
    found.contents
  })
  if !covered {
    None
  } else {
    let seen = Set.make()
    let result = []
    table->Array.forEach(((_, names)) =>
      names->Array.forEach(name => {
        if selected->Set.has(name) && !(seen->Set.has(name)) {
          seen->Set.add(name)
          result->Array.push(name)
        }
      })
    )
    Some(result)
  }
}
