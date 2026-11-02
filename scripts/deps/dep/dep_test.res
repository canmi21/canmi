open Testing

let now = Date.fromString("2026-11-01T12:00:00Z")->Date.getTime
let ago = hours => Date.fromTime(now -. hours *. 3600. *. 1000.)->Date.toISOString

let release = (version, hours) => {Dep.version, published: ago(hours), yanked: false}

let pnpmManifest = `{"dependencies": {"a": "~1.0.0", "b": "~2.1.0", "c": "^3.0.0", "w": "workspace:*"}}`
let cargoManifest = `[package]
name = "x"

[dependencies]
serde = "1.0.1"
tokio = { version = "1.2.3", features = ["rt"] }
local = { path = "../local" }

[dev-dependencies]
tempfile = "3.1.0"
`

let calls = ref([])
let lines = ref([])
let run = (command, args, root) => {
  calls := Array.concat(calls.contents, [`${command} ${args->Array.join(" ")} @ ${root}`])
  0
}
let log = line => lines := Array.concat(lines.contents, [line])
let found = releases => async (_, _) => Some(releases)

let root = temporaryRoot("dep-test-")
beforeEach(() => {
  calls := []
  lines := []
})

let add = (~kind=Dep.Npm, ~member=?, ~dev=false, ~dry=false, ~name="pkg", releases) =>
  Dep.add(
    ~root=root.contents,
    ~repository="apps/x",
    ~member?,
    ~name,
    ~kind,
    ~dev,
    ~dry,
    ~lookup=found(releases),
    ~run,
    ~now,
    ~log,
  )

describe("the version added", () => {
  testAsync("is the newest one public for a day, one of 3 hours passed over", async () => {
    tree(root.contents, [("package.json", pnpmManifest)])
    let status = await add([release("1.0.0", 500.), release("1.1.0", 30.), release("1.2.0", 3.)])
    expect(status)->toBe(0)
    expect(calls.contents)->toEqual([`pnpm add pkg@1.1.0 --save-prefix=~ @ ${root.contents}`])
  })

  test("passes over a prerelease, a yanked version and a deprecated one", () => {
    let yanked = {...release("1.3.0", 99.), yanked: true}
    expect(
      Dep.newestAged([release("1.0.0", 99.), yanked, release("2.0.0-rc.1", 99.)], ~now),
    )->toEqual(Some("1.0.0"))
    expect(Dep.newestAged([release("1.0.0", 23.)], ~now))->toEqual(None)
  })

  testAsync("is shown with its publish time, the newer ones named as passed over", async () => {
    tree(root.contents, [("package.json", pnpmManifest)])
    let _ = await add(~dry=true, [release("1.1.0", 30.), release("1.2.0", 3.)])
    expect(lines.contents->Array.length)->toBe(3)
    expect(lines.contents->Array.getUnsafe(0))->toMatch(/^pkg 1\.1\.0 published 2026-10-31/)
    expect(lines.contents->Array.getUnsafe(1))->toMatch(/^pkg 1\.2\.0 .*passed over$/)
  })

  testAsync("is refused where every version is under a day old", async () => {
    tree(root.contents, [("package.json", pnpmManifest)])
    await expect(add([release("1.0.0", 3.)]))->rejects->toThrowAsync("public for a day")
    expect(calls.contents)->toEqual([])
  })
})

describe("the range written", () => {
  testAsync("is the sign most of the repository's ranges open with", async () => {
    tree(root.contents, [("package.json", pnpmManifest)])
    let _ = await add([release("1.0.0", 99.)])
    expect(calls.contents->Array.getUnsafe(0))->toMatch(/--save-prefix=~/)
  })

  testAsync(
    "is exact where the repository pins exactly, and a caret where it says nothing",
    async () => {
      tree(root.contents, [("package.json", `{"dependencies": {"a": "1.0.0", "b": "2.0.0"}}`)])
      let _ = await add([release("1.0.0", 99.)])
      expect(calls.contents->Array.getUnsafe(0))->toMatch(/--save-exact/)
      tree(root.contents, [("package.json", `{"dependencies": {"w": "workspace:*"}}`)])
      calls := []
      let _ = await add([release("1.0.0", 99.)])
      expect(calls.contents->Array.getUnsafe(0))->toMatch(/--save-prefix=\^/)
    },
  )

  testAsync("is a bare requirement for a crate where the Cargo.toml writes them bare", async () => {
    tree(root.contents, [("Cargo.toml", cargoManifest)])
    let _ = await add(~kind=Crate, [release("1.0.5", 99.)])
    expect(calls.contents)->toEqual([`cargo add pkg@1.0.5 @ ${root.contents}`])
  })

  testAsync("keeps a crate's equals sign where the Cargo.toml pins that way", async () => {
    tree(root.contents, [("Cargo.toml", "[dependencies]\nserde = \"=1.0.1\"\n")])
    let _ = await add(~kind=Crate, [release("1.0.5", 99.)])
    expect(calls.contents->Array.getUnsafe(0))->toMatch(/pkg@=1\.0\.5/)
  })
})

describe("the file and the section", () => {
  testAsync("--dev adds to devDependencies through pnpm", async () => {
    tree(root.contents, [("package.json", pnpmManifest)])
    let _ = await add(~dev=true, [release("1.0.0", 99.)])
    expect(calls.contents->Array.getUnsafe(0))->toMatch(/--save-dev/)
  })

  testAsync("--rust adds to Cargo.toml through cargo, --dev to its dev-dependencies", async () => {
    tree(root.contents, [("Cargo.toml", cargoManifest), ("package.json", pnpmManifest)])
    let _ = await add(~kind=Crate, ~dev=true, [release("1.0.5", 99.)])
    expect(calls.contents)->toEqual([`cargo add pkg@1.0.5 --dev @ ${root.contents}`])
  })

  testAsync("goes through the workspace root where there is a pnpm workspace", async () => {
    tree(
      root.contents,
      [("package.json", pnpmManifest), ("pnpm-workspace.yaml", "packages:\n  - a\n")],
    )
    let _ = await add([release("1.0.0", 99.)])
    expect(calls.contents->Array.getUnsafe(0))->toMatch(/ -w @/)
  })
})

describe("a package the repository already has", () => {
  testAsync("is refused, naming mise run update", async () => {
    tree(root.contents, [("package.json", pnpmManifest)])
    await expect(add(~name="a", [release("1.0.0", 99.)]))
    ->rejects
    ->toThrowAsync("mise run update apps/x")
    expect(calls.contents)->toEqual([])
  })

  testAsync("is found in a crate's inline table and dev-dependencies too", async () => {
    tree(root.contents, [("Cargo.toml", cargoManifest)])
    await expect(add(~kind=Crate, ~name="tokio", [release("1.0.0", 99.)]))
    ->rejects
    ->toThrowAsync("already in Cargo.toml under dependencies")
    await expect(add(~kind=Crate, ~name="tempfile", [release("1.0.0", 99.)]))
    ->rejects
    ->toThrowAsync("dev-dependencies")
  })
})

describe("--dry-run", () => {
  testAsync("names the command and runs nothing", async () => {
    tree(root.contents, [("package.json", pnpmManifest)])
    let status = await add(~dry=true, [release("1.0.0", 99.)])
    expect(status)->toBe(0)
    expect(calls.contents)->toEqual([])
    expect(lines.contents->Array.at(-1))->toEqual(Some("$ pnpm add pkg@1.0.0 --save-prefix=~"))
    expect(Node.readFileSync(Node.join([root.contents, "package.json"])))->toBe(pnpmManifest)
  })
})

describe("remove", () => {
  test("runs pnpm remove for a package it holds and refuses one it does not", () => {
    tree(root.contents, [("package.json", pnpmManifest)])
    let status = Dep.remove(~root=root.contents, ~name="a", ~kind=Npm, ~dry=false, ~run, ~log)
    expect(status)->toBe(0)
    expect(calls.contents)->toEqual([`pnpm remove a @ ${root.contents}`])
    expect(
      () => Dep.remove(~root=root.contents, ~name="zz", ~kind=Npm, ~dry=false, ~run, ~log),
    )->toThrow("zz is not in package.json")
  })

  test("names the dev section to cargo, and --dry-run runs nothing", () => {
    tree(root.contents, [("Cargo.toml", cargoManifest)])
    let _ = Dep.remove(~root=root.contents, ~name="tempfile", ~kind=Crate, ~dry=false, ~run, ~log)
    expect(calls.contents)->toEqual([`cargo remove tempfile --dev @ ${root.contents}`])
    calls := []
    let _ = Dep.remove(~root=root.contents, ~name="serde", ~kind=Crate, ~dry=true, ~run, ~log)
    expect(calls.contents)->toEqual([])
  })
})

describe("a registry's document", () => {
  test("npm lists its times, past a version unpublished or deprecated", () => {
    let document = JSON.parseOrThrow(`{"time": {"created": "2020-01-01T00:00:00Z",
      "1.0.0": "2020-01-02T00:00:00Z", "1.1.0": "2020-01-03T00:00:00Z", "0.9.0": "2019-01-01T00:00:00Z"},
      "versions": {"1.0.0": {}, "1.1.0": {"deprecated": "no"}}}`)
    expect(Dep.npmReleases(document)->Array.map(r => (r.version, r.yanked)))->toEqual([
      ("1.0.0", false),
      ("1.1.0", true),
    ])
  })

  test("crates.io lists its versions with the yank flag", () => {
    let document = JSON.parseOrThrow(`{"versions": [
      {"num": "1.0.0", "created_at": "2020-01-02T00:00:00Z", "yanked": false},
      {"num": "1.0.1", "created_at": "2020-01-03T00:00:00Z", "yanked": true}]}`)
    expect(Dep.crateReleases(document)->Array.map(r => (r.version, r.yanked)))->toEqual([
      ("1.0.0", false),
      ("1.0.1", true),
    ])
  })
})

describe("a member named by --in", () => {
  testAsync("gets pnpm run in its directory, with the range form of its own manifest", async () => {
    tree(
      root.contents,
      [
        ("package.json", `{"private": true}`),
        ("pnpm-workspace.yaml", "packages:\n  - code/*\n"),
        ("code/lib/package.json", `{"dependencies": {"a": "1.0.0"}}`),
      ],
    )
    let status = await add(~member="code/lib", [release("1.0.0", 99.)])
    expect(status)->toBe(0)
    expect(calls.contents)->toEqual([`pnpm add pkg@1.0.0 --save-exact @ ${root.contents}/code/lib`])
  })

  testAsync("gets cargo run in the member, the workspace's ranges counted", async () => {
    tree(
      root.contents,
      [
        (
          "Cargo.toml",
          "[workspace]\nmembers = [\"m\"]\n[workspace.dependencies]\nserde = \"=1.0.1\"\n",
        ),
        ("m/Cargo.toml", "[package]\nname = \"m\"\n[dependencies]\nserde = { workspace = true }\n"),
      ],
    )
    let _ = await add(~kind=Crate, ~member="m", [release("1.0.5", 99.)])
    expect(calls.contents)->toEqual([`cargo add pkg@=1.0.5 @ ${root.contents}/m`])
  })

  testAsync("is refused where it leaves the repository or does not exist", async () => {
    tree(root.contents, [("package.json", pnpmManifest)])
    await expect(add(~member="../out", [release("1.0.0", 99.)]))->rejects->toThrowAsync("inside")
    await expect(add(~member="nope", [release("1.0.0", 99.)]))
    ->rejects
    ->toThrowAsync("does not exist")
  })

  testAsync("is asked for where the root only gathers members", async () => {
    tree(
      root.contents,
      [("package.json", `{"private": true}`), ("pnpm-workspace.yaml", "packages:\n  - c\n")],
    )
    await expect(add([release("1.0.0", 99.)]))->rejects->toThrowAsync("with --in")
    tree(root.contents, [("Cargo.toml", "[workspace]\nmembers = [\"m\"]\n")])
    await expect(add(~kind=Crate, [release("1.0.0", 99.)]))->rejects->toThrowAsync("with --in")
    expect(calls.contents)->toEqual([])
  })

  test("remove runs in the member too", () => {
    tree(root.contents, [("m/package.json", `{"dependencies": {"a": "1.0.0"}}`)])
    let _ = Dep.remove(
      ~root=root.contents,
      ~member="m",
      ~name="a",
      ~kind=Npm,
      ~dry=false,
      ~run,
      ~log,
    )
    expect(calls.contents)->toEqual([`pnpm remove a @ ${root.contents}/m`])
  })
})
