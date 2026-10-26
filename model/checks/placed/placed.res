/**
 * Each D1 database and R2 bucket a repository's scripts and tasks make, against
 * `cloudflare-placed`. A make by REST, a jurisdiction, a Durable Object's hint and a Worker's
 * placement go unread, the rule `cloudflare-placed-rest` waiting for them. A regex literal
 * holding the opening of a block comment still starts one where it stands.
 */
open Shells
open Sources

/** The names a caller reads from the modules the check is made of. */
let told = Placing.told
let blanked = Quoting.blanked
let bindings = Sources.bindings
let script = Shells.script
let source = Sources.source
let tasks = Shells.tasks

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
