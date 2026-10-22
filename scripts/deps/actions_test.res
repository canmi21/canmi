open Testing

let day = 24. *. 60. *. 60. *. 1000.
let now = Date.fromString("2026-10-22T00:00:00Z")->Date.getTime
let at = days => Nullable.make(Date.fromTime(now -. days *. day)->Date.toISOString)
let release = (~prerelease=false, ~draft=false, tag, days) => {
  Actions.tag,
  published: at(days),
  prerelease,
  draft,
}

describe("a pin", () => {
  let text = `jobs:
  check:
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: github/codeql-action/init@0123456789abcdef0123456789abcdef01234567 # v4.1.0
      - uses: actions/setup-node@v5
        with:
          installer-version: 2.35.3 # NixOS/nix-installer
          node-version: 24`

  test("is a uses pinned by commit or a value naming its repository, by its line", () => {
    let found = Actions.pins(text)
    expect(found->Array.map(pin => (pin.index, pin.repository, pin.current, pin.commit)))->toEqual([
      (3, "actions/checkout", "v7.0.1", true),
      (4, "github/codeql-action", "v4.1.0", true),
      (7, "NixOS/nix-installer", "2.35.3", false),
    ])
  })

  test("is written again with its release and commit, keeping the rest of its line", () => {
    let found = Actions.pins(text)
    expect(found->Array.map(pin => pin.write("v9.0.0", "f"->String.repeat(40))))->toEqual([
      `      - uses: actions/checkout@${"f"->String.repeat(40)} # v9.0.0`,
      `      - uses: github/codeql-action/init@${"f"->String.repeat(40)} # v9.0.0`,
      "          installer-version: v9.0.0 # NixOS/nix-installer",
    ])
  })

  test("keeps the spelling of its version, with its v or without", () => {
    expect(Actions.spelled("v2.36.0", "2.35.3"))->toBe("2.36.0")
    expect(Actions.spelled("2.36.0", "2.35.3"))->toBe("2.36.0")
    expect(Actions.spelled("v7.1.0", "v7.0.1"))->toBe("v7.1.0")
  })
})

describe("a plan", () => {
  test("moves to the newest release a day old within the major", () => {
    let releases = [release("v5.1.1", 30.), release("v5.2.1", 2.), release("v5.2.0", 5.)]
    expect(Actions.plan(releases, "v5.1.1", ~across=false, ~now))->toEqual({
      move: Some("v5.2.1"),
      waiting: None,
      beyond: None,
    })
  })

  test("leaves a release younger than a day waiting, and names it", () => {
    let releases = [release("v5.1.1", 30.), release("v5.2.1", 2.), release("v5.2.2", 0.5)]
    expect(Actions.plan(releases, "v5.1.1", ~across=false, ~now))->toEqual({
      move: Some("v5.2.1"),
      waiting: Some("v5.2.2"),
      beyond: None,
    })
    expect(Actions.plan([release("v5.2.2", 0.5)], "v5.2.1", ~across=false, ~now))->toEqual({
      move: None,
      waiting: Some("v5.2.2"),
      beyond: None,
    })
  })

  test("passes over a prerelease, a draft and a tag that is no version", () => {
    let releases = [
      release(~prerelease=true, "v7.2.0-rc.1", 9.),
      release(~draft=true, "v7.3.0", 9.),
      release("nightly", 9.),
      release("v7.0.1", 90.),
    ]
    expect(Actions.plan(releases, "v7.0.1", ~across=false, ~now))->toEqual({
      move: None,
      waiting: None,
      beyond: None,
    })
  })

  test("names a release past the major and crosses to it only with --major", () => {
    let releases = [release("v6.1.0", 9.), release("v7.0.1", 9.), release("v6.0.0", 90.)]
    expect(Actions.plan(releases, "v6.0.0", ~across=false, ~now))->toEqual({
      move: Some("v6.1.0"),
      waiting: None,
      beyond: Some("v7.0.1"),
    })
    expect(Actions.plan(releases, "v6.0.0", ~across=true, ~now))->toEqual({
      move: Some("v7.0.1"),
      waiting: None,
      beyond: None,
    })
  })

  test("orders by version, not by when a release came out", () => {
    let releases = [release("v7.0.1", 9.), release("v5.1.0", 3.), release("v6.1.0", 4.)]
    expect(Actions.plan(releases, "v5.0.0", ~across=false, ~now).move)->toEqual(Some("v5.1.0"))
    expect(Actions.plan(releases, "v5.0.0", ~across=true, ~now).move)->toEqual(Some("v7.0.1"))
  })
})
