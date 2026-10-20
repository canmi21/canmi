/**
 * The workspace's own verify, `check workspace [part ...] [--pending]`: every part, or those named.
 * A part either runs a script that prints its own report or answers with violations, one per line.
 * Every rule in model/rules/ is held by a part, a hook, a gate or nothing yet; the rules part holds
 * each to one that exists, and `--pending` lists the rules no check holds.
 */
let root = Registry.root
let python = "/usr/bin/python3"

type part = Script(unit => int) | Found(unit => array<string>)

let report = found => {
  found->Array.forEach(line => Console.log(`  x ${line}`))
  if found->Array.length == 0 {
    Console.log("  no violation")
  }
  found->Array.length > 0 ? 1 : 0
}

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
  ("commits", Found(() => History.main(~root))),
  ("names", Found(() => Filenames.main(~root))),
  ("words", Found(() => Words.main(~root))),
  ("pins", Found(() => Pins.main(~root))),
  ("settings", Found(() => Settings.main(~root))),
]

let known = parts->Array.map(((name, _)) => name)

/** Every rule held by something that exists: a part of this check, or a hook's or a gate's file. */
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
