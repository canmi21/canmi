open Testing

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
