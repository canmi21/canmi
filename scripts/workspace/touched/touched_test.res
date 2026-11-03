open Testing

let blocks = [("storage", "code/products/storage"), ("host", "code/products/host")]
let touched = paths => Touched.of_(~paths, ~blocks, ~full=false)

describe("the blocks a change touches", () => {
  test("is every block when asked for full", () => {
    expect(Touched.of_(~paths=["code/products/host/a.rs"], ~blocks, ~full=true))->toEqual(
      Touched.Every,
    )
  })
  test("is every block for an empty change", () => {
    expect(touched([]))->toEqual(Touched.Every)
  })
  test("names the block holding one file", () => {
    expect(touched(["code/products/host/src/a.rs"]))->toEqual(Touched.Blocks(["host"]))
  })
  test("names two blocks once each in the order given", () => {
    let paths = ["code/products/host/a.rs", "code/products/storage/b.rs", "code/products/host/c.rs"]
    expect(touched(paths))->toEqual(Touched.Blocks(["storage", "host"]))
  })
  test("is every block for a path in no block's directory", () => {
    expect(touched(["code/products/host/a.rs", "model/x.res"]))->toEqual(Touched.Every)
  })
  test("does not count a directory that only begins like a block's", () => {
    expect(touched(["code/products/storagex/a.rs"]))->toEqual(Touched.Every)
    expect(touched(["code/products/storage"]))->toEqual(Touched.Every)
  })
})

describe("the blocks of a repository and what its verify is handed", () => {
  test("names each package under code/ by its name without its scope, and its directory", () => {
    let root = Node.mkdtempSync(Node.join([Node.tmpdir(), "touched-"]))
    let package = (directory, name) => {
      Node.mkdirAll(Node.join([root, directory]))
      Node.writeFileSync(Node.join([root, directory, "package.json"]), `{"name": "${name}"}`)
    }
    package("code/products/storage", "@monoflake/storage")
    package("code/libs/keys", "@monoflake/keys")
    expect(
      Touched.blocksOf(root)->Array.toSorted(((a, _), (b, _)) => String.compare(a, b)),
    )->toEqual([("keys", "code/libs/keys"), ("storage", "code/products/storage")])
    expect(Touched.arguments(root))->toEqual([])
    Node.rmSync(root, {recursive: true, force: true})
  })
})

describe("a changed library's dependents", () => {
  let uses = [
    ("keys", []),
    ("envelope", []),
    ("storage", ["envelope", "keys"]),
    ("gateway", ["envelope"]),
    ("deploy", ["storage"]),
  ]
  test("brings every block using it, at any depth", () => {
    expect(Touched.withDependents(["keys"], ~uses))->toEqual(["keys", "storage", "deploy"])
    expect(Touched.withDependents(["envelope"], ~uses))->toEqual([
      "envelope",
      "storage",
      "gateway",
      "deploy",
    ])
  })
  test("leaves a block no other uses alone", () => {
    expect(Touched.withDependents(["gateway"], ~uses))->toEqual(["gateway"])
  })
})

describe("the verify parts a change touches", () => {
  let table = [
    (["pages/**", "*.md"], ["format"]),
    (["scripts/**"], ["format", "compile", "tests"]),
    (["assets/*"], []),
  ]
  test("formats a documents only change", () => {
    expect(Touched.parts(~paths=["pages/nested/guide.md", "README.md"], ~table))->toEqual(
      Some(["format"]),
    )
  })
  test("selects a script row's parts once in table order", () => {
    expect(Touched.parts(~paths=["scripts/a.res", "pages/a.md", "scripts/b.res"], ~table))->toEqual(
      Some(["format", "compile", "tests"]),
    )
  })
  test("requires every path to match a row", () => {
    expect(Touched.parts(~paths=["pages/a.md", "source/a.rs"], ~table))->toEqual(None)
  })
  test("does not let a single star cross a slash", () => {
    expect(Touched.parts(~paths=["assets/icon.svg"], ~table))->toEqual(Some([]))
    expect(Touched.parts(~paths=["assets/nested/icon.svg"], ~table))->toEqual(None)
    expect(Touched.parts(~paths=["source/guide.md"], ~table))->toEqual(None)
  })
  test("matches the whole path and treats other characters literally", () => {
    let table = [(["a.b/[x]+?", "prefix*suffix"], ["format"])]
    expect(Touched.parts(~paths=["a.b/[x]+?", "prefixsuffix"], ~table))->toEqual(Some(["format"]))
    expect(Touched.parts(~paths=["axb/[x]+?"], ~table))->toEqual(None)
    expect(Touched.parts(~paths=["prefixsuffix/extra"], ~table))->toEqual(None)
  })
  test("unions overlapping rows in the order the table first names each part", () => {
    let table = [
      (["other/**"], ["tests"]),
      (["scripts/**"], ["compile", "tests"]),
      (["**"], ["format", "compile"]),
    ]
    expect(Touched.parts(~paths=["scripts/a.res"], ~table))->toEqual(
      Some(["tests", "compile", "format"]),
    )
  })
  test("selects no parts for an empty change", () => {
    expect(Touched.parts(~paths=[], ~table))->toEqual(Some([]))
  })
})

describe("a repository's verify part table", () => {
  test("reads valid rows and skips malformed rows", () => {
    let root = Node.mkdtempSync(Node.join([Node.tmpdir(), "touched-table-"]))
    try {
      let config = Node.join([root, "workspace.toml"])
      expect(Touched.tableOf(root))->toEqual(None)
      Node.writeFileSync(config, "[check]\n")
      expect(Touched.tableOf(root))->toEqual(None)
      Node.writeFileSync(config, "[check]\ntouched = []\n")
      expect(Touched.tableOf(root))->toEqual(None)
      Node.writeFileSync(
        config,
        `[[check.touched]]
paths = ["pages/**", "*.md"]
parts = ["format"]
[[check.touched]]
paths = ["scripts/**"]
parts = ["compile", "tests"]
[[check.touched]]
paths = ["assets/*"]
parts = []
[[check.touched]]
paths = []
parts = []
[[check.touched]]
paths = ["bad/**", 1]
parts = ["bad"]
[[check.touched]]
paths = ["missing/**"]
[[check.touched]]
paths = "wrong"
parts = ["bad"]
[[check.touched]]
paths = ["bad/**"]
parts = [false]
`,
      )
      expect(Touched.tableOf(root))->toEqual(
        Some([
          (["pages/**", "*.md"], ["format"]),
          (["scripts/**"], ["compile", "tests"]),
          (["assets/*"], []),
          ([], []),
        ]),
      )
      Node.writeFileSync(config, "[[check.touched]]\npaths = [1]\nparts = []\n")
      expect(Touched.tableOf(root))->toEqual(None)
      Node.writeFileSync(config, "[invalid")
      expect(Touched.tableOf(root))->toEqual(None)
    } catch {
    | error =>
      Node.rmSync(root, {recursive: true, force: true})
      throw(error)
    }
    Node.rmSync(root, {recursive: true, force: true})
  })
})

describe("a crate's blocks and uses", () => {
  test("reads Cargo.toml beside package.json, build dependencies among its uses", () => {
    let root = Node.mkdtempSync(Node.join([Node.tmpdir(), "touched-cargo-"]))
    let write = (directory, file, text) => {
      Node.mkdirAll(Node.join([root, directory]))
      Node.writeFileSync(Node.join([root, directory, file]), text)
    }
    write("code/libs/envelope", "package.json", `{"name": "@monoflake/envelope"}`)
    write(
      "code/libs/envelope",
      "Cargo.toml",
      "[package]\nname = \"envelope\"\n\n[build-dependencies]\nenvelope-generator = { path = \"../../tools/envelope-generator\" }\nserde = \"1\"\n",
    )
    write(
      "code/tools/envelope-generator",
      "Cargo.toml",
      "[package]\nname = \"envelope-generator\"\n",
    )
    let uses = Touched.usesOf(root)->Array.toSorted(((a, _), (b, _)) => String.compare(a, b))
    expect(uses)->toEqual([("envelope", ["envelope-generator"]), ("envelope-generator", [])])
    expect(Touched.withDependents(["envelope-generator"], ~uses))->toEqual([
      "envelope",
      "envelope-generator",
    ])
    Node.rmSync(root, {recursive: true, force: true})
  })
})
