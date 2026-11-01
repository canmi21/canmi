/** `todo-cites-open`, model/rules/planning.res, each `%todo` and `todo!` against the RFCs. */
let marker = /[%]todo\(([^)]*)\)|\btodo!\(([^)]*)\)/
let quoted = /^\s*"([^"]*)"\s*$/

/** Whether a line is a comment, a marker named in prose there not being one. */
let commented = line =>
  ["//", "/*", "*"]->Array.some(open_ => line->String.trimStart->String.startsWith(open_))

/** The id each marker of one file's text names, none for a marker naming nothing, by line. */
let markers = (text: string): array<(int, option<string>)> =>
  text
  ->String.split("\n")
  ->Array.mapWithIndex((line, at) =>
    commented(line)
      ? None
      : marker
        ->RegExp.exec(line)
        ->Option.map(found => (
          at + 1,
          found
          ->RegExp.Result.matches
          ->Array.findMap(arguments => arguments)
          ->Option.flatMap(
            arguments =>
              switch quoted->RegExp.exec(arguments)->Option.map(RegExp.Result.matches) {
              | Some([Some(id)]) => Some(id)
              | _ => None
              },
          ),
        ))
  )
  ->Array.filterMap(found => found)

/** Each marker of a file that names no draft RFC, `rows` saying a checklist may hold its id. */
let problems = (text, ~file, ~statuses: Dict.t<string>, ~rows): array<string> =>
  markers(text)->Array.filterMap(((at, named)) => {
    let where = `${file}:${Int.toString(at)}`
    switch named {
    | None => Some(`${where}: a todo naming nothing`)
    | Some(id) =>
      switch statuses->Dict.get(id) {
      | Some("draft") => None
      | Some(status) => Some(`${where}: waits on ${id}, which is ${status}`)
      | None if rows => None
      | None => Some(`${where}: waits on ${id}, which no RFC of its id space holds`)
      }
    }
  })

/** A source the scan reads, no test or build output, which Placed.read holds apart. */
let coded = path =>
  (path->String.endsWith(".res") || path->String.endsWith(".rs")) && Placed.read(path)

/** The status of each RFC of a space, by its id. */
let statusesOf = (space: string): Dict.t<string> => {
  let statuses = Dict.make()
  Rfc_spaces.read(space).files->Array.forEach(file =>
    switch Rfc_record.readFront(Node.readFileSync(file.path)) {
    | (Some(front), _) => statuses->Dict.set(file.id, front.status)
    | (None, _) => ()
    }
  )
  statuses
}

/** The repository at `root`, `label` its path, `space` its id space if it declares one. */
let found = (~root, ~label, ~space): array<string> => {
  let statuses = space->Option.mapOr(Dict.make(), statusesOf)
  Lines.tracked(root)
  ->Array.filter(coded)
  ->Array.flatMap(path =>
    problems(
      Node.readFileSync(Node.join([root, path])),
      ~file=`${label}/${path}`,
      ~statuses,
      ~rows=Planning.rowsKept->Array.includes(label),
    )
  )
}

/** Every active repository's, and the workspace's. */
let main = (): array<string> =>
  Array.concat(
    found(~root=Registry.root, ~label="workspace", ~space=Some(Planning.workspaceSpace)),
    Waiting.active()->Array.flatMap(path =>
      found(~root=Node.join([Registry.repos, path]), ~label=path, ~space=Rfc_spaces.spaceOf(path))
    ),
  )
