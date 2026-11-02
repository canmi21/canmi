/** A repository's model/protocol/specs.json, what the shared TLC runner reads, RFC w0w82. */
exception Refused(string)

type flip = {name: string, breaks: string}

/** The step that turns TLC's output into a file a repository holds and compares. */
type export = {
  command: array<string>,
  file: string,
  inputs: array<string>,
  checks: array<string>,
  config: string,
}

type spec = {
  name: string,
  modulePath: string,
  quick: string,
  full: option<string>,
  inputs: array<string>,
  flips: array<flip>,
  temporal: array<string>,
  export: option<export>,
}

let directory = "model/protocol"
let path = `${directory}/specs.json`

let refuse = (where, what) => throw(Refused(`${path} ${where}: ${what}`))

let text = (fields: dict<JSON.t>, where, key) =>
  switch fields->Dict.get(key) {
  | Some(String(value)) => value
  | _ => refuse(where, `"${key}" must be a string`)
  }

let textOr = (fields: dict<JSON.t>, where, key, fallback) =>
  fields->Dict.get(key) == None ? fallback : text(fields, where, key)

let texts = (fields: dict<JSON.t>, where, key, ~required) =>
  switch fields->Dict.get(key) {
  | Some(Array(items)) =>
    items->Array.map(item =>
      switch item {
      | String(value) => value
      | _ => refuse(where, `"${key}" must hold strings`)
      }
    )
  | None if !required => []
  | _ => refuse(where, `"${key}" must be a list of strings`)
  }

let objects = (fields: dict<JSON.t>, where, key) =>
  switch fields->Dict.get(key) {
  | None => []
  | Some(Array(items)) =>
    items->Array.map(item =>
      switch item {
      | Object(inner) => inner
      | _ => refuse(where, `"${key}" must hold objects`)
      }
    )
  | _ => refuse(where, `"${key}" must be a list of objects`)
  }

let exportOf = (fields: dict<JSON.t>, where) =>
  switch fields->Dict.get("export") {
  | None => None
  | Some(Object(inner)) =>
    let here = `${where}.export`
    Some({
      command: texts(inner, here, "command", ~required=true),
      file: text(inner, here, "file"),
      inputs: texts(inner, here, "inputs", ~required=false),
      checks: texts(inner, here, "checks", ~required=true),
      config: textOr(inner, here, "config", "quick"),
    })
  | _ => refuse(where, `"export" must be an object`)
  }

/** The specifications a repository's manifest names. */
let parse = source => {
  let root = switch JSON.parseOrThrow(source) {
  | Object(fields) => fields
  | _ => refuse("", "must be an object")
  | exception _ => refuse("", "is not JSON")
  }
  objects(root, "", "specs")->Array.mapWithIndex((fields, index) => {
    let where = `specs[${Int.toString(index)}]`
    {
      name: text(fields, where, "name"),
      modulePath: text(fields, where, "module"),
      quick: text(fields, where, "quick"),
      full: fields->Dict.get("full") == None ? None : Some(text(fields, where, "full")),
      inputs: texts(fields, where, "inputs", ~required=false),
      flips: objects(fields, where, "switches")->Array.map(flip => {
        name: text(flip, `${where}.switches`, "name"),
        breaks: text(flip, `${where}.switches`, "breaks"),
      }),
      temporal: texts(fields, where, "temporal", ~required=false),
      export: exportOf(fields, where),
    }
  })
}
