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

describe("the formatting of a lane's files", () => {
  test("plans one check per formatter over the files it owns", () => {
    let plan = Handed.formatPlan(["a.res", "b.rs", "c.md", "d.toml", "e.resi"])
    expect(plan->Array.map(((program, _, mine)) => (program, mine)))->toEqual([
      ("rescript", ["a.res", "e.resi"]),
      ("oxfmt", ["c.md"]),
      ("rustfmt", ["b.rs"]),
    ])
  })

  test("reports the files a formatter names, or all of its files when it names none", () => {
    let said = (status, text) => (_program, _args) => (status, text)
    let names = ["a.res", "b.res", "c.md"]
    expect(Handed.unformatted(~check=said(1, "[format check] b.res\n"), names)->files)->toEqual([
      "b.res",
      "c.md",
    ])
    expect(Handed.unformatted(~check=said(0, "b.res"), names))->toEqual([])
  })
})

describe("a lane judged from inside", () => {
  let base = Testing.temporaryRoot("handed-form-")
  let comment = "// " ++ String.repeat("x", 98)
  let build = () => {
    let repo = Node.join([base.contents, "repo"])
    Testing.tree(
      base.contents,
      Array.concat(
        [("repo/long.res", comment ++ "\nlet a = 1\n"), ("repo/ok.res", "let a = 1\n")],
        Array.fromInitializer(~length=17, at => (`repo/wide/f${Int.toString(at)}.txt`, "x\n")),
      ),
    )
    ignore(Node.spawnSync("jj", ["git", "init", repo], {encoding: "utf8"}))
    ignore(Node.spawnSync("jj", ["bookmark", "create", "main", "-r", "@"], {cwd: repo}))
    ignore(Node.spawnSync("jj", ["new", "-m", "feat: x"], {cwd: repo}))
    repo
  }

  test("reports a directory past the width and a comment past the line", () => {
    let repo = build()
    expect(Handed.formedIn(repo)->Array.toSorted(String.compare))->toEqual(["comments", "shape"])
  })

  test("is refused as a whole when a formatter or the form layer finds something", () => {
    let repo = build()
    let run = (~check, ~form) =>
      Handed.report(~cwd=repo, ~dir="lane", ~own=[], ~all=true, ~check, ~form)
    Node.writeFileSync(Node.join([repo, "loose.res"]), "let   a = 1\n")
    expect(run(~check=(_, _) => (1, "loose.res"), ~form=_ => []))->toBe(1)
    expect(run(~check=(_, _) => (0, ""), ~form=_ => ["shape"]))->toBe(1)
  })

  test("passes a clean lane that changed nothing refused", () => {
    let repo = Node.join([base.contents, "clean"])
    Testing.tree(base.contents, [("clean/a.res", "let a = 1\n")])
    ignore(Node.spawnSync("jj", ["git", "init", repo], {encoding: "utf8"}))
    ignore(Node.spawnSync("jj", ["bookmark", "create", "main", "-r", "@"], {cwd: repo}))
    ignore(Node.spawnSync("jj", ["new", "-m", "feat: x"], {cwd: repo}))
    Node.writeFileSync(Node.join([repo, "b.res"]), "let b = 2\n")
    let ran = ref(false)
    let check = (_, _) => {
      ran := true
      (0, "")
    }
    expect(Handed.report(~cwd=repo, ~dir="lane", ~own=[], ~all=true, ~check, ~form=_ => []))->toBe(
      0,
    )
    expect(ran.contents)->toBe(true)
    expect(Handed.formedIn(repo))->toEqual([])
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
    let check = (_, _) => (0, "")
    expect(Handed.report(~cwd=repo, ~dir="lane", ~own=[], ~all=true, ~check, ~form=_ => []))->toBe(
      1,
    )
    expect(Handed.report(~cwd=repo, ~dir="lane", ~own=[], ~all=false))->toBe(0)
  })
})
