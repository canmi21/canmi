open Testing

let repos = "/w/repos"
let at = path => `${repos}/${path}`
let all =
  ["platform", "cloud", "driver", "machine", "runtime", "console"]->Array.map(one =>
    at(`monoflake/${one}`)
  )

describe("a sibling a build reaches into", () => {
  test("is read from a link, a path dependency, a sibling named, and a -C into it", () => {
    let driver = at("monoflake/driver")
    let found = (file, text) => Waves.reached(~repo=driver, ~file, ~others=all, text)
    expect(found(`${driver}/package.json`, `"@monoflake/platform": "link:../platform"`))->toEqual([
      at("monoflake/platform"),
    ])
    expect(
      found(
        `${driver}/cloudflare/object/package.json`,
        `"@monoflake/codec": "link:../../../platform/code/libs/codec"`,
      ),
    )->toEqual([at("monoflake/platform")])
    expect(found(`${driver}/workspace.toml`, `repository = "../platform"`))->toEqual([
      at("monoflake/platform"),
    ])
    expect(found(`${driver}/mise.toml`, `run = ["mise -C ../platform run prepare"]`))->toEqual([
      at("monoflake/platform"),
    ])
    expect(found(`${driver}/Cargo.toml`, `keys = { path = "../machine/keys" }`))->toEqual([
      at("monoflake/machine"),
    ])
  })

  test("is not a path that stays inside its own repository or reaches nothing registered", () => {
    let platform = at("monoflake/platform")
    let found = (file, text) => Waves.reached(~repo=platform, ~file, ~others=all, text)
    expect(
      found(`${platform}/code/libs/envelope/Cargo.toml`, `codec = { path = "../codec" }`),
    )->toEqual([])
    expect(found(`${platform}/package.json`, `"x": "link:../../elsewhere"`))->toEqual([])
    expect(found(`${platform}/package.json`, `"x": "^1.2.0"`))->toEqual([])
  })
})

describe("the waves", () => {
  let root = "/w"
  let workspace = [root]
  let edges = [
    (at("monoflake/driver"), at("monoflake/platform"), "driver/package.json"),
    (at("monoflake/cloud"), at("monoflake/platform"), "cloud/package.json"),
    (at("monoflake/cloud"), at("monoflake/driver"), "cloud/package.json"),
    (at("monoflake/cloud"), at("monoflake/machine"), "cloud/package.json"),
  ]

  test("put the workspace alone first, then each repository after its siblings", () => {
    expect(Waves.plan(Array.concat(workspace, all), ~first=root, ~edges))->toEqual([
      [root],
      [
        at("monoflake/platform"),
        at("monoflake/machine"),
        at("monoflake/runtime"),
        at("monoflake/console"),
      ],
      [at("monoflake/driver")],
      [at("monoflake/cloud")],
    ])
  })

  test("order by nothing a run leaves out, and need no workspace", () => {
    let chosen = [at("monoflake/driver"), at("monoflake/cloud")]
    expect(Waves.plan(chosen, ~first=root, ~edges))->toEqual([
      [at("monoflake/driver")],
      [at("monoflake/cloud")],
    ])
  })

  test("take a cycle one at a time, in the order given", () => {
    let a = at("a")
    let b = at("b")
    let cycle = [(a, b, "a"), (b, a, "b")]
    expect(Waves.plan([root, a, b, at("c")], ~first=root, ~edges=cycle))->toEqual([
      [root],
      [at("c")],
      [a],
      [b],
    ])
  })
})

describe("one run's outcome", () => {
  test("lists each part in the registry's order, whatever order the waves ended in", () => {
    let order = ["workspace", "monoflake/platform", "monoflake/driver", "apps/rdm"]
    let one = (failed): Waves.outcome => {...Waves.nothing(), failed}
    let merged = Waves.merged(
      [("x", one(["apps/rdm"])), ("y", one(["monoflake/driver"])), ("z", one(["workspace"]))],
      ~order,
    )
    expect(merged.failed)->toEqual(["workspace", "monoflake/driver", "apps/rdm"])
  })
})

describe("a wave's child", () => {
  let root = temporaryRoot("waves-child-")

  // A stand-in for one repository's update, printing slowly and keeping its outcome.
  let script = name =>
    `const fs = require('fs');
let n = 0;
const tick = setInterval(() => {
  console.log('${name} line ' + n);
  if (++n === 4) {
    clearInterval(tick);
    fs.writeFileSync(process.env.UPDATE_OUTCOME, JSON.stringify({skipped: [], failed: ['${name}'], reverted: [], held: []}));
  }
}, 5);`

  testAsync("keeps each repository's output whole and reads back what it came to", async () => {
    let command = repo => ("node", ["-e", script(Node.basename(repo))])
    let answers = await Net.bounded(
      ["/w/one", "/w/two"],
      ~limit=2,
      repo => Waves.child(repo, ~root=root.contents, ~command),
    )
    let lines = name =>
      [0, 1, 2, 3]->Array.map(n => `${name} line ${n->Int.toString}`)->Array.join("\n")
    expect(answers->Array.map(((block, _)) => block))->toEqual([lines("one"), lines("two")])
    expect(answers->Array.map(((_, outcome)) => outcome.failed))->toEqual([["one"], ["two"]])
    expect(Node.env->Dict.get(Waves.outcomeVariable))->toBe(None)
  })

  testAsync("counts a child that kept no outcome as failed where it exited non-zero", async () => {
    let (_, outcome) = await Waves.child(
      "/w/apps/rdm",
      ~root=root.contents,
      ~command=_ => ("node", ["-e", "process.exit(3)"]),
    )
    expect(outcome.failed->Array.length)->toBe(1)
  })
})
