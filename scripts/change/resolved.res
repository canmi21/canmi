/**
 * What each crate is built from beyond its repository's files, its resolved packages and what it
 * inherits from the root Cargo.toml, read at two revisions. Read by deployable.res.
 */
/** The profile every image is built with, `cargo build --profile container` in each Dockerfile. */
let imageProfile = "container"

/** The targets every image is built for, `$arch-unknown-linux-musl` in each Dockerfile. */
let targets = ["aarch64-unknown-linux-musl", "x86_64-unknown-linux-musl"]

/**
 * Parts of `[workspace]` no image is built from as such; each is read apart, or changes no output.
 */
let unbuilt = ["members", "exclude", "default-members", "lints", "metadata"]

type table = Dict.t<JSON.t>

/** `value` as a table, or an empty one where it is none. */
let tableOf = (value: option<JSON.t>): table =>
  switch value {
  | Some(Object(table)) => table
  | _ => Dict.make()
  }

let textOf = (table: table, key) =>
  switch table->Dict.get(key) {
  | Some(String(value)) => Some(value)
  | _ => None
  }

type package = {
  name: string,
  version: string,
  source: option<string>,
  checksum: option<string>,
  dependencies: array<string>,
}

let parens = /^[()]+|[()]+$/g

/** Two sets holding the same members. */
let equal = (a: Set.t<string>, b: Set.t<string>) =>
  a->Set.size == b->Set.size && a->Graph.setValues->Array.every(one => b->Set.has(one))

/**
 * Crate -> every package it reaches in the lockfile `lock`, itself included, each as its name,
 * version, source and checksum; None for a crate the lockfile does not hold.
 */
let closures = (lock: string, crates: array<string>): Map.t<string, option<Set.t<string>>> => {
  let byName: Map.t<string, array<package>> = Map.make()
  switch Toml.parse(lock) {
  | Object(data) =>
    switch data->Dict.get("package") {
    | Some(Array(packages)) =>
      packages->Array.forEach(one => {
        let one = tableOf(Some(one))
        let name = one->textOf("name")->Option.getOr("")
        let package = {
          name,
          version: one->textOf("version")->Option.getOr(""),
          source: one->textOf("source"),
          checksum: one->textOf("checksum"),
          dependencies: switch one->Dict.get("dependencies") {
          | Some(Array(dependencies)) =>
            dependencies->Array.filterMap(dependency =>
              switch dependency {
              | String(dependency) => Some(dependency)
              | _ => None
              }
            )
          | _ => []
          },
        }
        byName->Map.set(name, Array.concat(byName->Map.get(name)->Option.getOr([]), [package]))
      })
    | _ => ()
    }
  | _ => ()
  }

  // `name`, `name version` or `name version (source)`, as much as tells it apart.
  let resolve = (reference: string): array<package> => {
    let parts = reference->String.split(" ")
    let name = parts[0]->Option.getOr("")
    let rest = parts->Array.slice(~start=1)
    let tail =
      rest->Array.length > 1
        ? [rest->Array.getUnsafe(0), rest->Array.slice(~start=1)->Array.join(" ")]
        : rest
    let found = byName->Map.get(name)->Option.getOr([])
    let found = switch tail[0] {
    | Some(version) => found->Array.filter(one => one.version == version)
    | None => found
    }
    switch tail[1] {
    | Some(source) =>
      let source = source->String.replaceRegExp(parens, "")
      found->Array.filter(one => one.source == Some(source))
    | None => found
    }
  }

  let key = (one: package) =>
    [
      one.name,
      one.version,
      one.source->Option.getOr(""),
      one.checksum->Option.getOr(""),
    ]->Array.join("\x00")

  crates
  ->Array.map(crate => {
    let queue = byName->Map.get(crate)->Option.getOr([])->Array.filter(one => one.source == None)
    let seen = Set.make()
    while queue->Array.length > 0 {
      let one = queue->Array.pop->Option.getOrThrow
      if !(seen->Set.has(key(one))) {
        seen->Set.add(key(one))
        one.dependencies->Array.forEach(reference => queue->Array.pushMany(resolve(reference)))
      }
    }
    (crate, seen->Set.size > 0 ? Some(seen) : None)
  })
  ->Map.fromArray
}

/** The crates of `crates` whose packages differ between the two lockfiles. */
let lockMoved = (base: string, head: string, crates: Set.t<string>): Set.t<string> => {
  let all = crates->Graph.setValues
  let before = closures(base, all)
  let after = closures(head, all)
  all
  ->Array.filter(crate =>
    switch (
      before->Map.get(crate)->Option.flatMap(x => x),
      after->Map.get(crate)->Option.flatMap(x => x),
    ) {
    | (Some(was), Some(now)) => !equal(was, now)
    | (None, None) => false
    | _ => true
    }
  )
  ->Set.fromArray
}

/**
 * What `cargo build -p crate` compiles for an image in `tree`, each package with its features and
 * with paths made relative to the tree; None where cargo cannot say.
 */
let builtFrom = (tree: string, crate: string, cwd: string): option<Set.t<string>> => {
  let root = Node.realpathSync(tree)
  let command =
    [
      ["tree", "--locked", "--manifest-path", `${root}/Cargo.toml`, "-p", crate],
      ["-e", "normal,build", "--prefix", "none", "--format", "{p} {f}"],
      targets->Array.flatMap(target => ["--target", target]),
    ]->Array.flat
  let answer = Node.spawnSync("cargo", command, {cwd, encoding: "utf8", maxBuffer: 67108864})
  if answer.status != Nullable.make(0) {
    None
  } else {
    let lines = answer.stdout->Nullable.getOr("")->String.split("\n")
    if lines->Array.at(-1) == Some("") {
      lines->Array.pop->ignore
    }
    Some(
      lines
      ->Array.map(line => line->String.replaceAll(" (*)", "")->String.replaceAll(root, ""))
      ->Set.fromArray,
    )
  }
}

/**
 * The crates cargo builds from something else in `head` than in `base`; any it cannot read moved.
 */
let treeMoved = (base: string, head: string, crates: array<string>, cwd: string): Set.t<string> =>
  crates
  ->Array.filter(crate =>
    switch builtFrom(base, crate, cwd) {
    | None => true
    | Some(before) =>
      switch builtFrom(head, crate, cwd) {
      | None => true
      | Some(after) => !equal(before, after)
      }
    }
  )
  ->Set.fromArray

/** The profiles an image's build reads, following `inherits` from the image's own. */
let profiles = (manifest: table) => {
  let declared = tableOf(manifest->Dict.get("profile"))
  let chain = Set.fromArray(["release"])
  let name = ref(Some(imageProfile))
  let continue = ref(true)
  while continue.contents {
    switch name.contents {
    | Some(one) if one != "" && !(chain->Set.has(one)) =>
      chain->Set.add(one)
      name := tableOf(declared->Dict.get(one))->textOf("inherits")
    | _ => continue := false
    }
  }
  chain
}

/** Whether `member` takes `key` of `[workspace.<table>]` with `workspace = true`. */
let inherits = (member: table, table: string, key: string): bool =>
  if table == "package" {
    Node.isDeepStrictEqual(
      tableOf(member->Dict.get("package"))->Dict.get(key),
      Some(JSON.Object(Dict.fromArray([("workspace", JSON.Boolean(true))]))),
    )
  } else {
    let sections = Array.concat(
      [member],
      tableOf(member->Dict.get("target"))->Dict.valuesToArray->Array.map(one => tableOf(Some(one))),
    )
    sections->Array.some(section =>
      ["dependencies", "dev-dependencies", "build-dependencies"]->Array.some(kind =>
        tableOf(tableOf(section->Dict.get(kind))->Dict.get(key))->Dict.get("workspace") ==
          Some(JSON.Boolean(true))
      )
    )
  }

/** Whether any entry under `value` names a `path`. */
let rec hasPath = (value: JSON.t): bool =>
  switch value {
  | Object(table) if !Toml.isDate(value) =>
    table->Dict.get("path")->Option.isSome || table->Dict.valuesToArray->Array.some(hasPath)
  | _ => false
  }

let differ = (a, b) => !Node.isDeepStrictEqual(a, b)

/** `value`, or an empty table where it is empty or false, as Python's `value or {}` reads it. */
let orEmpty = (value: option<JSON.t>): JSON.t =>
  switch value {
  | None
  | Some(Null)
  | Some(Boolean(false))
  | Some(String(""))
  | Some(Number(0.)) =>
    JSON.Object(Dict.make())
  | Some(Array([])) => JSON.Object(Dict.make())
  | Some(Object(table) as one) if !Toml.isDate(one) && table->Dict.keysToArray->Array.length == 0 =>
    JSON.Object(Dict.make())
  | Some(one) => one
  }

let keysOfBoth = (a: table, b: table) =>
  Array.concat(a->Dict.keysToArray, b->Dict.keysToArray)->Set.fromArray->Graph.setValues

exception Every

/**
 * The crates a change to the root Cargo.toml reaches, or None where it reaches every image or
 * cannot be told. `members` maps each crate to its own Cargo.toml, parsed.
 */
let manifestMoved = (base: string, head: string, members: Map.t<string, table>): option<
  Set.t<string>,
> => {
  let before = tableOf(Some(Toml.parse(base)))
  let after = tableOf(Some(Toml.parse(head)))
  let reached = Set.make()
  try {
    keysOfBoth(before, after)->Array.forEach(top => {
      let old = before->Dict.get(top)->Option.getOr(JSON.Object(Dict.make()))
      let now = after->Dict.get(top)->Option.getOr(JSON.Object(Dict.make()))
      if differ(old, now) {
        switch top {
        | "profile" =>
          let chain = Array.concat(
            profiles(before)->Graph.setValues,
            profiles(after)->Graph.setValues,
          )
          if (
            chain->Array.some(name =>
              differ(tableOf(Some(old))->Dict.get(name), tableOf(Some(now))->Dict.get(name))
            )
          ) {
            throw(Every)
          }
        // One from the registry or git moves Cargo.lock, which is read apart; a path's does not.
        | "patch" | "replace" =>
          if hasPath(old) || hasPath(now) {
            throw(Every)
          }
        | "workspace" =>
          let was = tableOf(Some(old))
          let is = tableOf(Some(now))
          keysOfBoth(was, is)->Array.forEach(part => {
            let from = orEmpty(was->Dict.get(part))
            let to = orEmpty(is->Dict.get(part))
            if differ(from, to) && !(unbuilt->Array.includes(part)) {
              if part != "dependencies" && part != "package" {
                throw(Every)
              }
              let from = tableOf(Some(from))
              let to = tableOf(Some(to))
              keysOfBoth(from, to)->Array.forEach(
                key =>
                  if differ(from->Dict.get(key), to->Dict.get(key)) {
                    members->Map.forEachWithKey(
                      (one, name) =>
                        if inherits(one, part, key) {
                          reached->Set.add(name)
                        },
                    )
                  },
              )
            }
          })
        | _ => throw(Every)
        }
      }
    })
    Some(reached)
  } catch {
  | Every => None
  }
}
