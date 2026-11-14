open Testing

// Each case runs jj in a scratch repository, slow under load.
setConfig({"testTimeout": 30000})

let jj = (root, args) => Onset.read(~root, args)->Option.getOr("")

let crate = (~name, ~version="0.1.0", ~more="") =>
  `[package]\nname = "${name}"\nversion = "${version}"\n${more}`

let lock = (~a="0.1.0", ~b="0.1.0") =>
  `[[package]]\nname = "a"\nversion = "${a}"\n\n[[package]]\nname = "b"\nversion = "${b}"\n`

/** A repository whose main line holds a root, crate a, and crate b depending on a. */
let scratch = root => {
  Node.env->Dict.set("JJ_USER", "test")
  Node.env->Dict.set("JJ_EMAIL", "test@localhost")
  jj(root, ["git", "init", "--colocate"])->ignore
  tree(
    root,
    [
      ("package.json", "{\n\t\"name\": \"r\",\n\t\"version\": \"0.1.0\"\n}\n"),
      ("Cargo.lock", lock()),
      ("a/Cargo.toml", crate(~name="a")),
      ("a/src/lib.rs", "one\n"),
      ("b/Cargo.toml", crate(~name="b", ~more="[dependencies]\na = { path = \"../a\" }\n")),
      ("b/src/lib.rs", "one\n"),
    ],
  )
  jj(root, ["commit", "-m", "chore: begin"])->ignore
  jj(root, ["bookmark", "set", "main", "-r", "@-"])->ignore
}

let versions = root => {
  let judged = Roll.planned(~root)
  judged.rows
  ->Array.map(row => (row.package.name, Numbers.show(Numbers.rolled(row.asked))))
  ->Array.toSorted(((a, _), (b, _)) => String.compare(a, b))
}

let bumped = root => Bump.write(~root, Bump.moving(Roll.planned(~root)))->ignore

/** What the working copy holds, committed as `message` and put on the main line. */
let landed = (root, message) => {
  jj(root, ["commit", "-m", message])->ignore
  jj(root, ["bookmark", "set", "main", "-r", "@-"])->ignore
}

describe("a landing", () => {
  let root = temporaryRoot("landing-")

  test("with nothing changed owes nothing", () => {
    let root = root.contents
    scratch(root)
    expect(Versions.found(~root))->toEqual([])
  })

  test("is refused until it is rolled, then passes, and a second roll moves nothing", () => {
    let root = root.contents
    scratch(root)
    tree(root, [("a/src/lib.rs", "two\n")])
    expect(Versions.found(~root)->Array.length)->toBe(2)
    expect(versions(root))->toEqual([("a", "0.1.1"), ("b", "0.1.1"), ("r", "0.1.0")])
    bumped(root)
    expect(Versions.found(~root))->toEqual([])
    expect(Node.readFileSync(Node.join([root, "Cargo.lock"])))->toBe(lock(~a="0.1.1", ~b="0.1.1"))
    expect(Bump.moving(Roll.judged(~root))->Array.length)->toBe(0)
  })

  test("raises the root for its own file alone, and a document raises nothing", () => {
    let root = root.contents
    scratch(root)
    tree(root, [("docs/a.txt", "a\n"), ("a/tests/t.rs", "t\n")])
    expect(Versions.found(~root))->toEqual([])
    tree(root, [("mise.toml", "[tools]\n")])
    expect(versions(root))->toEqual([("a", "0.1.0"), ("b", "0.1.0"), ("r", "0.1.1")])
  })

  test("over a merge judges what every parent lands, not what the merge alone adds", () => {
    let root = root.contents
    scratch(root)
    tree(root, [("a/src/lib.rs", "two\n")])
    jj(root, ["commit", "-m", "feat: one lane"])->ignore
    let first = jj(root, ["log", "--no-graph", "-r", "@-", "-T", "commit_id"])
    jj(root, ["new", "main"])->ignore
    tree(root, [("mise.toml", "[tools]\n")])
    jj(root, ["commit", "-m", "feat: another lane"])->ignore
    let second = jj(root, ["log", "--no-graph", "-r", "@-", "-T", "commit_id"])
    jj(root, ["new", first, second])->ignore
    expect(versions(root))->toEqual([("a", "0.1.1"), ("b", "0.1.1"), ("r", "0.1.1")])
  })

  test("a breaking commit raises the minor of what it touched", () => {
    let root = root.contents
    scratch(root)
    tree(root, [("a/src/lib.rs", "two\n")])
    jj(root, ["commit", "-m", "feat!: change a"])->ignore
    expect(versions(root))->toEqual([("a", "0.2.0"), ("b", "0.1.1"), ("r", "0.1.0")])
  })

  test("a major moved is refused until the escape names it", () => {
    let root = root.contents
    scratch(root)
    tree(
      root,
      [("a/Cargo.toml", crate(~name="a", ~version="1.0.0")), ("Cargo.lock", lock(~a="1.0.0"))],
    )
    expect(Versions.found(~root)->Array.length)->toBe(1)
    Node.env->Dict.set("SKIP", "major")
    expect(Versions.found(~root))->toEqual([])
    Node.env->Dict.delete("SKIP")
  })

  test("a lock left behind its crate is refused", () => {
    let root = root.contents
    scratch(root)
    tree(root, [("a/src/lib.rs", "two\n"), ("a/Cargo.toml", crate(~name="a", ~version="0.1.1"))])
    expect(
      Versions.found(~root)->Array.some(line => line->String.startsWith("Cargo.lock holds a")),
    )->toBe(true)
  })

  test("in a lane is judged by nothing", () => {
    let root = root.contents
    scratch(root)
    let lane = Node.join([root, "lane"])
    jj(root, ["workspace", "add", lane])->ignore
    tree(lane, [("a/src/lib.rs", "two\n")])
    expect(Form.mainCheckout(lane))->toBe(false)
    expect(Versions.found(~root=lane))->toEqual([])
  })

  let interfaces = version =>
    `{"interfaces": {"one": {"version": ${version}}, "two": {"version": 1}}}\n`

  test("follows the one interface a package serves, from its own contracts", () => {
    let root = root.contents
    scratch(root)
    tree(
      root,
      [
        ("model/contracts.json", interfaces("2")),
        (
          "workspace.toml",
          "[versions]\ncontracts = \"model/contracts.json\"\n[versions.serves]\na = [\"one\"]\nb = [\"one\", \"two\"]\n",
        ),
      ],
    )
    jj(root, ["commit", "-m", "chore: declare"])->ignore
    jj(root, ["bookmark", "set", "main", "-r", "@-"])->ignore
    tree(root, [("model/contracts.json", interfaces("3"))])
    expect(versions(root))->toEqual([("a", "0.3.0"), ("b", "0.2.0"), ("r", "0.1.1")])
  })

  test("reads a sibling's contracts at the commit each end pins, and warns where it cannot", () => {
    let root = root.contents
    let sibling = Node.join([root, "platform"])
    let own = Node.join([root, "driver"])
    Node.mkdirAll(sibling)
    Node.mkdirAll(own)
    jj(sibling, ["git", "init", "--colocate"])->ignore
    tree(sibling, [("model/contracts.json", interfaces("1"))])
    jj(sibling, ["commit", "-m", "chore: first"])->ignore
    let first = jj(sibling, ["log", "--no-graph", "-r", "@-", "-T", "commit_id"])
    tree(sibling, [("model/contracts.json", interfaces("2"))])
    jj(sibling, ["commit", "-m", "chore: second"])->ignore
    let second = jj(sibling, ["log", "--no-graph", "-r", "@-", "-T", "commit_id"])
    let pin = commit => `ref: ${commit} # monoflake/platform@main\n`
    scratch(own)
    tree(
      own,
      [
        ("pin.yml", pin(first)),
        (
          "workspace.toml",
          "[versions]\ncontracts = \"model/contracts.json\"\nrepository = \"../platform\"\npin = \"pin.yml\"\n[versions.counts]\na = [\"pin.yml\"]\n[versions.serves]\na = [\"one\", \"two\"]\n",
        ),
      ],
    )
    jj(own, ["commit", "-m", "chore: declare"])->ignore
    jj(own, ["bookmark", "set", "main", "-r", "@-"])->ignore
    tree(own, [("pin.yml", pin(second))])
    expect(Roll.judged(~root=own).warnings)->toEqual([])
    expect(versions(own))->toEqual([("a", "0.2.0"), ("b", "0.1.1"), ("r", "0.1.1")])
    tree(own, [("pin.yml", pin("0000000000000000000000000000000000000000"))])
    expect(Roll.judged(~root=own).warnings->Array.length)->toBe(1)
    expect(versions(own))->toEqual([("a", "0.1.1"), ("b", "0.1.1"), ("r", "0.1.1")])
  })

  test("a lock moved raises the binary it builds and the root, not a library", () => {
    let root = root.contents
    scratch(root)
    tree(root, [("a/src/main.rs", "fn main() {}\n")])
    jj(root, ["commit", "-m", "feat: a binary"])->ignore
    jj(root, ["bookmark", "set", "main", "-r", "@-"])->ignore
    tree(
      root,
      [
        (
          "Cargo.lock",
          lock() ++ "\n[[package]]\nname = \"c\"\nversion = \"1.0.0\"\nsource = \"registry\"\n",
        ),
      ],
    )
    expect(versions(root))->toEqual([("a", "0.1.1"), ("b", "0.1.1"), ("r", "0.1.1")])
  })

  test("at a push refuses an outgoing commit with no raise, nothing further back", () => {
    let root = root.contents
    scratch(root)
    tree(root, [("a/src/lib.rs", "two\n")])
    landed(root, "feat: no raise")
    expect(Versions.outgoing(~root)->Array.length)->toBe(2)
    let tip = jj(root, ["log", "--no-graph", "-r", "main", "-T", "commit_id"])
    jj(root, ["git", "export"])->ignore
    Node.run(~cwd=root, "git", ["update-ref", "refs/remotes/origin/main", tip])->ignore
    jj(root, ["git", "import"])->ignore
    expect(Versions.outgoing(~root))->toEqual([])
  })

  test("at a push passes a landing whose raise came in a later commit by path", () => {
    let root = root.contents
    scratch(root)
    tree(root, [("a/src/lib.rs", "two\n")])
    bumped(root)
    jj(root, ["commit", "-m", "feat: the change", "a/src/lib.rs"])->ignore
    jj(root, ["bookmark", "set", "main", "-r", "@-"])->ignore
    landed(root, "chore: roll the versions")
    expect(Versions.outgoing(~root))->toEqual([])
  })

  test("at a push refuses a second landing a first one's raise does not cover", () => {
    let root = root.contents
    scratch(root)
    tree(root, [("a/src/lib.rs", "two\n")])
    bumped(root)
    landed(root, "feat: raised")
    tree(root, [("a/src/lib.rs", "three\n")])
    landed(root, "feat: not raised")
    expect(Versions.outgoing(~root)->Array.length)->toBe(2)
  })

  test("bump refuses where a sibling's crate on disk is apart from the pinned commit", () => {
    let root = root.contents
    let sibling = Node.join([root, "platform"])
    let own = Node.join([root, "driver"])
    Node.mkdirAll(sibling)
    Node.mkdirAll(own)
    jj(sibling, ["git", "init", "--colocate"])->ignore
    tree(sibling, [("lib/Cargo.toml", crate(~name="lib")), ("lib/src/lib.rs", "one\n")])
    jj(sibling, ["commit", "-m", "chore: first"])->ignore
    let first = jj(sibling, ["log", "--no-graph", "-r", "@-", "-T", "commit_id"])
    scratch(own)
    tree(
      own,
      [
        (
          "a/Cargo.toml",
          crate(~name="a", ~more="[dependencies]\nlib = { path = \"../../platform/lib\" }\n"),
        ),
        ("pin.yml", `ref: ${first} # monoflake/platform@main\n`),
        ("workspace.toml", "[versions]\nrepository = \"../platform\"\npin = \"pin.yml\"\n"),
      ],
    )
    let moved = Bump.moving(Roll.judged(~root=own))
    expect(moved != [])->toBe(true)
    expect(Bump.stale(~root=own))->toBe(None)
    tree(sibling, [("lib/src/lib.rs", "stale\n")])
    expect(Bump.stale(~root=own)->Option.isSome)->toBe(true)
  })
  test("bump pays a breaking outgoing commit after main advanced", () => {
    let root = root.contents
    scratch(root)
    tree(root, [("a/src/lib.rs", "two\n")])
    landed(root, "feat!: break a")
    expect(versions(root))->toEqual([("a", "0.2.0"), ("b", "0.1.1"), ("r", "0.1.0")])
    bumped(root)
    landed(root, "chore: roll")
    expect(Versions.outgoing(~root))->toEqual([])
  })

  test("a patch cannot pay an outgoing minor debt", () => {
    let root = root.contents
    scratch(root)
    tree(root, [("a/src/lib.rs", "two\n")])
    landed(root, "feat!: break a")
    tree(
      root,
      [
        ("a/Cargo.toml", crate(~name="a", ~version="0.1.1")),
        ("b/Cargo.toml", crate(~name="b", ~version="0.1.1")),
        ("Cargo.lock", lock(~a="0.1.1", ~b="0.1.1")),
      ],
    )
    landed(root, "chore: insufficient roll")
    expect(
      Versions.outgoing(~root)->Array.some(line => line->String.includes("owing 0.2.0")),
    )->toBe(true)
  })

  test("a package removed at the tip owes nothing", () => {
    let root = root.contents
    scratch(root)
    tree(root, [("a/src/lib.rs", "two\n")])
    landed(root, "feat!: break a")
    Node.rmSync(Node.join([root, "a"]), {recursive: true, force: true})
    Node.rmSync(Node.join([root, "b"]), {recursive: true, force: true})
    tree(root, [("package.json", "{\n\t\"name\": \"r\",\n\t\"version\": \"0.1.1\"\n}\n")])
    landed(root, "chore: remove crates")
    expect(Versions.outgoing(~root))->toEqual([])
    expect(Bump.moving(Roll.judged(~root)))->toEqual([])
  })

  test("an outgoing major refusal names push", () => {
    let root = root.contents
    scratch(root)
    tree(
      root,
      [("a/Cargo.toml", crate(~name="a", ~version="1.0.0")), ("Cargo.lock", lock(~a="1.0.0"))],
    )
    landed(root, "chore: major")
    expect(
      Versions.outgoing(~root)->Array.some(
        line => line->String.includes("SKIP=major mise run push"),
      ),
    )->toBe(true)
  })

  test("minor judgment refuses an unknown package and a single interface", () => {
    let root = root.contents
    scratch(root)
    tree(root, [("workspace.toml", "[versions.serves]\na = [\"one\"]\n")])
    expect(Roll.judged(~root, ~minors=["typo"]).problems != [])->toBe(true)
    expect(Roll.judged(~root, ~minors=["a"]).problems != [])->toBe(true)
  })

  test("the pinned sibling manifest holds the committed lock only at push", () => {
    let root = root.contents
    let sibling = Node.join([root, "platform"])
    let own = Node.join([root, "driver"])
    Node.mkdirAll(sibling)
    Node.mkdirAll(own)
    scratch(sibling)
    tree(sibling, [("lib/Cargo.toml", crate(~name="lib")), ("lib/src/lib.rs", "one\n")])
    landed(sibling, "chore: library")
    let pin = jj(sibling, ["log", "--no-graph", "-r", "main", "-T", "commit_id"])
    scratch(own)
    tree(
      own,
      [
        (
          "a/Cargo.toml",
          crate(~name="a", ~more="[dependencies]\nlib = { path = \"../../platform/lib\" }\n"),
        ),
        ("pin.yml", `ref: ${pin} # monoflake/platform@main\n`),
        ("workspace.toml", "[versions]\nrepository = \"../platform\"\npin = \"pin.yml\"\n"),
      ],
    )
    landed(own, "chore: declare")
    tree(own, [("Cargo.lock", lock() ++ "\n[[package]]\nname = \"lib\"\nversion = \"0.9.0\"\n")])
    tree(sibling, [("lib/Cargo.toml", crate(~name="lib", ~version="0.9.0"))])
    expect(
      Versions.found(~root=own)->Array.some(
        line =>
          line->String.includes("restore the committed lock to the pin's versions or move the pin"),
      ),
    )->toBe(false)
    landed(own, "chore: stale lock")
    expect(
      Versions.outgoing(~root=own)->Array.some(
        line =>
          line->String.includes("restore the committed lock to the pin's versions or move the pin"),
      ),
    )->toBe(true)
    tree(own, [("Cargo.lock", lock() ++ "\n[[package]]\nname = \"lib\"\nversion = \"0.1.0\"\n")])
    expect(
      Versions.outgoing(~root=own)->Array.some(
        line => line->String.includes("restore the committed lock"),
      ),
    )->toBe(true)
    let read = path => Landing.disk(~root=own, path)
    let packages = Roll.judged(~root=own).packages
    tree(own, [("pin.yml", "ref: main\n")])
    expect(Roll.siblingVersions(~root=own, ~read, packages))->toEqual(
      Error("pin.yml pins no commit of ../platform"),
    )
    expect(Versions.stale(~root=own, ~read, ~pushing=true, None, packages))->toEqual([
      "pin.yml pins no commit of ../platform",
    ])
    expect(Versions.stale(~root=own, ~read, None, packages))->toEqual([])
    tree(
      own,
      [("pin.yml", "ref: 0000000000000000000000000000000000000000 # monoflake/platform@main\n")],
    )
    expect(Roll.siblingVersions(~root=own, ~read, packages))->toEqual(
      Error(
        "../platform cannot be read at 0000000000000000000000000000000000000000, the commit pin.yml pins",
      ),
    )
    tree(own, [("workspace.toml", "[versions]\nrepository = \"../absent\"\npin = \"pin.yml\"\n")])
    expect(Roll.siblingVersions(~root=own, ~read, packages))->toEqual(Ok([]))
    tree(
      own,
      [
        ("workspace.toml", "[versions]\nrepository = \"../platform\"\npin = \"pin.yml\"\n"),
        ("pin.yml", `ref: ${pin} # monoflake/platform@main\n`),
      ],
    )
    tree(sibling, [("lib/src/lib.rs", "stale\n")])
    expect(Bump.stale(~root=own)->Option.isSome)->toBe(true)
    tree(own, [("a/src/lib.rs", "two\n")])
    let lockBefore = Node.readFileSync(Node.join([own, "Cargo.lock"]))
    let calls = ref(0)
    let run = (~cwd=?, _, _) => {
      cwd->ignore
      calls := calls.contents + 1
      0
    }
    expect(Bump.guard(~root=own, []))->toBe(None)
    expect(Bump.write(~root=own, ~run, []))->toBe(true)
    expect(Node.readFileSync(Node.join([own, "Cargo.lock"])))->toBe(lockBefore)
    let worker: Roll.row = {
      package: {
        directory: "worker",
        builds: [],
        name: "worker",
        version: (0, 1, 0),
        manifests: [{path: "worker/package.json", kind: Node, text: "{\"version\":\"0.1.0\"}"}],
      },
      asked: {base: Some((0, 1, 0)), now: (0, 1, 0), changed: true, minor: false, target: None},
      because: ["worker/index.ts"],
    }
    Node.mkdirAll(Node.join([own, "worker"]))
    expect(Bump.guard(~root=own, [worker]))->toBe(None)
    expect(Bump.guard(~root=own, Bump.moving(Roll.judged(~root=own)))->Option.isSome)->toBe(true)
    expect(Bump.write(~root=own, ~run, [worker]))->toBe(true)
    expect(Node.readFileSync(Node.join([own, "worker/package.json"])))->toContain("0.1.1")
    expect(calls.contents)->toBe(0)
    expect(Node.readFileSync(Node.join([own, "Cargo.lock"])))->toBe(lockBefore)
    tree(sibling, [("lib/src/lib.rs", "one\n"), ("lib/Cargo.toml", crate(~name="lib"))])
    expect(
      Bump.write(
        ~root=own,
        ~run=(~cwd=?, program, arguments) => {
          expect(cwd)->toBe(Some(own))
          expect(program)->toBe("cargo")
          expect(arguments)->toEqual(["update", "--workspace", "--offline"])
          calls := calls.contents + 1
          1
        },
        Bump.moving(Roll.judged(~root=own)),
      ),
    )->toBe(false)
    expect(calls.contents)->toBe(1)
  })

  test("bump pays a nonbreaking outgoing commit after main advanced", () => {
    let root = root.contents
    scratch(root)
    tree(root, [("a/src/lib.rs", "two\n")])
    landed(root, "feat: change a")
    expect(versions(root))->toEqual([("a", "0.1.1"), ("b", "0.1.1"), ("r", "0.1.0")])
    bumped(root)
    landed(root, "chore: roll")
    expect(Versions.outgoing(~root))->toEqual([])
  })

  // A main line holding a root that is only a pnpm workspace, beside `manifests`.
  let workspace = (root, manifests) => {
    Node.env->Dict.set("JJ_USER", "test")
    Node.env->Dict.set("JJ_EMAIL", "test@localhost")
    jj(root, ["git", "init", "--colocate"])->ignore
    tree(root, [("mise.toml", "[tools]\n"), ...manifests])
    landed(root, "chore: begin")
  }

  let bare = "{\n\t\"name\": \"w\",\n\t\"private\": true\n}\n"
  let app = (~name="@x/x", ~version="0.1.0") =>
    `{\n\t"name": "${name}",\n\t"version": "${version}",\n\t"private": true\n}\n`

  test("passes over a private root without a version, and rolls the app beside it", () => {
    let root = root.contents
    workspace(
      root,
      [("package.json", bare), ("apps/x/package.json", app()), ("apps/x/a.ts", "1\n")],
    )
    tree(root, [("apps/x/a.ts", "2\n"), ("mise.toml", "[tools]\nnode = \"24\"\n")])
    expect(versions(root))->toEqual([("@x/x", "0.1.1")])
    bumped(root)
    expect(Node.readFileSync(Node.join([root, "package.json"])))->toBe(bare)
  })

  test("a change at a workspace root alone rolls nothing", () => {
    let root = root.contents
    workspace(
      root,
      [("package.json", bare), ("apps/x/package.json", app()), ("apps/x/a.ts", "1\n")],
    )
    tree(root, [("mise.toml", "[tools]\nnode = \"24\"\n"), ("package.json", bare ++ "\n")])
    expect(Bump.moving(Roll.planned(~root)))->toEqual([])
  })

  test("a package moved under the root continues the version its name had", () => {
    let root = root.contents
    workspace(root, [("package.json", app(~name="@x/c", ~version="0.1.5")), ("a.ts", "1\n")])
    tree(
      root,
      [
        ("package.json", bare),
        ("apps/c/package.json", app(~name="@x/c", ~version="0.1.5")),
        ("apps/c/a.ts", "1\n"),
        ("pkgs/p/package.json", app(~name="@x/p")),
      ],
    )
    expect(versions(root))->toEqual([("@x/c", "0.1.6"), ("@x/p", "0.1.0")])
  })
})
