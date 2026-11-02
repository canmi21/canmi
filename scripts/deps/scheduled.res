/**
 * The stages of a repository's scheduled update, which the CI entry in .github/update/ calls, so
 * the same logic runs on the Mac. See docs/ci.md.
 */
let root = Node.resolve([Node.dirname(Node.fileURLToPath(Node.importMetaUrl)), "..", ".."])

/** The repository's directory, the workspace itself for an empty path. */
let place = path => path == "" ? root : Node.join([root, "repos", path])

/** A stage that cannot go on, its reason said by the entry that called it. */
exception Failed(string)

let ran = (~cwd, command, args) => {
  let status = Node.run(~cwd, command, args)
  if status != 0 {
    throw(Failed(`${command} ${args->Array.join(" ")} exited ${Int.toString(status)}`))
  }
}

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

/** The update's exit status and the sources whose pins it held back. */
let update = async path => {
  let (status, out) = await Node.stream(
    ~cwd=root,
    "mise",
    ["run", "update", ...path == "" ? [] : [path]],
  )
  (status, heldSources(out))
}

let changed = path =>
  Node.execFileSync(
    "git",
    ["status", "--porcelain", "-z", "--untracked-files=all"],
    {cwd: place(path), encoding: "utf8"},
  )->changedPaths

let moved = path => changed(path) != []

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
