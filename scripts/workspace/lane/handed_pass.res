/**
 * The pass `lane handed` last recorded for a lane, each workspace's working-copy commit, kept
 * beside the lane's workspaces and read by `lane take`, docs/agents/lanes.md.
 */
/** Where a lane's pass is recorded, in the lane's own directory and in no repository's tree. */
let file = (~root, name) => Node.join([Lane_state.lanes(root), name, "handed"])

/** The working-copy commit of a workspace, jj snapshotting its edits first, or why not. */
let commitOf = cwd => {
  let answer = Node.spawnSync(
    "jj",
    ["log", "-r", "@", "--no-graph", "-T", "commit_id"],
    {cwd, encoding: "utf8", maxBuffer: 268435456},
  )
  answer.status->Nullable.toOption == Some(0)
    ? Ok(answer.stdout->Nullable.getOr("")->String.trim)
    : Error(answer.stderr->Nullable.getOr("jj log failed")->String.trim)
}

/** The record's text, one workspace's path below the lane and its commit to a line. */
let // The last line names whether single-writer files were passed under `--integrator`.
written = (~integrator=false, pairs) =>
  pairs->Array.map(((rel, commit)) => `${rel} ${commit}\n`)->Array.join("") ++
    `# integrator ${integrator ? "yes" : "no"}\n`

let read = text =>
  text
  ->String.split("\n")
  ->Array.filterMap(line =>
    switch line->String.split(" ") {
    | [rel, commit] if rel != "" && commit != "" => Some((rel, commit))
    | _ => None
    }
  )

/** What the last pass recorded for lane `name`, none where no pass is recorded. */
let recorded = (~root, name) => {
  let path = file(~root, name)
  Node.existsSync(path) ? read(Node.readFileSync(path)) : []
}

/** Why one workspace may not be taken, given what was recorded and its commit now. */
let refusal = (~name, ~rel, ~recorded, present) => {
  let command = `\`mise run //:lane handed ${name}\``
  switch recorded->Array.find(((one, _)) => one == rel) {
  | Some((_, commit)) if commit == present => Ok()
  | Some(_) =>
    Error(
      `lanes/${name}/${rel} changed after its last passing ${command}, and a change after a pass needs another`,
    )
  | None =>
    Error(
      `lanes/${name}/${rel} has no passing ${command} recorded, which its seat runs before it reports`,
    )
  }
}

/** Whether a workspace of lane `name` holds what its last passing handing in judged. */
let held = (~root, ~name, ~commitOf=commitOf, one: Lane_state.found) =>
  switch commitOf(one.path) {
  | Error(why) => Error(`lanes/${name}/${one.rel}: ${why}`)
  | Ok(present) => refusal(~name, ~rel=one.rel, ~recorded=recorded(~root, name), present)
  }

/**
 * `judge` run over every workspace of a lane, any earlier pass forgotten first, and a pass recorded
 * with each commit read before judging, so an edit made meanwhile needs another pass.
 */
let judged = (
  ~root,
  ~name,
  ~commitOf=commitOf,
  ~integrator=false,
  workspaces: array<Lane_state.found>,
  judge,
) => {
  let path = file(~root, name)
  Node.rmSync(path, {recursive: false, force: true})
  let before =
    workspaces->Array.map(one => commitOf(one.path)->Result.map(commit => (one.rel, commit)))
  let status = judge()
  let pairs = before->Array.filterMap(one =>
    switch one {
    | Ok(pair) => Some(pair)
    | Error(_) => None
    }
  )
  let unread = before->Array.filterMap(one =>
    switch one {
    | Error(why) => Some(why)
    | Ok(_) => None
    }
  )
  switch (status, unread) {
  | (0, []) =>
    Node.writeFileSync(path, written(~integrator, pairs))
    0
  | (0, _) =>
    unread->Array.forEach(why => Console.error(`lanes/${name} pass not recorded: ${why}`))
    1
  | _ => status
  }
}
