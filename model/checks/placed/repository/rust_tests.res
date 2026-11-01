/** A Rust repository's tests run by nextest, its doctests apart, docs/code.md. */
let cargoTest = /\bcargo\s+test\b/

/** Each line running `cargo test` with no `--doc`, `file` naming it. */
let commands = (text, ~file): array<string> =>
  text
  ->String.split("\n")
  ->Array.mapWithIndex((line, index) =>
    cargoTest->RegExp.test(line) && !(line->String.includes("--doc"))
      ? Some(`${file}:${Int.toString(index + 1)}: cargo test runs more than the doctests`)
      : None
  )
  ->Array.filterMap(found => found)

/** What is wrong with a repository's nextest configuration, given its text if it has one. */
let slow = (text: option<string>): option<string> =>
  switch text {
  | Some(text) if text->String.includes("terminate-after") => None
  | _ => Some(".config/nextest.toml does not give a slow timeout that terminates a hung test")
  }

let runs = path =>
  path == "mise.toml" ||
  path->String.startsWith(".mise/tasks/") ||
  path->String.endsWith(".nix") ||
  (path->String.startsWith(".github/workflows/") && /\.ya?ml$/->RegExp.test(path))

/** Where a Rust repository, one with a Cargo.toml at its root, does not run nextest. */
let main = (~root, ~paths: array<string>): array<string> =>
  if !(paths->Array.includes("Cargo.toml")) {
    []
  } else {
    let read = path => Node.readFileSync(Node.join([root, path]))
    let config = ".config/nextest.toml"
    Array.concat(
      slow(paths->Array.includes(config) ? Some(read(config)) : None)->Option.mapOr([], why => [
        why,
      ]),
      paths->Array.filter(runs)->Array.flatMap(path => commands(read(path), ~file=path)),
    )
  }
