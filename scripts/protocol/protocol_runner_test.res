open Testing

@module("vitest") external testAsync: (string, unit => promise<unit>) => unit = "test"

let root = temporaryRoot("protocol-test-")

let config = (~top, ~properties) =>
  `\\* quick\nSPECIFICATION Spec\nCONSTANTS\n\tTop = ${top}\n\tSW_A = FALSE\n\tSW_B = FALSE\n\tSW_L = FALSE\nINVARIANTS\n\tTypeOK\n\tABelowB\nPROPERTIES\n${properties}\nCHECK_DEADLOCK FALSE\n`

let manifest = `{"specs": [{"name": "roll", "module": "roll.tla", "quick": "roll.cfg", "full": "roll-full.cfg",
  "inputs": ["model/protocol/roll.tla", "model/protocol/roll*.cfg"],
  "switches": [{"name": "SW_A", "breaks": "ABelowB"}, {"name": "SW_B", "breaks": "NeverBack"}, {"name": "SW_L", "breaks": "RerunSafe"}],
  "temporal": ["RerunSafe"]}]}`

let exporting = `{"specs": [{"name": "roll", "module": "roll.tla", "quick": "roll.cfg",
  "inputs": ["model/protocol/roll.tla"], "switches": [],
  "export": {"command": ["cat", "{output}"], "file": "model/protocol/roll-table.json", "checks": ["ABelowB"]}}]}`

let dataExport = `{"specs": [{"name": "roll", "module": "roll.tla", "quick": "roll.cfg",
  "inputs": ["model/protocol/roll.tla"], "switches": [],
  "export": {"command": ["node", "-e", "process.stdout.write('[1,2]')"], "file": "model/protocol/roll-table.json", "checks": ["ABelowB"]}}]}`

let withConstants = (script, ~inputs="") =>
  `{"specs": [{"name": "roll", "module": "roll.tla", "quick": "roll.cfg",
  "inputs": ["model/protocol/roll.tla"], "switches": [],
  "constants": {"command": ["node", "-e", ${JSON.stringifyAny(script)->Option.getOr(
      "",
    )}], "inputs": [${inputs}]}}]}`

let repo = () => Node.join([root.contents, "repo"])

let formatted = []

let lay = specs => {
  formatted->Array.splice(~start=0, ~remove=100, ~insert=[])
  tree(
    repo(),
    [
      ("model/protocol/roll.tla", "---- MODULE roll ----\n"),
      ("model/protocol/roll.cfg", config(~top="3", ~properties="\tNeverBack\n\tRerunSafe")),
      ("model/protocol/roll-full.cfg", config(~top="5", ~properties="\tNeverBack\n\tRerunSafe")),
      ("model/protocol/specs.json", specs),
    ],
  )
}

type call = {config: string, workers: int}

/** A TLC that answers from its configuration alone, counting how many run at once. */
let fake = (~unbreakable="") => {
  let calls = []
  let inflight = ref(0)
  let widest = ref(0)
  let launch: Protocol_runner.launch = (~modulePath as _, ~tla as _, ~config, ~workers) => {
    calls->Array.push({config, workers})
    inflight := inflight.contents + 1
    widest := Math.Int.max(widest.contents, inflight.contents)
    Promise.make((resolve, _) => Protocol_runner.setTimeout(() => {
        inflight := inflight.contents - 1
        let asked = Protocol_tlc.parse(config)->Array.filterMap(
          item =>
            switch item {
            | Checked(keyword, [name]) => Some((keyword, name))
            | _ => None
            },
        )
        let on = config->String.includes("= TRUE")
        let held = unbreakable != "" && config->String.includes(`${unbreakable} = TRUE`)
        resolve(
          switch (on && !held, asked) {
          | (true, [("INVARIANT", name)]) => `Error: Invariant ${name} is violated.`
          | (true, _) => "Error: Temporal properties were violated."
          | _ => "10 states generated, 7 distinct states found, 0 states left on queue.\nModel checking completed. No error has been found."
          },
        )
      }, 10))
  }
  (calls, widest, launch)
}

let times = () => Node.join([root.contents, "times.jsonl"])

let run = (launch, ~cpus=4, ~full=false, ~write=false) => {
  let lines = []
  let env: Protocol_runner.env = {
    root: repo(),
    cacheDir: Node.join([root.contents, "cache"]),
    timesFile: times(),
    jarSha: "jar",
    javaVersion: "java 25",
    cpus,
    launch,
    now: Date.now,
    log: line => lines->Array.push(line)->ignore,
    format: file => formatted->Array.push(file)->ignore,
  }
  Protocol_runner.run(
    env,
    Protocol_manifest.parse(Node.readFileSync(Node.join([repo(), Protocol_manifest.path]))),
    ~full,
    ~write,
  )->Promise.thenResolve(code => (code, lines->Array.join("\n")))
}

describe("the shared TLC runner", () => {
  testAsync("answers a second run from the cache and says so", async () => {
    lay(manifest)
    let (calls, _, launch) = fake()
    let (code, first) = await run(launch)
    expect(code)->toBe(0)
    expect(calls->Array.length)->toBe(3)
    expect(first)->toContain("roll: passed, 7 distinct states")
    expect(first)->toContain("not cached")
    let (code, second) = await run(launch)
    expect(code)->toBe(0)
    expect(calls->Array.length)->toBe(3)
    expect(second)->toContain("s, cached")
    expect(second)->toContain("total:")
    expect(Node.readFileSync(times())->String.split("\n")->Array.length)->toBe(3)
    expect(Node.readFileSync(times()))->toContain(`"cached":true`)
  })

  testAsync("misses when an input changed", async () => {
    lay(manifest)
    let (calls, _, launch) = fake()
    let _ = await run(launch)
    Node.writeFileSync(
      Node.join([repo(), "model/protocol/roll.tla"]),
      "---- MODULE roll ----\nEXTENDS Naturals\n",
    )
    let (_, again) = await run(launch)
    expect(calls->Array.length)->toBe(6)
    expect(again)->toContain("not cached")
  })

  testAsync("starts the main run and the switches together, the main on what is left", async () => {
    lay(manifest)
    let (calls, widest, launch) = fake()
    let _ = await run(launch, ~cpus=4)
    expect(widest.contents)->toBe(3)
    expect((calls->Array.getUnsafe(0)).workers)->toBe(2)
    expect(calls->Array.filter(c => c.workers == 1)->Array.length)->toBe(2)
    let (calls, widest, launch) = fake()
    Node.rmSync(Node.join([root.contents, "cache"]), {recursive: true, force: true})
    let _ = await run(launch, ~cpus=2)
    expect(widest.contents <= 2)->toBe(true)
    expect((calls->Array.getUnsafe(0)).workers)->toBe(1)
  })

  testAsync("fails a switch that does not break its property and does not cache it", async () => {
    lay(manifest)
    let (calls, _, launch) = fake(~unbreakable="SW_A")
    let (code, out) = await run(launch)
    expect(code)->toBe(1)
    expect(out)->toContain("FAIL roll SW_A: did not break")
    expect(out)->toContain("roll: FAILED")
    let before = calls->Array.length
    let _ = await run(launch)
    expect(calls->Array.length - before)->toBe(1)
  })

  testAsync(
    "runs the full model with the temporal properties and never reads the cache",
    async () => {
      lay(manifest)
      let (calls, _, launch) = fake()
      let _ = await run(launch)
      expect((calls->Array.getUnsafe(0)).config->String.includes("RerunSafe"))->toBe(false)
      expect((calls->Array.getUnsafe(0)).config->String.includes("Top = 3"))->toBe(true)
      let _ = await run(launch, ~full=true)
      let _ = await run(launch, ~full=true)
      expect(calls->Array.length)->toBe(3 + 4 + 4)
      let main = calls->Array.getUnsafe(3)
      expect(main.config->String.includes("RerunSafe"))->toBe(true)
      expect(main.config->String.includes("Top = 5"))->toBe(true)
    },
  )

  testAsync("holds the file an export step makes, and writes it on --write", async () => {
    lay(exporting)
    let (_, _, launch) = fake()
    let (code, out) = await run(launch)
    expect(code)->toBe(1)
    expect(out)->toContain("model/protocol/roll-table.json differs")
    let (code, out) = await run(launch, ~write=true)
    expect(code)->toBe(0)
    expect(out)->toContain("roll-table.json written")
    expect(formatted->Array.length)->toBe(1)
    let (code, _) = await run(launch)
    expect(code)->toBe(0)
  })

  testAsync("leaves a file equal as data untouched on --write", async () => {
    lay(dataExport)
    let (_, _, launch) = fake()
    let table = Node.join([repo(), "model/protocol/roll-table.json"])
    Node.writeFileSync(table, "[1,\n  2]\n")
    let (code, out) = await run(launch, ~write=true)
    expect(code)->toBe(0)
    expect(out)->toContain("already matches")
    expect(Node.readFileSync(table))->toBe("[1,\n  2]\n")
    Node.writeFileSync(table, "[3]")
    let (_, out) = await run(launch, ~write=true)
    expect(out)->toContain("roll-table.json written")
    expect(Node.readFileSync(table))->toBe("[1,2]")
  })

  testAsync("writes the command's values of each kind into the cfg it runs", async () => {
    lay(
      withConstants(`process.stdout.write('{"Top": 7, "SW_L": false, "Names": ["a","b"], "Ids": [1,2], "Mode": "x", "Yes": false}')`),
    )
    let path = Node.join([repo(), "model/protocol/roll.cfg"])
    Node.writeFileSync(
      path,
      Node.readFileSync(path) ++ "CONSTANT Names = {}\nIds = {}\nMode = \"\"\nYes = 1\n",
    )
    let (calls, _, launch) = fake()
    let (code, _) = await run(launch)
    expect(code)->toBe(0)
    let config = (calls->Array.getUnsafe(0)).config
    expect(config)->toContain("\tTop = 7\n")
    expect(config)->toContain("\tSW_L = FALSE\n")
    expect(config)->toContain("Names = {\"a\", \"b\"}")
    expect(config)->toContain("Ids = {1, 2}")
    expect(config)->toContain("Mode = \"x\"")
    expect(config)->toContain("Yes = FALSE")
    expect(config->String.includes("Top = 3"))->toBe(false)
  })

  testAsync("refuses a name the cfg lacks and a command that fails", async () => {
    lay(withConstants(`process.stdout.write('{"Missing": 1}')`))
    let (_, _, launch) = fake()
    let refused = async script => {
      lay(withConstants(script))
      try {
        let _ = await run(launch)
        ""
      } catch {
      | Protocol_manifest.Refused(why) => why
      }
    }
    expect(await refused(`process.stdout.write('{"Missing": 1}')`))->toContain("Missing")
    expect(await refused(`process.exit(3)`))->toContain("exited 3")
    expect(await refused(`process.stdout.write('{"Top": 1.5}')`))->toContain("Top")
    expect(await refused(`process.stdout.write('nope')`))->toContain("did not print JSON")
  })

  testAsync("misses the cache when a constants input changed", async () => {
    let script = `process.stdout.write('{"Top": 2}')`
    lay(withConstants(script, ~inputs=`"model/in.txt"`))
    Node.writeFileSync(Node.join([repo(), "model/in.txt"]), "one")
    let (calls, _, launch) = fake()
    let _ = await run(launch)
    let _ = await run(launch)
    expect(calls->Array.length)->toBe(1)
    Node.writeFileSync(Node.join([repo(), "model/in.txt"]), "two")
    let _ = await run(launch)
    expect(calls->Array.length)->toBe(2)
  })

  testAsync("runs a spec without constants as it does today", async () => {
    lay(manifest)
    let (calls, _, launch) = fake()
    let (code, _) = await run(launch)
    expect(code)->toBe(0)
    expect((calls->Array.getUnsafe(0)).config)->toContain("Top = 3")
  })
})
