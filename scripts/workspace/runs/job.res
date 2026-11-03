/**
 * The one entry for a long command, docs/agents/runs.md. `job start` returns at once, `job run`
 * waits, and either writes the ledger at the start and the end.
 */
type stdio
external stdioName: string => stdio = "%identity"
external stdioFile: int => stdio = "%identity"
type detached = {cwd: string, stdio: array<stdio>, detached: bool}
type process
@module("node:child_process")
external launch: (string, array<string>, detached) => process = "spawn"
@send external unref: process => unit = "unref"
@module("node:fs") external openFile: (string, string) => int = "openSync"
@val external selfPid: int = "process.pid"
@module("node:process") external signal: (int, string) => unit = "kill"
@val external nodePath: string = "process.execPath"

type given = {
  by: string,
  limit: option<float>,
  quiet: bool,
  wait: bool,
  command: array<string>,
}

/** A word as sh reads it literally, plain words left as they are. */
let quoted = word =>
  /^[A-Za-z0-9_@%+=:,.\/-]+$/->RegExp.test(word)
    ? word
    : `'${word->String.replaceAll("'", "'\\''")}'`

/** One word is a line for sh as written; several are a program and its arguments. */
let lineOf = (words: array<string>) =>
  words->Array.length == 1 ? words->Array.getUnsafe(0) : words->Array.map(quoted)->Array.join(" ")

/** The flags before the command, `--` optional as mise may keep or drop it. */
let parseGiven = (argv: array<string>, ~defaultBy) => {
  let rec go = (rest: list<string>, given) =>
    switch rest {
    | list{"--by", who, ...more} => go(more, {...given, by: who})
    | list{"--limit", seconds, ...more} => go(more, {...given, limit: Float.fromString(seconds)})
    | list{"--quiet", ...more} => go(more, {...given, quiet: true})
    | list{"--wait", ...more} => go(more, {...given, wait: true})
    | list{"--", ...more} => {...given, command: more->List.toArray}
    | command => {...given, command: command->List.toArray}
    }
  go(argv->List.fromArray, {by: defaultBy, limit: None, quiet: false, wait: false, command: []})
}

let pad = (value, width) => Int.toString(value)->String.padStart(width, "0")

/** A job's id, sortable by its UTC time, with a random end for two in one second. */
let newId = (~now) => {
  let date = Date.fromTime(now)
  let stamp =
    pad(date->Date.getUTCFullYear, 4) ++
    pad(date->Date.getUTCMonth + 1, 2) ++
    pad(date->Date.getUTCDate, 2) ++
    "-" ++
    pad(date->Date.getUTCHours, 2) ++
    pad(date->Date.getUTCMinutes, 2) ++
    pad(date->Date.getUTCSeconds, 2)
  let tail = Math.Int.floor(Math.random() *. 65536.)->Int.toString(~radix=16)
  `${stamp}-${tail->String.padStart(4, "0")}`
}

let originalCwd = () => Node.env->Dict.get("MISE_ORIGINAL_CWD")->Option.getOr(Node.cwd())

/** The process that owns the command: it writes the start, runs it, and writes the end. */
let supervise = (text: string) =>
  switch Ledger.fold(text) {
  | [job] =>
    Ledger.started({...job, pid: selfPid})
    let ran = Node.spawnSync("sh", ["-c", job.command], {stdio: "inherit", cwd: job.cwd})
    let status = ran.status->Nullable.getOr(1)
    Ledger.ended(~id=job.id, ~status, ~at=Date.now())
    Console.log(`[exited with code ${Int.toString(status)}]`)
    status
  | _ =>
    Console.error("job supervise: the job given is not one job")
    2
  }

let died = (job: Ledger.job, ~alive=Watchdog.alive) =>
  job.ended == None && job.pid > 0 && !alive(job.pid)

let listState = (job: Ledger.job, ~alive=Watchdog.alive) =>
  switch job.status {
  | Some(status) => `${Int.toString(status)}${Ledger.wasRead(job) ? "" : " unread"}`
  | None => died(job, ~alive) ? "died" : "running"
  }

let unfinished = (job: Ledger.job, ~alive=Watchdog.alive) =>
  `job ${job.id}: ${died(job, ~alive) ? "died" : "still running"}, output ${job.output}`

/** A finished job's status and the end of its output, its read recorded. */
let read = id =>
  switch Ledger.find(id) {
  | None =>
    Console.error(`${id} is no job of the ledger`)
    2
  | Some(job) =>
    let text = Node.existsSync(job.output) ? Node.readFileSync(job.output) : ""
    text->String.split("\n")->Array.slice(~start=-40)->Array.forEach(line => Console.log(line))
    switch (job.status, Ledger.seconds(job)) {
    | (Some(status), Some(took)) =>
      Ledger.markRead(~id, ~at=Date.now())
      Console.log(
        `job ${id}: status ${Int.toString(status)}, ${took->Float.toFixed(
            ~digits=1,
          )} s; whole output ${job.output}`,
      )
    | _ => Console.log(unfinished(job))
    }
    0
  }

/** The harness session calling, read from what each vendor sets, none where it sets nothing. */
let sessionNames = ["CLAUDE_CODE_SESSION_ID", "CODEX_THREAD_ID", "CODEX_SESSION_ID"]
let currentSession = () =>
  sessionNames->Array.findMap(name => Node.env->Dict.get(name))->Option.getOr("")

/** Whose a job is where the caller is not its owner, `job-stop-own`, none where it may stop it. */
let notOwn = (job: Ledger.job, ~session, ~by) =>
  job.by == by && job.session == session
    ? None
    : Some(`${job.by}${job.session == "" ? "" : ` in session ${job.session}`}`)

/** A job's process group ended, its end written since its owner dies with it. */
let stop = (id, ~by) =>
  switch Ledger.find(id) {
  | None =>
    Console.error(`${id} is no job of the ledger`)
    2
  | Some({ended: Some(_)}) =>
    Console.log(`${id} ended already`)
    0
  | Some(job) if notOwn(job, ~session=currentSession(), ~by) != None =>
    let whose = notOwn(job, ~session=currentSession(), ~by)->Option.getOr("")
    Console.error(
      `${id} is not yours to stop: it is ${whose}'s, and you are ${by}. Ask that session or seat, or pass --by if you started it under another name, job-stop-own.`,
    )
    1
  | Some(job) =>
    try signal(-job.pid, "SIGTERM") catch {
    | _ => ()
    }
    let now = Date.now()
    Ledger.ended(~id, ~status=143, ~at=now)
    // A watch of it ends here, as its owner died before saying so.
    Ledger.append(job.output, "[exited with code 143]\n")
    // Whoever stops a job has read its end.
    Ledger.markRead(~id, ~at=now)
    Console.log(`${id} stopped`)
    0
  }

let usage =
  "usage: mise run //:job start|run [--by <who>] [--limit <seconds>] [--quiet] -- <command>\n" ++
  "       mise run //:job read <id> | stop <id> [--by <who>] | list | table [--by-class] [--since <yyyy-mm-dd>] | events\n" ++
  "       mise run //:job register <role> <name> [--thread <name>] [--transcript <file>] | unregister <name>\n" ++ "       mise run //:job watchdog | install [--dry-run]"

let defaultBy = () => Node.env->Dict.get("MONOFLAKE_ROLE")->Option.getOr("session")

let begin = (argv, ~wait) => {
  let given = parseGiven(argv, ~defaultBy=defaultBy())
  if given.command == [] {
    Console.error(usage)
    2
  } else {
    Node.mkdirAll(Ledger.outputs())
    let now = Date.now()
    let id = newId(~now)
    let output = Ledger.outputOf(id)
    let cwd = originalCwd()
    let opening = Ledger.startLine({
      id,
      by: given.by,
      session: currentSession(),
      command: lineOf(given.command),
      cwd,
      pid: 0,
      started: now,
      output,
      limit: given.limit,
      quiet: given.quiet,
      ended: None,
      status: None,
      read: None,
    })
    let out = stdioFile(openFile(output, "a"))
    launch(
      nodePath,
      [Node.argv->Array.getUnsafe(1), "supervise", opening],
      {cwd, stdio: [stdioName("ignore"), out, out], detached: true},
    )->unref
    Console.log(`job ${id}`)
    Console.log(`output ${output}`)
    Console.log(`watch under Monitor: mise run //:watch ${id}`)
    Console.log(`read its result: mise run //:job read ${id}`)
    if wait || given.wait {
      let finished = ref(None)
      let waited = ref(0)
      while finished.contents == None {
        Node.spawnSync("sleep", ["1"], {stdio: "ignore"})->ignore
        finished :=
          switch Ledger.find(id) {
          | Some({status: Some(status)}) => Some(status)
          // Its owner gone with no end written is the end of the wait.
          | Some({pid}) if pid > 0 && !Watchdog.alive(pid) => Some(1)
          | Some(_) => None
          // No owner ever wrote its start, so nothing will write its end.
          | None =>
            waited := waited.contents + 1
            waited.contents > 30 ? Some(1) : None
          }
      }
      finished.contents->Option.getOr(1)
    } else {
      0
    }
  }
}

let register = (role, name, ~transcript, ~thread=None) =>
  if !(Delegation.registeredRoles->Array.includes(role)) {
    let roles = Delegation.registeredRoles->Array.join(", ")
    Console.error(`${role} has no limit; the roles are ${roles}`)
    2
  } else {
    Ledger.registerSession(~role, ~name, ~transcript, ~thread)
    Console.log(
      `${role} ${name} registered${transcript == None
          ? "; the hook names its transcript, and where none runs the watchdog says it cannot watch it"
          : ""}`,
    )
    0
  }

let unregister = name => {
  Node.rmSync(Node.join([Ledger.sessions(), `${name}.json`]), {recursive: false, force: true})
  Console.log(`${name} unregistered`)
  0
}

let listed = () => {
  Ledger.jobs()
  ->Array.slice(~start=-30)
  ->Array.forEach(job => {
    let state = listState(job)
    Console.log(`${job.id}  ${state}  ${job.by}  ${job.command->String.slice(~start=0, ~end=60)}`)
  })
  0
}

let tabled = since => {
  Ledger.table(
    Ledger.jobs(),
    ~since=since->Option.mapOr(0., day => Date.fromString(day)->Date.getTime),
  )->Array.forEach(row => Console.log(Ledger.shownRow(row)))
  0
}

/** The plist launchd runs the watchdog by, through mise so its node is the pinned one. */
let plist = (~mise, ~root, ~log) =>
  `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>${Delegation.watchdogLabel}</string>
	<key>ProgramArguments</key>
	<array>
		<string>${mise}</string>
		<string>exec</string>
		<string>-C</string>
		<string>${root}</string>
		<string>--</string>
		<string>node</string>
		<string>${root}/scripts/workspace/runs/watchdog.res.mjs</string>
	</array>
	<key>WorkingDirectory</key>
	<string>${root}</string>
	<key>StartInterval</key>
	<integer>${Int.toString(Delegation.watchdogSeconds)}</integer>
	<key>RunAtLoad</key>
	<true/>
	<key>StandardOutPath</key>
	<string>${log}</string>
	<key>StandardErrorPath</key>
	<string>${log}</string>
</dict>
</plist>
`

/** Writes the plist under the author's LaunchAgents and loads it, the dry run writing nothing. */
let install = (~dry) => {
  let mise = Node.output("sh", ["-c", "command -v mise"])->String.trim
  let user = Node.env->Dict.get("HOME")->Option.getOr("")
  let path = Node.join([user, "Library", "LaunchAgents", `${Delegation.watchdogLabel}.plist`])
  let domain = `gui/${Node.output("id", ["-u"])->String.trim}`
  let text = plist(~mise, ~root=Registry.root, ~log=Node.join([Ledger.home(), "watchdog.log"]))
  if dry {
    Console.log(`would write ${path}:\n${text}`)
    Console.log(
      `would run launchctl bootout ${domain}/${Delegation.watchdogLabel}, an absent one ignored`,
    )
    Console.log(`would run launchctl bootstrap ${domain} ${path}`)
    0
  } else {
    Node.mkdirAll(Ledger.home())
    Node.writeFileSync(path, text)
    Node.spawnSync(
      "launchctl",
      ["bootout", `${domain}/${Delegation.watchdogLabel}`],
      {stdio: "ignore"},
    )->ignore
    let status = Node.run("launchctl", ["bootstrap", domain, path])
    Console.log(
      status == 0
        ? `the watchdog runs each ${Int.toString(
              Delegation.watchdogSeconds,
            )} s, events in ${Ledger.events()}`
        : "launchctl refused it",
    )
    status
  }
}

let main = (argv: array<string>) =>
  switch argv {
  | ["supervise", text] => supervise(text)
  | ["read", id] => read(id)
  | ["stop", id] => stop(id, ~by=defaultBy())
  | ["stop", id, "--by", by] => stop(id, ~by)
  | ["list"] => listed()
  | _ if argv[0] == Some("table") && argv[1] == Some("--by-class") =>
    Classes.run(argv->Array.slice(~start=2))
  | ["table"] => tabled(None)
  | ["table", "--since", day] => tabled(Some(day))
  | ["events"] =>
    Console.log(Ledger.events())
    0
  | ["register", role, name] => register(role, name, ~transcript=None)
  | ["register", role, name, "--transcript", file] => register(role, name, ~transcript=Some(file))
  | ["register", role, name, "--thread", thread] =>
    register(role, name, ~transcript=None, ~thread=Some(thread))
  | ["register", role, name, "--thread", thread, "--transcript", file]
  | ["register", role, name, "--transcript", file, "--thread", thread] =>
    register(role, name, ~transcript=Some(file), ~thread=Some(thread))
  | ["unregister", name] => unregister(name)
  | ["watchdog"] =>
    Console.log(`${Int.toString(Watchdog.look())} events written to ${Ledger.events()}`)
    0
  | ["install"] => install(~dry=false)
  | ["install", "--dry-run" | "-n"] => install(~dry=true)
  | _ =>
    switch argv[0] {
    | Some("start") => begin(argv->Array.slice(~start=1), ~wait=false)
    | Some("run") => begin(argv->Array.slice(~start=1), ~wait=true)
    | _ =>
      Console.error(usage)
      2
    }
  }

if Node.isMain {
  Node.exit(main(Node.args()))
}
