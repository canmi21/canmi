open Testing

let root = "/base"
let registered = [
  "monoflake/platform",
  "monoflake/driver",
  "monoflake/machine",
  "monoflake/cloud",
  "canmi/web",
]
let boundaries = Dict.fromArray([
  (
    "monoflake/cloud",
    [
      ("monoflake/driver", "monoflake/driver:driver-archive"),
      ("monoflake/driver", "monoflake/driver:driver-install"),
      ("monoflake/machine", "monoflake/machine:machine-flake"),
      ("monoflake/platform", "monoflake/platform:operator-tasks"),
    ],
  ),
  ("monoflake/driver", [("monoflake/platform", "monoflake/platform:contracts")]),
  ("monoflake/machine", [("monoflake/driver", "monoflake/driver:driver-archive")]),
])
let open_ = (~exists=_ => false, ~cloned=_ => true, ~hasPackage=_ => false, ~root=root, opened) =>
  Lane.openPlan(
    ~root,
    ~registered,
    ~cloned,
    ~exists,
    ~hasPackage,
    ~depends=one => boundaries->Dict.get(one)->Option.getOr([]),
    opened,
  )
let repositoriesOf = plan =>
  plan
  ->Result.getOr([])
  ->Array.filterMap(step =>
    switch step {
    | Lane.Run({cwd, program: "jj"}) => Some(cwd->String.replace("/base/repos/", ""))
    | _ => None
    }
  )

let found = (lane, rel): Lane_state.found => {lane, rel, path: `/base/lanes/${lane}/${rel}`}

describe("opening a lane", () => {
  test(
    "adds a jj workspace on main for the target and each sibling, and prepares platform before handing it",
    () => {
      let plan = open_(
        ~hasPackage=one => one == "monoflake/platform",
        {target: "monoflake/platform", name: "wave", siblings: ["monoflake/driver"]},
      )
      expect(plan)->toEqual(
        Ok([
          Lane.MakeDir("/base/lanes/wave/monoflake"),
          Run({
            cwd: "/base/repos/monoflake/platform",
            program: "jj",
            args: [
              "workspace",
              "add",
              "--name",
              "wave",
              "-r",
              "main",
              "/base/lanes/wave/monoflake/platform",
            ],
          }),
          Run({
            cwd: "/base/lanes/wave/monoflake/platform",
            program: "sh",
            args: [
              "-c",
              "(pnpm install --frozen-lockfile && rescript build && mise run generate) > '/base/lanes/wave/monoflake-platform-install.log' 2>&1",
            ],
          }),
          MakeDir("/base/lanes/wave/monoflake"),
          Run({
            cwd: "/base/repos/monoflake/driver",
            program: "jj",
            args: [
              "workspace",
              "add",
              "--name",
              "wave",
              "-r",
              "main",
              "/base/lanes/wave/monoflake/driver",
            ],
          }),
        ]),
      )
    },
  )

  test("puts the workspace's own lane at canmi", () => {
    switch open_({target: "workspace", name: "rules", siblings: []}) {
    | Ok([_, Run({cwd, args})]) =>
      expect(cwd)->toBe("/base")
      expect(args->Array.at(-1))->toEqual(Some("/base/lanes/rules/canmi"))
    | _ => expect("a plan")->toBe("two steps")
    }
  })

  test(
    "refuses a bad name, an existing lane, an unknown or uncloned repository, and a lane",
    () => {
      let refused = plan => plan->Result.isError
      expect(open_({target: "workspace", name: "../x", siblings: []})->refused)->toBe(true)
      expect(
        open_(~exists=_ => true, {target: "workspace", name: "x", siblings: []})->refused,
      )->toBe(true)
      expect(open_({target: "monoflake/nope", name: "x", siblings: []})->refused)->toBe(true)
      expect(
        open_(~cloned=_ => false, {target: "canmi/web", name: "x", siblings: []})->refused,
      )->toBe(true)
      expect(open_({target: "workspace", name: "x", siblings: ["canmi/web"]})->refused)->toBe(true)
      expect(
        open_(~root="/base/lanes/a/canmi", {target: "workspace", name: "x", siblings: []})->refused,
      )->toBe(true)
    },
  )
})

describe("opening a lane with its boundary", () => {
  test("puts beside cloud the three repositories it depends on", () => {
    let plan = open_({target: "monoflake/cloud", name: "w", siblings: []})
    expect(plan->repositoriesOf)->toEqual([
      "monoflake/cloud",
      "monoflake/driver",
      "monoflake/machine",
      "monoflake/platform",
    ])
  })

  test("puts platform beside driver, and generates its libraries after the install", () => {
    let plan = open_(~hasPackage=_ => true, {target: "monoflake/driver", name: "w", siblings: []})
    expect(plan->repositoriesOf)->toEqual(["monoflake/driver", "monoflake/platform"])
    let commands =
      plan
      ->Result.getOr([])
      ->Array.filterMap(
        step =>
          switch step {
          | Lane.Background({cwd, command}) => Some((cwd, command))
          | Lane.Run({cwd, program: "sh", args: [_, command]}) => Some((cwd, command))
          | _ => None
          },
      )
    expect(commands)->toEqual([
      ("/base/lanes/w/monoflake/driver", "pnpm install --frozen-lockfile"),
      (
        "/base/lanes/w/monoflake/platform",
        "(pnpm install --frozen-lockfile && rescript build && mise run generate) > '/base/lanes/w/monoflake-platform-install.log' 2>&1",
      ),
    ])
  })

  test("opens a repository with no boundary alone, platform included", () => {
    expect(open_({target: "canmi/web", name: "w", siblings: []})->repositoriesOf)->toEqual([
      "canmi/web",
    ])
    expect(
      open_({target: "monoflake/platform", name: "w", siblings: []})->repositoriesOf,
    )->toEqual(["monoflake/platform"])
  })

  test("still adds a --with the boundary does not name, without doubling one it does", () => {
    let plan = open_({
      target: "monoflake/driver",
      name: "w",
      siblings: ["canmi/web", "monoflake/platform"],
    })
    expect(plan->repositoriesOf)->toEqual(["monoflake/driver", "canmi/web", "monoflake/platform"])
  })

  test("still refuses a repository named twice", () => {
    expect(
      open_({
        target: "monoflake/driver",
        name: "w",
        siblings: ["canmi/web", "canmi/web"],
      })->Result.isError,
    )->toBe(true)
  })

  test("says in a dry run which depends line each sibling was added for", () => {
    let said =
      open_({target: "monoflake/cloud", name: "w", siblings: []})
      ->Result.getOr([])
      ->Array.map(Lane.shown)
      ->Array.filter(line => line->String.startsWith("note: "))
    expect(said)->toEqual([
      "note: monoflake/driver beside, as monoflake/cloud's boundary depends names monoflake/driver:driver-archive",
      "note: monoflake/machine beside, as monoflake/cloud's boundary depends names monoflake/machine:machine-flake",
      "note: monoflake/platform beside, as monoflake/cloud's boundary depends names monoflake/platform:operator-tasks",
    ])
  })

  test("reads the repositories out of a workspace.toml boundary", () => {
    let text = "[boundary]\nexports = []\ndepends = [\"a/b:x\", \"c/d:y\"]\n"
    expect(Lane.dependsOf(text))->toEqual([("a/b", "a/b:x"), ("c/d", "c/d:y")])
    expect(Lane.dependsOf("[format]\nx = 1\n"))->toEqual([])
  })
})

describe("closing a lane", () => {
  let two = [found("wave", "monoflake/platform"), found("wave", "monoflake/driver")]
  let plan = Lane.closePlan(~root, ~registered, ~hasCargo=_ => true, ~name="wave", two)

  let guard = repo =>
    `(in /base/lanes/wave/monoflake/${repo}) refuse if jj log -r 'main..@ ~ empty()' ` ++
    `lists a change, lanes/wave/monoflake/${repo}`
  let lengths = repo =>
    `(in /base/lanes/wave/monoflake/${repo}) judge the files changed from main, lengths`
  test("snapshots and judges every working copy before it forgets any", () => {
    let steps = plan->Result.getOr([])
    let guards = steps->Array.filterMap(
      step =>
        switch step {
        | Lane.Guard(_) => Some(true)
        | _ => None
        },
    )
    expect(guards->Array.length)->toBe(2)
    expect(steps->Array.slice(~start=0, ~end=6)->Array.map(Lane.shown))->toEqual([
      lengths("platform"),
      "(in /base/lanes/wave/monoflake/platform) jj st",
      guard("platform"),
      lengths("driver"),
      "(in /base/lanes/wave/monoflake/driver) jj st",
      guard("driver"),
    ])
  })

  test("then forgets, cleans cargo, removes node_modules and the directory", () => {
    let shown = plan->Result.getOr([])->Array.map(Lane.shown)
    expect(shown->Array.slice(~start=6, ~end=9))->toEqual([
      "(in /base/repos/monoflake/platform) jj workspace forget wave",
      "(in /base/lanes/wave/monoflake/platform) cargo clean",
      "remove /base/lanes/wave/monoflake/platform/node_modules",
    ])
    expect(shown->Array.at(-1))->toEqual(Some("remove /base/lanes/wave"))
  })

  test("refuses a lane run from a lane, a bad name, none found and a stray path", () => {
    let close = (~root=root, ~name="wave", workspaces) =>
      Lane.closePlan(~root, ~registered, ~hasCargo=_ => false, ~name, workspaces)->Result.isError
    expect(close(~root="/base/lanes/a/canmi", two))->toBe(true)
    expect(close(~name="..", two))->toBe(true)
    expect(close([]))->toBe(true)
    expect(close([found("wave", "workspace")]))->toBe(true)
  })

  test("removes nothing outside lanes/", () => {
    expect(Lane.perform(~root, Remove("/base/repos/x"))->Result.isError)->toBe(true)
    expect(Lane.perform(~root, Remove("/base/lanes"))->Result.isError)->toBe(true)
  })
})

describe("handing a lane in", () => {
  let two = [found("wave", "monoflake/platform"), found("wave", "monoflake/driver")]
  let plan = (~root=root, ~name="wave", workspaces) =>
    Lane.handedPlan(~root, ~registered, ~own=[], ~name, workspaces)

  test("judges every workspace of the lane by every rule", () => {
    expect(plan(two)->Result.getOr([])->Array.map(Lane.shown))->toEqual([
      "(in /base/lanes/wave/monoflake/platform) judge the files changed from main, every rule",
      "(in /base/lanes/wave/monoflake/driver) judge the files changed from main, every rule",
    ])
  })

  test("finds the base workspace from inside a lane, and a base as itself", () => {
    expect(Lane.baseOf("/base/lanes/wave/canmi"))->toBe("/base")
    expect(Lane.baseOf("/base/lanes/wave/monoflake/platform"))->toBe("/base")
    expect(Lane.baseOf("/base"))->toBe("/base")
    expect(plan(~root=Lane.baseOf("/base/lanes/wave/canmi"), two)->Result.isOk)->toBe(true)
  })

  test("refuses a lane run from a lane, a bad name, none found and a stray path", () => {
    expect(plan(~root="/base/lanes/a/canmi", two)->Result.isError)->toBe(true)
    expect(plan(~name="..", two)->Result.isError)->toBe(true)
    expect(plan([])->Result.isError)->toBe(true)
    expect(plan([found("wave", "workspace")])->Result.isError)->toBe(true)
  })
})

describe("the arguments of lane", () => {
  test("keep the words, the siblings given with --with and the dry run apart", () => {
    expect(Lane.parse(["open", "a", "b", "--with", "c", "-n", "--with", "d"]))->toEqual((
      ["open", "a", "b"],
      ["c", "d"],
      [],
      true,
    ))
  })

  test("keep the directories given with --own", () => {
    expect(Lane.parse(["handed", "a", "--own", "x/y", "--own", "z"]))->toEqual((
      ["handed", "a"],
      [],
      ["x/y", "z"],
      false,
    ))
  })
})

describe("a real lane", () => {
  let base = Testing.temporaryRoot("lane-")
  test("is refused its close while a working copy holds a change not in main", () => {
    let repo = Node.join([base.contents, "repo"])
    let jj = args => Node.spawnSync("jj", args, {cwd: repo, encoding: "utf8"})
    Testing.tree(base.contents, [("repo/a.txt", "one")])
    ignore(Node.spawnSync("jj", ["git", "init", repo], {encoding: "utf8"}))
    ignore(jj(["bookmark", "create", "main", "-r", "@"]))
    expect(Lane.unlandedIn(repo))->toEqual(Ok(""))
    ignore(jj(["new", "-m", "feat: x"]))
    Node.writeFileSync(Node.join([repo, "b.txt"]), "two")
    expect(Lane.unlandedIn(repo)->Result.getOr("")->String.includes("feat: x"))->toBe(true)
  })

  test("passes a change main holds by content under another commit, or moved on since", () => {
    let repo = Node.join([base.contents, "held"])
    let jj = args => Node.spawnSync("jj", args, {cwd: repo, encoding: "utf8"})
    Testing.tree(base.contents, [("held/a.txt", "one"), ("held/c.txt", "one")])
    ignore(Node.spawnSync("jj", ["git", "init", repo], {encoding: "utf8"}))
    ignore(jj(["bookmark", "create", "main", "-r", "@"]))
    ignore(jj(["new", "-m", "feat: lane"]))
    Node.writeFileSync(Node.join([repo, "b.txt"]), "two")
    Node.writeFileSync(Node.join([repo, "c.txt"]), "lane")
    ignore(jj(["bookmark", "create", "lane", "-r", "@"]))
    ignore(jj(["new", "main", "-m", "feat: landed by path"]))
    Node.writeFileSync(Node.join([repo, "b.txt"]), "two")
    Node.writeFileSync(Node.join([repo, "c.txt"]), "later")
    ignore(jj(["bookmark", "set", "main", "-r", "@"]))
    ignore(jj(["new", "lane"]))
    expect(Lane.unlandedIn(repo))->toEqual(Ok(""))
  })

  test("refuses a change main lacks even when main moved on elsewhere", () => {
    let repo = Node.join([base.contents, "lacks"])
    let jj = args => Node.spawnSync("jj", args, {cwd: repo, encoding: "utf8"})
    Testing.tree(base.contents, [("lacks/a.txt", "one")])
    ignore(Node.spawnSync("jj", ["git", "init", repo], {encoding: "utf8"}))
    ignore(jj(["bookmark", "create", "main", "-r", "@"]))
    ignore(jj(["new", "-m", "feat: lane"]))
    Node.writeFileSync(Node.join([repo, "b.txt"]), "two")
    ignore(jj(["bookmark", "create", "lane", "-r", "@"]))
    ignore(jj(["new", "main", "-m", "feat: other"]))
    Node.writeFileSync(Node.join([repo, "a.txt"]), "elsewhere")
    ignore(jj(["bookmark", "set", "main", "-r", "@"]))
    ignore(jj(["new", "lane"]))
    expect(Lane.unlandedIn(repo)->Result.getOr("")->String.includes("feat: lane"))->toBe(true)
  })

  test("names the paths a main that neither equals nor moved lacks", () => {
    expect(Lane.notHeld(~touched=["a", "b", "c"], ~differ=["a", "b"], ~moved=["b"]))->toEqual(["a"])
  })
})

describe("closing every half of a real lane", () => {
  setConfig({"testTimeout": 30000})
  let base = Testing.temporaryRoot("lane-close-")
  let command = (cwd, args) => {
    let answer = Node.spawnSync("jj", args, {cwd, encoding: "utf8"})
    expectAs(answer.status->Nullable.toOption, answer.stderr->Nullable.getOr(""))->toEqual(Some(0))
  }
  let build = () => {
    let root = base.contents
    let halves = ["first", "second"]->Array.map(rel => {
      let source = Node.join([root, "repos", rel])
      Testing.tree(source, [("a.txt", "one\n")])
      command(source, ["git", "init"])
      command(source, ["bookmark", "create", "main", "-r", "@"])
      command(source, ["new"])
      let path = Node.join([root, "lanes", "wave", rel])
      Node.mkdirAll(Node.dirname(path))
      command(source, ["workspace", "add", "--name", "wave", "-r", "main", path])
      {Lane_state.lane: "wave", rel, path}
    })
    (root, halves)
  }
  let closed = (root, rel) => Lane.closedIn(~name="wave", Node.join([root, "repos", rel]))
  let close = (root, halves) =>
    Lane.closePlan(
      ~root,
      ~registered=["first", "second"],
      ~hasCargo=_ => false,
      ~closed=cwd => Lane.closedIn(~name="wave", cwd),
      ~name="wave",
      halves,
    )->Result.flatMap(steps => Lane.execute(~root, steps))

  test("forgets neither half when the second half refuses", () => {
    let (root, halves) = build()
    let second = halves->Array.getUnsafe(1)
    Node.writeFileSync(Node.join([second.path, "b.txt"]), "unlanded\n")
    switch close(root, halves) {
    | Error(why) => expect(why)->toContain("lanes/wave/second holds changes not in main")
    | Ok() => expect("closed")->toBe("refused")
    }
    expect(closed(root, "first"))->toEqual(Ok(false))
    expect(closed(root, "second"))->toEqual(Ok(false))
    expect(Node.readFileSync(Node.join([second.path, "b.txt"])))->toBe("unlanded\n")
    expect(Node.existsSync(Node.join([root, "lanes", "wave"])))->toBe(true)
  })

  test("forgets both halves only after both pass", () => {
    let (root, halves) = build()
    expect(close(root, halves))->toEqual(Ok())
    expect(closed(root, "first"))->toEqual(Ok(true))
    expect(closed(root, "second"))->toEqual(Ok(true))
    expect(Node.existsSync(Node.join([root, "lanes", "wave"])))->toBe(false)
  })

  test("passes over an already forgotten half and closes the remaining half", () => {
    let (root, halves) = build()
    command(Node.join([root, "repos", "first"]), ["workspace", "forget", "wave"])
    expect(closed(root, "first"))->toEqual(Ok(true))
    expect(close(root, halves))->toEqual(Ok())
    expect(closed(root, "second"))->toEqual(Ok(true))
    expect(Node.existsSync(Node.join([root, "lanes", "wave"])))->toBe(false)
  })
})
