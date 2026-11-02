/**
 * The shared TLC runner, `mise run protocol`: each specification's quick model from a cache, its
 * switches in parallel, and every run timed, RFC w0w82. The full model is `--full`, never cached.
 */
open Protocol_tlc

@module("node:fs") external globSync: (string, {"cwd": string}) => array<string> = "globSync"
@module("node:fs") external appendFileSync: (string, string) => unit = "appendFileSync"
@module("node:os") external availableParallelism: unit => int = "availableParallelism"
@module("node:os") external homedir: unit => string = "homedir"
@val external setTimeout: (unit => unit, int) => unit = "setTimeout"

type launch = (
  ~modulePath: string,
  ~tla: array<(string, string)>,
  ~config: string,
  ~workers: int,
) => promise<string>

/** What a run touches outside the repository, so a test can give it a fake TLC and a cache. */
type env = {
  root: string,
  cacheDir: string,
  timesFile: string,
  jarSha: string,
  javaVersion: string,
  cpus: int,
  launch: launch,
  now: unit => float,
  log: string => unit,
  format: string => unit,
}

type kind = Main | Flip(string) | Export

type job = {
  spec: Protocol_manifest.spec,
  kind: kind,
  label: string,
  config: string,
  expected: option<expected>,
  key: string,
  tla: array<(string, string)>,
  workers: int,
}

type outcome = {
  job: job,
  ok: bool,
  states: string,
  cached: bool,
  started: float,
  ended: float,
  detail: string,
  table: option<string>,
}

let seconds = ms => (ms /. 1000.)->Float.toFixed(~digits=1)

let read = file => Node.readFileSync(file)
let sha = text => Net.createHash("sha256")->Net.updateText(text)->Net.hexDigest

/** The files the patterns name under the root, sorted, each with its text. */
let filesOf = (root, patterns) =>
  patterns
  ->Array.flatMap(pattern => globSync(pattern, {"cwd": root}))
  ->Set.fromArray
  ->Set.values
  ->Array.fromIterator
  ->Array.toSorted(String.compare)
  ->Array.map(file => (file, read(Node.join([root, file]))))

let cachePath = (env, key) => Node.join([env.cacheDir, `${key}.json`])

let cachedOf = (env, key) =>
  switch Node.existsSync(cachePath(env, key)) {
  | false => None
  | true =>
    switch JSON.parseOrThrow(read(cachePath(env, key))) {
    | Object(fields) =>
      Some((
        fields->Dict.get("states")->Option.flatMap(JSON.Decode.string)->Option.getOr("?"),
        fields->Dict.get("table")->Option.flatMap(JSON.Decode.string),
      ))
    | _ => None
    | exception _ => None
    }
  }

let remember = (env, outcome) => {
  Node.mkdirAll(env.cacheDir)
  let fields = Dict.fromArray([("states", JSON.String(outcome.states))])
  outcome.table->Option.forEach(table => fields->Dict.set("table", JSON.String(table)))
  Node.writeFileSync(cachePath(env, outcome.job.key), JSON.stringify(JSON.Object(fields)))
}

/** The jobs of one specification, its main run first. */
let jobsOf = (env, ~full, ~spec: Protocol_manifest.spec) => {
  let dir = file => Node.join([env.root, Protocol_manifest.directory, file])
  let quick = read(dir(spec.quick))
  let base = full ? read(dir(spec.full->Option.getOr(spec.quick))) : quick
  let base = full ? base : without(base, spec.temporal)
  let inputs = [
    (spec.modulePath, read(dir(spec.modulePath))),
    ...filesOf(env.root, spec.inputs)->Array.map(((file, text)) => (file, text)),
  ]
  let tla = inputs->Array.filter(((file, _)) => file->String.endsWith(".tla"))
  let tla = tla->Array.map(((file, text)) => (Node.basename(file), text))
  let keyed = (kind, config, extra) =>
    [
      [
        kind,
        full ? "full" : "quick",
        spec.name,
        spec.modulePath,
        config,
        env.jarSha,
        env.javaVersion,
      ],
      inputs->Array.flatMap(((file, text)) => [file, text]),
      extra,
    ]
    ->Array.flat
    ->JSON.stringifyAny
    ->Option.getOr("")
    ->sha
  let job = (kind, label, config, expected, extra) => {
    spec,
    kind,
    label,
    config,
    expected,
    key: keyed(label, config, extra),
    tla,
    workers: 1,
  }
  let flips = spec.flips->Array.filterMap(({name, breaks}) =>
    switch (expectedOf(base, breaks), spec.temporal->Array.includes(breaks)) {
    | (_, true) if !full => None
    | (None, _) =>
      throw(
        Protocol_manifest.Refused(
          `${spec.name}: ${breaks} is checked by no section of its configuration`,
        ),
      )
    | (Some(expected), _) =>
      switch switchedOn(base, name) {
      | None =>
        throw(
          Protocol_manifest.Refused(
            `${spec.name}: ${name} is no constant set FALSE in its configuration`,
          ),
        )
      | Some(on) =>
        Some(job(Flip(name), `${spec.name} ${name}`, askingFor(on, expected), Some(expected), []))
      }
    }
  )
  let export = switch spec.export {
  | None => []
  | Some(step) =>
    let config = read(dir(step.config == "full" ? spec.full->Option.getOr(spec.quick) : spec.quick))
    let asked = asking(config, ~invariants=step.checks, ~properties=[])
    let extra = [
      step.command->Array.join(" "),
      ...filesOf(env.root, step.inputs)->Array.flatMap(((f, t)) => [f, t]),
    ]
    [job(Export, `${spec.name} export`, asked, None, extra)]
  }
  [job(Main, spec.name, base, None, []), ...flips, ...export]
}

/** Jobs started together up to the slots they weigh, in order, each result in its place. */
let pool = (~slots, tasks: array<(int, unit => promise<'a>)>): promise<array<'a>> =>
  Promise.make((resolve, reject) => {
    let total = tasks->Array.length
    let results = Array.make(~length=total, None)
    let next = ref(0)
    let free = ref(slots)
    let finished = ref(0)
    let rec pump = () => {
      if next.contents < total {
        let (weight, start) = tasks->Array.getUnsafe(next.contents)
        let weight = Math.Int.min(weight, slots)
        if weight <= free.contents {
          let index = next.contents
          next := index + 1
          free := free.contents - weight
          start()
          ->Promise.then(result => {
            results->Array.setUnsafe(index, Some(result))
            free := free.contents + weight
            finished := finished.contents + 1
            if finished.contents == total {
              resolve(results->Array.map(result => result->Option.getOrThrow))
            }
            pump()
            Promise.resolve()
          })
          ->Promise.catch(error => {
            reject(error)
            Promise.resolve()
          })
          ->ignore
          pump()
        }
      }
    }
    total == 0 ? resolve([]) : pump()
  })

let tail = out => out->String.split("\n")->Array.slice(~start=-40)->Array.join("\n")

/** The step's command run over TLC's output, which is the file the repository holds. */
let exported = (step: Protocol_manifest.export, ~root, out) => {
  let place = Node.mkdtempSync(Node.join([Node.tmpdir(), "protocol-"]))
  let output = Node.join([place, "tlc-output.txt"])
  Node.writeFileSync(output, out)
  let args = step.command->Array.map(arg => arg->String.replaceAll("{output}", output))
  let ran = Node.spawnSync(
    args->Array.getUnsafe(0),
    args->Array.slice(~start=1),
    {cwd: root, encoding: "utf8", maxBuffer: 536870912},
  )
  Node.rmSync(place, {recursive: true, force: true})
  switch ran.status->Nullable.getOr(1) {
  | 0 => Ok(ran.stdout->Nullable.getOr(""))
  | status =>
    Error(
      `${step.command->Array.join(" ")} exited ${Int.toString(
          status,
        )}\n${ran.stderr->Nullable.getOr("")}`,
    )
  }
}

let run1 = (env, job) => {
  let started = env.now()
  env.launch(
    ~modulePath=job.spec.modulePath,
    ~tla=job.tla,
    ~config=job.config,
    ~workers=job.workers,
  )->Promise.thenResolve(out => {
    let ended = env.now()
    let finish = (ok, detail, table) => {
      job,
      ok,
      states: distinct(out),
      cached: false,
      started,
      ended,
      detail,
      table,
    }
    switch (job.kind, job.expected) {
    | (Flip(_), Some(expected)) =>
      broke(out, expected)
        ? finish(true, "", None)
        : finish(false, `did not break\n${tail(out)}`, None)
    | (Export, _) =>
      switch (passed(out), job.spec.export) {
      | (true, Some(step)) =>
        switch exported(step, ~root=env.root, out) {
        | Ok(table) => finish(true, "", Some(table))
        | Error(why) => finish(false, why, None)
        }
      | _ => finish(false, `TLC did not pass the export run\n${tail(out)}`, None)
      }
    | _ => passed(out) ? finish(true, "", None) : finish(false, `did not pass\n${tail(out)}`, None)
    }
  })
}

/** Two tables as data where both parse, so a formatter rewriting the file is no drift. */
let same = (a, b) =>
  try JSON.stringify(JSON.parseOrThrow(a)) == JSON.stringify(JSON.parseOrThrow(b)) catch {
  | _ => a == b
  }

/** A run of the manifest's specifications, the status it ends with. */
let run = (env, specs: array<Protocol_manifest.spec>, ~full, ~write) => {
  let begun = env.now()
  let jobs = specs->Array.map(spec => jobsOf(env, ~full, ~spec))
  let hits = jobs->Array.map(group => group->Array.map(job => full ? None : cachedOf(env, job.key)))
  let pending =
    Array.zip(jobs, hits)->Array.flatMap(((group, found)) =>
      Array.zip(group, found)->Array.filter(((_, hit)) => hit == None)->Array.map(((job, _)) => job)
    )
  let others = pending->Array.filter(job => job.kind != Main)->Array.length
  let left = Math.Int.max(1, env.cpus - others)
  let ordered = Array.concat(
    pending->Array.filter(job => job.kind == Main),
    pending->Array.filter(job => job.kind != Main),
  )
  let tasks = ordered->Array.map(job => {
    let job = job.kind == Main ? {...job, workers: left} : job
    (job.workers, () => run1(env, job))
  })
  pool(~slots=env.cpus, tasks)->Promise.thenResolve(ran => {
    let failures = ref(0)
    let ranBy = Dict.make()
    ran->Array.forEach(outcome => {
      ranBy->Dict.set(outcome.job.key, outcome)
      if outcome.ok && !full {
        remember(env, outcome)
      }
    })
    Array.zip(jobs, hits)->Array.forEachWithIndex(((group, found), index) => {
      let spec = specs->Array.getUnsafe(index)
      let outcomes = Array.zip(group, found)->Array.map(
        ((job, hit)) =>
          switch hit {
          | Some((states, table)) => {
              job,
              ok: true,
              states,
              cached: true,
              started: begun,
              ended: begun,
              detail: "",
              table,
            }
          | None => ranBy->Dict.get(job.key)->Option.getOrThrow
          },
      )
      let main = outcomes->Array.getUnsafe(0)
      let ranOnes = outcomes->Array.filter(o => !o.cached)
      let from =
        ranOnes->Array.reduce(
          Float.Constants.positiveInfinity,
          (low, o) => Math.min(low, o.started),
        )
      let upto = ranOnes->Array.reduce(0., (high, o) => Math.max(high, o.ended))
      let elapsed = ranOnes == [] ? 0. : upto -. from
      let nCached = outcomes->Array.filter(o => o.cached)->Array.length
      let nRuns = outcomes->Array.length
      let cachedWord =
        nCached == nRuns
          ? "cached"
          : nCached == 0
          ? "not cached"
          : `${Int.toString(nCached)} of ${Int.toString(nRuns)} cached`
      let bad = outcomes->Array.filter(o => !o.ok)
      let exportCheck = outcomes->Array.filterMap(
        o =>
          switch (o.job.kind, o.table, spec.export) {
          | (Export, Some(table), Some(step)) =>
            let file = Node.join([env.root, step.file])
            if write {
              if Node.existsSync(file) && same(read(file), table) {
                env.log(`${step.file} already matches what TLC decides`)
              } else {
                Node.writeFileSync(file, table)
                env.format(file)
                env.log(`${step.file} written`)
              }
              None
            } else if !Node.existsSync(file) || !same(read(file), table) {
              Some(
                `${step.file} differs from what TLC decides, \`mise run protocol --write\` writes it`,
              )
            } else {
              None
            }
          | _ => None
          },
      )
      let good = bad == [] && exportCheck == []
      env.log(
        `${spec.name}: ${good ? "passed" : "FAILED"}, ${main.states} distinct states, ${seconds(
            elapsed,
          )}s, ${cachedWord}`,
      )
      bad->Array.forEach(o => env.log(`FAIL ${o.job.label}: ${o.detail}`))
      exportCheck->Array.forEach(why => env.log(`FAIL ${why}`))
      failures := failures.contents + (good ? 0 : 1)
      Node.mkdirAll(Node.dirname(env.timesFile))
      appendFileSync(
        env.timesFile,
        JSON.stringify(
          JSON.Object(
            Dict.fromArray([
              ("at", JSON.String(Date.fromTime(env.now())->Date.toISOString)),
              ("repository", JSON.String(Node.basename(env.root))),
              ("spec", JSON.String(spec.name)),
              ("mode", JSON.String(full ? "full" : "quick")),
              ("passed", JSON.Boolean(good)),
              ("states", JSON.String(main.states)),
              ("seconds", JSON.Number(Float.fromString(seconds(elapsed))->Option.getOr(0.))),
              ("cached", JSON.Boolean(nCached == nRuns)),
              ("runs", JSON.Number(Float.fromInt(nRuns))),
              ("cached_runs", JSON.Number(Float.fromInt(nCached))),
              ("cpus", JSON.Number(Float.fromInt(env.cpus))),
            ]),
          ),
        ) ++ "\n",
      )
    })
    env.log(`total: ${seconds(env.now() -. begun)}s`)
    failures.contents > 0 ? 1 : 0
  })
}
