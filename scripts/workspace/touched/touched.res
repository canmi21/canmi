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

let arguments = repo =>
  if !takesBlocks(repo) {
    []
  } else {
    switch of_(~paths=changed(repo), ~blocks=blocksOf(repo), ~full=false) {
    | Every | Blocks([]) => []
    | Blocks(names) => ["--blocks", names->Array.join(",")]
    }
  }
