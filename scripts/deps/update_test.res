open Testing

describe("Cargo dry reports", () => {
  test("reads actual update and upgrade formats without including headings", () => {
    expect(
      Update.cargoItems("    Updating toml v0.5.10 -> v0.5.11 (available: v1.1.8)", false),
    )->toEqual([Reminder.item("package", "toml", "0.5.10", "0.5.11")])
    expect(
      Update.cargoItems(
        "name old req compatible latest new req\n==== ======= ========== ====== =======\ntoml 0.5     0.5.11     1.1.8  1.1    \n    Checking reminder-fixture's dependencies",
        true,
      ),
    )->toEqual([Reminder.item("major", "toml", "0.5", "1.1")])
    expect(Update.cargoItems("nothing moved", false))->toEqual([])
  })
})

let tools = "[env]\nX = \"1\"\n\n[tools]\nnode = \"26\"\n\"npm:cf\" = \"1.0.0-beta.29\"\n\"github:nextest-rs/nextest\" = \"0.9\"\n# a note\npython = { version = \"3.14\" }\n\n[tasks.x]\nrun = \"y\"\n"

describe("a repository's tools", () => {
  test("are read quoted or bare, each with its plain pin", () => {
    expect(Update.toolsOf(tools))->toEqual([
      ("node", "26"),
      ("npm:cf", "1.0.0-beta.29"),
      ("github:nextest-rs/nextest", "0.9"),
      ("python", ""),
    ])
  })

  test("an npm package pinned at a prerelease is the one mise cannot move", () => {
    let moved = Update.toolsOf(tools)->Array.filter(Update.npmPrerelease)
    expect(moved)->toEqual([("npm:cf", "1.0.0-beta.29")])
    expect(Update.npmPrerelease(("npm:oxlint", "1.2.0")))->toBe(false)
    expect(Update.npmPrerelease(("github:x/y", "1.0.0-rc.1")))->toBe(false)
  })

  test("a pin is written again on its own line alone", () => {
    expect(Update.repinned(tools, "npm:cf", "1.0.0-beta.30"))->toBe(
      tools->String.replace("1.0.0-beta.29", "1.0.0-beta.30"),
    )
    expect(Update.repinned("[tasks.a]\n\"npm:cf\" = \"1\"\n", "npm:cf", "2"))->toBe(
      "[tasks.a]\n\"npm:cf\" = \"1\"\n",
    )
  })
})

describe("npm's latest", () => {
  let day = Int.toFloat(Toolchain.releaseAge) *. 60000.
  let now = 1_800_000_000_000.

  test("is read with when it was published", () => {
    let answer = `{"dist-tags.latest": "1.0.0-beta.30", "time": {"1.0.0-beta.30": "2026-11-10T18:09:16.119Z"}}`
    expect(Update.viewOf(answer))->toEqual((
      "1.0.0-beta.30",
      Some(Date.fromString("2026-11-10T18:09:16.119Z")->Date.getTime),
    ))
    expect(Update.viewOf("not json"))->toEqual(("", None))
  })

  test("moves a pin once newer and old enough, waits while young, and stays otherwise", () => {
    let move = (latest, published) =>
      Update.npmMove(~pin="1.0.0-beta.29", ~latest, ~published, ~now)
    expect(move("1.0.0-beta.30", Some(now -. day)))->toEqual(Update.Moves("1.0.0-beta.30"))
    expect(move("1.0.0", Some(now -. day -. 1.)))->toEqual(Update.Moves("1.0.0"))
    expect(move("1.0.0-beta.30", Some(now -. day +. 1.)))->toEqual(Update.Young("1.0.0-beta.30"))
    expect(move("1.0.0-beta.30", None))->toEqual(Update.Young("1.0.0-beta.30"))
    expect(move("1.0.0-beta.29", Some(0.)))->toEqual(Update.Stays)
    expect(move("0.15.0", Some(0.)))->toEqual(Update.Stays)
    expect(move("", None))->toEqual(Update.Stays)
  })
})

describe("SemVer's order", () => {
  test("ranks prereleases by their parts, a release above them all", () => {
    let ordered = [
      "1.0.0-alpha",
      "1.0.0-alpha.1",
      "1.0.0-beta.2",
      "1.0.0-beta.11",
      "1.0.0",
      "1.0.1",
    ]
    expect(
      ordered->Array.toShuffled->Array.toSorted((a, b) => Int.toFloat(Update.semver(a, b))),
    )->toEqual(ordered)
    expect(Update.semver("1.0.0-beta.29", "1.0.0-beta.29"))->toBe(0)
  })
})
