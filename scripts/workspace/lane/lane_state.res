/** The lanes on disk under `lanes/`, and what the `lanes` and `lane-state` parts read of them. */
type found = {lane: string, rel: string, path: string}

let lanes = root => Node.join([root, "lanes"])

/** Whether a lane's path is the base workspace's one, a repository's or neither. */
let sourceOf = (~root, ~registered, rel) =>
  if rel == "canmi" {
    Some(root)
  } else if registered->Array.includes(rel) {
    Some(Node.join([root, "repos", rel]))
  } else {
    None
  }

/**
 * Each jj workspace below `dir`, found down to `depth`, `subdirs` naming the directories of one
 * and `isWorkspace` telling a workspace root.
 */
let rec find = (~subdirs, ~isWorkspace, dir, ~depth): array<string> =>
  if isWorkspace(dir) {
    [dir]
  } else if depth == 0 {
    []
  } else {
    subdirs(dir)->Array.flatMap(name =>
      find(~subdirs, ~isWorkspace, Node.join([dir, name]), ~depth=depth - 1)
    )
  }

/** The workspaces of lane `lane`, each with its path below the lane. */
let workspacesOf = (~root, ~subdirs, ~isWorkspace, lane) => {
  let base = Node.join([lanes(root), lane])
  find(~subdirs, ~isWorkspace, base, ~depth=3)->Array.map(path => {
    lane,
    rel: Node.relative(base, path),
    path,
  })
}

let realSubdirs = dir =>
  try Node.entries(dir)->Array.filter(Node.isDirectory)->Array.map(Node.name) catch {
  | _ => []
  }

let realIsWorkspace = dir => Node.existsSync(Node.join([dir, ".jj"]))

/** Every lane's name on disk, none where there is no `lanes/`. */
let names = root => realSubdirs(lanes(root))

/** Every workspace of every lane on disk. */
let all = root =>
  names(root)->Array.flatMap(lane =>
    workspacesOf(~root, ~subdirs=realSubdirs, ~isWorkspace=realIsWorkspace, lane)
  )

/** A lane holding no workspace, or one at a path that is neither `canmi` nor a registered one. */
let layout = (~registered, ~lanesNamed, workspaces: array<found>) =>
  Array.concat(
    lanesNamed
    ->Array.filter(lane => !(workspaces->Array.some(one => one.lane == lane)))
    ->Array.map(lane => `lanes/${lane} holds no jj workspace`),
    workspaces
    ->Array.filter(one => sourceOf(~root="", ~registered, one.rel) == None)
    ->Array.map(one =>
      `lanes/${one.lane}/${one.rel} is neither canmi nor a registered repository's path`
    ),
  )

let gigabytes = kilobytes => Int.toFloat(kilobytes) /. 1048576.

/** The workspaces whose `target` is past `limit` gigabytes, `sizeKb` measuring one directory. */
let heavy = (~sizeKb, ~limit, workspaces: array<found>) =>
  workspaces->Array.filterMap(one => {
    let gb = gigabytes(sizeKb(Node.join([one.path, "target"])))
    gb > Int.toFloat(limit)
      ? Some(
          `lanes/${one.lane}/${one.rel}/target holds ${Float.toFixed(
              gb,
              ~digits=1,
            )} gigabytes, past ${Int.toString(limit)}; cargo clean clears it`,
        )
      : None
  })

/** Kilobytes of a directory by du, 0 where there is none. */
let duKb = dir =>
  Node.existsSync(dir)
    ? Node.output("du", ["-sk", dir])
      ->String.split("\t")
      ->Array.get(0)
      ->Option.flatMap(text => Int.fromString(text))
      ->Option.getOr(0)
    : 0

/** What the `lanes` part reads, the two tasks declared and the docs naming their verbs. */
let declared = (~mise, ~lanes, ~friction) =>
  [
    mise->String.includes("[tasks.lane]") ? [] : ["mise.toml declares no [tasks.lane]"],
    mise->String.includes("[tasks.friction]") ? [] : ["mise.toml declares no [tasks.friction]"],
    ["mise run lane open", "mise run lane close"]->Array.filterMap(verb =>
      lanes->String.includes(verb) ? None : Some(`the lanes doc does not name \`${verb}\``)
    ),
    friction->String.includes("mise run friction")
      ? []
      : ["the friction doc does not name `mise run friction`"],
  ]->Array.flat

let held = (~root) => {
  let read = path => Node.readFileSync(Node.join(Array.concat([root], path)))
  declared(
    ~mise=read(["mise.toml"]),
    ~lanes=read(["docs", "agents", "lanes.md"]),
    ~friction=read(["docs", "agents", "friction.md"]),
  )
}

/** The warnings of the `lane-state` part, over the lanes on disk. */
let state = (~root) => {
  let workspaces = all(root)
  Array.concat(
    layout(~registered=Registry.paths(), ~lanesNamed=names(root), workspaces),
    heavy(~sizeKb=duKb, ~limit=Delegation.laneTarget, workspaces),
  )
}
