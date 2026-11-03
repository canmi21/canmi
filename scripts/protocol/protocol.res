/**
 * `node scripts/protocol/protocol.res.mjs [--full] [--write] [<spec>...]`.
 * Run from the repository root with WORKSPACE only locating the shared runner.
 */
@send external onError: (Node.child, @as("error") _, JsExn.t => unit) => unit = "on"

let release = "v1.7.4"
let sha256 = "936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88"

/** The release's jar in a cache outside the tree, taken once and refused on a different hash. */
let jar = () => {
  let cache = `${Protocol_runner.homedir()}/.cache/tlaplus/${release}`
  let file = `${cache}/tla2tools.jar`
  if !Node.existsSync(file) {
    Node.mkdirAll(cache)
    let url = `https://github.com/tlaplus/tlaplus/releases/download/${release}/tla2tools.jar`
    ignore(Node.spawnSync("curl", ["-fsSL", "-o", file, url], {encoding: "utf8"}))
  }
  let found = Node.existsSync(file)
    ? Net.createHash("sha256")->Net.updateBytes(Node.readBytes(file))->Net.hexDigest
    : ""
  if found != sha256 {
    throw(Protocol_manifest.Refused(`tla2tools.jar at ${file} hashes to ${found}, not ${sha256}`))
  }
  file
}

let javaVersion = () =>
  Node.spawnSync("java", ["-version"], {encoding: "utf8"}).stderr
  ->Nullable.getOr("")
  ->String.split("\n")
  ->Array.getUnsafe(0)

/** TLC in a directory of its own, as it writes its states beside the specification it reads. */
let launch = (tools): Protocol_runner.launch =>
  (~modulePath, ~tla, ~config, ~workers) =>
    Promise.make((resolve, _) => {
      let place = Node.mkdtempSync(Node.join([Node.tmpdir(), "protocol-"]))
      let name = modulePath->String.replace(".tla", "")
      tla->Array.forEach(((file, text)) => Node.writeFileSync(Node.join([place, file]), text))
      Node.writeFileSync(Node.join([place, `${name}.cfg`]), config)
      let child = Node.spawn(
        "java",
        [
          "-XX:+UseParallelGC",
          // an RMI export looks the host up, stalling five seconds when several JVMs start at once
          "-Djava.rmi.server.hostname=localhost",
          // TLC unpacks its standard modules into the temp directory, shared by parallel runs
          `-Djava.io.tmpdir=${place}`,
          "-cp",
          tools,
          "tlc2.TLC",
          "-lncheck",
          "final",
          "-workers",
          Int.toString(workers),
          "-config",
          `${name}.cfg`,
          name,
        ],
        {cwd: place, stdio: ["ignore", "pipe", "pipe"]},
      )
      let seen = []
      let take = chunk => seen->Array.push(chunk->Node.chunkText)
      child->Node.childOut->Node.onChunk(take)
      child->Node.childErr->Node.onChunk(take)
      let finish = () => {
        Node.rmSync(place, {recursive: true, force: true})
        resolve(seen->Array.join(""))
      }
      child->onError(error => {
        seen->Array.push(error->JsExn.message->Option.getOr("java did not start"))
        finish()
      })
      child->Node.onClose(_ => finish())
    })

let main = () => {
  let args = Node.args()
  let known = ["--full", "--write"]
  args->Array.forEach(arg =>
    if arg->String.startsWith("--") && !(known->Array.includes(arg)) {
      throw(
        Protocol_manifest.Refused(
          `unknown argument ${arg}, expected [--full] [--write] [<spec>...]`,
        ),
      )
    }
  )
  let root = Node.cwd()
  let manifest = Node.join([root, Protocol_manifest.path])
  if !Node.existsSync(manifest) {
    throw(Protocol_manifest.Refused(`${Protocol_manifest.path} is not in ${root}`))
  }
  let names = args->Array.filter(arg => !(arg->String.startsWith("--")))
  let specs = Protocol_manifest.chosen(Protocol_manifest.parse(Node.readFileSync(manifest)), names)
  let tools = jar()
  let home = Protocol_runner.homedir()
  let env: Protocol_runner.env = {
    root,
    cacheDir: `${home}/.cache/monoflake/protocol`,
    timesFile: `${home}/.local/share/monoflake/protocol-times.jsonl`,
    jarSha: sha256,
    javaVersion: javaVersion(),
    cpus: Protocol_runner.availableParallelism(),
    launch: launch(tools),
    now: Date.now,
    log: Console.log,
    format: file => {
      let ran = Node.spawnSync("oxfmt", [file], {cwd: root, encoding: "utf8"})
      if ran.status->Nullable.getOr(1) != 0 {
        Console.log(`warning: oxfmt did not format ${file}`)
      }
    },
  }
  Protocol_runner.run(
    env,
    specs,
    ~full=args->Array.includes("--full"),
    ~write=args->Array.includes("--write"),
  )
}

if Node.isMain {
  Promise.resolve()
  ->Promise.then(main)
  ->Promise.thenResolve(code => Node.exit(code))
  ->Promise.catch(error => {
    Console.error(
      switch error {
      | Protocol_manifest.Refused(why) => why
      | JsExn(exn) => exn->JsExn.message->Option.getOr("protocol failed")
      | _ => "protocol failed"
      },
    )
    Node.exit(1)
  })
  ->ignore
}
