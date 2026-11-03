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
