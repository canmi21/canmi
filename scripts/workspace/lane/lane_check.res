/**
 * `lane check <part> ...`, what a seat runs of its repository's check from inside its lane, each
 * part by what it catches, `Delegation.seatParts`, docs/agents/checking.md.
 */
/** The repository holding `directory`, the nearest with a `.jj`, or none. */
let rec holder = directory =>
  if Node.existsSync(Node.join([directory, ".jj"])) {
    Some(directory)
  } else if Node.dirname(directory) == directory {
    None
  } else {
    holder(Node.dirname(directory))
  }

/** Whether jj refuses a working copy for having gone stale, from what it said. */
let staleSaid = text => text->String.includes("working copy is stale")

/** Whether a lane's working copy is stale, asked of jj itself. */
let stale = cwd => {
  let answer = Node.spawnSync("jj", ["st"], {cwd, encoding: "utf8", maxBuffer: 268435456})
  staleSaid(answer.stderr->Nullable.getOr(""))
}

/** The tasks a repository's mise.toml declares, or none. */
let tasksOf = root => {
  let file = Node.join([root, "mise.toml"])
  Node.existsSync(file)
    ? switch Toml.parse(Node.readFileSync(file)) {
      | Object(top) =>
        switch top->Dict.get("tasks") {
        | Some(Object(tasks)) => tasks->Dict.keysToArray
        | _ => []
        }
      | _ => []
      }
    : []
}

/** What a part runs in a repository, none where the repository has no such thing. */
type step = Mise(array<string>) | Names | Say(string)

let formatStep = (~tasks, ~hasRescript) =>
  if tasks->Array.includes("formatted") {
    [Mise(["run", "formatted"])]
  } else if tasks->Array.includes("verify:format") {
    [Mise(["run", "verify:format"])]
  } else if hasRescript {
    [Mise(["x", "--", "rescript", "format", "--check"])]
  } else {
    [Say("format: this repository declares no format check")]
  }

/** The steps of each part named, or the first word that is no part. */
let plan = (parts: array<string>, ~tasks, ~hasRescript, ~hasCargo) => {
  let known = Delegation.seatParts->Array.map(((name, _)) => name)
  let rec go = (rest: list<string>, steps) =>
    switch rest {
    | list{} => Ok(steps)
    | list{"tests", block, ...more} if !(known->Array.includes(block)) =>
      go(more, Array.concat(steps, [Mise(["run", "built", block])]))
    | list{"tests", ...more} =>
      go(
        more,
        Array.concat(
          steps,
          tasks->Array.includes("test")
            ? [Mise(["run", "test"])]
            : [
                Say(
                  "tests: this repository has no `test`; name the block: lane check tests <block>",
                ),
              ],
        ),
      )
    | list{"format", ...more} => go(more, Array.concat(steps, formatStep(~tasks, ~hasRescript)))
    | list{"names", ...more} => go(more, Array.concat(steps, [Names]))
    | list{"wire", ...more} =>
      go(
        more,
        Array.concat(
          steps,
          tasks->Array.includes("check")
            ? [Mise(["run", "check"])]
            : [Say("wire: this repository has no model to check")],
        ),
      )
    | list{"compile", ...more} =>
      go(
        more,
        Array.concat(
          steps,
          Array.concat(
            hasRescript ? [Mise(["x", "--", "rescript", "build"])] : [],
            hasCargo ? [Mise(["x", "--", "cargo", "check", "--workspace", "--all-targets"])] : [],
          ),
        ),
      )
    | list{word, ..._} => Error(word)
    }
  go(parts->List.fromArray, [])
}

let shown = step =>
  switch step {
  | Mise(words) => `mise ${words->Array.join(" ")}`
  | Names => "the names part over this repository"
  | Say(text) => `note: ${text}`
  }

/** The names part over `root`, the workspace's own or a repository's as the check reads it. */
let names = root => {
  let found = Node.existsSync(Node.join([root, "repos"]))
    ? Filenames.main(~root)
    : Array.concat(Filenames.names(~root), Own_name.main(~root))
  found->Array.forEach(line => Console.log(`  x ${line}`))
  found == [] ? 0 : 1
}

let run = (~root, step) =>
  switch step {
  | Mise(words) => Node.run(~cwd=root, "mise", words)
  | Names => names(root)
  | Say(text) =>
    Console.log(`note: ${text}`)
    0
  }

let usage = () => {
  Console.error(
    "usage: mise run //:lane check <part> ... [--dry-run], from inside the lane; the parts:",
  )
  Delegation.seatParts->Array.forEach(((name, catches)) => Console.error(`  ${name}: ${catches}`))
}

let main = (parts: array<string>, ~dry) => {
  let cwd = Node.env->Dict.get("MISE_ORIGINAL_CWD")->Option.getOr(Node.cwd())
  switch (parts, holder(cwd)) {
  | ([], _) =>
    usage()
    2
  | (_, None) =>
    Console.error(`${cwd} is in no repository`)
    2
  | (_, Some(root)) if !dry && stale(root) =>
    Console.error(
      `${root}: this working copy is stale, so it is not the tree you think. Stop and report to the integrator, who opens a fresh lane, lane-not-stale.`,
    )
    1
  | (_, Some(root)) =>
    let cargo = Node.join([root, "Cargo.toml"])
    switch plan(
      parts,
      ~tasks=tasksOf(root),
      ~hasRescript=Node.existsSync(Node.join([root, "rescript.json"])),
      ~hasCargo=Node.existsSync(cargo) &&
      !(Node.readFileSync(cargo)->String.includes("members = []")),
    ) {
    | Error(word) =>
      Console.error(`${word} is no part of a seat's check`)
      usage()
      2
    | Ok(steps) if dry =>
      steps->Array.forEach(step => Console.log(shown(step)))
      0
    | Ok(steps) =>
      let failed = steps->Array.filter(step => {
        Console.log(`\n=== ${shown(step)} ===`)
        run(~root, step) != 0
      })
      failed->Array.forEach(step => Console.log(`failed: ${shown(step)}`))
      failed == [] ? 0 : 1
    }
  }
}
