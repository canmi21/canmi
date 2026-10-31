/**
 * The stages of a repository's scheduled update in CI, one per workflow step, so the same entry
 * runs on the Mac. See docs/ci.md.
 */
@module("node:fs") external appendFileSync: (string, string) => unit = "appendFileSync"

let root = Node.resolve([Node.dirname(Node.fileURLToPath(Node.importMetaUrl)), "..", ".."])

/** The repository's directory, the workspace itself for an empty path. */
let place = path => path == "" ? root : Node.join([root, "repos", path])

let usage = "scheduled beside <repositories> | colocate <path> | update <path> | moved <path> | message <path> <file> | commit <path> <file> | held <names>"

let fail = why => {
  Console.error(`scheduled: ${why}`)
  Node.exit(1)
}

/** A value handed to the next step, where GitHub reads them, or shown on the Mac. */
let output = (key, value) =>
  switch Node.env->Dict.get("GITHUB_OUTPUT") {
  | Some(file) if file != "" => appendFileSync(file, `${key}=${value}\n`)
  | _ => Console.log(`${key}=${value}`)
  }

let ran = (~cwd, command, args) => {
  let status = Node.run(~cwd, command, args)
  if status != 0 {
    fail(`${command} ${args->Array.join(" ")} exited ${Int.toString(status)}`)
  }
}

/** Another repository a check reads, cloned at its main beside this one, as at home. */
let beside = repositories =>
  repositories->Array.forEach(repository => {
    let into = place(repository)
    if !Node.existsSync(into) {
      ran(
        ~cwd=root,
        "git",
        ["clone", "--depth", "1", "--branch", "main", `https://github.com/${repository}`, into],
      )
    }
  })

/** jj beside git in the workspace and the repository, as update snapshots and restores by jj. */
let colocate = path =>
  (path == "" ? [root] : [root, place(path)])
  ->Array.filter(dir => !Node.existsSync(Node.join([dir, ".jj"])))
  ->Array.forEach(dir => ran(~cwd=dir, "jj", ["git", "init", "--colocate"]))

let heldSources = out =>
  out
  ->String.split("\n")
  ->Array.flatMap(line =>
    /^warning: \S+ holds back its pins from (.+), whose releases/
    ->RegExp.exec(line)
    ->Option.flatMap(r => r->RegExp.Result.matches->Array.get(0)->Option.flatMap(x => x))
    ->Option.mapOr([], sources => sources->String.split(", "))
  )
  ->Array.reduce([], (kept, source) => kept->Array.includes(source) ? kept : [...kept, source])

/** Porcelain with NUL separators puts a rename's destination before its original path. */
let changedPaths = status => {
  let original = ref(false)
  status
  ->String.split("\x00")
  ->Array.filterMap(entry =>
    if original.contents {
      original := false
      None
    } else if String.length(entry) > 3 {
      let state = entry->String.slice(~start=0, ~end=2)
      original := state->String.includes("R") || state->String.includes("C")
      Some(entry->String.slice(~start=3))
    } else {
      None
    }
  )
}

let update = async path => {
  let (status, out) = await Node.stream(
    ~cwd=root,
    "mise",
    ["run", "update", ...path == "" ? [] : [path]],
  )
  let held = heldSources(out)
  output("held", held->Array.join(", "))
  if status != 0 {
    fail(`update exited ${Int.toString(status)}, so nothing is committed`)
  }
}

let changed = path =>
  Node.execFileSync(
    "git",
    ["status", "--porcelain", "-z", "--untracked-files=all"],
    {cwd: place(path), encoding: "utf8"},
  )->changedPaths

let moved = path => output("moved", changed(path) == [] ? "false" : "true")

let message = (path, file) => {
  let dir = place(path)
  let texts = changed(path)->Array.map(changedPath => {
    let shown = Node.spawnSync("git", ["show", `HEAD:${changedPath}`], {cwd: dir, encoding: "utf8"})
    let old = shown.status == Nullable.make(0) ? shown.stdout->Nullable.getOr("") : ""
    let full = Node.join([dir, changedPath])
    (changedPath, old, Node.existsSync(full) ? Node.readFileSync(full) : "")
  })
  Node.writeFileSync(file, Message.message(texts))
}

/** What moved, committed by the Actions bot and pushed straight to main, with no pull request. */
let commit = (path, file) => {
  let cwd = place(path)
  ran(~cwd, "git", ["config", "user.name", "github-actions[bot]"])
  ran(
    ~cwd,
    "git",
    ["config", "user.email", "41898282+github-actions[bot]@users.noreply.github.com"],
  )
  ran(~cwd, "git", ["add", "--all"])
  ran(~cwd, "git", ["commit", "--file", file])
  ran(~cwd, "git", ["push", "origin", "HEAD:main"])
}

let main = async () =>
  switch Node.args() {
  | ["beside", repositories] => beside(repositories->String.split(" ")->Array.filter(r => r != ""))
  | ["colocate", path] => colocate(path)
  | ["update", path] => await update(path)
  | ["moved", path] => moved(path)
  | ["message", path, file] => message(path, file)
  | ["commit", path, file] => commit(path, file)
  | ["held", names] if names != "" =>
    Console.log(
      `::error::the releases of ${names} could not be read, so their pins were kept as they were`,
    )
    Node.exit(1)
  | ["held", _] => ()
  | _ => fail(usage)
  }

if Node.isMain {
  await main()
}
