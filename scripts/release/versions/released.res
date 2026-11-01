/** How far monoflake/driver's main has moved past its last Release, one line at a plan's end. */
let repository = "monoflake/driver"
let package = "driver-machine"
let manifest = "machine/Cargo.toml"
let waited = 10000

/** What a published release lists of the program, its highest version and where it was. */
let lastOf = entries =>
  entries->Array.reduce(None, (best, entry) =>
    switch entry {
    | JSON.Object(fields) if fields->Dict.get("name") == Some(JSON.String(package)) =>
      switch (fields->Dict.get("version"), fields->Dict.get("release")) {
      | (Some(String(version)), release) =>
        switch (Numbers.parse(version), best) {
        | (Some(numbers), Some((held, _))) if !Numbers.later(numbers, held) => best
        | (Some(numbers), _) =>
          Some((
            numbers,
            switch release {
            | Some(String(tag)) => tag
            | _ => ""
            },
          ))
        | (None, _) => best
        }
      | _ => best
      }
    | _ => best
    }
  )

/** The line itself, from the main line's version and the last Release's. */
let said = (~main, ~last: option<(Numbers.t, string)>) =>
  switch last {
  | None => `${repository} main is ${Numbers.show(main)}, and no Release lists ${package} yet`
  | Some(((major, minor, patch) as held, tag)) =>
    let (now, was, count) = main
    let shown = `Release ${Numbers.show(held)} (${tag})`
    let plural = n => `${n->Int.toString} patch${n == 1 ? "" : "es"}`
    `${repository} main is ${Numbers.show(main)}, ` ++ if now == major && was == minor {
      `${plural(count - patch)} past ${shown}`
    } else {
      `a minor and ${plural(count)} past ${shown}`
    }
  }

/** The line a plan ends with, or none where the repository is not here. */
let line = () => {
  let root = Landing.place(repository)
  if !Registry.isRepository(root) || !Landing.isJj(root) {
    None
  } else {
    let main =
      Landing.at(~root, ~base="main", manifest)
      ->Option.flatMap(text => Packages.group(Packages.cargoVersion, text))
      ->Option.flatMap(Numbers.parse)
    let script = Node.join([Registry.root, "scripts", "release", "release.res.mjs"])
    let answer = Node.spawnSync(
      "node",
      [script, "listed"],
      {cwd: root, encoding: "utf8", maxBuffer: 67108864, timeout: waited},
    )
    let listed =
      answer.status == Nullable.make(0)
        ? switch JSON.parseOrThrow(answer.stdout->Nullable.getOr("")) {
          | Array(entries) => Some(entries)
          | _ => None
          | exception JsExn(_) => None
          }
        : None
    switch (main, listed) {
    | (None, _) => Some(`${repository}: main names no version in ${manifest}`)
    | (Some(main), None) =>
      Some(`${repository} main is ${Numbers.show(main)}, its last Release could not be read`)
    | (Some(main), Some(entries)) => Some(said(~main, ~last=lastOf(entries)))
    }
  }
}
