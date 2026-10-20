/**
 * Every verb across the repositories, `repos <verb> [name | --all] [--dry-run]`: bare, the
 * workspace alone; a path from repos/registry.toml, that repository; `--all`, every one. pull, push
 * and clone are jj's and the same everywhere; fmt, clean, update and verify run a repository's own
 * task, and the workspace's own half here. See docs/repos.md, "One verb, the workspace unless told
 * otherwise".
 */
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

/** Push main wherever origin is behind it; an origin with no main yet is behind by all of it. */
let push = (name, ~dry, ~everything) => {
  Registry.selected(name, ~everything)
  ->Array.filter(Registry.isRepository)
  ->Array.forEach(repo => {
    let place = Registry.label(repo)
    let result = capture(
      ~cwd=repo,
      "jj",
      [
        "log",
        "--no-graph",
        "-r",
        `remote_bookmarks(exact:"main", exact:"origin")..main ~ root()`,
        "-T",
        `commit_id.short() ++ "\\n"`,
      ],
    )
    if result.status != 0 {
      Console.log(`${place}: cannot tell what to push`)
      Console.error(result.err)
    } else {
      switch result.out->lines {
      | [] => Console.log(`${place}: nothing to push`)
      | ahead =>
        Console.log(
          `${place}: ${dry ? "would push" : "pushing"} ${Int.toString(
              ahead->Array.length,
            )} commit(s)`,
        )
        let flags = dry ? ["--dry-run"] : []
        if Node.run(~cwd=repo, "jj", ["git", "push", "--bookmark", "main", ...flags]) != 0 {
          Registry.fail(`jj git push failed in ${place}`)
        }
      }
    }
  })
  0
}

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

/** The workspace's own fmt: oxfmt and ReScript's formatter over the files jj.toml gives them. */
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

/** The workspace's own clean: the bytecode Python leaves beside the hooks it still runs. */
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
  if found == [] {
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

/** The workspace's own update: [tools] within their pins, package.json within its ranges. */
let refresh = async (~dry, ~major) => {
  let tools = await Tools.up(~name="workspace", ~dry)
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

let summary = (verb, skipped, failed) =>
  if skipped != [] || failed != [] {
    Console.log("\n" ++ String.repeat("-", 72))
    if skipped != [] {
      Console.log(
        `warning: no ${verb} task of their own, so passed over: ${skipped->Array.join(", ")}`,
      )
    }
    if failed != [] {
      Console.log(`failed: ${failed->Array.join(", ")}`)
    }
  }

/** fmt, clean or verify: the workspace's half here, each repository's own task, past a failure. */
let dispatch = (verb, name, ~dry, ~everything, ~parts) => {
  let skipped = []
  let failed = []
  Registry.selected(name, ~everything)->Array.forEach(repo => {
    let place = Registry.label(repo)
    let code = if repo == root {
      Console.log(`\n=== workspace ${verb}${dry ? " --dry-run" : ""} ===`)
      switch verb {
      | "fmt" => fmt(~dry)
      | "clean" => clean(~dry)
      | _ if dry =>
        Console.log("would run check workspace")
        0
      | _ => Check.run(parts)
      }
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
    if code != 0 {
      failed->Array.push(place)
    }
  })
  summary(verb, skipped, failed)
  failed == [] ? 0 : 1
}

/** The lines of a failed verify worth repeating under the summary, which a long log buries. */
let marked = /\berror\b|panicked|FAILED/
let symptom = output => {
  let all = output->String.split("\n")
  let flagged = all->Array.filter(line => marked->RegExp.test(line))
  (flagged == [] ? all : flagged)->Array.slice(~start=0, ~end=10)
}

/** The working copy as a commit, as of now; jj snapshots on every command, so asking is enough. */
let snapshot = repo =>
  jj(~cwd=repo, ["log", "-r", "@", "--no-graph", "-T", "commit_id"])->String.trim

/** Exactly these paths put back as they were in `before`, by path so others' edits survive. */
let restore = (repo, before, paths) => {
  let literal = path =>
    `root-file:"${path->String.replaceAll("\\", "\\\\")->String.replaceAll("\"", "\\\"")}"`
  jj(~cwd=repo, ["restore", "--from", before, ...paths->Array.map(literal)])->ignore
}

/** Each repository's own update, kept only where its verify still passes. See docs/toolchain.md. */
let update = async (name, ~dry, ~major, ~everything) => {
  let skipped = []
  let failed = []
  let reverted = []
  let flags = Array.concat(dry ? ["--dry-run"] : [], major ? ["--major"] : [])
  let chosen = Registry.selected(name, ~everything)
  for index in 0 to chosen->Array.length - 1 {
    let repo = chosen->Array.getUnsafe(index)
    let place = Registry.label(repo)
    let own = repo == root
    if !own && !declares(repo, "update") {
      skipped->Array.push(place)
    } else {
      let shown = own ? "workspace update" : task(repo, "update")
      Console.log(`\n=== ${[shown, ...flags]->Array.join(" ")} ===`)
      let move = async () =>
        own
          ? await refresh(~dry, ~major)
          : Node.run(~cwd=root, "mise", ["run", task(repo, "update"), ...flags])
      if dry {
        if (await move()) != 0 {
          failed->Array.push(place)
        }
      } else {
        let before = snapshot(repo)
        let code = await move()
        let after = snapshot(repo)
        let paths = jj(~cwd=repo, ["diff", "--from", before, "--to", after, "--name-only"])->lines
        if code != 0 {
          if paths != [] {
            restore(repo, before, paths)
          }
          failed->Array.push(place)
        } else if paths != [] {
          if !own && !declares(repo, "verify") {
            Console.log(`\n${place} has no verify, so what moved is kept unchecked`)
          } else {
            let (command, commandArgs) = own
              ? ("node", [Node.join([root, "model", "check.res.mjs"])])
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
  summary("update", skipped, failed)
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
  everything: bool,
  parts: array<string>,
  passed: array<string>,
}

let usage = "usage: repos list | clone | pull | push | fmt | update | clean | verify | publish  [name | --all] [--dry-run]"
let across = ["update", "fmt", "clean", "verify", "pull", "push"]

/** What was typed, or why it is refused: a name means that repository, and nothing is dropped. */
let parse = (argv: array<string>): request => {
  let flag = names => argv->Array.some(arg => names->Array.includes(arg))
  let known = ["-n", "--dry-run", "--major", "-a", "--all", "--pending"]
  let rest = argv->Array.filter(arg => !(arg->String.startsWith("-")))
  let verb = rest[0]->Option.getOr("")
  let name = rest[1]
  let request = {
    verb,
    name,
    dry: flag(["-n", "--dry-run"]),
    major: flag(["--major"]),
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
    switch argv->Array.find(arg => arg->String.startsWith("-") && !(known->Array.includes(arg))) {
    | Some(unknown) => Registry.fail(`unknown option ${unknown}`)
    | None => ()
    }
    if flag(["--pending"]) && !owned {
      Registry.fail("--pending belongs to the workspace's own check: check workspace --pending")
    }
    let extra = rest->Array.slice(~start=2)
    if extra != [] && !owned {
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

let main = async argv => {
  let request = parse(argv)
  let {name, dry, everything} = request
  switch request.verb {
  | "list" => list()
  | "clone" => clone(name, ~dry)
  | "pull" => pull(name, ~dry, ~everything)
  | "push" => push(name, ~dry, ~everything)
  | "fmt" | "clean" => dispatch(request.verb, name, ~dry, ~everything, ~parts=[])
  | "verify" if request.parts->Array.includes("--pending") =>
    Check.pending()->Array.forEach(line => Console.log(line))
    0
  | "verify" => dispatch("verify", name, ~dry, ~everything, ~parts=request.parts)
  | "update" => await update(name, ~dry, ~major=request.major, ~everything)
  | "publish" => publish(name, request.passed)
  | _ => Registry.fail(usage)
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
