/**
 * What a repository declares to the workspace in its root's `workspace.toml`, its layout, gates,
 * deployables and what update moves. A key the workspace does not know is refused.
 */
type table = Dict.t<JSON.t>

/** What a path under a prefix reaches that no graph shows, these packages or crates. */
type reach = {under: array<string>, packages: array<string>, crates: array<string>}

type verify = {
  always: array<string>,
  node: array<string>,
  rust: array<string>,
  tasks: array<string>,
  packages: Dict.t<array<string>>,
  nodeCheckedRust: array<string>,
  nodeRead: array<string>,
  reaches: array<reach>,
}

/** A repository's Workers, none, every one or those named. */
type workers = None | All | Only(array<string>)

type deployable = {images: bool, workers: workers}

/** The workspace's movers its update runs, besides the repository's own task. */
type update = {
  packages: bool,
  actions: bool,
  images: bool,
  /** Each manifest.toml whose manifest.lock is moved. */
  releases: array<string>,
}

/** The workspace's rules over what is inside a repository, each on unless turned off here. */
type rules = {lines: bool}

/** The id space a repository's docs/rfcs holds its RFCs in, its ids unique within it. */
type rfcs = {ids: string}

/** What scripts/release takes, `built` the path from the root to the `built.json` the repository's
 * own build writes, and `columns` the head of the notes' table its rows fill. */
type release = {built: string, columns: array<string>}

type declared = {
  /** The workspace it sits under, as that one's `.git` address. */
  base: option<string>,
  layout: Graph.layout,
  verify: option<verify>,
  deployable: option<deployable>,
  update: update,
  rules: rules,
  rfcs: option<rfcs>,
  release: option<release>,
}

exception Malformed(string)

let fail = why => throw(Malformed(why))

/** `table`'s keys, each refused unless `known` holds it. */
let only = (table: table, where, known) =>
  table
  ->Dict.keysToArray
  ->Array.forEach(key =>
    if !(known->Array.includes(key)) {
      fail(`${where}.${key}: no key the workspace reads`)
    }
  )

let tableAt = (table: table, key, where) =>
  switch table->Dict.get(key) {
  | Some(Object(found)) => Some(found)
  | None => None
  | Some(_) => fail(`${where}.${key}: not a table`)
  }

let texts = (table: table, key, where) =>
  switch table->Dict.get(key) {
  | None => []
  | Some(Array(values)) =>
    values->Array.map(value =>
      switch value {
      | String(text) => text
      | _ => fail(`${where}.${key}: not a list of text`)
      }
    )
  | Some(_) => fail(`${where}.${key}: not a list of text`)
  }

let layoutOf = (root, table: table): Graph.layout => {
  only(table, "layout", ["packages", "apps"])
  {
    root,
    packageDirectories: texts(table, "packages", "layout"),
    appRoots: switch table->Dict.get("apps") {
    | Some(String("grouped")) => Graph.groupedAppRoots(root)
    | _ => texts(table, "apps", "layout")
    },
  }
}

let verifyOf = (table: table): verify => {
  let where = "verify"
  only(
    table,
    where,
    ["always", "node", "rust", "tasks", "packages", "node-checked-rust", "node-read", "reaches"],
  )
  {
    always: texts(table, "always", where),
    node: texts(table, "node", where),
    rust: texts(table, "rust", where),
    tasks: texts(table, "tasks", where),
    packages: tableAt(table, "packages", where)
    ->Option.getOr(Dict.make())
    ->Dict.toArray
    ->Array.map(((name, _)) => (
      name,
      texts(tableAt(table, "packages", where)->Option.getOrThrow, name, "verify.packages"),
    ))
    ->Dict.fromArray,
    nodeCheckedRust: texts(table, "node-checked-rust", where),
    nodeRead: texts(table, "node-read", where),
    reaches: switch table->Dict.get("reaches") {
    | None => []
    | Some(Array(entries)) =>
      entries->Array.mapWithIndex((entry, index) => {
        let at = `verify.reaches[${Int.toString(index)}]`
        switch entry {
        | Object(entry) =>
          only(entry, at, ["under", "packages", "crates"])
          {
            under: texts(entry, "under", at),
            packages: texts(entry, "packages", at),
            crates: texts(entry, "crates", at),
          }
        | _ => fail(`${at}: not a table`)
        }
      })
    | Some(_) => fail("verify.reaches: not a list of tables")
    },
  }
}

let deployableOf = (table: table): deployable => {
  only(table, "deployable", ["images", "workers"])
  {
    images: switch table->Dict.get("images") {
    | Some(Boolean(images)) => images
    | None => false
    | Some(_) => fail("deployable.images: not true or false")
    },
    workers: switch table->Dict.get("workers") {
    | None | Some(Boolean(false)) => None
    | Some(Boolean(true)) => All
    | Some(Array(_)) => Only(texts(table, "workers", "deployable"))
    | Some(_) => fail("deployable.workers: not true, false or a list of names")
    },
  }
}

let switchOf = (table: table, key, where) =>
  switch table->Dict.get(key) {
  | None => false
  | Some(Boolean(on)) => on
  | Some(_) => fail(`${where}.${key}: not true or false`)
  }

let updateOf = (table: table): update => {
  only(table, "update", ["packages", "actions", "images", "releases"])
  {
    packages: switchOf(table, "packages", "update"),
    actions: switchOf(table, "actions", "update"),
    images: switchOf(table, "images", "update"),
    releases: texts(table, "releases", "update"),
  }
}

let rulesOf = (table: table): rules => {
  only(table, "rules", ["lines"])
  {
    lines: switch table->Dict.get("lines") {
    | None => true
    | Some(Boolean(on)) => on
    | Some(_) => fail("rules.lines: not true or false")
    },
  }
}

let rfcsOf = (table: table): rfcs => {
  only(table, "rfcs", ["ids"])
  switch table->Dict.get("ids") {
  | Some(String(ids)) if /^[a-z][a-z0-9-]*$/->RegExp.test(ids) => {ids: ids}
  | _ => fail("rfcs.ids: not an id space's name in lowercase words and hyphens")
  }
}

let releaseOf = (table: table): release => {
  only(table, "release", ["built", "columns"])
  {
    built: switch table->Dict.get("built") {
    | Some(String(path)) if path->String.endsWith(".json") => path
    | _ => fail("release.built: not the path of a .json file")
    },
    columns: switch texts(table, "columns", "release") {
    | [] => fail("release.columns: no column for the notes' table")
    | columns => columns
    },
  }
}

/** What the repository at `root` declares, or why it cannot be read. */
let read = (root: string): result<declared, string> => {
  let path = Node.join([root, "workspace.toml"])
  if !Node.existsSync(path) {
    Error(`${path}: none, which this repository's tasks need`)
  } else {
    try {
      switch Toml.parse(Node.readFileSync(path)) {
      | Object(top) =>
        only(
          top,
          "workspace.toml",
          ["base", "layout", "verify", "deployable", "update", "rules", "rfcs", "release"],
        )
        Ok({
          base: switch top->Dict.get("base") {
          | None => None
          | Some(String(address)) if address->String.endsWith(".git") => Some(address)
          | Some(_) => fail("base: not the workspace's .git address")
          },
          layout: layoutOf(
            root,
            tableAt(top, "layout", "workspace.toml")->Option.getOr(Dict.make()),
          ),
          verify: tableAt(top, "verify", "workspace.toml")->Option.map(verifyOf),
          deployable: tableAt(top, "deployable", "workspace.toml")->Option.map(deployableOf),
          update: updateOf(tableAt(top, "update", "workspace.toml")->Option.getOr(Dict.make())),
          rules: rulesOf(tableAt(top, "rules", "workspace.toml")->Option.getOr(Dict.make())),
          rfcs: tableAt(top, "rfcs", "workspace.toml")->Option.map(rfcsOf),
          release: tableAt(top, "release", "workspace.toml")->Option.map(releaseOf),
        })
      | _ => Error(`${path}: not a table`)
      }
    } catch {
    | Malformed(why) => Error(`${path}: ${why}`)
    | JsExn(error) => Error(`${path}: does not parse: ${error->JsExn.message->Option.getOr("")}`)
    }
  }
}

/** What the repository the script runs in declares, or its reason on stderr and exit 1. */
let here = (task, part: declared => option<'a>): (Graph.layout, 'a) =>
  switch read(Node.cwd()) {
  | Ok(declared) =>
    switch part(declared) {
    | Some(found) => (declared.layout, found)
    | None =>
      Console.error(`${task}: workspace.toml declares no [${task}] table`)
      Node.exit(1)
    }
  | Error(why) =>
    Console.error(`${task}: ${why}`)
    Node.exit(1)
  }

/** The layout alone, for a task that reads nothing else. */
let layout = task =>
  switch read(Node.cwd()) {
  | Ok(declared) => declared.layout
  | Error(why) =>
    Console.error(`${task}: ${why}`)
    Node.exit(1)
  }
