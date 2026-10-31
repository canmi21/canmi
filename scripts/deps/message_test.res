open Testing

let lock = packages =>
  packages
  ->Array.map(((name, version)) => `[[package]]\nname = "${name}"\nversion = "${version}"\n`)
  ->Array.join("\n")

let pnpmLock = deps =>
  "lockfileVersion: '9.0'\n\nimporters:\n\n  .:\n    devDependencies:\n" ++
  deps
  ->Array.map(((name, version)) =>
    `      ${name}:\n        specifier: ^${version}\n        version: ${version}\n`
  )
  ->Array.join("") ++ "\npackages:\n\n  oxfmt@0.1.0:\n    resolution: {}\n"

let sha = digit => String.repeat(digit, 40)

describe("a scheduled update's message", () => {
  test("names each moved crate by its new version, and the old in the body", () => {
    expect(
      Message.message([
        (
          "Cargo.lock",
          lock([("serde", "1.0.1"), ("tokio", "1.54.1"), ("libc", "0.2.1")]),
          lock([("serde", "1.0.2"), ("tokio", "1.54.1"), ("libc", "0.2.1")]),
        ),
      ]),
    )->toEqual("build: update serde 1.0.2\n\nserde 1.0.1 -> 1.0.2\n")
  })

  test("reads pnpm's importers alone, a quoted scope and a peer suffix taken apart", () => {
    let old = pnpmLock([("'@types/node'", "26.6.5"), ("oxfmt", "0.74.0")])
    let now = pnpmLock([("'@types/node'", "26.6.6"), ("oxfmt", "0.75.0(typescript@6.0.0)")])
    expect(Message.message([("pnpm-lock.yaml", old, now)]))->toEqual(
      "build: update @types/node 26.6.6 and oxfmt 0.75.0\n\n@types/node 26.6.5 -> 26.6.6, oxfmt 0.74.0 -> 0.75.0\n",
    )
  })

  test("reads a workflow's release pins and branch commits", () => {
    let workflow = (release, commit) =>
      `jobs:\n  a:\n    steps:\n      - uses: jdx/mise-action@${sha(
          "1",
        )} # ${release}\n      - uses: actions/checkout@${sha(
          "2",
        )} # v7.0.1\n        with:\n          ref: ${commit} # monoflake/platform@main\n`
    expect(
      Message.message([
        (
          ".github/actions/workspace/action.yml",
          workflow("v5.2.1", sha("a")),
          workflow("v5.2.4", sha("b")),
        ),
      ]),
    )->toEqual(
      "build: update jdx/mise-action v5.2.4 and monoflake/platform bbbbbbb\n\njdx/mise-action v5.2.1 -> v5.2.4, monoflake/platform aaaaaaa -> bbbbbbb\n",
    )
  })

  test("names a flake input by its revision once, however many flakes move it", () => {
    let flake = rev =>
      `{"nodes":{"machine":{"locked":{"rev":"${rev}"}},"root":{"inputs":{}}},"root":"root"}`
    expect(
      Message.message([
        ("machines/a/flake.lock", flake(sha("1")), flake(sha("2"))),
        ("machines/b/flake.lock", flake(sha("1")), flake(sha("2"))),
      ]),
    )->toEqual("build: update machine 2222222\n\nmachine 1111111 -> 2222222\n")
  })

  test("reads Dockerfile digest changes even when the tag stays the same", () => {
    let dockerfile = digit => `FROM node:26@sha256:${String.repeat(digit, 64)} AS build\n`
    expect(Message.message([("Dockerfile", dockerfile("1"), dockerfile("2"))]))->toEqual(
      "build: update node 26@222222222222\n\nnode 26@111111111111 -> 26@222222222222\n",
    )
  })

  test("names a known file whose edits move no dependency versions", () => {
    expect(
      Message.message([(".github/workflows/update.yml", "name: old\n", "name: update\n")]),
    )->toEqual("build: update .github/workflows/update.yml\n")
  })

  test(
    "counts what does not fit the subject's 96 columns, and names a file no reader knows",
    () => {
      let many = Array.fromInitializer(
        ~length=12,
        i => (`crate-number-${Int.toString(i)}`, "1.0.0"),
      )
      let moved = many->Array.map(((name, _)) => (name, "1.0.1"))
      let text = Message.message([
        ("Cargo.lock", lock(many), lock(moved)),
        ("system/containers/manifest.lock", "a", "b"),
      ])
      let subject = text->String.split("\n")->Array.getUnsafe(0)
      expect(String.length(subject) <= 96)->toBe(true)
      expect(subject)->toMatch(/^build: update crate-number-0 1\.0\.1, .* and \d+ more$/)
      expect(text->String.split("\n")->Array.length <= 8)->toBe(true)
    },
  )
})
