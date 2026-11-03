open Testing

let asked: Land.asked = {
  repository: "monoflake/driver",
  subject: "test: nothing",
  trailers: [],
  paths: [],
  thread: None,
  dry: false,
}

describe("landing a working copy", () => {
  test("parses a full line", () => {
    expect(
      Land.parse([
        "monoflake/driver",
        "-m",
        "test: nothing",
        "--trailer",
        "A: b",
        "--trailer",
        "C: d",
        "--paths",
        "x",
        "--thread",
        "fifth",
        "--dry-run",
      ]),
    )->toEqual(
      Ok({...asked, trailers: ["A: b", "C: d"], paths: ["x"], thread: Some("fifth"), dry: true}),
    )
  })
  test("refuses a missing subject", () => {
    expect(
      switch Land.parse(["workspace"]) {
      | Error(why) => why->String.includes("land <name> -m <subject>")
      | _ => false
      },
    )->toBe(true)
  })
  test("refuses an unknown flag", () => {
    expect(
      switch Land.parse(["workspace", "-m", "test: nothing", "--unknown"]) {
      | Error(why) => why->String.includes("land <name> -m <subject>")
      | _ => false
      },
    )->toBe(true)
  })
  test("takes every path before the next flag", () => {
    expect(
      Land.parse(["monoflake/driver", "-m", "test: nothing", "--paths", "a", "b", "--dry-run"]),
    )->toEqual(Ok({...asked, paths: ["a", "b"], dry: true}))
  })
  test("keeps two trailers in the commit message", () => {
    expect(Land.command({...asked, trailers: ["A: b", "C: d"], paths: ["x"]}, Commit))->toEqual((
      "jj",
      [
        "-R",
        "repos/monoflake/driver",
        "commit",
        "-m",
        "test: nothing\n\nA: b\nC: d",
        "repos/monoflake/driver/x",
      ],
    ))
  })
  test("uses the workspace defaults", () => {
    let workspace = {...asked, repository: "workspace"}
    expect(Land.command(workspace, Format))->toEqual(("mise", ["run", "fmt"]))
    expect(Land.command(workspace, Bump))->toEqual(("mise", ["run", "bump"]))
    expect(Land.command(workspace, Check))->toEqual(("mise", ["run", "check"]))
    expect(Land.command(workspace, PushDry))->toEqual(("mise", ["run", "push", "--dry-run"]))
    expect(Land.command(workspace, Push))->toEqual(("mise", ["run", "push"]))
    expect(Land.command(workspace, Bookmark))->toEqual((
      "jj",
      ["-R", ".", "bookmark", "move", "main", "--to", "@-"],
    ))
  })
  test("passes over recording without a thread", () => {
    expect(Land.command(asked, Record))->toEqual(("", []))
  })
})
