open Testing

let found = (lane, rel): Lane_state.found => {lane, rel, path: `/base/lanes/${lane}/${rel}`}

describe("the lanes on disk", () => {
  test("are found down their directories to each jj workspace", () => {
    let tree = Dict.fromArray([
      ("/base/lanes/a", ["monoflake", "stray"]),
      ("/base/lanes/a/monoflake", ["platform"]),
      ("/base/lanes/b", ["canmi"]),
    ])
    let subdirs = dir => tree->Dict.get(dir)->Option.getOr([])
    let isWorkspace = dir => dir->String.endsWith("platform") || dir->String.endsWith("canmi")
    let in_ = lane => Lane_state.workspacesOf(~root="/base", ~subdirs, ~isWorkspace, lane)
    expect(in_("a")->Array.map(one => one.rel))->toEqual(["monoflake/platform"])
    expect(in_("b")->Array.map(one => one.rel))->toEqual(["canmi"])
  })

  test("warn of a lane with no workspace and a path that names no repository", () => {
    expect(
      Lane_state.layout(
        ~registered=["monoflake/platform"],
        ~lanesNamed=["a", "b", "c"],
        [found("a", "canmi"), found("b", "monoflake/platform"), found("b", "workspace")],
      ),
    )->toEqual([
      "lanes/c holds no jj workspace",
      "lanes/b/workspace is neither canmi nor a registered repository's path",
    ])
  })

  test("warn of a target past the limit and none under it", () => {
    let sizeKb = dir => dir->String.includes("/big/") ? 12 * 1048576 : 1048576
    expect(
      Lane_state.heavy(~sizeKb, ~limit=10, [found("big", "canmi"), found("small", "canmi")]),
    )->toEqual(["lanes/big/canmi/target holds 12.0 gigabytes, past 10; cargo clean clears it"])
  })

  test("must have the lane task, the friction task and the docs naming their verbs", () => {
    let good = "[tasks.lane]\n[tasks.friction]"
    let lanes = "mise run lane open and mise run lane close"
    expect(Lane_state.declared(~mise=good, ~lanes, ~friction="mise run friction"))->toEqual([])
    expect(Lane_state.declared(~mise="", ~lanes="", ~friction=""))->toEqual([
      "mise.toml declares no [tasks.lane]",
      "mise.toml declares no [tasks.friction]",
      "the lanes doc does not name `mise run lane open`",
      "the lanes doc does not name `mise run lane close`",
      "the friction doc does not name `mise run friction`",
    ])
  })
})
