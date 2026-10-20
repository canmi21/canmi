/** Every mise task a repository tracks against `Toolchain.taskLines`. */
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

/** Each task of one mise.toml's text, `file` naming it, that runs past the limit. */
let problems = (text, ~file): array<string> =>
  switch Toml.parse(text) {
  | JSON.Object(config) =>
    switch config->Dict.get("tasks") {
    | Some(JSON.Object(tasks)) =>
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
    | _ => []
    }
  | _ => []
  | exception _ => [`${file}: does not parse`]
  }

let main = (~root): array<string> =>
  Lines.tracked(root)
  ->Array.filter(path => Node.basename(path) == "mise.toml")
  ->Array.flatMap(path => {
    let file = Node.join([root, path])
    Node.existsSync(file) ? problems(Node.readFileSync(file), ~file=path) : []
  })
