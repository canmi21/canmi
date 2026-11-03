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

describe("what a landing commits and says", () => {
  test("adds to the paths given each file bump changed, and none the change held before", () => {
    expect(
      Land.raised(
        ~before=["machine/object/src/lib.rs", "notes.md"],
        ~after=["machine/object/src/lib.rs", "notes.md", "machine/object/Cargo.toml", "Cargo.lock"],
        ~paths=["machine/object/src/lib.rs"],
      ),
    )->toEqual(["machine/object/src/lib.rs", "machine/object/Cargo.toml", "Cargo.lock"])
  })

  test("returns a compile failure before thirty passing lines", () => {
    let causes = ["  We've found a bug for you!", "  scripts/example.res:12:3-8"]
    let tail = Array.fromInitializer(~length=30, index => `passing ${Int.toString(index)}`)
    let output = [...causes, "  12 | let value = missing", ...tail]->Array.join("\n")
    expect(Land.causes(output))->toEqual(causes)
  })

  test("returns the last eight marked lines", () => {
    let causes = Array.fromInitializer(~length=12, index => `error ${Int.toString(index)}`)
    let output = [...causes, "passing"]->Array.join("\n")
    expect(Land.causes(output))->toEqual(causes->Array.slice(~start=4))
  })

  test("falls back to the last eight nonempty lines without a marked cause", () => {
    let output = Array.fromInitializer(~length=12, index => `line ${Int.toString(index)}`)
    expect(Land.causes(output->Array.join("\n") ++ "\n\n"))->toEqual(output->Array.slice(~start=4))
  })

  test("strips ANSI colors before matching and returning causes", () => {
    let output = "\u001b[31merror\u001b[0m problem\n\u001b[1;31m  scripts/example.res:12:3\u001b[0m\npassing"
    expect(Land.causes(output))->toEqual(["error problem", "  scripts/example.res:12:3"])
    expect(Land.causes("\u001b[32mplain tail\u001b[0m\n\u001b[0m\n"))->toEqual(["plain tail"])
  })
})
