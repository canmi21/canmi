open Testing

describe("the shape of a tree", () => {
  test("is measured over what version control keeps, the root exempt from the width", () => {
    let wide = Array.fromInitializer(~length=Layout.widest + 1, at => `docs/${Int.toString(at)}.md`)
    expect(Shape.problems(wide, ~cargo=None))->toEqual([
      `docs/: ${Int.toString(Layout.widest + 1)} entries, past ${Int.toString(Layout.widest)}`,
    ])
    let flat = Array.fromInitializer(~length=Layout.widest + 1, at => `${Int.toString(at)}.toml`)
    expect(Shape.problems(flat, ~cargo=None))->toEqual([])
  })

  test("counts depth from a top-level directory, and again from a package's root", () => {
    let deep = "a/1/2/3/4/5/6/file.md"
    expect(Shape.problems([deep], ~cargo=None))->toEqual([`a/1/2/3/4/5/6/: 6 deep, past 5`])
    expect(Shape.problems([deep, "a/1/2/package.json"], ~cargo=None))->toEqual([])
  })

  test("keeps the root to configuration, its Cargo.toml virtual and its rules in docs", () => {
    expect(
      Shape.problems(
        ["main.rs", "vitest.config.ts", "spec/a.md"],
        ~cargo=Some("[package]\nname = \"x\""),
      ),
    )->toEqual([
      "main.rs: a source file at the root, where configuration alone sits",
      "Cargo.toml: a [package] at the root, where a virtual manifest alone is",
      "spec/: the rules are docs/ now",
    ])
    expect(Shape.problems(["Cargo.toml"], ~cargo=Some("[workspace]\nmembers = []")))->toEqual([])
  })
})

describe("a mise task", () => {
  test("runs the limit's lines at most, a list counted step by step", () => {
    let long = Array.fromInitializer(~length=Toolchain.taskLines + 1, _ => "echo")->Array.join("\n")
    expect(
      Tasks.problems(`[tasks.a]\nrun = """\n${long}\n"""\n[tasks.b]\nrun = "x"`, ~file="mise.toml"),
    )->toEqual([
      `mise.toml: [tasks.a] runs ${Int.toString(
          Toolchain.taskLines + 1,
        )} lines, past ${Int.toString(Toolchain.taskLines)}; a script holds it`,
    ])
    expect(Tasks.lines(JSON.Array([JSON.String("a\nb"), JSON.String("c")])))->toBe(3)
  })
})

describe("drift", () => {
  let said = "Every repository keeps its rules in docs and restates nothing the workspace already says to it."
  test("is a sentence the workspace says, or another repository says too", () => {
    let own = Drift.sentences(said, ~file="own.md")
    let repositories = [
      ("a", Drift.sentences(`# A\n\n${said}`, ~file="intro.md")),
      (
        "b",
        Drift.sentences(
          "Words of its own, long enough to count as a sentence by any measure here.",
          ~file="b.md",
        ),
      ),
      (
        "c",
        Drift.sentences(
          "Words of its own, long enough to count as a sentence by any measure here.",
          ~file="c.md",
        ),
      ),
    ]
    expect(Drift.problems(~own, ~repositories, ~only=None))->toEqual([
      `a/intro.md:3 "Every repository keeps its rules in ...": restates the workspace's own.md`,
      `b/b.md:1 "Words of its own, long enough ...": c say it too; two repositories' rule is the workspace's`,
      `c/c.md:1 "Words of its own, long enough ...": b say it too; two repositories' rule is the workspace's`,
    ])
    expect(Drift.problems(~own, ~repositories, ~only=Some("b"))->Array.length)->toBe(1)
  })

  test("leaves code, tables and short phrases unread", () => {
    expect(
      Drift.sentences(`\`\`\`\n${said}\n\`\`\`\n| ${said} |\nshort words only here`, ~file="x"),
    )->toEqual([])
  })
})

describe("a deferred item", () => {
  let rules: array<Rule.t> = [
    {name: "rules-in-docs", says: "", doc: "", held: Check("shape")},
    {name: "drifted", says: "", doc: "", held: Check("drift")},
  ]
  let item: Deferred.item = {
    id: "spec-to-docs",
    what: "",
    repos: ["seam"],
    until: Author,
    waives: ["rules-in-docs"],
  }

  test("names what is there, and waives only what a part can", () => {
    let statuses = Dict.fromArray([("p992n", "accepted")])
    expect(
      Waiting.problemsIn(
        [item, {...item, until: Closes("p992n")}],
        ~repos=["seam"],
        ~rules,
        ~statuses,
      ),
    )->toEqual(["deferred spec-to-docs: its id is taken by another item"])
    expect(
      Waiting.problemsIn(
        [
          {
            ...item,
            id: "Bad id",
            repos: ["gone"],
            until: Closes("zzzzz"),
            waives: ["drifted", "none"],
          },
        ],
        ~repos=["seam"],
        ~rules,
        ~statuses,
      ),
    )->toEqual([
      "deferred Bad id: its id is not lowercase words joined by hyphens",
      "deferred Bad id: gone is not in repos/registry.toml",
      "deferred Bad id: waives drifted, held by no part that can waive: shape",
      "deferred Bad id: waives none, which is no rule",
      "deferred Bad id: waits on zzzzz, which is no RFC",
    ])
  })

  test("waives its rule over its repositories alone", () => {
    expect(Waiting.waiverIn([item], ~repo="seam", ~rule="rules-in-docs"))->toEqual(
      Some("spec-to-docs"),
    )
    expect(Waiting.waiverIn([item], ~repo="apps/still", ~rule="rules-in-docs"))->toEqual(None)
    expect(Waiting.waiverIn([item], ~repo="seam", ~rule="tree-wide"))->toEqual(None)
    expect(Shape.ruled(["spec/a.md"], ~cargo=None))->toEqual([
      ("rules-in-docs", "spec/: the rules are docs/ now"),
    ])
  })
})
