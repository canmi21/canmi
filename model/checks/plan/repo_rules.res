/**
 * A repository's own decidable rules, `model/rules.json` or `model/rules/rules.json`, read beside
 * its plan. It is plain JSON because a repository's model cannot import the workspace's. A rule
 * is a name, what it says, the doc naming it and what holds it, as Rule.t does, each name made
 * unique by the repository's path.
 */
exception Bad(string)
let bad = why => throw(Bad(why))

let file = "model/rules.json"

/** Where a repository keeps its rules, `file` or `model/rules/rules.json` where model/ is full. */
let fileAt = root => {
  let nested = "model/rules/rules.json"
  !Node.existsSync(Node.join([root, file])) && Node.existsSync(Node.join([root, nested]))
    ? nested
    : file
}

let ruleKeys = ["name", "says", "doc", "held"]

let text = (table: dict<JSON.t>, name, ~at) =>
  switch table->Dict.get(name) {
  | Some(String(found)) if found != "" => found
  | _ => bad(`${at}: ${name} is no text`)
  }

let heldOf = (table: dict<JSON.t>, ~at): Rule.held =>
  switch table->Dict.get("held") {
  | Some(Object(held)) =>
    switch held->Dict.toArray {
    | [("check", String(part))] => Check(part)
    | [("hook", String(path))] => Hook(path)
    | [("gate", String(name))] => Gate(name)
    | [("pending", String(owed))] if owed != "" => Pending(owed)
    | _ => bad(`${at}: held is not one of check, hook, gate, pending, each with a text`)
    }
  | _ => bad(`${at}: held is missing`)
  }

/** The rules of a repository's file, each name prefixed by `owner`. */
let parse = (json: string, ~owner): result<array<Rule.t>, string> =>
  try {
    let list = switch JSON.parseOrThrow(json) {
    | Array(list) => list
    | _ => bad("the rules are no list")
    }
    Ok(
      list->Array.mapWithIndex((one, index) => {
        let at = `rule ${Int.toString(index)}`
        let table = switch one {
        | Object(table) => table
        | _ => bad(`${at} is no object`)
        }
        let name = text(table, "name", ~at)
        table
        ->Dict.keysToArray
        ->Array.forEach(key =>
          if !(ruleKeys->Array.includes(key)) {
            bad(`${name}: ${key} is no key of a rule`)
          }
        )
        {
          Rule.name: `${owner}:${name}`,
          says: text(table, "says", ~at=name),
          doc: text(table, "doc", ~at=name),
          held: heldOf(table, ~at=name),
        }
      }),
    )
  } catch {
  | Bad(why) => Error(why)
  | JsExn(_) => Error("the rules are not JSON")
  }

/** Every cloned, unpaused repository's rules, and the files that cannot be read. */
let load = (): (array<(string, Rule.t)>, array<string>) => {
  let errors = []
  let found = Waiting.active()->Array.flatMap(path => {
    let root = Node.join([Registry.repos, path])
    let name = fileAt(root)
    let at = Node.join([root, name])
    if !Node.existsSync(at) {
      []
    } else {
      switch parse(Node.readFileSync(at), ~owner=path) {
      | Ok(rules) => rules->Array.map(rule => (path, rule))
      | Error(why) =>
        errors->Array.push(`rules ${path}: ${name}: ${why}`)
        []
      }
    }
  })
  (found, errors)
}
