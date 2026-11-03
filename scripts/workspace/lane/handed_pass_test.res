open Testing

setConfig({"testTimeout": 30000})

let jj = (cwd, args) => ignore(Node.spawnSync("jj", args, {cwd, encoding: "utf8"}))

/** A repository at `dir` holding one file on main, its working copy a change above it. */
let repository = dir => {
  Testing.tree(dir, [(".gitignore", "lanes/\nrepos/\n"), ("a.txt", "one\n")])
  jj(dir, ["git", "init"])
  jj(dir, ["bookmark", "create", "main", "-r", "@"])
  jj(dir, ["new"])
}

/** A lane named `name` of the repository at `source`, at `rel` below the lane, one file changed. */
let laneOf = (~root, ~name, ~source, rel) => {
  let there = Node.join([Lane_state.lanes(root), name, rel])
  Node.mkdirAll(Node.dirname(there))
  jj(source, ["workspace", "add", "--name", name, "-r", "main", there])
  Node.writeFileSync(Node.join([there, "b.txt"]), "two\n")
  there
}

let workspacesOf = (~root, name) =>
  Lane_state.workspacesOf(
    ~root,
    ~subdirs=Lane_state.realSubdirs,
    ~isWorkspace=Lane_state.realIsWorkspace,
    name,
  )

let said = result =>
  switch result {
  | Ok() => ""
  | Error(why) => why
  }

describe("a lane taken only once handed in", () => {
  let base = Testing.temporaryRoot("handed-pass-")
  let build = () => {
    let root = base.contents
    repository(root)
    let lane = laneOf(~root, ~name="wave", ~source=root, "canmi")
    (root, lane)
  }
  let take = (~root, ~registered=[]) =>
    workspacesOf(~root, "wave")->Lane_take.main(
      ~root,
      ~registered,
      ~name="wave",
      ~dry=true,
      ~handed=one => Handed_pass.held(~root, ~name="wave", one),
    )
  let hand = (~root, status) =>
    Handed_pass.judged(~root, ~name="wave", workspacesOf(~root, "wave"), () => status)

  test("refuses a lane never handed in, naming the command", () => {
    let (root, _) = build()
    let one = workspacesOf(~root, "wave")->Array.getUnsafe(0)
    expect(said(Handed_pass.held(~root, ~name="wave", one)))->toContain(
      "mise run //:lane handed wave",
    )
    expect(take(~root))->toBe(1)
  })

  test("takes a lane whose last handing in passed over what it holds now", () => {
    let (root, _) = build()
    expect(hand(~root, 0))->toBe(0)
    expect(take(~root))->toBe(0)
  })

  test("refuses a lane changed after its last pass, saying it needs another", () => {
    let (root, lane) = build()
    expect(hand(~root, 0))->toBe(0)
    Node.writeFileSync(Node.join([lane, "c.txt"]), "three\n")
    let one = workspacesOf(~root, "wave")->Array.getUnsafe(0)
    expect(said(Handed_pass.held(~root, ~name="wave", one)))->toContain("changed after")
    expect(take(~root))->toBe(1)
  })

  test("refuses a lane whose last handing in failed, though an earlier one passed", () => {
    let (root, _) = build()
    expect(hand(~root, 0))->toBe(0)
    expect(hand(~root, 1))->toBe(1)
    expect(take(~root))->toBe(1)
  })

  test("judges a lane of two repositories as one, a change in either refusing it", () => {
    let (root, _) = build()
    let source = Node.join([root, "repos", "x"])
    repository(source)
    let other = laneOf(~root, ~name="wave", ~source, "x")
    expect(hand(~root, 0))->toBe(0)
    expect(take(~root, ~registered=["x"]))->toBe(0)
    Node.writeFileSync(Node.join([other, "c.txt"]), "three\n")
    expect(take(~root, ~registered=["x"]))->toBe(1)
    let held =
      workspacesOf(~root, "wave")->Array.map(
        one => (one.rel, Handed_pass.held(~root, ~name="wave", one)->Result.isOk),
      )
    expect(held)->toEqual([("canmi", true), ("x", false)])
  })

  test(
    "records nothing where a workspace could not be read, and keeps the record out of trees",
    () => {
      let (root, _) = build()
      let workspaces = workspacesOf(~root, "wave")
      let commitOf = _ => Error("unreadable")
      expect(Handed_pass.judged(~root, ~name="wave", ~commitOf, workspaces, () => 0))->toBe(1)
      expect(take(~root))->toBe(1)
      expect(hand(~root, 0))->toBe(0)
      expect(Handed_pass.file(~root, "wave")->String.startsWith(Lane_state.lanes(root)))->toBe(true)
    },
  )
})
