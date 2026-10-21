/**
 * Holds each app's directory to its declaration's `name`, since the artifact takes one and the
 * container the other. Run from `verify` where apps carry a `service.toml`. RFC l6r4u.
 */
/** Why each app's declaration does not name it as its directory does, in the order found. */
let misnamed = (layout: Graph.layout): array<string> => {
  let found = []
  layout
  ->Graph.appDirectories
  ->Map.forEachWithKey((directory, leaf) => {
    let declaration = Node.join([directory, "service.toml"])
    if Node.existsSync(declaration) {
      let where = Node.relative(layout.root, declaration)
      switch Toml.parse(Node.readFileSync(declaration)) {
      | Object(data) =>
        switch data->Dict.get("name") {
        | Some(String(name)) if name == leaf => ()
        | name =>
          found->Array.push(
            `${where}: name is ${JSON.stringifyAny(name)->Option.getOr(
                "undefined",
              )}, its directory ${leaf}`,
          )
        }
      | _ => found->Array.push(`${where}: name is undefined, its directory ${leaf}`)
      | exception JsExn(error) =>
        found->Array.push(`${where}: does not parse: ${error->JsExn.message->Option.getOr("")}`)
      }
    }
  })
  found
}

/** A repository's `check-names` task, which reports each app not named as its directory is. */
let main = (layout: Graph.layout) => {
  let found = misnamed(layout)
  if found->Array.length > 0 {
    Console.error("An app is named as its directory is, in its service.toml:\n")
    found->Array.forEach(one => Console.error(`  ${one}`))
    Node.exit(1)
  }
  Console.log("names OK: every app's service.toml names it as its directory does")
}

if Node.isMain {
  main(Project.layout("names"))
}
