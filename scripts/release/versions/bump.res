/**
 * `bump [name | --all] [--dry-run] [--minor <package>]`, every package of a repository raised to
 * what a landing on its main line owes, Cargo.lock following. It writes in a main checkout alone.
 */
type request = {dry: bool, everything: bool, minors: array<string>, names: array<string>}

let usage = "usage: bump [name | --all] [--dry-run] [--minor <package>]"

let refuse = why => {
  Console.error(`bump: ${why}`)
  Node.exit(2)
}

let rec parsed = (given, request) =>
  switch given {
  | [] => request
  | _ =>
    let first = given->Array.getUnsafe(0)
    let rest = given->Array.slice(~start=1)
    switch first {
    | "-n" | "--dry-run" => parsed(rest, {...request, dry: true})
    | "-a" | "--all" => parsed(rest, {...request, everything: true})
    | "--minor" =>
      switch rest[0] {
      | Some(name) =>
        parsed(rest->Array.slice(~start=1), {...request, minors: [...request.minors, name]})
      | None => refuse(usage)
      }
    | name if !(name->String.startsWith("-")) =>
      parsed(rest, {...request, names: [...request.names, name]})
    | _ => refuse(usage)
    }
  }

/** The repositories asked for, those cloned at neither place and those paused passed over. */
let chosen = request =>
  switch (request.everything, request.names) {
  | (false, []) => ["workspace"]
  | (false, [name]) =>
    name == "workspace" || Registry.paths()->Array.includes(name)
      ? [name]
      : Registry.fail(`${name} is not in repos/registry.toml`)
  | (true, []) =>
    let (paused, rest) =
      Registry.paths()->Array.partition(path => Waiting.pauser(~repo=path)->Option.isSome)
    Console.log(`paused, passed over: ${paused->Array.join(", ")}`)
    ["workspace", ...rest]
  | _ => refuse(usage)
  }

let shown = (row: Roll.row) => {
  let version = Numbers.rolled(row.asked)
  let was = row.package.version
  let why = switch row.because {
  | [] => "starts"
  | [one] => one
  | many => `${many[0]->Option.getOr("")} and ${Int.toString(many->Array.length - 1)} more`
  }
  `  ${row.package.name}  ${Numbers.show(was)} -> ${Numbers.show(version)}  ${why}`
}

/** The rows a roll moves. */
let moving = (judged: Roll.t) =>
  judged.rows->Array.filter(row => Numbers.rolled(row.asked) != row.package.version)

/**
 * Why a sibling's crates cannot be trusted to write Cargo.lock, their disk apart from the commit
 * this repository pins, checked before any cargo write.
 */
let stale = (~root) => {
  let versions = Project.versionsAt(root)
  switch (versions.repository, versions.pin) {
  | (Some(repository), Some(pin)) =>
    let sibling = Node.resolve([root, repository])
    let crates = Packages.siblingCrates(
      ~root,
      ~sibling,
      Packages.found(~fallback="", ~read=path => Landing.disk(~root, path), Landing.tracked(~root))
      ->Pair.first
      ->Array.filter(package => package.manifests->Array.some(({kind}) => kind == Cargo))
      ->Array.map(package => package.directory),
    )
    let commit = Landing.disk(~root, pin)->Option.flatMap(text => Roll.pinned(text, repository))
    switch commit {
    | None => Some(`${pin} pins no commit of ${repository}`)
    | Some(_) if crates == [] => None
    | Some(commit) =>
      switch Landing.siblingApart(~root=sibling, ~commit, crates) {
      | None => Some(`${repository} cannot be read at ${commit}, the commit ${pin} pins`)
      | Some([]) => None
      | Some(apart) =>
        Some(
          `${repository} on disk is not at ${commit}, the commit ${pin} pins, in ${apart
            ->Array.slice(~start=0, ~end=3)
            ->Array.join(", ")}`,
        )
      }
    }
  | _ => None
  }
}

let cargoMoves = (moved: array<Roll.row>) =>
  moved->Array.filter(row => row.package.manifests->Array.some(({kind}) => kind == Cargo))

let guard = (~root, moved) => cargoMoves(moved) == [] ? None : stale(~root)

/** Everything the roll writes, Cargo.lock by text, then cargo for a sibling's crates it holds. */
let write = (~root, ~run=Node.run, moved: array<Roll.row>) => {
  switch guard(~root, moved) {
  | Some(why) =>
    Console.error(`bump: ${why}, so nothing is written`)
    false
  | None =>
    let succeeded = ref(true)
    moved->Array.forEach(row =>
      row.package.manifests->Array.forEach(manifest =>
        Node.writeFileSync(
          Node.join([root, manifest.path]),
          Packages.written(manifest, Numbers.rolled(row.asked)),
        )
      )
    )
    let lock = Node.join([root, "Cargo.lock"])
    if cargoMoves(moved) != [] && Node.existsSync(lock) {
      let crates =
        moved->Array.filterMap(row =>
          row.package.manifests->Array.some(({kind}) => kind == Cargo)
            ? Some((row.package.name, Numbers.rolled(row.asked)))
            : None
        )
      Node.writeFileSync(lock, Packages.lockFollowed(Node.readFileSync(lock), crates))
      if (
        Project.versionsAt(root).repository->Option.isSome &&
          run(~cwd=root, "cargo", ["update", "--workspace", "--offline"]) != 0
      ) {
        Console.error("bump: cargo could not bring Cargo.lock to the sibling's crates")
        succeeded := false
      }
    }
    succeeded.contents
  }
}

/** One repository's roll, its status 1 where it could not be judged. */
let one = (~request, path) => {
  let root = Landing.place(path)
  if Waiting.pauser(~repo=path)->Option.isSome {
    Console.log(`${path}: paused, passed over`)
    0
  } else if !Registry.isRepository(root) {
    Console.log(`${path}: not cloned, passed over`)
    0
  } else if !Landing.isJj(root) {
    Console.error(`bump: ${path} has no jj beside it, which a landing is read by`)
    1
  } else if !request.dry && !Form.mainCheckout(root) {
    Console.error(`bump: ${path} is a lane, and versions roll at landing on a main line`)
    1
  } else {
    let judged = Roll.planned(~root, ~minors=request.minors)
    judged.warnings->Array.forEach(line => Console.error(`bump: warning: ${path}: ${line}`))
    judged.problems->Array.forEach(line => Console.error(`bump: ${path}: ${line}`))
    let moved = moving(judged)
    if judged.packages == [] {
      Console.log(`${path}: no crate or package, passed over`)
    } else {
      Console.log(
        `${path}: ${Int.toString(moved->Array.length)} of ${Int.toString(
            judged.packages->Array.length,
          )} packages ${request.dry ? "would move" : "move"}`,
      )
      moved->Array.forEach(row => Console.log(shown(row)))
    }
    let refused = guard(~root, moved)
    refused->Option.forEach(why => Console.error(`bump: ${path}: ${why}, so nothing is written`))
    let valid = judged.problems == [] && refused->Option.isNone
    valid && (request.dry || write(~root, moved)) ? 0 : 1
  }
}

let main = () => {
  let request = parsed(Node.args(), {dry: false, everything: false, minors: [], names: []})
  let failed = chosen(request)->Array.filter(path => one(~request, path) != 0)
  if failed != [] {
    Console.error(`bump: could not roll ${failed->Array.join(", ")}`)
    Node.exit(1)
  }
}

if Node.isMain {
  try main() catch {
  | Registry.Refused(why) => refuse(why)
  }
}
