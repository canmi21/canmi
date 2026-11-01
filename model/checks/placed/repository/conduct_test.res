open Testing

let digest = "sha256:" ++ String.repeat("a", 64)
let call = (name, port) => name ++ "(" ++ port ++ ")"

describe("a pnpm repository's release age", () => {
  test("is a day or more in pnpm-workspace.yaml, which it must have", () => {
    expect(Pinned.releaseAge(Some("minimumReleaseAge: 1440\n")))->toEqual(None)
    expect(Pinned.releaseAge(Some("minimumReleaseAge: 60\n")))->toEqual(
      Some("pnpm-workspace.yaml does not set minimumReleaseAge to 1440 or more"),
    )
    expect(Pinned.releaseAge(Some("packages: []\n")))->toEqual(
      Some("pnpm-workspace.yaml does not set minimumReleaseAge to 1440 or more"),
    )
    expect(Pinned.releaseAge(None)->Option.isSome)->toBe(true)
  })
})

describe("a Dockerfile's base image", () => {
  test("is pinned by tag and digest, a stage and scratch passed over", () => {
    let text = `FROM --platform=$BUILDPLATFORM busybox:1.37@${digest} AS fetch-a
FROM fetch-\${ARCH} AS fetch
FROM scratch
FROM busybox:1.37
FROM busybox@${digest}`
    expect(Pinned.images(text, ~file="Dockerfile"))->toEqual([
      "Dockerfile:4: busybox:1.37 is not pinned by its tag and a digest",
      `Dockerfile:5: busybox@${digest} is not pinned by its tag and a digest`,
    ])
  })
})

describe("a dev server", () => {
  test("fails when its port is taken, as a vite config says", () => {
    expect(Ports.dev("apps/a/vite.config.ts", "server: { strictPort: true }"))->toEqual(None)
    expect(Ports.dev("apps/a/vite.config.ts", "server: { port: 5173 }")->Option.isSome)->toBe(true)
    expect(Ports.dev("apps/a/main.ts", "server: { port: 5173 }"))->toEqual(None)
  })
})

describe("a test's port", () => {
  test("is 0, a literal listen or bind refused in a test and not in a comment", () => {
    expect(
      Ports.listens(
        "a_test.ts",
        `${call("server.lis" ++ "ten", "3000")}\n${call("server.lis" ++ "ten", "0")}\n// ${call(
            "lis" ++ "ten",
            "3000",
          )}`,
      ),
    )->toEqual(["a_test.ts:1: a test binds a literal port, not port 0"])
    expect(
      Ports.listens(
        "a.rs",
        `#[test]\n${call("TcpListener::bi" ++ "nd", "\"127.0.0" ++ ".1:8080\"")}`,
      ),
    )->toEqual(["a.rs:2: a test binds a literal port, not port 0"])
    expect(
      Ports.listens("a.rs", `#[test]\n${call("TcpListener::bi" ++ "nd", "\"127.0.0" ++ ".1:0\"")}`),
    )->toEqual([])
    expect(
      Ports.listens("main.rs", call("TcpListener::bi" ++ "nd", "\"127.0.0" ++ ".1:8080\"")),
    )->toEqual([])
  })
})

describe("a Rust repository's tests", () => {
  test("run by nextest with a slow timeout, cargo test only for doctests", () => {
    expect(
      Rust_tests.commands("cargo nextest run\ncargo test --doc", ~file="mise.toml"),
    )->toEqual([])
    expect(Rust_tests.commands("a\ncargo test -p x", ~file="mise.toml"))->toEqual([
      "mise.toml:2: cargo test runs more than the doctests",
    ])
    expect(Rust_tests.slow(Some("slow-timeout = { terminate-after = 2 }")))->toEqual(None)
    expect(Rust_tests.slow(None)->Option.isSome)->toBe(true)
  })
})

describe("generated code", () => {
  test("opens with @generated exactly where .gitattributes marks it", () => {
    let globs = Generated.marked("src/*.css linguist-generated=true\ndata/ linguist-generated\n")
    let marked = path => globs->Array.some(glob => glob->RegExp.test(path))
    expect(marked("src/a.css"))->toBe(true)
    expect(marked("src/deep/a.css"))->toBe(false)
    expect(marked("data/x/y.json"))->toBe(true)
    expect(marked("other.css"))->toBe(false)
    expect(Generated.opens("/* @generated */\nbody"))->toBe(true)
    expect(Generated.opens("1\n2\n3\n4\n5\n@generated"))->toBe(false)
    expect(Generated.problem("a.css", ~marked=true, ~opens=false)->Option.isSome)->toBe(true)
    expect(Generated.problem("a.css", ~marked=false, ~opens=true)->Option.isSome)->toBe(true)
    expect(Generated.problem("a.css", ~marked=true, ~opens=true))->toEqual(None)
  })
})

describe("a repository's conduct", () => {
  test("is read over its tracked files, a rust-nextest finding only a warning", () => {
    let root = Node.mkdtempSync(Node.join([Node.tmpdir(), "conduct-"]))
    tree(
      root,
      [
        ("Cargo.toml", "[workspace]\n"),
        ("mise.toml", "run = \"cargo test\"\n"),
        ("package.json", "{}"),
        ("pnpm-lock.yaml", ""),
        ("Dockerfile", "FROM busybox:1\n"),
      ],
    )
    Node.run(~cwd=root, "git", ["init", "-q"])->ignore
    Node.run(~cwd=root, "git", ["add", "-A"])->ignore
    let (failed, warned) = Conduct.found(~root)
    expect(failed->Array.length)->toBe(1)
    expect(failed->Array.some(line => line->String.startsWith("Dockerfile:1:")))->toBe(true)
    expect(warned->Array.some(line => line->String.endsWith("(release-age)")))->toBe(true)
    expect(warned->Array.some(line => line->String.endsWith("(rust-nextest)")))->toBe(true)
  })
})
