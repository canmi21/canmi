/**
 * Clone the repositories a job's stages read beside the calling one, at its pin where it has
 * one.
 */
type tools = {
  run: (~cwd: option<string>, string, array<string>) => int,
  reference: (~root: string, ~sibling: string) => string,
}

let pinned = path => Node.existsSync(path) && /^pin =/m->RegExp.test(Node.readFileSync(path))

/** Each repository cloned if absent, moved to the pinned commit, its packages installed. */
let prepare = (~workspace, ~caller, ~beside, tools) => {
  let root = Node.join([workspace, "repos", caller])
  let declared = pinned(Node.join([root, "workspace.toml"]))
  let steps = (repository, into) => {
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
    (clone, move)
  }
  Spawn.words(Some(beside))->Array.reduce(0, (status, repository) => {
    let into = Node.join([workspace, "repos", repository])
    let (clone, move) = steps(repository, into)
    let ran =
      Array.concat(clone, move)->Array.reduce(status, (status, (cwd, command, args)) =>
        status == 0 ? tools.run(~cwd, command, args) : status
      )
    ran == 0 && Node.existsSync(Node.join([into, "package.json"]))
      ? tools.run(~cwd=Some(into), "pnpm", ["install", "--frozen-lockfile"])
      : ran
  })
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
