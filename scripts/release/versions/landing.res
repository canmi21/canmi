/** What a landing changes in one repository, read by jj against the main line it lands on. */
let quiet = (~root, args) => Onset.read(~root, ["--ignore-working-copy", ...args])

/** The repository at a path of the registry, as cloned or beside a lane's own workspace. */
let place = path =>
  if path == "workspace" {
    Registry.root
  } else {
    let cloned = Node.join([Registry.repos, path])
    Registry.isRepository(cloned) ? cloned : Node.resolve([Registry.root, "..", path])
  }

let isJj = root => Node.existsSync(Node.join([root, ".jj"]))

/** The one commit a revset names, none where it names no commit or several. */
let commit = (~root, revset) =>
  switch quiet(~root, ["log", "--no-graph", "-r", revset, "-T", `commit_id ++ "\\n"`]) {
  | Some(text) =>
    switch Onset.lines(text) {
    | [one] => Some(one)
    | _ => None
    }
  | None => None
  }

/**
 * Where the working copy leaves the main line, local or remote. A working copy on the main line
 * itself lands what its parent lacks.
 */
let base = (~root) => {
  let at = Stamp.snapshot(root)
  let fork = line => commit(~root, `heads(::@ & ::${line})`)
  switch ["main", "main@origin"]->Array.findMap(fork) {
  | Some(found) if found != at => Some(found)
  | _ =>
    quiet(~root, ["log", "--no-graph", "-r", "@-", "-T", `commit_id ++ "\\n"`])
    ->Option.mapOr([], Onset.lines)
    ->Array.at(0)
  }
}

/** The paths the working copy changes from `base`, each side of a rename apart. */
let changed = (~root, ~base, ~top="@") =>
  quiet(~root, ["diff", "--from", base, "--to", top, "--summary"])
  ->Option.mapOr([], Onset.lines)
  ->Array.flatMap(Counted.summarized)

/** A file at `base`, none where it was not there. */
let at = (~root, ~base, path) =>
  quiet(~root, ["file", "show", "-r", base, `root-file:${Onset.quoted(path)}`])

let disk = (~root, path) => {
  let full = Node.join([root, path])
  Node.existsSync(full) ? Some(Node.readFileSync(full)) : None
}

let tracked = (~root, ~top="@") =>
  quiet(~root, ["file", "list", "-r", top])->Option.mapOr([], Onset.lines)

/** The first parent of `commit`, the line a landing on it left. */
let firstParent = (~root, commit) =>
  quiet(
    ~root,
    ["log", "--no-graph", "-r", commit, "-T", `parents.map(|p| p.commit_id()).join(" ")`],
  )
  ->Option.getOr("")
  ->String.trim
  ->String.split(" ")
  ->Array.at(0)
  ->Option.flatMap(parent => parent == "" ? None : Some(parent))

/** Each main line commit a push would send, oldest first, none further back. */
let outgoing = (~root) =>
  quiet(
    ~root,
    [
      "log",
      "--no-graph",
      "--reversed",
      "-r",
      `first_ancestors(main) ~ ::remote_bookmarks(exact:"main", exact:"origin") ~ root()`,
      "-T",
      `commit_id ++ "\\n"`,
    ],
  )->Option.mapOr([], Onset.lines)

let git = (~root, args) => {
  let answer = Node.spawnSync("git", args, {cwd: root, encoding: "utf8", maxBuffer: 268435456})
  answer.status == Nullable.make(0) ? Some(answer.stdout->Nullable.getOr("")) : None
}

/** A sibling's commit made readable, CI's clone beside it being one commit deep. */
let reachable = (~root, commit) =>
  git(~root, ["cat-file", "-e", `${commit}^{commit}`])->Option.isSome ||
    git(~root, ["fetch", "--quiet", "--depth", "1", "origin", commit])->Option.isSome

/** A file of a sibling at a commit, by jj, or by git where it is CI's plain clone. */
let siblingAt = (~root, ~commit, path) =>
  if isJj(root) {
    at(~root, ~base=commit, path)
  } else if reachable(~root, commit) {
    git(~root, ["show", `${commit}:${path}`])
  } else {
    None
  }

/** What a sibling's disk holds apart from `commit` in `directories`, none if it cannot tell. */
let siblingApart = (~root, ~commit, directories) =>
  if isJj(root) {
    Onset.read(
      ~root,
      [
        "diff",
        "--from",
        commit,
        "--to",
        "@",
        "--summary",
        ...directories->Array.map(directory => `root:${Onset.quoted(directory)}`),
      ],
    )->Option.map(Onset.lines)
  } else if reachable(~root, commit) {
    git(~root, ["diff", "--name-only", commit, "--", ...directories])->Option.map(Onset.lines)
  } else {
    None
  }

/** Each message from `base` to the working copy that touches `directory`. */
let messages = (~root, ~base, ~top="@", directory) =>
  quiet(
    ~root,
    [
      "log",
      "--no-graph",
      "-r",
      `${base}..${top}`,
      "-T",
      `description ++ "\\x00"`,
      ...directory == "" ? [] : [`root:${Onset.quoted(directory)}`],
    ],
  )
  ->Option.getOr("")
  ->String.split("\x00")
  ->Array.map(String.trim)
  ->Array.filter(message => message != "")

let breaking = message =>
  RegExp.test(/^[a-z]+(?:\([^\n)]+\))?!:/, message) ||
  RegExp.test(/(?:^|\n)BREAKING CHANGE: /, message)
