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
        ~statuses=_ => statuses,
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
        ~statuses=_ => statuses,
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
    expect(Waiting.pauserIn([item], ~repo="seam"))->toEqual(None)
    expect(Waiting.pauserIn([{...item, pauses: true}], ~repo="seam"))->toEqual(Some("spec-to-docs"))
    expect(Waiting.pauserIn([{...item, pauses: true}], ~repo="apps/still"))->toEqual(None)
    expect(Shape.ruled(["spec/a.md"], ~cargo=None))->toEqual([
      ("rules-in-docs", "spec/: the rules are docs/ now"),
    ])
  })
})

describe("a workflow's actions", () => {
  let owned = ["canmi21", "monoflake"]
  test("pins an outside action by commit, its release beside it", () => {
    let text =
      [
        "      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1",
        "      - uses: actions/checkout@v7",
        "      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1",
        "      - uses: ./.github/actions/local",
        "      - uses: docker://alpine:3",
      ]->Array.join("\n")
    expect(Workflows.problems(text, ~file="a.yml", ~owned))->toEqual([
      "a.yml:2: actions/checkout@v7 is pinned by v7, not by a commit",
      "a.yml:3: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 has no comment naming its release",
      "a.yml:5: docker://alpine:3 names an image by its tag alone, not its digest",
    ])
  })

  test("takes the author's own at main", () => {
    let text =
      [
        "      - uses: canmi21/canmi/.github/actions/workspace@main",
        "      - uses: monoflake/runtime@3d3c42e5aac5ba805825da76410c181273ba90b1 # v1.0.0",
      ]->Array.join("\n")
    expect(Workflows.problems(text, ~file="a.yml", ~owned))->toEqual([
      "a.yml:2: monoflake/runtime@3d3c42e5aac5ba805825da76410c181273ba90b1 is the author's own, taken at main and not pinned",
    ])
  })
})

describe("the project's own name", () => {
  let owner: Own_name.owner = {name: "monoflake", repositories: ["platform", "driver", "machine"]}
  let found = (text, ~file, ~spelled=[]) => Own_name.problems(text, ~file, ~owner, ~spelled)

  test("passes a manifest's name, a scope, a published address and a repository named", () => {
    expect(
      found(`\t"name": "@monoflake/codec",\n\t\t"@monoflake/keys": "1"`, ~file="package.json"),
    )->toEqual([])
    expect(found(`name = "monoflake"`, ~file="Cargo.toml"))->toEqual([])
    expect(found(`@module("@monoflake/envelope/generated/a.res.mjs")`, ~file="a.res"))->toEqual([])
    expect(
      found(
        [
          `url = "https://github.com/monoflake/runtime/releases/download/1/a.tar"`,
          `machine.url = "github:monoflake/machine";`,
          `image = "ghcr.io/monoflake/driver:1"`,
          `flake = "git+ssh://git@github.com/monoflake/cloud?dir=machines/buf";`,
          `let withheld = ["monoflake.net", "api.monoflake.com"]`,
          `// The fill monoflake/platform's model reads, from repos/monoflake/driver.`,
        ]->Array.join("\n"),
        ~file="a.nix",
      ),
    )->toEqual([])
    expect(found(`ids = "monoflake"`, ~file="workspace.toml"))->toEqual([])
    expect(found(`spelled = ["monoflake:"]`, ~file="workspace.toml"))->toEqual([])
    expect(
      found(`spelled = [\n\t"monoflake:",\n\t"monoflake-challenge",\n]`, ~file="workspace.toml"),
    )->toEqual([])
    expect(found(`owner = "monoflake";`, ~file="a.nix"))->toEqual([])
  })

  test("refuses a name a path, a host or a dotted key only resembles", () => {
    expect(
      found(
        [
          `state = "/var/lib/monoflake/driver"`,
          `secrets = "/run/monoflake/machine/secrets"`,
          `at = "/etc/systemd.d/monoflake/x"`,
          `url = "http://localhost.test/monoflake/state"`,
          `options.monoflake.dev.enable = true;`,
          `label = "monoflake.app.runs"`,
          `spelled = ["monoflake:"]`,
        ]->Array.join("\n"),
        ~file="a.nix",
      ),
    )->toEqual([
      "a.nix:1: /var/lib/monoflake/driver spells monoflake",
      "a.nix:2: /run/monoflake/machine/secrets spells monoflake",
      "a.nix:3: /etc/systemd.d/monoflake/x spells monoflake",
      "a.nix:4: http://localhost.test/monoflake/state spells monoflake",
      "a.nix:5: options.monoflake.dev.enable spells monoflake",
      "a.nix:6: monoflake.app.runs spells monoflake",
      "a.nix:7: monoflake: spells monoflake",
    ])
  })

  test("passes a declared spelling in its own file alone", () => {
    let text = `  | Salt => "monoflake:organization:salt:1"`
    expect(found(text, ~file="src/context.res", ~spelled=["monoflake:"]))->toEqual([])
    expect(found(text, ~file="tests/context_test.res"))->toEqual([
      "tests/context_test.res:1: monoflake:organization:salt:1 spells monoflake",
    ])
  })

  test("refuses it in any case anywhere else inside the system", () => {
    expect(
      found(
        [
          `let unit = "monoflake-driver"`,
          `let env = "MONOFLAKE_FOOTING"`,
          `module Cbor = MonoflakeCodec.Cbor`,
          `default_value = "/var/lib/monoflake/dev"`,
          `name: pin: "monoflake/images/a.tar"`,
          `const OUTPUT: &str = "monoflake.output";`,
          `see monoflake/driverless`,
          `name = "monoflake"`,
          `ids = "monoflake"`,
        ]->Array.join("\n"),
        ~file="a.nix",
      ),
    )->toEqual([
      "a.nix:1: monoflake-driver spells monoflake",
      "a.nix:2: MONOFLAKE_FOOTING spells monoflake",
      "a.nix:3: MonoflakeCodec.Cbor spells monoflake",
      "a.nix:4: /var/lib/monoflake/dev spells monoflake",
      "a.nix:5: monoflake/images/a.tar spells monoflake",
      "a.nix:6: monoflake.output spells monoflake",
      "a.nix:7: monoflake/driverless spells monoflake",
      "a.nix:8: monoflake spells monoflake",
      "a.nix:9: monoflake spells monoflake",
    ])
  })

  test("names a declaration that passes nothing", () => {
    let read = file => file == "src/context.res" ? Some(`"monoflake:parcel:key:1"`) : None
    expect(
      Own_name.stale(
        [
          {file: "src/gone.res", spelled: ["monoflake:"]},
          {file: "src/context.res", spelled: ["parcel:", "monoflake:journal:", "monoflake:"]},
          {file: "src/context.res", spelled: ["Monoflake"]},
        ],
        ~owner,
        ~read,
      ),
    )->toEqual([
      "workspace.toml: names.data names src/gone.res, which is not there",
      "workspace.toml: names.data spells parcel: in src/context.res, no own name",
      "workspace.toml: names.data spells monoflake:journal:, which src/context.res no longer holds",
      "workspace.toml: names.data spells Monoflake bare in src/context.res, passing it all",
    ])
  })

  test("leaves documents unread", () => {
    expect(
      [
        "docs/rfcs/plan.txt",
        "AGENTS.md",
        "code/README.md",
        "LICENSE-MIT",
        "spec/a.txt",
      ]->Array.every(Own_name.prose),
    )->toBe(true)
    expect(Own_name.prose("code/libs/a.res"))->toBe(false)
  })
})
