let field = (value, key) =>
  value->JSON.Decode.object->Option.flatMap(fields => fields->Dict.get(key))

let steps = value =>
  value
  ->Option.flatMap(value => field(value, "steps"))
  ->Option.flatMap(JSON.Decode.array)
  ->Option.getOr([])

let problems = (text, ~file): array<string> =>
  try {
    let document = Yaml.parse(text)
    let jobs =
      field(document, "jobs")
      ->Option.flatMap(JSON.Decode.object)
      ->Option.mapOr([], fields => fields->Dict.valuesToArray)
      ->Array.flatMap(job => steps(Some(job)))
    Array.concat(jobs, steps(field(document, "runs")))->Array.filterMap(step =>
      field(step, "name")
      ->Option.flatMap(JSON.Decode.string)
      ->Option.flatMap(name =>
        /^[a-z]/->RegExp.test(name)
          ? Some(`${file}: step name "${name}" starts with a lowercase letter`)
          : None
      )
    )
  } catch {
  | JsExn(error) => [`${file}: cannot read YAML ${error->JsExn.message->Option.getOr("")}`]
  }

let main = (~root): array<string> => {
  let rec read = directory =>
    Node.entries(Node.join([root, directory]))->Array.flatMap(entry => {
      let path = Node.join([directory, entry->Node.name])
      if entry->Node.isDirectory {
        read(path)
      } else if entry->Node.isFile && /\.ya?ml$/->RegExp.test(path) {
        problems(Node.readFileSync(Node.join([root, path])), ~file=path)
      } else {
        []
      }
    })
  Node.existsSync(Node.join([root, ".github"])) ? read(".github") : []
}
