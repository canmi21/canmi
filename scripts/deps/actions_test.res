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

describe("a followed branch", () => {
  let commit = "0ae9cea166b8849d61ccaccfc5c73d330d4e38b9"
  let text = `      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          repository: monoflake/platform
          ref: ${commit} # monoflake/platform@main
          installer-version: 2.35.3 # NixOS/nix-installer`

  test("is a commit whose comment names a repository and its branch, and no release", () => {
    expect(
      Actions.heads(text)->Array.map(
        head => (head.index, head.repository, head.branch, head.current),
      ),
    )->toEqual([(3, "monoflake/platform", "main", commit)])
    expect(Actions.pins(text)->Array.map(pin => pin.repository))->toEqual([
      "actions/checkout",
      "NixOS/nix-installer",
    ])
  })

  test("is written again with the head's commit, keeping the rest of its line", () => {
    expect(Actions.heads(text)->Array.map(head => head.write("f"->String.repeat(40))))->toEqual([
      `          ref: ${"f"->String.repeat(40)} # monoflake/platform@main`,
    ])
  })
})

describe("the actions mover", () => {
  let root = temporaryRoot("actions-bump-")
  let script = Node.join([Node.cwd(), "scripts/deps/actions.res.mjs"])
  let pinned = "0ae9cea166b8849d61ccaccfc5c73d330d4e38b9"
  let workflow = `jobs:\n  release:\n    steps:\n      - with:\n          ref: ${pinned} # monoflake/platform@main\n`
  let run = (~driver, ~head, ~dry=false, ()) => {
    tree(
      root.contents,
      [
        (".github/workflows/release.yml", workflow),
        ("bin/gh", `#!/bin/sh\nprintf '%s\\n' "gh $*" >> calls\nprintf '{"sha":"%s"}' ${head}\n`),
        ("bin/mise", "#!/bin/sh\nprintf '%s\\n' \"mise $*\" >> calls\n"),
      ],
    )
    if driver {
      tree(root.contents, [(".github/release/bump.res", "")])
    }
    Node.run(
      "chmod",
      ["+x", Node.join([root.contents, "bin/gh"]), Node.join([root.contents, "bin/mise"])],
    )->ignore
    let path = Node.env->Dict.get("PATH")->Option.getOr("")
    Node.env->Dict.set("PATH", Node.join([root.contents, "bin"]) ++ ":" ++ path)
    let result = Node.spawnSync(
      "node",
      [script, ...dry ? ["--dry-run"] : []],
      {cwd: root.contents, encoding: "utf8"},
    )
    Node.env->Dict.set("PATH", path)
    expect(result.status)->toEqual(Nullable.make(0))
    (
      Node.readFileSync(Node.join([root.contents, "calls"])),
      Node.readFileSync(Node.join([root.contents, ".github/workflows/release.yml"])),
    )
  }
  let moved = "f"->String.repeat(40)
  let asked = "gh api repos/monoflake/platform/commits/main\n"
  test("bumps the driver after it moves the platform's pin", () => {
    let (calls, text) = run(~driver=true, ~head=moved, ())
    expect(calls)->toBe(`${asked}mise run bump\n`)
    expect(text)->toBe(workflow->String.replace(pinned, moved))
  })
  test("moves a pin and runs nothing more in a repository without bump.res", () => {
    let (calls, text) = run(~driver=false, ~head=moved, ())
    expect(calls)->toBe(asked)
    expect(text)->toBe(workflow->String.replace(pinned, moved))
  })
  test("does not bump where no pin moved", () => {
    expect(run(~driver=true, ~head=pinned, ()))->toEqual((asked, workflow))
  })
  test("does not bump or write in a dry run", () => {
    expect(run(~driver=true, ~head=moved, ~dry=true, ()))->toEqual((asked, workflow))
  })
})
