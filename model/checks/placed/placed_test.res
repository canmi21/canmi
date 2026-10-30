open Testing

@module("node:fs") external chmodSync: (string, int) => unit = "chmodSync"
@module("node:fs") external symlinkSync: (string, string) => unit = "symlinkSync"

describe("a Cloudflare resource made with a place", () => {
  let made = (~bound=[], ~file="make.res", text) => Placed.source(text, ~file, ~bound)
  let unset = what => `${what} names no --location; add --location ${Placed.told}`
  let wrong = (what, value) => `${what} names --location ${value}; ${Placed.told} alone`
  let runtime = what =>
    `${what} names a place decided at run time; use a literal or a bound name the check can read`
  let root = temporaryRoot("placed-")

  test("names wnam or apac in its array or list, and nothing else", () => {
    expect(made(`let a = ["d1", "create", "example-db", "--location", "wnam"]`))->toEqual([])
    expect(
      made(`let b = [\n  "r2",\n  "bucket",\n  "create",\n  name,\n  "--location",\n  "apac",\n]`),
    )->toEqual([])
    expect(made(`let a = ["d1", "create", db, "--location=wnam"]`))->toEqual([])
    expect(made("let a = [\"d1\", \"create\", db, \"--location\", `apac`]"))->toEqual([])
    expect(made("let a = [\"d1\", \"create\", db, \"--location\", `${place}`]"))->toEqual([
      `make.res:1: ${runtime("d1 create")}`,
    ])
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
    expect(made(~bound, `\n${create}`))->toEqual([`make.res:2: ${runtime("d1 create")}`])
    expect(made(~bound, `\n["d1", "create", db, "--location", Names.located]`))->toEqual([
      `make.res:2: d1 create names --location Names.located, bound to enam in scripts/names.res; ${Placed.told} alone`,
    ])
    expect(made(~bound, `\n["d1", "create", db, "--location", West.located]`))->toEqual([])
    expect(made(~bound, `open Names\n["d1", "create", db, "--location", placeOf(env)]`))->toEqual([
      `make.res:2: ${runtime("d1 create")}`,
    ])
    let names = Placed.blanked(`let located = "wnam"\nlet far = "enam" // east\n`, ~quotes="\"`")
    expect(
      Placed.bindings(names, ~file="names.res")->Array.map(({name, value}) => (name, value)),
    )->toEqual([("located", Some("wnam")), ("far", Some("enam"))])
  })

  test("rejects a create whose configuration decides its place at run time", () => {
    // A runtime configuration used to pass as Open.
    expect(made(`["r2", "bucket", "create", c.bucket, "--location", c.location]`))->toEqual([
      `make.res:1: ${runtime("r2 bucket create")}`,
    ])
  })

  test("spreads a function of its own file whose place passes", () => {
    let create = `let a = ["d1", "create", db, ...placed(w)]`
    expect(made(`let placed = w => ["--location", w.place]\n\n${create}`))->toEqual([
      `make.res:3: ${runtime("d1 create")}`,
    ])
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
    expect(made("\nlet a = `wrangler r2 bucket create ${b} --location ${place}`"))->toEqual([
      `make.res:2: ${runtime("r2 bucket create")}`,
    ])
    expect(made(`// ["d1", "create", db]\n/* ["r2", "bucket", "create", b] */`))->toEqual([])
  })

  test("is any shell line making one, each command of it judged alone", () => {
    let shell = text => Placed.script(text, ~file="make.sh")
    expect(shell("wrangler d1 create example-db --location apac"))->toEqual([])
    expect(shell("wrangler d1 create example-db --location=wnam"))->toEqual([])
    expect(shell(`wrangler d1 create example-db --location {{arg(name="place")}}`))->toEqual([
      `make.sh:1: ${runtime("d1 create")}`,
    ])
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
    expect(shell(`wrangler d1 create example-db --location "$PLACE"`))->toEqual([
      `make.sh:1: ${runtime("d1 create")}`,
    ])
    let toml = `[tasks.make]\ndescription = "wrangler d1 create"\nrun = [\n  "pnpm install",\n  "wrangler d1 create example-db",\n]\n[tasks.other]\nrun = "wrangler r2 bucket create b --location wnam"\n`
    expect(Placed.tasks(toml, ~file="mise.toml"))->toEqual([`mise.toml:5: ${unset("d1 create")}`])
  })

  test("judges configuration keys at every depth and passes unreadable configuration", () => {
    let files = [
      ("systems.toml", `[systems.west]\nlocation = "enam"`),
      ("worker.json", `{"durable": [{"locationHint": "weur"}]}`),
      (
        "worker.jsonc",
        `{
				// A string containing comment marks stays intact.
				"url": "https://example.com/*kept*/",
				"settings": { /* place */ "location_hint": "eeur", },
			}`,
      ),
      ("west.toml", `location = "wnam"`),
      ("wrong.toml", `location = `),
      ("wrong.json", `{"location":`),
      ("wrong.jsonc", `{"location": }`),
      ("numbers.json", `{"location": 42, "locationHint": null}`),
      ("package.json", `{"location": "enam"}`),
      ("nested/package.json", `{"location": "enam"}`),
      ("package-lock.json", `{"location": "enam"}`),
      ("flake.lock", `{"location": "enam"}`),
      ("Cargo.lock", `location = "enam"`),
      ("pnpm-lock.yaml", `location: enam`),
      ("node_modules/config.json", `{"location": "enam"}`),
      ("tests/config.toml", `location = "enam"`),
      ("lib/bs/config.json", `{"location": "enam"}`),
    ]
    tree(root.contents, files)
    expect(
      Placed.within(~root=root.contents, ~paths=files->Array.map(((file, _)) => file)),
    )->toEqual([
      `systems.toml: systems.west.location names enam; ${Placed.told} alone`,
      `worker.json: durable[0].locationHint names weur; ${Placed.told} alone`,
      `worker.jsonc: settings.location_hint names eeur; ${Placed.told} alone`,
    ])
  })

  test("allows an exception only for its repository, file and value", () => {
    let files = [
      ("excepted.toml", `location = "enam"`),
      ("excepted.res", `["d1", "create", db, "--location", "enam"]`),
      ("bound.res", `open East\n["d1", "create", db, "--location", located]`),
      ("east.res", `let located = "enam"`),
      ("west.res", `let located = "wnam"`),
      ("make.res", `open West\n["d1", "create", db, "--location", located]`),
      ("excepted.sh", `wrangler d1 create db --location enam`),
      ("nested/mise.toml", `[tasks.make]\nrun = "wrangler d1 create db --location enam"`),
    ]
    tree(root.contents, files)
    let paths = files->Array.map(((file, _)) => file)
    let exceptions = paths->Array.map(file => ("monoflake/cloud", file, "enam"))
    expect(
      Placed.within(~root=root.contents, ~paths, ~repo="monoflake/cloud", ~exceptions),
    )->toEqual([])
    let denied = Placed.within(~root=root.contents, ~paths, ~repo="canmi/web", ~exceptions)
    expect(denied->Array.length)->toEqual(5)
    expect(Placed.within(~root=root.contents, ~paths, ~repo="monoflake/cloud"))->toEqual(denied)
    expect(
      Placed.within(
        ~root=root.contents,
        ~paths,
        ~repo="monoflake/cloud",
        ~exceptions=[("monoflake/cloud", "other.toml", "enam")],
      ),
    )->toEqual(denied)
    expect(
      Placed.within(
        ~root=root.contents,
        ~paths,
        ~repo="monoflake/cloud",
        ~exceptions=paths->Array.map(file => ("monoflake/cloud", file, "weur")),
      ),
    )->toEqual(denied)
  })

  test("allows a listed runtime place only with a literal list and its membership filter", () => {
    let file = "scripts/install/install_parts.res"
    let world = "scripts/install/install_world.res"
    let repo = "monoflake/driver"
    let atRunTime = [(repo, file)]
    let guarded = `let locations = ["wnam", "apac"]
let placeOf = env => value(env, location)->Option.filter(hint => locations->Array.includes(hint))`
    let create = `open! Install_world
let placed = w => ["--location", placeOf(w.env)->Option.getOr("unset")]
let db = ["d1", "create", db, ...placed(w)]
let bucket = ["r2", "bucket", "create", bucket, ...placed(w)]`
    let scan = (~guard=guarded, ~text=create, ~repository=repo, ~listed=atRunTime) => {
      let files = [(file, text), (world, guard)]
      tree(root.contents, files)
      Placed.within(
        ~root=root.contents,
        ~paths=files->Array.map(((file, _)) => file),
        ~repo=repository,
        ~atRunTime=listed,
      )
    }
    expect(scan())->toEqual([])
    expect(scan(~listed=[]))->toEqual([
      `${file}:3: ${runtime("d1 create")}`,
      `${file}:4: ${runtime("r2 bucket create")}`,
    ])
    expect(scan(~repository="monoflake/cloud"))->toEqual([
      `${file}:3: ${runtime("d1 create")}`,
      `${file}:4: ${runtime("r2 bucket create")}`,
    ])
    expect(scan(~listed=[(repo, "other.res")]))->toEqual([
      `${file}:3: ${runtime("d1 create")}`,
      `${file}:4: ${runtime("r2 bucket create")}`,
    ])
    expect(scan(~guard=guarded->String.replace("apac", "enam")))->toEqual([
      `${file}:3: the guard in ${world} drifts from places`,
      `${file}:4: the guard in ${world} drifts from places`,
    ])
    expect(scan(~guard=guarded->String.replace(`let locations = ["wnam", "apac"]`, "")))->toEqual([
      `${file}:3: the guard in ${file} drifts from places; no literal locations binding`,
      `${file}:4: the guard in ${file} drifts from places; no literal locations binding`,
    ])
    expect(scan(~guard=`let locations = ["wnam", "apac"]`))->toEqual([
      `${file}:3: the guard in ${world} does not refuse an unset value`,
      `${file}:4: the guard in ${world} does not refuse an unset value`,
    ])
    expect(scan(~text=create->String.replace("open! Install_world", "")))->toEqual([
      `${file}:3: the guard in ${file} drifts from places; no literal locations binding`,
      `${file}:4: the guard in ${file} drifts from places; no literal locations binding`,
    ])
    expect(
      scan(
        ~text=create
        ->String.replace("open! Install_world", "")
        ->String.replace("placeOf(w.env)", "Install_world.placeOf(w.env)"),
      ),
    )->toEqual([])
    expect(
      scan(
        ~text=create->String.replace("open! Install_world", `import World from "./install_world"`),
      ),
    )->toEqual([])
    expect(
      scan(
        ~guard="",
        ~text=`${guarded}
${create}`,
      ),
    )->toEqual([])
    expect(
      scan(
        ~guard=guarded->String.replace(
          "hint => locations->Array.includes(hint)",
          "hint => Array.includes(locations, hint)",
        ),
      ),
    )->toEqual([])
    expect(
      scan(
        ~guard=guarded->String.replace(
          "hint => locations->Array.includes(hint)",
          "hint => locations->Array.includes(other)",
        ),
      ),
    )->toEqual([
      `${file}:3: the guard in ${world} does not refuse an unset value`,
      `${file}:4: the guard in ${world} does not refuse an unset value`,
    ])
    expect(
      scan(
        ~guard=`let locations = ["wnam", "apac"]
let example = "Option.filter(hint => locations->Array.includes(hint))"`,
      ),
    )->toEqual([
      `${file}:3: the guard in ${world} does not refuse an unset value`,
      `${file}:4: the guard in ${world} does not refuse an unset value`,
    ])
    expect(scan(~guard=guarded->String.replace(`["wnam", "apac"]`, "allowed")))->toEqual([
      `${file}:3: the guard in ${world} drifts from places`,
      `${file}:4: the guard in ${world} drifts from places`,
    ])
    expect(
      scan(~guard=guarded->String.replace(`["wnam", "apac"]`, `[\n  "wnam",\n  "apac",\n]`)),
    )->toEqual([])
    expect(
      scan(
        ~text=`open Install_world
["d1", "create", db, "--location", "enam"]`,
      ),
    )->toEqual([`${file}:2: ${wrong("d1 create", "enam")}`])
    expect(
      scan(
        ~text=`open Install_world
let east = "enam"
["d1", "create", db, "--location", east]`,
      ),
    )->toEqual([
      `${file}:3: d1 create names --location east, bound to enam in ${file}; ${Placed.told} alone`,
    ])
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
