/**
 * Each mise.toml a repository tracks and each executable file under its .mise/tasks/, against
 * `Toolchain.taskLines` and `task-nested`.
 */
/** The deferred item that waits on renaming a repository's tasks, warned of there meanwhile. */
let renaming = "task-names-nested-rest"

/** What a name joined by a hyphen is told to become, as `task-nested` says. */
let nested = "one word, an action its first argument"

/** The lines a run holds that say something, a script's or each of a list's. */
let lines = (run: JSON.t) => {
  let count = text =>
    text->String.split("\n")->Array.filter(line => line->String.trim != "")->Array.length
  switch run {
  | JSON.String(text) => count(text)
  | JSON.Array(steps) =>
    steps->Array.reduce(0, (sum, step) =>
      switch step {
      | JSON.String(text) => sum + count(text)
      | _ => sum + 1
      }
    )
  | _ => 0
  }
}

/** Each of `tasks`, `file` naming their mise.toml, that runs past the limit. */
let problems = (tasks: Dict.t<JSON.t>, ~file): array<string> =>
  tasks
  ->Dict.toArray
  ->Array.filterMap(((name, task)) =>
    switch task {
    | JSON.Object(fields) =>
      let held = fields->Dict.get("run")->Option.mapOr(0, lines)
      held > Toolchain.taskLines
        ? Some(
            `${file}: [tasks.${name}] runs ${Int.toString(held)} lines, past ${Int.toString(
                Toolchain.taskLines,
              )}; a script holds it`,
          )
        : None
    | _ => None
    }
  )

/** Each of `tasks`, `file` naming their mise.toml, whose name joins words by a hyphen. */
let joined = (tasks: Dict.t<JSON.t>, ~file): array<string> =>
  tasks
  ->Dict.keysToArray
  ->Array.filter(name => name->String.includes("-"))
  ->Array.map(name => `${file}: [tasks.${name}] joins words by a hyphen; ${nested}`)

/** One mise.toml's text, `file` naming it, read once, its long tasks and then its joined names. */
let read = (text, ~file): (array<string>, array<string>) =>
  switch Toml.parse(text) {
  | JSON.Object(config) =>
    switch config->Dict.get("tasks") {
    | Some(JSON.Object(tasks)) => (problems(tasks, ~file), joined(tasks, ~file))
    | _ => ([], [])
    }
  | _ => ([], [])
  | exception _ => ([`${file}: does not parse`], [])
  }

@get external mode: Node.stats => int = "mode"

/** Whether `file` may be run, as mise asks of a file before it is a task. */
let executable = file =>
  Node.stat(file)->Option.mapOr(false, stats => Int.bitwiseAnd(mode(stats), 0o111) != 0)

/** The file task a tracked `path` under `.mise/tasks/` is, named as mise names it, if joined. */
let joinedFile = (path, ~executable): option<string> =>
  switch path->String.match(/(?:^|\/)\.mise\/tasks\/(.+)$/) {
  | Some([_, Some(below)]) if executable && below->String.includes("-") =>
    let name = below->String.split("/")->Array.join(":")
    Some(`${path}: the task ${name} joins words by a hyphen; ${nested}`)
  | _ => None
  }

/** The deferred item among `items` that waits on renaming `repo`'s tasks, if one does. */
let renamingIn = (items: array<Deferred.item>, ~repo) =>
  items
  ->Array.find(item => item.id == renaming && item.repos->Array.includes(repo))
  ->Option.map(item => item.id)

/** What `root` breaks, then what it is warned of while a deferred item renames its tasks. */
let found = (~root): (array<string>, array<string>) => {
  let tracked = Lines.tracked(root)
  let (long, hyphens) =
    tracked
    ->Array.filter(path => Node.basename(path) == "mise.toml")
    ->Array.reduce(([], []), ((long, hyphens), path) => {
      let file = Node.join([root, path])
      if Node.existsSync(file) {
        let (more, joined) = read(Node.readFileSync(file), ~file=path)
        (Array.concat(long, more), Array.concat(hyphens, joined))
      } else {
        (long, hyphens)
      }
    })
  let hyphens = Array.concat(
    hyphens,
    tracked->Array.filterMap(path =>
      joinedFile(path, ~executable=executable(Node.join([root, path])))
    ),
  )
  switch renamingIn(Deferred.items, ~repo=Registry.label(root)) {
  | Some(id) => (long, hyphens->Array.map(line => `${line}, deferred ${id}`))
  | None => (Array.concat(long, hyphens), [])
  }
}
