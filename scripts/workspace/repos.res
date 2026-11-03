/**
 * Every verb across the repositories, `repos <verb> [name | --all] [--dry-run]`, and the
 * workspace's own half of fmt, clean, update and verify. See docs/repos.md.
 */
/** The update verifies before the landing rolls, leaving versions to the check after it. */
let updateParts = () => ["rules", ...Check.known->Array.filter(name => name != "versions")]

let root = Registry.root
let repos = Registry.repos

type ran = {status: int, out: string, err: string}

let capture = (~cwd, command, commandArgs) => {
  let result = Node.spawnSync(command, commandArgs, {cwd, encoding: "utf8", maxBuffer: 268435456})
  {
    status: result.status->Nullable.getOr(1),
    out: result.stdout->Nullable.getOr(""),
    err: result.stderr->Nullable.getOr(""),
  }
}

/** jj's answer, or its error on stderr and a refusal naming where it failed. */
let jj = (~cwd, args) => {
  let result = capture(~cwd, "jj", args)
  if result.status != 0 {
    Console.error(result.err)
    Registry.fail(`jj ${args->Array.join(" ")} failed in ${Registry.label(cwd)}`)
  }
  result.out
}

let lines = text => text->String.trim->String.split("\n")->Array.filter(line => line != "")

let list = () => {
  let onDisk = Registry.discovered()
  let listed = Registry.registry()
  listed->Array.forEach(((directory, (user, repo))) => {
    let mark = onDisk->Array.includes(directory) ? "" : "   (not cloned)"
    Console.log(`${directory->String.padEnd(16, " ")} ${user}:${repo}${mark}`)
  })
  let names = listed->Array.map(((directory, _)) => directory)
  onDisk
  ->Array.filter(directory => !(names->Array.includes(directory)))
  ->Array.forEach(directory =>
    Console.log(`${directory->String.padEnd(16, " ")} on disk but not listed in registry.toml`)
  )
  0
}

let clone = (name, ~dry) => {
  if name == Some("workspace") {
    Registry.fail("the workspace is this checkout; there is nothing to clone")
  }
  let listed = Registry.registry()
  let wanted = switch name {
  | Some(name) =>
    switch listed->Array.find(((directory, _)) => directory == name) {
    | Some(entry) => [entry]
    | None =>
      Registry.fail(
        `registry.toml does not list ${name}; the names are ${listed
          ->Array.map(((directory, _)) => directory)
          ->Array.join(", ")}`,
      )
    }
  | None => listed
  }
  let added =
    wanted
    ->Array.filter(((directory, _)) => !Node.existsSync(Node.join([repos, directory])))
    ->Array.map(((directory, (user, repo))) => {
      let target = Node.join([repos, directory])
      if dry {
        Console.log(`would clone ${user}:${repo} into repos/${directory}`)
      } else {
        Console.log(`cloning ${user}:${repo} into repos/${directory}`)
        // Colocated, because the git side is what the remote and any contributor speak.
        let url = `https://github.com/${user}/${repo}.git`
        if Node.run("jj", ["git", "clone", "--colocate", url, target]) != 0 {
          Registry.fail(`cloning ${user}:${repo} failed`)
        }
      }
    })
  Console.log(`${Int.toString(added->Array.length)} ${dry ? "would be cloned" : "cloned"}`)
  0
}

/** Fetch, and say what it brought in; a dry run fetches nothing and says its answer is old. */
let pull = (name, ~dry, ~everything) => {
  Registry.selected(name, ~everything)->Array.forEach(repo => {
    let place = Registry.label(repo)
    if !Registry.isRepository(repo) {
      Console.log(`${place}: not a repository, skipped`)
    } else {
      let fetched =
        dry || {
          let result = capture(~cwd=repo, "jj", ["git", "fetch"])
          if result.status != 0 {
            Console.log(`${place}: fetch failed`)
            Console.error(result.err)
          }
          result.status == 0
        }
      if fetched {
        let behind =
          capture(
            ~cwd=repo,
            "jj",
            [
              "log",
              "--no-graph",
              "-r",
              "main..main@origin",
              "-T",
              `commit_id.short() ++ " " ++ description.first_line() ++ "\\n"`,
            ],
          ).out->lines
        let stale = dry ? " (as of the last fetch; none run)" : ""
        Console.log(`${place}: ${behind == [] ? "up to date" : "behind by"}${stale}`)
        behind->Array.forEach(line => Console.log(`    ${line}`))
      }
    }
  })
  0
}

/** What main holds that origin lacks, or None where jj cannot tell. */
/** Whether a repository below has its own task for a verb, inline or as a file task. */
let declares = (repo, verb) => {
  let config = Node.join([repo, "mise.toml"])
  let text = Node.existsSync(config) ? Node.readFileSync(config) : ""
  let inline =
    text->String.includes(`[tasks.${verb}]`) || text->String.includes(`[tasks."${verb}"]`)
  let tasks = Node.join([repo, ".mise", "tasks"])
  // A file task is named for its file without the extension, as mise names `verify.ts` `verify`.
  inline ||
  (Node.existsSync(tasks) &&
  Node.readdir(tasks)->Array.some(file =>
    file->String.split(".")->Array.get(0) == Some(verb) &&
      Node.stat(Node.join([tasks, file]))->Option.mapOr(false, Node.statsIsFile)
  ))
}

let task = (repo, verb) => `//repos/${Registry.label(repo)}:${verb}`

/** The workspace's own fmt, oxfmt and ReScript's formatter over the files jujutsu.toml names. */
let formatted = "**/*.{ts,tsx,mts,cts,js,mjs,cjs,jsx,css,json,jsonc,md,svelte}"
let fmt = (~dry) =>
  if dry {
    Node.run(
      ~cwd=root,
      "oxfmt",
      ["--list-different", "--no-error-on-unmatched-pattern", formatted],
    )->ignore
    Node.run(~cwd=root, "rescript", ["format", "--check"])->ignore
    0
  } else if (
    Node.run(~cwd=root, "oxfmt", ["--no-error-on-unmatched-pattern", formatted]) == 0 &&
      Node.run(~cwd=root, "rescript", ["format"]) == 0
  ) {
    0
  } else {
    1
  }

/** The workspace's own clean, what ReScript compiled and the hooks' bytecode, repos/ apart. */
let clean = (~dry) => {
  let found = ["hooks", ".mise"]->Array.flatMap(top => {
    let rec walk = at =>
      Node.entries(at)
      ->Array.filter(Node.isDirectory)
      ->Array.flatMap(entry => {
        let path = Node.join([at, entry->Node.name])
        entry->Node.name == "__pycache__" ? [path] : walk(path)
      })
    let start = Node.join([root, top])
    Node.existsSync(start) ? walk(start) : []
  })
  let uncompiled = Clean.uncompile(root, ~dry, ~apart=["repos"])
  if found == [] && !uncompiled {
    Console.log("nothing to clean")
  }
  found->Array.forEach(path => {
    let shown = Node.relative(root, path)
    if dry {
      Console.log(`would remove ${shown}`)
    } else {
      Node.rmSync(path, {recursive: true, force: true})
      Console.log(`removed ${shown}`)
    }
  })
  0
}

let mover = name => Node.join([root, "scripts", "deps", `${name}.res.mjs`])

/**
 * Each mover run from `repo`, logged as typed, on past a failure, 1 where one failed and
 * `Releases.partly` where the one that did not pass was the releases mover writing what it read,
 * each source it held back put in `held`.
 */
let moved = async (repo, movers: array<array<string>>, ~held=[]) => {
  let status = ref(0)
  for index in 0 to movers->Array.length - 1 {
    let commandArgs = movers->Array.getUnsafe(index)
    let shown = commandArgs->Array.map(arg => arg->String.replace(`${root}/`, ""))
    Console.log(`\n$ node ${shown->Array.join(" ")}`)
    let code = if commandArgs[0]->Option.map(Node.basename) == Some("releases.res.mjs") {
      let (code, out) = await Node.stream(~cwd=repo, "node", commandArgs)
      if code == Releases.partly {
        Releases.heldIn(out)->Array.forEach(source => held->Array.push(source))
      }
      code
    } else {
      Node.run(~cwd=repo, "node", commandArgs)
    }
    status :=
      switch (code, status.contents) {
      | (0, status) => status
      | (code, 0 | 2) if code == Releases.partly => Releases.partly
      | _ => 1
      }
  }
  status.contents
}

/** The workspace's movers a repository's `[update]` asks for, beside its own task. */
let movers = (repo, ~dry, ~major): array<array<string>> => {
  let n = dry ? ["--dry-run"] : []
  let crossing = Array.concat(n, major ? ["--major"] : [])
  switch Project.read(repo) {
  | Ok({update}) =>
    Array.concat(
      [
        update.packages ? Some([mover("update"), ...crossing]) : None,
        update.actions ? Some([mover("actions"), ...crossing]) : None,
        update.images ? Some([mover("images"), ...n]) : None,
      ]->Array.filterMap(found => found),
      update.releases->Array.map(manifest => [mover("releases"), manifest, ...n]),
    )
  | Error(_) => []
  }
}

/** The workspace's own update, [tools] within their pins, its action, and package.json. */
let refresh = async (~dry, ~major) => {
  let tools = await Tools.up(~name="workspace", ~dry)
  let flags = Array.concat(dry ? ["--dry-run"] : [], major ? ["--major"] : [])
  let tools = tools != 0 ? tools : await moved(root, [[mover("actions"), ...flags]])
  Console.log("")
  if dry {
    Console.log("$ pnpm outdated")
    // Exits non-zero whenever something is outdated, which is the answer rather than a failure.
    Node.run(~cwd=root, "pnpm", ["outdated"])->ignore
    tools
  } else if tools != 0 {
    tools
  } else {
    let flags = major ? ["--latest"] : []
    Console.log(`$ pnpm update${major ? " --latest" : ""}`)
    let (status, out) = await Node.stream(~cwd=root, "pnpm", ["update", ...flags])

    // A version younger than minimumReleaseAge is the supply-chain delay holding, not a failure.
    if status != 0 && out->String.includes("ERR_PNPM_NO_MATURE_MATCHING_VERSION") {
      Console.log("held by the supply-chain delay, nothing moved; run again once it has aged")
      0
    } else {
      status
    }
  }
}

/** Each line a check's blocks in work failed, once, as they were listed, `in-work-shown`. */
let inWorkOf = text =>
  text
  ->String.split("\n")
  ->Array.filter(line => line != "")
  ->Set.fromArray
  ->Set.values
  ->Array.fromIterator

let inWorkSaid = (lines: array<string>) =>
  lines == []
    ? []
    : [
        `in work, failing and not counted until accepted, ${Int.toString(
            lines->Array.length,
          )}: read these before landing`,
        ...lines->Array.map(line => `  ! ${line->String.slice(~start=0, ~end=96)}`),
      ]

/** Each failed repository's symptom lines under its label, the last a failed check prints. */
let causesSaid = (causes: array<(string, array<string>)>) =>
  causes->Array.flatMap(((place, lines)) =>
    lines == [] ? [] : [`${place}:`, ...lines->Array.map(line => `  ${line}`)]
  )

let summaryLines = (verb, skipped, failed, ~paused=[], ~inWork=[], ~causes=[]) =>
  skipped == [] && failed == [] && paused == [] && inWork == []
    ? []
    : Array.flat([
        ["\n" ++ String.repeat("-", 72)],
        skipped == []
          ? []
          : [`warning: no ${verb} task of their own, so passed over: ${skipped->Array.join(", ")}`],
        paused == [] ? [] : [`paused, so passed over: ${paused->Array.join(", ")}`],
        inWorkSaid(inWork),
        failed == [] ? [] : [`failed: ${failed->Array.join(", ")}`],
        causesSaid(causes),
      ])

let summary = (verb, skipped, failed, ~paused=[], ~inWork=[], ~causes=[]) =>
  summaryLines(verb, skipped, failed, ~paused, ~inWork, ~causes)->Array.forEach(line =>
    Console.log(line)
  )

/** Each `verify:<part>` task a repository's mise.toml declares inline, in the order declared. */
let verifyParts = repo => {
  let config = Node.join([repo, "mise.toml"])
  let text = Node.existsSync(config) ? Node.readFileSync(config) : ""
  let opening = `[tasks."verify:`
  text
  ->String.split("\n")
  ->Array.map(String.trim)
  ->Array.filter(line => line->String.startsWith(opening) && line->String.endsWith(`"]`))
  ->Array.map(line => line->String.slice(~start=opening->String.length, ~end=-2))
}

/** The repository's own verify parts named, in the order its mise.toml declares them. */
let namedVerifyParts = (repo, parts) =>
  verifyParts(repo)->Array.filter(part => parts->Array.includes(part))

let checkParts = (repo, parts) => {
  let available = Check.over(repo)
  let shared = available->Array.map(((name, _)) => name)
  let owned = verifyParts(repo)
  let known = ["own", ...owned, ...shared]
  parts->Array.forEach(name =>
    if owned->Array.includes(name) && shared->Array.includes(name) {
      Registry.fail(
        `${name} is ambiguous, both ${task(
            repo,
            `verify:${name}`,
          )} and the workspace's part ${name}`,
      )
    } else if !(known->Array.includes(name)) {
      Registry.fail(
        `${Registry.label(repo)}'s check has no part ${name}; the parts are ${known->Array.join(
            ", ",
          )}`,
      )
    }
  )
  available->Array.filter(((name, _)) => parts == [] || parts->Array.includes(name))
}

/** Whether a check of these parts runs a repository's own verify. */
let runsOwn = parts => parts == [] || parts->Array.includes("own")

/** Whether a run may write the stamp a commit waits on, the full check alone, docs/commits.md. */
let stamps = (verb, ~dry, ~parts) => verb == "verify" && !dry && parts == []

/** The dry-run line for the workspace's rules over a repository, naming the parts selected. */
let rulesLine = (parts, shared: array<(string, Check.part)>) =>
  "would run the workspace's rules over it" ++ (
    parts == [] ? "" : " " ++ shared->Array.map(((name, _)) => name)->Array.join(" ")
  )

/** The repositories `--all` reaches, each one a deferred item pauses passed over and named. */
let active = (name, ~everything, paused) =>
  Registry.selected(name, ~everything)->Array.filter(repo =>
    switch everything ? Waiting.pauser(~repo=Registry.label(repo)) : None {
    | Some(id) =>
      paused->Array.push(`${Registry.label(repo)} (deferred ${id})`)
      false
    | None => true
    }
  )

/** The lines of a failed verify worth repeating under the summary, which a long log buries. */
let marked = /\berror\b|panicked|FAILED/
let symptom = output => {
  let all = output->String.split("\n")
  let flagged = all->Array.filter(line => marked->RegExp.test(line))
  (flagged == [] ? all : flagged)->Array.slice(~start=0, ~end=10)
}

type consoleObject
@val external consoleObject: consoleObject = "console"
@get external logger: consoleObject => string => unit = "log"
@set external setLogger: (consoleObject, string => unit) => unit = "log"

/** A part run in this process, what it logged shown as it goes and kept beside its status. */
let heard = run => {
  let shown = consoleObject->logger
  let seen = []
  consoleObject->setLogger(text => {
    shown(text)
    seen->Array.push(text)
  })
  let status = try run() catch {
  | error =>
    consoleObject->setLogger(shown)
    throw(error)
  }
  consoleObject->setLogger(shown)
  (status, seen->Array.join("\n"))
}

/** The form layer's parts, in the order a full check runs them, docs/agents/checking.md. */
let formParts = ["shape", "lines", "comments"]

type step =
  | Gate(string, Check.part)
  | OwnGate(string)
  | Verify
  | Rule(string, Check.part)

let stepName = step =>
  switch step {
  | Gate(name, _) | Rule(name, _) => name
  | OwnGate(name) => `verify:${name}`
  | Verify => "verify"
  }

/** A full check's steps over a repository, its form parts and own format first as gates. */
let planned = (shared: array<(string, Check.part)>, owned) =>
  Array.flat([
    formParts
    ->Array.filterMap(name => shared->Array.find(((one, _)) => one == name))
    ->Array.map(((name, part)) => Gate(name, part)),
    owned->Array.includes("format") ? [OwnGate("format")] : [],
    [Verify],
    shared
    ->Array.filter(((name, _)) => !(formParts->Array.includes(name)))
    ->Array.map(((name, part)) => Rule(name, part)),
  ])

/** Each step in order, on past a failure but a gate's, with what each failing step printed. */
let walked = async (steps, run) => {
  let said = []
  let stopped = ref(false)
  for index in 0 to steps->Array.length - 1 {
    if !stopped.contents {
      let step = steps->Array.getUnsafe(index)
      let (status, out) = await run(step)
      if status != 0 {
        said->Array.push(out)
        switch step {
        | Gate(_) | OwnGate(_) => stopped := true
        | _ => ()
        }
      }
    }
  }
  (said == [] ? 0 : 1, said->Array.join("\n"))
}

/** One repository's full check, its deferred items shown only when asked. */
let checked = async (repo, ~skipped, ~verbose) => {
  let place = Registry.label(repo)
  let run = async step =>
    switch step {
    | Gate(name, part) | Rule(name, part) =>
      Console.log(`\n=== ${place} ${name}, the workspace's ===`)
      heard(() => Check.outcome(part))
    | OwnGate(name) =>
      let path = task(repo, `verify:${name}`)
      Console.log(`\n=== ${path} ===`)
      await Node.stream(~cwd=root, "mise", ["run", path])
    | Verify if !declares(repo, "verify") =>
      skipped->Array.push(place)
      (0, "")
    | Verify =>
      Console.log(`\n=== ${task(repo, "verify")} ===`)
      await Node.stream(~cwd=root, "mise", ["run", task(repo, "verify")])
    }
  let result = await walked(planned(checkParts(repo, []), verifyParts(repo)), run)
  let waiting = Array.concat(Waiting.shown(~repo=Some(place)), Repo_plan.waiting(~repo=Some(place)))
  if verbose && waiting != [] {
    Console.log("")
    waiting->Array.forEach(line => Console.log(line))
  }
  result
}

/** A verb over one repository other than a full check below the workspace, as it ran before. */
let dispatched = async (repo, verb, ~dry, ~parts, ~skipped) => {
  let place = Registry.label(repo)
  let shared = repo != root && verb == "verify" ? checkParts(repo, parts) : []
  let said = []
  let kept = ((status, out)) => {
    if status != 0 {
      said->Array.push(out)
    }
    status
  }
  let own = if repo == root {
    Console.log(`\n=== workspace ${verb}${dry ? " --dry-run" : ""} ===`)
    switch verb {
    | "fmt" => fmt(~dry)
    | "clean" => clean(~dry)
    | _ if dry =>
      Check.validate(parts)
      Console.log(`would run check workspace${parts == [] ? "" : " " ++ parts->Array.join(" ")}`)
      0
    | _ => kept(heard(() => Check.run(parts)))
    }
  } else if verb == "verify" && !runsOwn(parts) {
    let chosen = namedVerifyParts(repo, parts)
    let failures = ref(0)
    for index in 0 to chosen->Array.length - 1 {
      let path = task(repo, `verify:${chosen->Array.getUnsafe(index)}`)
      Console.log(dry ? `would run ${path}` : `\n=== ${path} ===`)
      if !dry {
        failures := failures.contents + kept(await Node.stream(~cwd=root, "mise", ["run", path]))
      }
    }
    failures.contents
  } else if !declares(repo, verb) {
    skipped->Array.push(place)
    0
  } else if dry && verb == "verify" {
    Console.log(`would run ${task(repo, verb)}`)
    0
  } else {
    let flags = dry ? ["--dry-run"] : []
    Console.log(`\n=== ${[task(repo, verb), ...flags]->Array.join(" ")} ===`)
    Node.run(~cwd=root, "mise", ["run", task(repo, verb), ...flags])
  }
  // Below the workspace, the parts named, or what a dry run would run.
  let held = if repo == root || verb != "verify" || (parts != [] && shared == []) {
    0
  } else if dry {
    Console.log(rulesLine(parts, shared))
    0
  } else {
    shared->Array.reduce(0, (failed, (name, part)) => {
      Console.log(`\n=== ${place} ${name}, the workspace's ===`)
      kept(heard(() => Check.outcome(part))) + failed
    })
  }
  (own != 0 || held != 0 ? 1 : 0, said->Array.join("\n"))
}

/** fmt, clean or verify, the workspace's half here and each repository's own, past a failure. */
let dispatch = async (verb, name, ~dry, ~everything, ~parts, ~verbose=false, ~ahead=() => ()) => {
  if everything && parts != [] {
    Registry.fail("--all and check parts cannot be combined")
  }
  let skipped = []
  let failed = []
  let causes = []
  let paused = []
  let listed = Node.join([Node.mkdtempSync(Node.join([Node.tmpdir(), "in-work-"])), "listed"])
  Node.env->Dict.set(Delegation.inWorkFile, listed)
  let chosen = active(name, ~everything, paused)
  for index in 0 to chosen->Array.length - 1 {
    let repo = chosen->Array.getUnsafe(index)
    let place = Registry.label(repo)
    let before = stamps(verb, ~dry, ~parts) ? Stamp.snapshot(repo) : ""
    let (status, said) = if repo != root && verb == "verify" && parts == [] && !dry {
      await checked(repo, ~skipped, ~verbose)
    } else {
      await dispatched(repo, verb, ~dry, ~parts, ~skipped)
    }
    if status != 0 {
      failed->Array.push(place)
      let lines = said->String.split("\n")->Array.filter(line => line->String.trim != "")
      causes->Array.push((
        place,
        symptom(lines->Array.join("\n"))->Array.filter(line => line != ""),
      ))
    } else if before != "" {
      Stamp.write(repo, before)
    }
  }
  let inWork = Node.existsSync(listed) ? inWorkOf(Node.readFileSync(listed)) : []
  Node.rmSync(Node.dirname(listed), {recursive: true, force: true})
  ahead()
  summary(verb, skipped, failed, ~paused, ~inWork, ~causes)
  failed == [] ? 0 : 1
}

let snapshot = Stamp.snapshot

/** Exactly these paths put back as they were in `before`, by path so others' edits survive. */
let restore = (repo, before, paths) => {
  let literal = path =>
    `root-file:"${path->String.replaceAll("\\", "\\\\")->String.replaceAll("\"", "\\\"")}"`
  jj(~cwd=repo, ["restore", "--from", before, ...paths->Array.map(literal)])->ignore
}

/**
 * Whether what a repository's update moved is kept, its movers having exited `code`, on 0 and on
 * `Releases.partly`, a release source held back while the rest was written; on any other exit the
 * paths are put back as they were in `before`.
 */
let settled = (repo, ~code, ~before, ~paths) =>
  if code == 0 || code == Releases.partly {
    true
  } else {
    if paths != [] {
      restore(repo, before, paths)
    }
    false
  }

/**
 * Each repository's own update and the movers its `[update]` declares, kept only where its verify
 * still passes. See docs/toolchain/dependencies.md.
 */
let update = async (name, ~dry, ~major, ~everything) => {
  let skipped = []
  let failed = []
  let reverted = []
  let held = []
  let paused = []
  let flags = Array.concat(dry ? ["--dry-run"] : [], major ? ["--major"] : [])
  let chosen = active(name, ~everything, paused)
  for index in 0 to chosen->Array.length - 1 {
    let repo = chosen->Array.getUnsafe(index)
    let place = Registry.label(repo)
    let own = repo == root
    let shared = own ? [] : movers(repo, ~dry, ~major)
    let tasked = !own && declares(repo, "update")
    if !own && !tasked && shared == [] {
      skipped->Array.push(place)
    } else {
      let shown = own ? "workspace update" : tasked ? task(repo, "update") : `${place} update`
      Console.log(`\n=== ${[shown, ...flags]->Array.join(" ")} ===`)
      let move = async () =>
        if own {
          await refresh(~dry, ~major)
        } else {
          let ran = tasked
            ? Node.run(~cwd=root, "mise", ["run", task(repo, "update"), ...flags])
            : 0
          let sources = []
          let status = await moved(repo, shared, ~held=sources)
          if status == Releases.partly {
            held->Array.push((place, sources))
          }
          ran != 0 ? 1 : status
        }
      if dry {
        let code = await move()
        if code != 0 && code != Releases.partly {
          failed->Array.push(place)
        }
      } else {
        let before = snapshot(repo)
        let code = await move()
        let after = snapshot(repo)
        let paths = jj(~cwd=repo, ["diff", "--from", before, "--to", after, "--name-only"])->lines
        if !settled(repo, ~code, ~before, ~paths) {
          failed->Array.push(place)
        } else if paths != [] {
          if !own && !declares(repo, "verify") {
            Console.log(`\n${place} has no verify, so what moved is kept unchecked`)
          } else {
            let (command, commandArgs) = own
              ? ("node", [Node.join([root, "checks", "check.res.mjs"]), ...updateParts()])
              : ("mise", ["run", task(repo, "verify")])
            Console.log(`\n=== ${own ? "check workspace" : task(repo, "verify")} ===`)
            let (status, out) = await Node.stream(~cwd=root, command, commandArgs)
            if status != 0 {
              restore(repo, before, paths)
              reverted->Array.push((place, symptom(out), paths))
            }
          }
        }
      }
    }
  }
  summary("update", skipped, failed, ~paused)
  held
  ->Array.filter(((place, _)) =>
    !(failed->Array.includes(place)) && !(reverted->Array.some(((back, _, _)) => back == place))
  )
  ->Array.forEach(((place, sources)) =>
    Console.log(
      `warning: ${place} holds back its pins from ${sources->Array.join(
          ", ",
        )}, whose releases were not read; the rest that moved is kept`,
    )
  )
  if reverted != [] {
    Console.log(
      "\nReverted, because verify failed with what moved; these files are back as they were:\n",
    )
    reverted->Array.forEach(((place, shown, paths)) => {
      Console.log(`  ${place}: ${paths->Array.join(", ")}`)
      shown->Array.forEach(line => Console.log(`      ${line}`))
    })
    Console.log("\n  the full log is above; the next `update` tries the same bounds again")
  }
  failed == [] && reverted == [] ? 0 : 1
}

/** One repository's publish, the one verb a missing name refuses; what follows goes on unread. */
let publish = (name, passed) => {
  let have = () =>
    Registry.paths()->Array.filter(path => {
      let repo = Node.join([repos, path])
      Node.existsSync(repo) && declares(repo, "publish")
    })
  switch name {
  | None =>
    let named = have()
    Registry.fail(
      `publish takes a repository name, one of: ${named == []
          ? "<name>"
          : named->Array.join(", ")}`,
    )
  | Some("workspace") => Registry.fail("the workspace publishes nothing; it holds configuration")
  | Some(name) =>
    let repo = Registry.selected(Some(name))->Array.getUnsafe(0)
    if !declares(repo, "publish") {
      Registry.fail(`repos/${name} has no publish task`)
    }
    let path = task(repo, "publish")
    Console.log(`=== ${[path, ...passed]->Array.join(" ")} ===`)
    Node.run(~cwd=root, "mise", ["run", path, ...passed])
  }
}

type request = {
  verb: string,
  name: option<string>,
  dry: bool,
  major: bool,
  json: bool,
  verbose: bool,
  everything: bool,
  parts: array<string>,
  passed: array<string>,
}

let usage = "usage: repos list | clone | pull | push | fmt | update | clean | verify | publish  [name | --all] [part ...] [--dry-run] [--verbose]"
let across = ["update", "fmt", "clean", "verify", "pull", "push"]

/** What was typed, or why it is refused. A name means that repository, and nothing is dropped. */
let parse = (argv: array<string>): request => {
  let flag = names => argv->Array.some(arg => names->Array.includes(arg))
  let known = ["-n", "--dry-run", "--major", "-a", "--all", "--pending", "--json", "--verbose"]
  let rest = argv->Array.filter(arg => !(arg->String.startsWith("-")))
  let verb = rest[0]->Option.getOr("")
  let name = rest[1]
  let request = {
    verb,
    name,
    dry: flag(["-n", "--dry-run"]),
    major: flag(["--major"]),
    json: flag(["--json"]),
    verbose: flag(["--verbose"]),
    everything: flag(["-a", "--all"]),
    parts: [],
    passed: [],
  }
  if verb == "publish" {
    // Its flags are the project's own, so whatever follows the name goes on as it was typed.
    let skipped = ref(0)
    let passed = argv->Array.filter(arg =>
      if skipped.contents < 2 && !(arg->String.startsWith("-")) {
        skipped := skipped.contents + 1
        false
      } else {
        true
      }
    )
    {...request, passed: passed->Array.map(arg => arg == "-n" ? "--dry-run" : arg)}
  } else {
    let owned = verb == "verify" && name == Some("workspace")
    if request.json && (verb != "update" || !request.dry) {
      Registry.fail("--json belongs to update --dry-run")
    }
    switch argv->Array.find(arg => arg->String.startsWith("-") && !(known->Array.includes(arg))) {
    | Some(unknown) => Registry.fail(`unknown option ${unknown}`)
    | None => ()
    }
    if flag(["--pending"]) && !owned {
      Registry.fail("--pending belongs to the workspace's own check: check workspace --pending")
    }
    let extra = rest->Array.slice(~start=2)
    if extra != [] && verb != "verify" {
      Registry.fail(`one name at most; ${extra->Array.join(" ")} would have been ignored`)
    }
    if name->Option.isSome && verb == "list" {
      Registry.fail("list reads the whole registry and takes no name")
    }
    if request.major && verb != "update" {
      Registry.fail("--major belongs to update; crossing a boundary is that command's to take")
    }
    if request.everything && !(across->Array.includes(verb)) {
      Registry.fail(`--all belongs to the verbs that run across repositories; ${verb} is not one`)
    }
    {...request, parts: Array.concat(extra, flag(["--pending"]) ? ["--pending"] : [])}
  }
}

let ownItems = (~repository, output) => {
  try {Reminder.decode(output)->Array.map(item => {...item, repository})} catch {
  | _ =>
    let lines = output->String.split("\n")
    lines
    ->Array.mapWithIndex((line, index) =>
      switch Actions.groups(/Updated input '([^']+)'/, line) {
      | Some([name]) =>
        let version = offset =>
          lines[index + offset]
          ->Option.flatMap(line => Actions.groups(/'([^']+)'/, line))
          ->Option.flatMap(groups => groups[0])
        switch (version(1), version(2)) {
        | (Some(from), Some(to)) => Some(Reminder.item(~repository, "flake", name, from, to))
        | _ => None
        }
      | _ => None
      }
    )
    ->Array.filterMap(item => item)
  }
}

let jsonUpdate = async (name, ~everything, ~major) => {
  let items = []
  let failed = ref(false)
  let take = (repo, command, args) => {
    let result = capture(~cwd=repo, command, args)
    try {
      Reminder.decode(result.out)->Array.forEach(item =>
        items->Array.push({...item, repository: Registry.label(repo)})
      )
    } catch {
    | _ => failed := true
    }
    if result.status != 0 {
      failed := true
    }
  }
  active(name, ~everything, [])->Array.forEach(repo => {
    if repo != root && declares(repo, "update") {
      let result = capture(
        ~cwd=root,
        "mise",
        ["run", task(repo, "update"), "--dry-run", ...major ? ["--major"] : []],
      )
      if result.status != 0 {
        failed := true
      }
      ownItems(
        ~repository=Registry.label(repo),
        result.out ++ "\n" ++ result.err,
      )->Array.forEach(item => items->Array.push(item))
    }
    let commands =
      repo == root
        ? [
            [mover("update"), "--dry-run"],
            [mover("actions"), "--dry-run", ...major ? ["--major"] : []],
          ]
        : movers(repo, ~dry=true, ~major)
    commands->Array.forEach(args => take(repo, "node", [...args, "--json"]))
  })
  Console.log(Reminder.encode(items))
  failed.contents ? 1 : 0
}

/** The update reminder, said before a check's summary so its causes stay the last lines. */
let reminded = () => {
  let line = Reminder.line()
  if line != "" {
    Console.log(line)
  }
}

let execute = async argv => {
  let request = parse(argv)
  let {name, dry, everything} = request
  switch request.verb {
  | "list" => list()
  | "clone" => clone(name, ~dry)
  | "pull" => pull(name, ~dry, ~everything)
  | "push" => Outgoing.push(name, ~dry, ~everything)
  | "fmt" | "clean" => await dispatch(request.verb, name, ~dry, ~everything, ~parts=[])
  | "verify" if request.parts->Array.includes("--pending") =>
    Check.pending()->Array.forEach(line => Console.log(line))
    0
  | "verify" =>
    await dispatch(
      "verify",
      name,
      ~dry,
      ~everything,
      ~parts=request.parts,
      ~verbose=request.verbose,
      ~ahead=reminded,
    )
  | "update" =>
    request.json
      ? await jsonUpdate(name, ~everything, ~major=request.major)
      : await update(name, ~dry, ~major=request.major, ~everything)
  | "publish" => publish(name, request.passed)
  | _ => Registry.fail(usage)
  }
}

let main = async argv => {
  let request = parse(argv)
  let remind = request.verb == "pull" || request.verb == "verify"
  if remind {
    Reminder.start()
  }
  try {
    let code = await execute(argv)
    if request.verb == "pull" {
      reminded()
    }
    code
  } catch {
  | error =>
    if remind {
      reminded()
    }
    throw(error)
  }
}

if Node.isMain {
  main(Node.args())
  ->Promise.thenResolve(code => Node.exit(code))
  ->Promise.catch(error => {
    switch error {
    | Registry.Refused(why) => Console.error(`error: ${why}`)
    | JsExn(error) => Console.error(`error: ${error->JsExn.message->Option.getOr("")}`)
    | _ => Console.error("error: repos failed")
    }
    Node.exit(1)
  })
  ->ignore
}
