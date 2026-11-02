open Testing

let platformPlan = `{"items": [
  {"id": "contracts-v2", "says": "the next contracts", "delivers": ["contracts"], "holds": {"owes": "the file"}},
  {"id": "tidy", "says": "tidy", "holds": {"owes": "a pass"}}
]}`

let cloudPlan = `{"items": [
  {"id": "record", "says": "a record", "holds": {"owes": "its shape"}},
  {"id": "roll", "says": "a roll", "after": ["record"], "needs": ["fixture/platform:contracts"], "delivers": ["archive"], "holds": {"owes": "a task"}},
  {"id": "old", "says": "done", "holds": {"committed": {"commit": "abc1234"}}}
]}`

let parsed = (owner, text) =>
  switch Repo_plan.parse(text, ~owner) {
  | Ok(items) => items
  | Error(why) => throw(Repo_plan.Bad(why))
  }

let platform = (~plan=platformPlan, ~exports=["contracts"], ~depends=[]): Repo_plan.source => {
  owner: "fixture/platform",
  file: "model/plan.json",
  isPrivate: false,
  text: plan,
  items: parsed("fixture/platform", plan),
  boundary: {exports, depends},
}

let cloud = (
  ~plan=cloudPlan,
  ~isPrivate=true,
  ~exports=["archive"],
  ~depends=["fixture/platform:contracts"],
): Repo_plan.source => {
  owner: "fixture/cloud",
  file: "model/plan.json",
  isPrivate,
  text: plan,
  items: parsed("fixture/cloud", plan),
  boundary: {exports, depends},
}

let workspace: Repo_plan.source = {
  owner: "workspace",
  file: "model/plan/work.res",
  isPrivate: false,
  text: "",
  items: [],
  boundary: {exports: [], depends: []},
}

let repos = ["fixture/platform", "fixture/cloud", "fixture/other"]

let own = (source, ~listed=None) =>
  Repo_plan.ownProblems(
    source,
    ~repos,
    ~rules=[],
    ~has=_ => true,
    ~passes=_ => None,
    ~rfc=(_, _) => true,
    ~committed=(_, _) => Some(true),
    ~listed,
  )

let joined = (sources, ~skipped=_ => None) => Repo_plan.joinProblems(sources, ~repos, ~skipped)

describe("a repository's own plan", () => {
  test("is model/plan.json, or model/plan/plan.json where only that one is present", () => {
    let root = Node.mkdtempSync(Node.join([Node.tmpdir(), "plan-"]))
    expect(Repo_plan.fileAt(root))->toBe("model/plan.json")
    Node.mkdirAll(Node.join([root, "model", "plan"]))
    Node.writeFileSync(Node.join([root, "model", "plan", "plan.json"]), `{"items": []}`)
    expect(Repo_plan.fileAt(root))->toBe("model/plan/plan.json")
    Node.writeFileSync(Node.join([root, "model", "plan.json"]), `{"items": []}`)
    expect(Repo_plan.fileAt(root))->toBe("model/plan.json")
    Node.rmSync(root, {recursive: true, force: true})
  })

  test("reads its items, defaulting the repository to its owner", () => {
    let items = cloud().items
    expect(items->Array.length)->toBe(3)
    expect((items->Array.getUnsafe(0)).repos)->toEqual(["fixture/cloud"])
    expect((items->Array.getUnsafe(1)).needs)->toEqual(Some(["fixture/platform:contracts"]))
    expect((items->Array.getUnsafe(2)).holds)->toEqual(
      Committed({repo: "fixture/cloud", commit: "abc1234"}),
    )
  })

  test("refuses another repository's item in after, a key, a hold or a document unknown", () => {
    let refused = text => Repo_plan.parse(text, ~owner="fixture/cloud")->Result.isError
    expect(
      refused(`{"items": [{"id": "a", "says": "x", "after": ["fixture/platform:b"], "holds": {"owes": "y"}}]}`),
    )->toBe(true)
    expect(
      refused(`{"items": [{"id": "a", "says": "x", "mood": 1, "holds": {"owes": "y"}}]}`),
    )->toBe(true)
    expect(refused(`{"items": [{"id": "a", "says": "x", "holds": {"done": "y"}}]}`))->toBe(true)
    expect(refused("not json"))->toBe(true)
  })

  test("holds a need inside depends and a delivery inside exports, reading no sibling", () => {
    expect(own(cloud()))->toEqual([])
    expect(own(cloud(~depends=[])))->toEqual([
      "fixture/cloud: plan roll: needs fixture/platform:contracts, which is not in [boundary] depends",
    ])
    expect(own(cloud(~exports=[])))->toEqual([
      "fixture/cloud: plan roll: delivers archive, which is not in [boundary] exports",
    ])
  })

  test("holds its own graph acyclic and its ids unique", () => {
    let doubled = `{"items": [
      {"id": "a", "says": "x", "after": ["b"], "holds": {"owes": "y"}},
      {"id": "b", "says": "x", "after": ["a"], "holds": {"owes": "y"}},
      {"id": "b", "says": "x", "holds": {"owes": "y"}}
    ]}`
    let found = own(cloud(~plan=doubled, ~depends=[]))
    expect(found->Array.some(line => line->String.includes("after itself")))->toBe(true)
    expect(found->Array.some(line => line->String.includes("taken by another")))->toBe(true)
  })

  test("keeps an id unique per repository, not across them", () => {
    let twin = `{"items": [{"id": "record", "says": "x", "holds": {"owes": "y"}}]}`
    expect(joined([workspace, cloud(), platform(~plan=twin, ~exports=["contracts"])]))->toEqual([])
  })

  test("refuses a private identifier in a public plan and not in a private one", () => {
    let listed = Some(Scan.patterns([{identifier: "secretword", exceptions: [], allowed: None}]))
    let leaky = `{"items": [\n{"id": "a", "says": "about secretword", "holds": {"owes": "y"}}\n]}`
    expect(own(cloud(~plan=leaky, ~isPrivate=false, ~depends=[]), ~listed))->toEqual([
      "fixture/cloud: plan fixture/cloud: model/plan.json:2: a public plan holds a private identifier",
    ])
    expect(own(cloud(~plan=leaky, ~isPrivate=true, ~depends=[]), ~listed))->toEqual([])
  })
})

describe("the total joining the repositories", () => {
  let keys = entries => entries->Array.map((entry: Repo_plan.entry) => entry.item.id)
  let after = (entries, id) =>
    (
      entries->Array.find((entry: Repo_plan.entry) => entry.item.id == id)->Option.getOrThrow
    ).item.after

  test("makes a need wait on the items that deliver it", () => {
    let merged = Repo_plan.merge([workspace, platform(), cloud()])
    expect(keys(merged))->toEqual([
      "fixture/platform:contracts-v2",
      "fixture/platform:tidy",
      "fixture/cloud:record",
      "fixture/cloud:roll",
      "fixture/cloud:old",
    ])
    expect(after(merged, "fixture/cloud:roll"))->toEqual([
      "fixture/cloud:record",
      "fixture/platform:contracts-v2",
    ])
  })

  test("leaves a standing export, which nothing delivers, owing nothing", () => {
    let standing = platform(~plan=`{"items": []}`)
    let merged = Repo_plan.merge([workspace, standing, cloud()])
    expect(after(merged, "fixture/cloud:roll"))->toEqual(["fixture/cloud:record"])
  })

  test("waits on an exporter that is not read, as on something undelivered", () => {
    let merged = Repo_plan.merge([workspace, cloud()])
    expect(after(merged, "fixture/cloud:roll"))->toEqual([
      "fixture/cloud:record",
      "fixture/platform:contracts",
    ])
  })

  test("derives an item done only once what it needs is delivered", () => {
    let state = (sources, id) => {
      let items = Repo_plan.merge(sources)->Array.map((entry: Repo_plan.entry) => entry.item)
      let item = items->Array.find(item => item.id == id)->Option.getOrThrow
      Plan.stateOf(items, item, ~committed=(_, _) => Some(true))
    }
    let late = state([workspace, platform(), cloud()], "fixture/cloud:roll")
    expect(late)->toEqual(Behind(["fixture/cloud:record", "fixture/platform:contracts-v2"]))
    let delivered = `{"items": [{"id": "contracts-v2", "says": "x", "delivers": ["contracts"], "holds": {"observed": {"at": "2026-11-01", "what": "shipped"}}}]}`
    let ready = state([workspace, platform(~plan=delivered), cloud()], "fixture/cloud:roll")
    expect(ready)->toEqual(Behind(["fixture/cloud:record"]))
  })

  test("names a dependency its exporter does not list, or one in no registry", () => {
    expect(joined([workspace, platform(~exports=[]), cloud()]))->toEqual([
      "plan fixture/cloud: depends on fixture/platform:contracts, which fixture/platform does not export",
    ])
    expect(joined([workspace, platform(), cloud(~depends=["fixture/nowhere:x"])]))->toEqual([
      "plan fixture/cloud: depends on fixture/nowhere:x, fixture/nowhere is not in repos/registry.toml",
    ])
  })

  test("passes over an exporter that is not cloned and says so", () => {
    let skipped = name => name == "fixture/platform" ? Some("not cloned") : None
    expect(joined([workspace, cloud()], ~skipped))->toEqual([])
    expect(Repo_plan.passedOver([workspace, cloud()], ~skipped))->toEqual([
      "plan fixture/cloud: depends on fixture/platform:contracts not joined, fixture/platform not cloned",
    ])
    expect(joined([workspace, cloud()]))->toEqual([
      "plan fixture/cloud: depends on fixture/platform:contracts, fixture/platform declares no workspace.toml to export it",
    ])
  })

  test("finds a cycle that runs through both repositories", () => {
    let looping = `{"items": [{"id": "contracts-v2", "says": "x", "needs": ["fixture/cloud:archive"], "delivers": ["contracts"], "holds": {"owes": "y"}}]}`
    let found = joined([
      workspace,
      platform(~plan=looping, ~depends=["fixture/cloud:archive"]),
      cloud(),
    ])
    expect(found)->toEqual([
      "plan fixture/cloud:roll: is after itself through fixture/platform:contracts-v2, across repositories",
    ])
    expect(joined([workspace, platform(), cloud()]))->toEqual([])
  })
})

describe("the waiting items of a repository's plan", () => {
  let waiting = `{"items": [
    {"id": "later", "says": "the secret thing", "holds": {"owes": "y"}, "waits": "author"},
    {"id": "now", "says": "no wait", "holds": {"owes": "y"}}
  ]}`
  let shown = (~hidden, ~isPrivate=true) =>
    Repo_plan.waitingIn(
      [workspace, cloud(~plan=waiting, ~isPrivate, ~depends=[])],
      ~repo=None,
      ~hidden,
      ~due=_ => false,
    )->Array.map(line => line->String.replaceRegExp(/\u001b\[\d+m/g, ""))

  test("lists the item plainly where the output stays on the machine", () => {
    expect(shown(~hidden=false))->toEqual([
      "deferred fixture/cloud:later: the secret thing -- fixture/cloud; until the author says",
    ])
  })

  test("names a private repository's item by id and repository alone where it could leave", () => {
    expect(shown(~hidden=true))->toEqual([
      "deferred fixture/cloud:later: private, withheld -- fixture/cloud",
    ])
  })

  test("lists a public repository's item plainly even where the output could leave", () => {
    expect(shown(~hidden=true, ~isPrivate=false))->toEqual([
      "deferred fixture/cloud:later: the secret thing -- fixture/cloud; until the author says",
    ])
  })
})
