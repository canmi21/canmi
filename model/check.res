/**
 * The workspace's own verify, `check workspace [part ...] [--pending]`.
 * Each rule in model/rules/ is held by a part, a hook, a gate or nothing yet.
 */
let root = Registry.root
let python = "/usr/bin/python3"

/**
 * A Soft part's findings are warnings, failing only under AUDIT, as soft rules are read; a Waivable
 * part's each name the rule broken, passed over in the repository a deferred item waives it for.
 */
type part =
  | Script(unit => int)
  | Found(unit => array<string>)
  | Soft(unit => array<string>)
  | Waivable(string, unit => array<(string, string)>)

let report = found => {
  found->Array.forEach(line => Console.log(`  x ${line}`))
  if found->Array.length == 0 {
    Console.log("  no violation")
  }
  found->Array.length > 0 ? 1 : 0
}

/** A repository's history after its `since`, or that it has none. */
let commits = repo => {
  let name = Registry.label(repo)
  switch History.since(name) {
  | Some(after) => History.main(~root=repo, ~after)
  | None => [`${name} has no since in model/rules/commits.res, so its history is not read`]
  }
}

/** Every repository the registry lists with its `since`. */
let recorded = () =>
  Registry.paths()->Array.filterMap(path =>
    History.since(path)->Option.isSome
      ? None
      : Some(`${path} has no since in model/rules/commits.res`)
  )

let parts: array<(string, part)> = [
  ("tools", Script(() => Tools.check(~everything=true))),
  ("repos", Script(Registry.check)),
  (
    "declared",
    Found(
      () =>
        Registry.paths()
        ->Array.map(path => Node.join([Registry.repos, path]))
        ->Array.filter(path => Node.existsSync(Node.join([path, "workspace.toml"])))
        ->Array.filterMap(path =>
          switch Project.read(path) {
          | Ok({base: Some(address)}) if Some(address) != Registry.origin() =>
            Some(`${path}/workspace.toml: base ${address} is not this workspace's origin`)
          | Ok(_) => None
          | Error(why) => Some(why)
          }
        ),
    ),
  ),
  // The rm guard's tests, under macOS's own Python, which is what runs the guard.
  (
    "hooks",
    Script(
      () =>
        Node.run(
          ~cwd=root,
          python,
          ["-m", "unittest", "discover", "-s", "hooks", "-p", "test_*.py"],
        ),
    ),
  ),
  (
    "scripts",
    Script(
      () =>
        Node.run(~cwd=root, "pnpm", ["exec", "tsc", "-p", "tsconfig.json"]) == 0
          ? Node.run(~cwd=root, "pnpm", ["exec", "vitest", "run"])
          : 1,
    ),
  ),
  ("lines", Script(() => Lines.main())),
  ("refs", Script(() => Refs.main())),
  (
    "comments",
    Script(
      () => {
        let measured = Comments.main(~root, ~given=[])
        report(Notes.main(~root)) + measured > 0 ? 1 : 0
      },
    ),
  ),
  ("commits", Found(() => Array.concat(commits(root), recorded()))),
  ("names", Found(() => Filenames.main(~root))),
  ("words", Found(() => Words.main(~root))),
  ("pins", Found(() => Pins.main(~root))),
  ("settings", Found(() => Settings.main(~root))),
  ("shape", Waivable("workspace", () => Shape.tagged(~root))),
  ("deferred", Found(Waiting.problems)),
  ("tasks", Found(() => Tasks.main(~root))),
  ("plain", Soft(() => Comments.plain(~root))),
  ("drift", Soft(() => Drift.main(~only=None))),
]

let known = parts->Array.map(((name, _)) => name)

/** Each rule held by a part, a hook or a gate that does not exist. */
let unheld = (): array<string> =>
  Rules.all->Array.filterMap(rule =>
    switch rule.held {
    | Check(part) if !(known->Array.includes(part)) =>
      Some(`${rule.name} is held by a part ${part}, which this check does not have`)
    | Hook(path) | Gate(path)
      if !(
        ["", ".res", ".py"]->Array.some(suffix =>
          Node.existsSync(Node.join([root, path ++ suffix]))
        )
      ) =>
      Some(`${rule.name} is held by ${path}, which does not exist`)
    | _ => None
    }
  )

let pending = () =>
  Rules.all->Array.filterMap(rule =>
    switch rule.held {
    | Pending(owed) => Some(`${rule.name} (${rule.doc}): ${rule.says}; owed: ${owed}`)
    | _ => None
    }
  )

let outcome = part =>
  switch part {
  | Script(run) => run()
  | Found(found) => report(found())
  | Soft(found) =>
    let warned = found()
    warned->Array.forEach(line => Console.log(`  warning: ${line}`))
    if warned == [] {
      Console.log("  no warning")
    }
    warned != [] && Node.envIs("AUDIT", "1") ? 1 : 0
  | Waivable(repo, found) =>
    let kept = found()->Array.filter(((rule, says)) =>
      switch Waiting.waiver(~repo, ~rule) {
      | Some(id) =>
        Console.log(`  waived by deferred ${id}: ${says}`)
        false
      | None => true
      }
    )
    report(kept->Array.map(((_, says)) => says))
  }

/** What the workspace holds over every repository below it, each part by its name. */
let over = (repo): array<(string, part)> => [
  ("shape", Waivable(Registry.label(repo), () => Shape.tagged(~root=repo))),
  ("tasks", Found(() => Tasks.main(~root=repo))),
  ("names", Found(() => Filenames.names(~root=repo))),
  ("commits", Found(() => commits(repo))),
  ("comments", Script(() => Comments.main(~root=repo, ~given=[]))),
  ("plain", Soft(() => Comments.plain(~root=repo))),
  ("drift", Soft(() => Drift.main(~only=Some(Registry.label(repo))))),
]

/** The workspace's rules over one repository below it, each part logged, on past a failure. */
let repository = (repo): int => {
  let failed = over(repo)->Array.filter(((name, part)) => {
    Console.log(`\n=== ${Registry.label(repo)} ${name}, the workspace's ===`)
    outcome(part) != 0
  })
  let waiting = Waiting.shown(~repo=Some(Registry.label(repo)))
  if waiting != [] {
    Console.log("")
    waiting->Array.forEach(line => Console.log(line))
  }
  failed->Array.length > 0 ? 1 : 0
}

/** Each part named, or every one, its own log under its name, and on past a failure. */
let run = (named: array<string>): int => {
  named->Array.forEach(name =>
    if name != "rules" && !(known->Array.includes(name)) {
      Registry.fail(
        `the workspace's check has no part ${name}; the parts are rules, ${known->Array.join(
            ", ",
          )}`,
      )
    }
  )
  let chosen = name => named->Array.length == 0 || named->Array.includes(name)
  let failed = Array.concat(
    chosen("rules")
      ? {
          Console.log("\n=== workspace rules ===")
          report(unheld()) == 0 ? [] : ["rules"]
        }
      : [],
    parts
    ->Array.filter(((name, _)) => chosen(name))
    ->Array.filterMap(((name, part)) => {
      Console.log(`\n=== workspace ${name} ===`)
      outcome(part) == 0 ? None : Some(name)
    }),
  )
  let owed = pending()->Array.length
  Console.log(
    `\n${Int.toString(Rules.all->Array.length)} rules, ${Int.toString(
        owed,
      )} pending a check: check workspace --pending`,
  )
  Waiting.shown(~repo=None)->Array.forEach(line => Console.log(line))
  if failed->Array.length > 0 {
    Console.log(`failed: ${failed->Array.join(", ")}`)
  }
  failed->Array.length > 0 ? 1 : 0
}

if Node.isMain {
  let given = Node.args()
  if given->Array.includes("--pending") {
    pending()->Array.forEach(line => Console.log(line))
    Node.exit(0)
  }
  Node.exit(
    try run(given) catch {
    | Registry.Refused(why) =>
      Console.error(why)
      2
    },
  )
}
