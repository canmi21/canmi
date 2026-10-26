/**
 * The workspace's own verify, `check workspace [part ...] [--pending]`.
 * Each rule in model/rules/ is held by a part, a hook, a gate or nothing yet.
 */
let root = Registry.root
let python = "/usr/bin/python3"

/**
 * A Soft part warns, failing only under AUDIT; a Waivable part's findings name their rule, waived
 * by a deferred item. A Waivable or Formed part fails the form layer under AUDIT or at a push.
 */
type part =
  | Script(unit => int)
  | Found(unit => array<string>)
  | Soft(unit => array<string>)
  | Waivable(string, unit => array<Form_layer.finding>)
  | Formed(bool => int)

let report = found => {
  found->Array.forEach(line => Console.log(`  x ${line}`))
  if found->Array.length == 0 {
    Console.log("  no violation")
  }
  found->Array.length > 0 ? 1 : 0
}

/** Each warning logged, failing only under AUDIT. */
let warn = warned => {
  warned->Array.forEach(line => Console.log(`  warning: ${line}`))
  if warned == [] {
    Console.log("  no warning")
  }
  warned != [] && Node.envIs("AUDIT", "1") ? 1 : 0
}

/** What a part breaks reported, then what it warns of. */
let reported = ((failed, warned)) => report(failed) + warn(warned) > 0 ? 1 : 0

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
  ("lines", Formed(pushing => Lines.main(~pushing))),
  ("refs", Script(() => Refs.main())),
  (
    "comments",
    Formed(
      pushing => {
        let measured = Comments.main(~root, ~given=[], ~pushing)
        report(Notes.main(~root)) + measured > 0 ? 1 : 0
      },
    ),
  ),
  ("commits", Found(() => Array.concat(commits(root), recorded()))),
  ("names", Found(() => Filenames.main(~root))),
  ("words", Found(() => Words.main(~root))),
  ("pins", Found(() => Pins.main(~root))),
  ("workflows", Found(() => Workflows.main(~root))),
  ("settings", Found(() => Settings.main(~root))),
  ("suffixes", Found(() => Suffix_owned.main(~root, ~label="workspace"))),
  ("shape", Waivable("workspace", () => Shape.tagged(~root))),
  ("deferred", Found(Waiting.problems)),
  ("rfcs", Found(() => Rfc_check.repository(Planning.workspaceSpace))),
  ("tasks", Script(() => reported(Tasks.found(~root)))),
  ("placed", Found(() => Placed.found(~root))),
  ("plain", Soft(() => Comments.plain(~root))),
  ("drift", Soft(() => Drift.main(~only=None))),
]

let known = parts->Array.map(((name, _)) => name)

let written = path =>
  ["", ".res", ".py"]->Array.some(suffix => Node.existsSync(Node.join([root, path ++ suffix])))

/** Why a rule's holder does not exist, or none where it does. */
let unheldRule = (rule: Rule.t) =>
  switch rule.held {
  | Check(part) if part != "rules" && !(known->Array.includes(part)) =>
    Some(`${rule.name} is held by a part ${part}, which this check does not have`)
  | Gate(name) if Rule.gates->Array.includes(name) => None
  | Hook(path) if !written(path) => Some(`${rule.name} is held by ${path}, which is no file`)
  | Gate(path) if !written(path) =>
    Some(`${rule.name} is held by ${path}, which is no file and no gate in Rule.gates`)
  | _ => None
  }

/** Each rule held by a part, a hook or a gate that does not exist. */
let unheld = (): array<string> => Rules.all->Array.filterMap(unheldRule)

let pending = () =>
  Rules.all->Array.filterMap(rule =>
    switch rule.held {
    | Pending(owed) => Some(`${rule.name} (${rule.doc}): ${rule.says}; owed: ${owed}`)
    | _ => None
    }
  )

let outcome = (part, ~pushing=false) =>
  switch part {
  | Script(run) => run()
  | Formed(run) => run(pushing)
  | Found(found) => report(found())
  | Soft(found) => warn(found())
  | Waivable(repo, found) =>
    let kept = found()->Array.filter(({rule, says}) =>
      switch Waiting.waiver(~repo, ~rule) {
      | Some(id) =>
        Console.log(`  waived by deferred ${id}: ${says}`)
        false
      | None => true
      }
    )
    let (formed, logical) = kept->Array.partition(({rule}) => Form_layer.holds(rule))
    let failing = Form_layer.fails(~pushing)
    if !failing {
      formed->Array.forEach(finding => Console.log(`  warning: ${Form_layer.shown(finding)}`))
    }
    report(Array.concat(logical, failing ? formed : [])->Array.map(Form_layer.shown))
  }

/** What the workspace holds over every repository below it, each part by its name. */
let over = (repo): array<(string, part)> =>
  Array.concat(
    [
      ("shape", Waivable(Registry.label(repo), () => Shape.tagged(~root=repo))),
      ("tasks", Script(() => reported(Tasks.found(~root=repo)))),
      ("placed", Found(() => Placed.found(~root=repo))),
      ("names", Found(() => Array.concat(Filenames.names(~root=repo), Own_name.main(~root=repo)))),
      ("commits", Found(() => commits(repo))),
      ("comments", Formed(pushing => Comments.main(~root=repo, ~given=[], ~pushing))),
      ("workflows", Found(() => Workflows.main(~root=repo))),
      ("suffixes", Found(() => Suffix_owned.main(~root=repo, ~label=Registry.label(repo)))),
      ("plain", Soft(() => Comments.plain(~root=repo))),
      ("drift", Soft(() => Drift.main(~only=Some(Registry.label(repo))))),
    ],
    switch Rfc_spaces.spaceOf(Registry.label(repo)) {
    | Some(_) => [("rfcs", Found(() => Rfc_check.repository(Registry.label(repo))))]
    | None => []
    },
  )

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

/** Whether `repo` keeps the lines rule, as the lines part reads it with no root given. */
let keepsLines = repo =>
  repo == root ||
    switch Project.read(repo) {
    | Ok(declared) => declared.rules.lines
    | Error(_) => true
    }

/** The form layer's parts over a tree of `repo`, only their form findings, for a push. */
let formed = (repo, tree: Lines.tree): array<(string, part)> =>
  [
    (
      "shape",
      Waivable(
        Registry.label(repo),
        () => Shape.measured(tree)->Array.filter(({rule}) => Form_layer.holds(rule)),
      ),
    ),
    ("lines", Formed(pushing => keepsLines(repo) ? Lines.judged([tree], ~pushing) : 0)),
    ("comments", Formed(pushing => Comments.measured(tree, ~pushing))),
  ]->Array.filter(((name, _)) => Form_layer.parts->Array.includes(name))

/** The commits `bookmarks` point to in `repo`, each once. */
let pointed = (repo, bookmarks: array<string>) =>
  bookmarks->Array.reduce([], (found, bookmark) =>
    Onset.read(
      ~root=repo,
      [
        "--ignore-working-copy",
        "log",
        "--no-graph",
        "-r",
        `bookmarks(exact:${Onset.quoted(bookmark)})`,
        "-T",
        `commit_id ++ "\\n"`,
      ],
    )
    ->Option.mapOr([], Onset.lines)
    ->Array.reduce(found, (found, commit) =>
      found->Array.includes(commit) ? found : [...found, commit]
    )
  )

/**
 * The form layer over the tree of each commit `bookmarks` point to, read from the repository and
 * never the disk, its warnings failing and each part logged past a failure.
 */
let gate = (repo, ~bookmarks): int => {
  let failed = pointed(repo, bookmarks)->Array.flatMap(commit => {
    let tree = Lines.committed(repo, commit)
    let short = commit->String.slice(~start=0, ~end=12)
    formed(repo, tree)->Array.filter(((name, part)) => {
      Console.log(
        `\n=== ${Registry.label(repo)} ${name} at ${short}, the form layer before a push ===`,
      )
      outcome(part, ~pushing=true) != 0
    })
  })
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
