/**
 * Clone the repositories a job's stages read beside the calling one, at its pin where it has
 * one.
 */
type tools = {
  run: (~cwd: option<string>, string, array<string>) => int,
  reference: (~root: string, ~sibling: string) => string,
}

let pinned = path => Node.existsSync(path) && /^pin =/m->RegExp.test(Node.readFileSync(path))

/** Every repository after the ones it depends on, `direct` giving each one's own dependencies. */
let dependenciesFirst = (~direct: dict<array<string>>, repositories) => {
  let rec visit = (order, trail, one) =>
    order->Array.includes(one) || trail->Array.includes(one)
      ? order
      : Array.concat(
          direct
          ->Dict.get(one)
          ->Option.getOr([])
          ->Array.reduce(order, (order, dependency) =>
            visit(order, Array.concat(trail, [one]), dependency)
          ),
          [one],
        )
  repositories->Array.reduce([], (order, one) => visit(order, [], one))
}

/**
 * The caller's [boundary] depends, transitively, then the named ones, each cloned if absent and
 * moved to the pinned commit as it is met, then every package installed dependencies first.
 */
let prepare = (~workspace, ~caller, ~beside, tools) => {
  let root = Node.join([workspace, "repos", caller])
  let declared = pinned(Node.join([root, "workspace.toml"]))
  let place = (repository, into) => {
    let clone = Node.existsSync(into)
      ? []
      : [
          (
            None,
            "git",
            ["clone", "--depth", "1", "--branch", "main", `https://github.com/${repository}`, into],
          ),
        ]
    let ref = declared ? tools.reference(~root, ~sibling=into) : "main"
    let move =
      ref == "main"
        ? []
        : [
            (Some(into), "git", ["fetch", "--depth", "1", "origin", ref]),
            (Some(into), "git", ["checkout", "--detach", "FETCH_HEAD"]),
          ]
    Array.concat(clone, move)->Array.reduce(0, (status, (cwd, command, args)) =>
      status == 0 ? tools.run(~cwd, command, args) : status
    )
  }
  let where = repository => Node.join([workspace, "repos", repository])
  let status = ref(0)
  let direct = Dict.make()
  let placed = ref([])
  let ensure = repository =>
    if status.contents == 0 && !(placed.contents->Array.includes(repository)) {
      placed := Array.concat(placed.contents, [repository])
      status := place(repository, where(repository))
    }
  let depends = one => {
    let file = Node.join([one == caller ? root : where(one), "workspace.toml"])
    let lines = switch (status.contents == 0, Node.existsSync(file)) {
    | (true, true) => Lane.dependsOf(Node.readFileSync(file))
    | _ => []
    }
    direct->Dict.set(one, lines->Array.map(((repository, _)) => repository))
    lines->Array.forEach(((repository, _)) => ensure(repository))
    lines
  }
  let boundary =
    caller == "" ? [] : Lane.boundarySiblings(~depends, caller)->Array.map(((r, _, _)) => r)
  let named = Spawn.words(Some(beside))->Array.filter(one => one != caller)
  named->Array.forEach(ensure)
  let all = Array.concat(boundary, named)
  dependenciesFirst(~direct, all)
  ->Array.filter(one => all->Array.includes(one))
  ->Array.reduce(status.contents, (status, repository) =>
    status == 0 && Node.existsSync(Node.join([where(repository), "package.json"]))
      ? tools.run(~cwd=Some(where(repository)), "pnpm", ["install", "--frozen-lockfile"])
      : status
  )
}

if Node.isMain {
  let env = name => Node.env->Dict.get(name)->Option.getOr("")
  let tools = {
    run: (~cwd, command, args) => Node.run(~cwd?, command, args),
    reference: Beside.reference,
  }
  Node.exit(
    prepare(
      ~workspace=env("GITHUB_WORKSPACE"),
      ~caller=env("CALLER"),
      ~beside=env("BESIDE"),
      tools,
    ),
  )
}
