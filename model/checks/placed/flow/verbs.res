/** `verb-contract`, model/rules/layout.res, each verb task of a repository declaring --dry-run. */
let flag = /flag\s+"[^"]*--dry-run/

/** The tasks of a mise.toml's text that name a verb, each with its usage text. */
let usages = (text: string): array<(string, string)> =>
  switch Toml.parse(text) {
  | JSON.Object(config) =>
    switch config->Dict.get("tasks") {
    | Some(JSON.Object(tasks)) =>
      Layout.dryRunVerbs->Array.filterMap(verb =>
        switch tasks->Dict.get(verb) {
        | Some(JSON.Object(fields)) =>
          Some((
            verb,
            switch fields->Dict.get("usage") {
            | Some(JSON.String(usage)) => usage
            | _ => ""
            },
          ))
        | _ => None
        }
      )
    | _ => []
    }
  | _ => []
  }

/** The header a file task declares its flags in, its lines that open with a hash. */
let header = (text: string) =>
  text->String.split("\n")->Array.filter(line => line->String.startsWith("#"))->Array.join("\n")

/** Each verb task of the repository at `root` that does not take --dry-run, `label` naming it. */
let found = (~root, ~label): array<string> => {
  let config = Node.join([root, "mise.toml"])
  let declared = Node.existsSync(config) ? usages(Node.readFileSync(config)) : []
  let files = Layout.dryRunVerbs->Array.filterMap(verb => {
    let path = Node.join([root, ".mise", "tasks", verb])
    Node.existsSync(path) ? Some((verb, header(Node.readFileSync(path)))) : None
  })
  Array.concat(declared, files)->Array.filterMap(((verb, usage)) =>
    flag->RegExp.test(usage) ? None : Some(`${label}: the task ${verb} takes no --dry-run flag`)
  )
}

/** Every active repository's verb tasks. */
let main = (): array<string> =>
  Waiting.active()->Array.flatMap(path =>
    found(~root=Node.join([Registry.repos, path]), ~label=path)
  )
