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
      Tasks.read(`[tasks.a]\nrun = """\n${long}\n"""\n[tasks.b]\nrun = "x"`, ~file="mise.toml"),
    )->toEqual((
      [
        `mise.toml: [tasks.a] runs ${Int.toString(
            Toolchain.taskLines + 1,
          )} lines, past ${Int.toString(Toolchain.taskLines)}; a script holds it`,
      ],
      [],
    ))
    expect(Tasks.lines(JSON.Array([JSON.String("a\nb"), JSON.String("c")])))->toBe(3)
  })

  test("is named by one word, in a mise.toml and as a file run under .mise/tasks", () => {
    let text = `[tasks.new-rfc]\nrun = "x"\n[tasks.rfc]\nrun = "x"\n[tasks."lane:open"]\nrun = "x"`
    expect(Tasks.read(text, ~file="mise.toml"))->toEqual((
      [],
      [
        "mise.toml: [tasks.new-rfc] joins words by a hyphen; one word, an action its first argument",
      ],
    ))
    expect(Tasks.read("[tasks", ~file="mise.toml"))->toEqual((["mise.toml: does not parse"], []))
    expect(Tasks.joinedFile("app/.mise/tasks/dev-server", ~executable=true))->toEqual(
      Some(
        `app/.mise/tasks/dev-server: the task dev-server joins words by a hyphen; ${Tasks.nested}`,
      ),
    )
    expect(Tasks.joinedFile(".mise/tasks/lane/open-all", ~executable=true))->toEqual(
      Some(
        `.mise/tasks/lane/open-all: the task lane:open-all joins words by a hyphen; ${Tasks.nested}`,
      ),
    )
    expect(Tasks.joinedFile(".mise/tasks/lane/open", ~executable=true))->toEqual(None)
    expect(Tasks.joinedFile("docs/<f>-rfc.md", ~executable=true))->toEqual(None)
    expect(Tasks.joinedFile(".mise/tasks/lib-local.ts", ~executable=false))->toEqual(None)
  })

  test(
    "joined by a hyphen warns only where the deferred renaming names the repository, guarding that the live item exists",
    () => {
      let item: Deferred.item = {
        id: Tasks.renaming,
        what: "renamed",
        repos: ["seam"],
        until: Author,
      }
      expect(Tasks.renamingIn([item], ~repo="seam"))->toEqual(Some(Tasks.renaming))
      expect(Tasks.renamingIn([item], ~repo="workspace"))->toEqual(None)
      expect(Tasks.renamingIn([{...item, id: "other"}], ~repo="seam"))->toEqual(None)
      expect(Deferred.items->Array.some(({id}) => id == Tasks.renaming))->toBe(true)
    },
  )

  test("warned of fails nothing outside AUDIT, and what it breaks fails", () => {
    let line = `mise.toml: [tasks.dev-site] joins words by a hyphen; ${Tasks.nested}`
    expect(Check.reported(([], [line])))->toBe(0)
    expect(Check.reported(([line], [])))->toBe(1)
    expect(Check.reported(([], [])))->toBe(0)
    let audit = Node.env->Dict.get("AUDIT")
    Node.env->Dict.set("AUDIT", "1")
    expect(Check.reported(([], [line])))->toBe(1)
    switch audit {
    | Some(value) => Node.env->Dict.set("AUDIT", value)
    | None => Node.env->Dict.delete("AUDIT")
    }
  })
})

@module("node:fs") external chmodSync: (string, int) => unit = "chmodSync"
@module("node:fs") external symlinkSync: (string, string) => unit = "symlinkSync"

describe("a Cloudflare resource made with a place", () => {
  let made = (~bound=[], ~file="make.res", text) => Placed.source(text, ~file, ~bound)
  let unset = what => `${what} names no --location; add --location ${Placed.told}`
  let wrong = (what, value) => `${what} names --location ${value}; ${Placed.told} alone`
  let root = temporaryRoot("placed-")

  test("names wnam or apac in its array or list, and nothing else", () => {
    expect(made(`let a = ["d1", "create", "example-db", "--location", "wnam"]`))->toEqual([])
    expect(
      made(`let b = [\n  "r2",\n  "bucket",\n  "create",\n  name,\n  "--location",\n  "apac",\n]`),
    )->toEqual([])
    expect(made(`let a = ["d1", "create", db, "--location=wnam"]`))->toEqual([])
    expect(made("let a = [\"d1\", \"create\", db, \"--location\", `apac`]"))->toEqual([])
    expect(made("let a = [\"d1\", \"create\", db, \"--location\", `${place}`]"))->toEqual([])
    expect(made(`let a = ["d1", "create", "example-db"]`))->toEqual([
      `make.res:1: ${unset("d1 create")}`,
    ])
    expect(made(`\nlet b = run(["r2", "bucket", "create", b, "--location", "eeur"])`))->toEqual([
      `make.res:2: ${wrong("r2 bucket create", "eeur")}`,
    ])
    expect(made(`let a = ["d1", "create", db, "--location=enam"]`))->toEqual([
      `make.res:1: ${wrong("d1 create", "enam")}`,
    ])
    expect(made("let a = [\"d1\", \"create\", db, \"--location\", `weur`]"))->toEqual([
      `make.res:1: ${wrong("d1 create", "weur")}`,
    ])
    expect(made(`| ("wrangler", list{"d1", "create", name}) => ok`))->toEqual([
      `make.res:1: ${unset("d1 create")}`,
    ])
    expect(
      made(~file="make.ts", `const a = ['d1', 'create', db, '--location', 'apac']`),
    )->toEqual([])
  })

  test("names a name bound in its own file, a module it opens, or the module it names", () => {
    let bound = Array.concat(
      Placed.bindings(`let located = "enam"\n`, ~file="scripts/names.res"),
      Placed.bindings(`let located = "wnam"\n`, ~file="scripts/west.res"),
    )
    let create = `["d1", "create", db, "--location", located]`
    let far = `make.res:2: d1 create names --location located, bound to enam in scripts/names.res; ${Placed.told} alone`
    expect(made(~bound, `open West\n${create}`))->toEqual([])
    expect(made(~bound, `open Names\n${create}`))->toEqual([far])
    expect(made(~bound, `let located = "apac"\n${create}\nopen Names`))->toEqual([])
    expect(made(~bound, `\n${create}`))->toEqual([])
    expect(made(~bound, `\n["d1", "create", db, "--location", Names.located]`))->toEqual([
      `make.res:2: d1 create names --location Names.located, bound to enam in scripts/names.res; ${Placed.told} alone`,
    ])
    expect(made(~bound, `\n["d1", "create", db, "--location", West.located]`))->toEqual([])
    expect(
      made(~bound, `open Names\n["d1", "create", db, "--location", placeOf(env)]`),
    )->toEqual([])
    let names = Placed.blanked(`let located = "wnam"\nlet far = "enam" // east\n`, ~quotes="\"`")
    expect(
      Placed.bindings(names, ~file="names.res")->Array.map(({name, value}) => (name, value)),
    )->toEqual([("located", Some("wnam")), ("far", Some("enam"))])
  })

  test("spreads a function of its own file whose place passes", () => {
    let create = `let a = ["d1", "create", db, ...placed(w)]`
    expect(made(`let placed = w => ["--location", w.place]\n\n${create}`))->toEqual([])
    expect(made(`let placed = w => ["--location", "apac"]\n${create}`))->toEqual([])
    expect(made(`let placed = w => ["--location", "enam"]\n${create}`))->toEqual([
      `make.res:2: ${wrong("d1 create", "enam")}`,
    ])
    expect(made(`let placed = w => [w.flag]\n${create}`))->toEqual([
      `make.res:2: ${unset("d1 create")}`,
    ])
  })

  test("reads a string holding a create as a shell line, and no comment", () => {
    expect(made(`let a = ["-c", "wrangler d1 create example-db"]`))->toEqual([
      `make.res:1: ${unset("d1 create")}`,
    ])
    expect(made("\nlet a = `wrangler r2 bucket create ${b} --location ${place}`"))->toEqual([])
    expect(made(`// ["d1", "create", db]\n/* ["r2", "bucket", "create", b] */`))->toEqual([])
  })

  test("is any shell line making one, each command of it judged alone", () => {
    let shell = text => Placed.script(text, ~file="make.sh")
    expect(shell("wrangler d1 create example-db --location apac"))->toEqual([])
    expect(shell("wrangler d1 create example-db --location=wnam"))->toEqual([])
    expect(shell(`wrangler d1 create example-db --location {{arg(name="place")}}`))->toEqual([])
    expect(shell("# wrangler d1 create example-db"))->toEqual([])
    expect(shell(`"$WRANGLER" d1 create example-db`))->toEqual([`make.sh:1: ${unset("d1 create")}`])
    expect(shell("wrangler d1 create a --location wnam && wrangler r2 bucket create b"))->toEqual([
      `make.sh:1: ${unset("r2 bucket create")}`,
    ])
    expect(shell("#!/bin/sh\nwrangler d1 create example-db \\\n  --location eeur\n"))->toEqual([
      `make.sh:2: ${wrong("d1 create", "eeur")}`,
    ])
    expect(shell("wrangler d1 create example-db \\\n  --location wnam"))->toEqual([])
    let python = `python3 -c 'run(["wrangler", "d1", "create", db, "--location", "wnam"])'`
    expect(shell(python))->toEqual([])
    expect(shell(`python3 -c 'run(["wrangler", "r2", "bucket", "create", b])'`))->toEqual([
      `make.sh:1: ${unset("r2 bucket create")}`,
    ])
    let quoted = `node -e 'run(["sh", "-c", "wrangler d1 create db --location wnam", x])'`
    expect(shell(quoted))->toEqual([])
  })

  test("is placed by a shell variable as it is bound, defaulted or left to a run", () => {
    let shell = text => Placed.script(text, ~file="make.sh")
    expect(shell(`PLACE=enam\nwrangler d1 create example-db --location "$PLACE"`))->toEqual([
      `make.sh:2: d1 create names --location $PLACE, bound to enam in make.sh; ${Placed.told} alone`,
    ])
    expect(shell(`PLACE=apac\nwrangler d1 create example-db --location "$PLACE"`))->toEqual([])
    expect(shell("wrangler d1 create example-db --location ${PLACE:-enam}"))->toEqual([
      `make.sh:1: ${wrong("d1 create", "enam")}`,
    ])
    expect(shell("wrangler d1 create example-db --location ${PLACE:-wnam}"))->toEqual([])
    expect(shell(`wrangler d1 create example-db --location "$PLACE"`))->toEqual([])
    let toml = `[tasks.make]\ndescription = "wrangler d1 create"\nrun = [\n  "pnpm install",\n  "wrangler d1 create example-db",\n]\n[tasks.other]\nrun = "wrangler r2 bucket create b --location wnam"\n`
    expect(Placed.tasks(toml, ~file="mise.toml"))->toEqual([`mise.toml:5: ${unset("d1 create")}`])
  })

  test(
    "reads what a repository tracks, never a fake, a test, a build or what cannot be read",
    () => {
      tree(
        root.contents,
        [
          ("scripts/names.res", `let located = "eeur"\n`),
          ("scripts/make.res", `open Names\nlet a = ["d1", "create", db, "--location", located]\n`),
          ("scripts/make_test.res", `let a = ["d1", "create", db]\n`),
          ("scripts/make.res.mjs", `let a = ["d1", "create", db]\n`),
          ("scripts/tests/fakes/account.res", `let a = ["d1", "create", db]\n`),
          ("lib/bs/make.res", `let a = ["d1", "create", db]\n`),
          ("lib/src/make.ts", `\nconst a = ['d1', 'create', db]\n`),
          ("lib/src/make.test.ts", `const a = ['d1', 'create', db]\n`),
          (".mise/tasks/deploy.mjs", `#!/usr/bin/env node\nrun(["d1", "create", db])\n`),
          ("deploy/make.sh", "#!/bin/sh\nwrangler r2 bucket create b\n"),
          (".mise/tasks/make", "#!/bin/sh\nwrangler d1 create db --location enam\n"),
          (".mise/tasks/notes", "wrangler d1 create db\n"),
          ("mise.toml", `[tasks.make]\nrun = "wrangler r2 bucket create b"\n`),
          ("scripts/dir.sh/kept", ""),
        ],
      )
      chmodSync(Node.join([root.contents, ".mise/tasks/make"]), 0o755)
      chmodSync(Node.join([root.contents, ".mise/tasks/deploy.mjs"]), 0o755)
      symlinkSync("loop.sh", Node.join([root.contents, "scripts/loop.sh"]))
      let paths = [
        "scripts/names.res",
        "scripts/make.res",
        "scripts/make_test.res",
        "scripts/make.res.mjs",
        "scripts/tests/fakes/account.res",
        "lib/bs/make.res",
        "lib/src/make.ts",
        "lib/src/make.test.ts",
        ".mise/tasks/deploy.mjs",
        "deploy/make.sh",
        ".mise/tasks/make",
        ".mise/tasks/notes",
        "mise.toml",
        "scripts/gone.res",
        "scripts/dir.sh",
        "scripts/loop.sh",
      ]
      expect(Placed.within(~root=root.contents, ~paths))->toEqual([
        `scripts/make.res:2: d1 create names --location located, bound to eeur in scripts/names.res; ${Placed.told} alone`,
        `lib/src/make.ts:2: ${unset("d1 create")}`,
        `.mise/tasks/deploy.mjs:2: ${unset("d1 create")}`,
        `deploy/make.sh:2: ${unset("r2 bucket create")}`,
        `.mise/tasks/make:2: ${wrong("d1 create", "enam")}`,
        `mise.toml:2: ${unset("r2 bucket create")}`,
      ])
    },
  )
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
          `flake = "git+ssh://git@github.com/monoflake/cloud?dir=machines/example";`,
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

describe("a tracked suffix", () => {
  test("needs a formatter in the table or to be Unformatted, a file with none passed over", () => {
    expect(
      Suffix_owned.problems(
        ~label="x",
        ["a.ts", "b.toml", "LICENSE", "hooks/rm", ".gitignore", "c.lock", "d.lock", "e.png"],
      ),
    )->toEqual(["x: .png has no formatter in Format.owners and is not Unformatted, as e.png"])
  })

  test("is registered by a repository's own unformatted list", () => {
    expect(Suffix_owned.problems(~label="x", ~unformatted=[".sql"], ["a.sql", "b.wit"]))->toEqual([
      "x: .wit has no formatter in Format.owners and is not Unformatted, as b.wit",
    ])
  })

  test("passes over test data and a binary file, and reads the rest", () => {
    let root = Node.mkdtempSync(Node.join([Node.tmpdir(), "suffix-"]))
    Node.mkdirAll(Node.join([root, "data"]))
    Node.writeFileSync(Node.join([root, "data/a.sql"]), "select 1\n")
    Node.writeFileSync(Node.join([root, "b.png"]), "PNG\u0000data")
    Node.writeFileSync(Node.join([root, "c.sql"]), "select 1\n")
    let format: Project.format = {unformatted: [], testData: ["data"]}
    expect(
      ["data/a.sql", "b.png", "c.sql"]->Array.filter(
        relative => Suffix_owned.read(~root, ~format, relative),
      ),
    )->toEqual(["c.sql"])
  })

  test("is declared in a repository's workspace.toml without being refused", () => {
    let root = Node.mkdtempSync(Node.join([Node.tmpdir(), "declared-"]))
    Node.writeFileSync(
      Node.join([root, "workspace.toml"]),
      "[format]\nunformatted = [\".sql\", \".wit\"]\ntest_data = [\"some/dir\"]\n",
    )
    expect(Project.read(root)->Result.map(declared => declared.format))->toEqual(
      Ok({Project.unformatted: [".sql", ".wit"], testData: ["some/dir"]}),
    )
    expect(Project.formatAt(root).unformatted->Array.includes(".sql"))->toBe(true)
  })
})

describe("a rule's gate", () => {
  let held = (held: Rule.held): Rule.t => {name: "r", says: "s", doc: "d", held}

  test("is a name in Rule.gates or a file, and nothing else", () => {
    expect(Check.unheldRule(held(Gate("push"))))->toEqual(None)
    expect(Check.unheldRule(held(Gate("scripts/lints/secrets.res"))))->toEqual(None)
    expect(Check.unheldRule(held(Gate("nowhere")))->Option.isSome)->toBe(true)
    expect(Check.unheldRule(held(Hook("push")))->Option.isSome)->toBe(true)
  })

  test("holds every rule the model lists by what exists, a part by one this check has", () => {
    expect(Check.unheld())->toEqual([])
    expect(Check.known->Array.includes("placed"))->toBe(true)
  })
})
