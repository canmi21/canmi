open Testing

/** A lockfile of `(name, version, source or None, dependency references)`. */
let lock = (packages: array<(string, string, option<string>, array<string>)>) =>
  packages->Array.reduce("version = 4\n", (text, (name, version, source, dependencies)) => {
    let text = text ++ `\n[[package]]\nname = "${name}"\nversion = "${version}"\n`
    let text = switch source {
    | Some(source) => text ++ `source = "${source}"\nchecksum = "${name}${version}"\n`
    | None => text
    }
    dependencies->Array.length > 0
      ? text ++ `dependencies = [${dependencies->Array.map(one => `"${one}"`)->Array.join(", ")}]\n`
      : text
  })

// A source as the lockfile spells one; its text is never read.
let registry = Some("registry+crates-io")
let base = lock([
  ("ledger", "0.0.0", None, ["serde"]),
  ("probe", "0.0.0", None, ["serde", "getrandom"]),
  ("serde", "1.0.0", registry, []),
  ("getrandom", "0.2.0", registry, ["wasi"]),
  ("wasi", "0.11.0", registry, []),
])
let both = Set.fromArray(["ledger", "probe"])

describe("the lockfile", () => {
  test("a new dependency moves the crate that takes it alone", () => {
    let head = lock([
      ("ledger", "0.0.0", None, ["serde", "tokio-postgres"]),
      ("probe", "0.0.0", None, ["serde", "getrandom"]),
      ("serde", "1.0.0", registry, []),
      ("tokio-postgres", "0.7.0", registry, ["getrandom"]),
      ("getrandom", "0.2.0", registry, ["wasi"]),
      ("wasi", "0.11.0", registry, []),
    ])
    expect(Resolved.lockMoved(base, head, both))->toEqual(Set.fromArray(["ledger"]))
  })

  test("a shared package at another version moves every crate that reaches it", () => {
    let head =
      base->String.replace("\"wasi\"\nversion = \"0.11.0\"", "\"wasi\"\nversion = \"0.11.1\"")
    expect(Resolved.lockMoved(base, head, both))->toEqual(Set.fromArray(["probe"]))
  })

  test("a reference spelled out beside a second version is the same package", () => {
    let head = lock([
      ("ledger", "0.0.0", None, ["serde", "wasi 0.14.0"]),
      ("probe", "0.0.0", None, ["serde", "getrandom"]),
      ("serde", "1.0.0", registry, []),
      ("getrandom", "0.2.0", registry, ["wasi 0.11.0"]),
      ("wasi", "0.11.0", registry, []),
      ("wasi", "0.14.0", registry, []),
    ])
    expect(Resolved.lockMoved(base, head, both))->toEqual(Set.fromArray(["ledger"]))
  })

  test("a crate the lockfile does not hold has nothing to compare", () => {
    expect(
      Resolved.closures(base, ["quorum"])->Map.get("quorum")->Option.flatMap(x => x),
    )->toBeUndefined
    expect(Resolved.lockMoved(base, base, Set.fromArray(["quorum"])))->toEqual(Set.make())
  })
})

let root = `
[workspace]
resolver = "3"
members = ["apps/ledger", "apps/probe"]

[workspace.package]
edition = "2024"

[workspace.dependencies]
serde = "1"

[profile.dev]
opt-level = 0

[profile.container]
inherits = "release"
lto = "fat"
`

let table = (text: string) => Resolved.tableOf(Some(JSON.parseOrThrow(text)))
let members = Map.fromArray([
  (
    "ledger",
    table(`{"package": {"edition": {"workspace": true}}, "dependencies": {"serde": {"workspace": true}}}`),
  ),
  ("probe", table(`{"package": {"edition": "2021"}, "dependencies": {"serde": "1"}}`)),
])

let moved = head => Resolved.manifestMoved(root, head, members)

describe("the root manifest", () => {
  test("a profile no image is built with moves nothing", () =>
    expect(moved(root->String.replace("opt-level = 0", "opt-level = 1")))->toEqual(Some(Set.make()))
  )

  test("the image profile or one it inherits moves every image", () => {
    expect(moved(root->String.replace("lto = \"fat\"", "lto = \"thin\"")))->toBeUndefined
    expect(moved(`${root}\n[profile.release]\ndebug = true\n`))->toBeUndefined
  })

  test("a workspace dependency moves the crates that inherit it", () =>
    expect(moved(root->String.replace("serde = \"1\"", "serde = \"1.0.200\"")))->toEqual(
      Some(Set.fromArray(["ledger"])),
    )
  )

  test("a workspace package key moves the crates that inherit it", () =>
    expect(moved(root->String.replace("edition = \"2024\"", "edition = \"2021\"")))->toEqual(
      Some(Set.fromArray(["ledger"])),
    )
  )

  test("membership moves nothing by itself", () =>
    expect(
      moved(root->String.replace("\"apps/probe\"]", "\"apps/probe\", \"apps/new\"]")),
    )->toEqual(Some(Set.make()))
  )

  test("what cannot be told apart moves every image", () => {
    expect(moved(root->String.replace("resolver = \"3\"", "resolver = \"2\"")))->toBeUndefined
    expect(moved(`${root}\n[patch.crates-io]\nserde = { path = "../serde" }\n`))->toBeUndefined
    expect(moved(`${root}\n[unknown]\nkey = 1\n`))->toBeUndefined
  })

  test("a patch from a registry or git is left to the lockfile", () => {
    let patch = "\n[patch.crates-io]\nserde = { version = \"1.0.201\", registry = \"mirror\" }\n"
    expect(moved(root ++ patch))->toEqual(Some(Set.make()))
  })
})
