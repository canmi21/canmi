open Testing

let root = temporaryRoot("graph-")
let layout = (): Graph.layout => {
  root: root.contents,
  packageDirectories: ["apps/*/*", "libs/*"],
  appRoots: ["apps/data", "apps/edge"],
}

describe("what a binary carries", () => {
  test("is what its own code includes, never a test's", () => {
    tree(
      root.contents,
      [
        ("apps/data/store/service.toml", "name = \"store\"\n"),
        ("apps/data/store/schema.sql", ""),
        ("apps/data/store/fixture.json", ""),
        (
          "apps/data/store/src/main.rs",
          "const S: &str = include_str!(\"../schema.sql\");\n#[cfg(test)]\nmod tests;\n" ++ "#[cfg(test)]\npub(crate) mod testing;\n#[cfg(test)]\nmod inline { const F: &str = include_str!(\"../fixture.json\"); }\n",
        ),
        // A test module in a file of its own, and one in a directory of its own.
        ("apps/data/store/src/tests.rs", "const D: &str = include_str!(\"../service.toml\");\n"),
        ("apps/data/store/src/testing/mod.rs", "mod deeper;\n"),
        (
          "apps/data/store/src/testing/deeper.rs",
          "const D: &str = include_str!(\"../../fixture.json\");\n",
        ),
        ("apps/data/store/tests/api.rs", "const D: &str = include_str!(\"../service.toml\");\n"),
      ],
    )
    let carried = Graph.embedded(root.contents, Map.fromArray([("apps/data/store", "store")]))
    expect(carried->Graph.keysOf)->toEqual(["apps/data/store/schema.sql"])
  })

  test("reads a test module declared beside a file that is not the crate root", () => {
    tree(
      root.contents,
      [
        ("apps/data/secrets/service.toml", ""),
        ("apps/data/secrets/src/main.rs", "mod peers;\n"),
        (
          "apps/data/secrets/src/peers.rs",
          "const N: &str = include_str!(\"../service.toml\");\n#[cfg(test)]\nmod tests;\n",
        ),
        (
          "apps/data/secrets/src/peers/tests.rs",
          "const D: &str = include_str!(\"../../service.toml\");\n",
        ),
      ],
    )
    let crates = Map.fromArray([("apps/data/secrets", "secrets")])
    expect(
      Graph.embedded(root.contents, crates)->Map.get("apps/data/secrets/service.toml"),
    )->toEqual(Some(Set.fromArray(["secrets"])))
    tree(root.contents, [("apps/data/secrets/src/peers.rs", "#[cfg(test)]\nmod tests;\n")])
    expect(Graph.embedded(root.contents, crates)->Map.size)->toBe(0)
  })
})

describe("the apps", () =>
  test("are found under each root, and a path is in the one it sits in", () => {
    tree(
      root.contents,
      [("apps/data/store/x", ""), ("apps/edge/gateway/x", ""), ("libs/sdk/x", "")],
    )
    expect(Graph.appDirectories(layout())->Graph.keysOf)->toEqual(["store", "gateway"])
    expect(Graph.appOf(layout(), "apps/data/store/src/main.rs"))->toEqual(Some("store"))
    expect(Graph.appOf(layout(), "apps/data/README.md"))->toBeUndefined
    expect(Graph.appOf(layout(), "libs/sdk/src/lib.rs"))->toBeUndefined
  })
)

describe("the packages", () =>
  test("are found by their patterns, with edges from what they depend on", () => {
    tree(
      root.contents,
      [
        (
          "apps/edge/gateway/package.json",
          `{"name": "@m/gateway", "dependencies": {"@m/sdk": "workspace:*", "hono": "4"}}`,
        ),
        ("libs/sdk/package.json", `{"name": "@m/sdk"}`),
        ("libs/probe/package.json", `{"name": "@m/probe", "devDependencies": {"@m/sdk": "*"}}`),
      ],
    )
    let {directories, edges}: Graph.nodeGraph = Graph.nodeGraph(layout())
    expect(directories)->toEqual(
      Map.fromArray([
        ("apps/edge/gateway", "@m/gateway"),
        ("libs/probe", "@m/probe"),
        ("libs/sdk", "@m/sdk"),
      ]),
    )
    expect(Graph.dependents(["@m/sdk"], edges))->toEqual(
      Set.fromArray(["@m/sdk", "@m/gateway", "@m/probe"]),
    )
    expect(Graph.owner("libs/sdk/src/a.ts", directories->Graph.keysOf))->toEqual(Some("libs/sdk"))
    expect(Graph.owner("libs/other/a.ts", directories->Graph.keysOf))->toBeUndefined
  })
)
