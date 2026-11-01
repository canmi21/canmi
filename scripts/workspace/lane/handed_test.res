open Testing

let counts = (file): option<int> =>
  switch file {
  | "big.res" => Some(1200)
  | "wide.res" => Some(900)
  | "ok.res" => Some(800)
  | "pnpm-lock.yaml" => Some(5000)
  | _ => None
  }

let files = (found: array<Handed.finding>) => found->Array.map(one => one.file)

describe("the lengths of a lane's files", () => {
  let names = ["big.res", "wide.res", "ok.res", "pnpm-lock.yaml", "gone.res"]
  let judged = Handed.sizes(~lines=counts, names)

  test("refuse a file past hardLines and list one past splitBeforeLines", () => {
    expect(judged.refused->files)->toEqual(["big.res"])
    expect(judged.listed->files)->toEqual(["wide.res"])
  })

  test("pass over a lockfile and a file that is gone", () => {
    expect(judged.refused->files->Array.includes("pnpm-lock.yaml"))->toBe(false)
    expect(judged.listed->files->Array.includes("gone.res"))->toBe(false)
  })
})

describe("the rules a lane's diff is read against", () => {
  test("single-writer refuses what only the integrator changes", () => {
    let touched = ["model/rules/code.res", "docs/code.md", "AGENTS.md", "src/a.res"]
    expect(Handed.single(touched)->files)->toEqual([
      "model/rules/code.res",
      "docs/code.md",
      "AGENTS.md",
    ])
  })

  test("lockfile-derived refuses a lockfile at any depth", () => {
    expect(Handed.locked(["a/pnpm-lock.yaml", "Cargo.lock", "src/a.res"])->files)->toEqual([
      "a/pnpm-lock.yaml",
      "Cargo.lock",
    ])
  })

  test("own-directory refuses a file outside the directories given, and judges none given", () => {
    let outside = Handed.outside(~own=["blocks/a"], ["blocks/a/x.res", "blocks/b/y.res"])
    expect(outside->files)->toEqual(["blocks/b/y.res"])
    expect(Handed.outside(~own=[], ["blocks/b/y.res"]))->toEqual([])
  })

  test("a plain change is refused by none", () => {
    let judged = Handed.judge(~lines=counts, ~own=["src"], ["src/a.res"])
    expect(judged.refused)->toEqual([])
  })
})

describe("a real lane", () => {
  let base = Testing.temporaryRoot("handed-")
  test("is judged by the files it changed from main", () => {
    let repo = Node.join([base.contents, "repo"])
    let jj = args => Node.spawnSync("jj", args, {cwd: repo, encoding: "utf8"})
    Testing.tree(base.contents, [("repo/a.txt", "one")])
    ignore(Node.spawnSync("jj", ["git", "init", repo], {encoding: "utf8"}))
    ignore(jj(["bookmark", "create", "main", "-r", "@"]))
    ignore(jj(["new", "-m", "feat: x"]))
    Node.writeFileSync(Node.join([repo, "b.txt"]), "two")
    Node.writeFileSync(Node.join([repo, "pnpm-lock.yaml"]), "x")
    expect(Handed.changed(repo))->toEqual(Ok(["b.txt", "pnpm-lock.yaml"]))
    expect(Handed.report(~cwd=repo, ~dir="lane", ~own=[], ~all=true))->toBe(1)
    expect(Handed.report(~cwd=repo, ~dir="lane", ~own=[], ~all=false))->toBe(0)
  })
})
