/**
 * Every credential name of the workspace and the monoflake repositories against the table in
 * model/rules/credentials.res, docs/naming.md.
 */
type source =
  | Key
  | Reference

type found = {file: string, name: string, source: source}

let reference = /\bsecrets\.([A-Za-z_][A-Za-z0-9_]*)/g

/** The names one tree holds, a secrets.json's keys alone and a workflow's secrets.NAME. */
let read = (tree: Lines.tree, ~label): array<found> =>
  tree.paths->Array.flatMap(path => {
    let file = `${label}/${path}`
    if Node.basename(path) == "secrets.json" {
      tree.bytes(path)->Option.mapOr([], bytes =>
        try Node.chunkText(bytes)
        ->JSON.parseOrThrow
        ->JSON.Decode.object
        ->Option.getOr(Dict.make())
        ->Dict.keysToArray
        ->Array.filter(name => name != "sops")
        ->Array.map(name => {file, name, source: Key}) catch {
        | JsExn(_) => []
        }
      )
    } else if Runs.workflow->RegExp.test(path) || Runs.composite->RegExp.test(path) {
      tree.bytes(path)->Option.mapOr([], bytes =>
        Node.chunkText(bytes)
        ->String.match(reference)
        ->Option.getOr([])
        ->Array.filterMap(used => used)
        ->Array.map(
          used => {
            file,
            name: used->String.replace("secrets.", ""),
            source: Reference,
          },
        )
      )
    } else {
      []
    }
  })

/** What is wrong with one table entry, none where its words run subject, platform, purpose. */
let entryProblem = (entry: Credentials.t): option<string> => {
  let carried = Credentials.words(entry.variable)
  let expected = Credentials.ordered(entry)
  if (
    entry.platform == Foundation &&
      carried->Array.some(word => Credentials.platformWords->Array.includes(word))
  ) {
    Some(
      `${entry.variable} carries a platform word in the foundation, which is the default and names none`,
    )
  } else if entry.variable != expected {
    let order = entry.tied ? "vendor, platform, purpose" : "subject, platform, purpose"
    Some(`${entry.variable} breaks the order ${order}, which writes ${expected}`)
  } else {
    None
  }
}

/** The table against itself, its entries in order and no two sharing a variable or a short form. */
let tableProblems = (~table: array<Credentials.t>, ~planned): array<string> => {
  let entries = table->Array.filterMap(entryProblem)
  let repeated =
    table->Array.filterMapWithIndex((entry, at) =>
      table->Array.findIndex(other =>
        Credentials.short(other.variable) == Credentials.short(entry.variable)
      ) < at
        ? Some(`${entry.variable} shares its short form with an earlier entry`)
        : None
    )
  let unmade =
    planned->Array.filterMap(((held, becomes)) =>
      table->Array.some(entry => entry.variable == becomes)
        ? None
        : Some(`${held} is planned to become ${becomes}, which the table does not hold`)
    )
  Array.flat([entries, repeated, unmade])
}

/** The names found checked against the table, a key in either form, a workflow's as a variable. */
let problems = (~table: array<Credentials.t>, ~planned, ~supplied, names: array<found>): array<
  string,
> => {
  let variables = table->Array.map(entry => entry.variable)
  let shorts = variables->Array.map(Credentials.short)
  let held = ({name, source}) =>
    variables->Array.includes(name) ||
    planned->Array.some(((old, _)) => old == name) ||
    switch source {
    | Key => shorts->Array.includes(name)
    | Reference => supplied->Array.includes(name)
    }
  let seen = Dict.make()
  let unknown = names->Array.filterMap(found => {
    let said = `${found.file}: ${found.name} is no credential in model/rules/credentials.res`
    if held(found) || seen->Dict.get(said) != None {
      None
    } else {
      seen->Dict.set(said, true)
      Some(said)
    }
  })
  Array.concat(tableProblems(~table, ~planned), unknown)
}

/** The workspace and each repository of monoflake that is cloned. */
let trees = (~root, ~repos) => {
  let monoflake = Node.join([repos, "monoflake"])
  let cloned = Node.existsSync(monoflake)
    ? Node.entries(monoflake)
      ->Array.filter(entry => Node.isDirectory(entry))
      ->Array.map(entry => Node.join([monoflake, Node.name(entry)]))
    : []
  [root]->Array.concat(cloned)
}

let main = (~root, ~repos=Registry.repos): array<string> =>
  problems(
    ~table=Credentials.table,
    ~planned=Credentials.planned,
    ~supplied=Credentials.supplied,
    trees(~root, ~repos)->Array.flatMap(place =>
      read(Lines.disk(place), ~label=Registry.label(place))
    ),
  )
