/**
 * A thread's private files in one place and one shape, `thread new <name>`, docs/agents/threads.md.
 * What is the record, its charter's decision among it, stays in the thread's RFC.
 */
let root = Figures.root

/** Each file a thread keeps, and what it starts with. */
let shape = [
  (
    "charter.md",
    "# Charter\n\nRFC: the thread's RFC id.\nGoal: what is true when this thread ends.\nTarget test: the command that decides it and where it runs, in steps, each green or not; the author's and the advisor's, changed by no one below them.\nBounds: what is out of scope, and what only the author may change.\nValues to fix: each policy value, a default or the author's.\n",
  ),
  (
    "decisions.md",
    "# Decision queue\n\nOne block each, the oldest open first; an answered one stays, marked.\n\n## <short name>\nStep: the step of the current path it stands on.\nAsk: the question, in plain words.\nDefault: what happens if nobody answers.\nUndone by: how it can be undone, or `irreversible`, which blocks its branch alone.\nFound in: the RFC, plan or ledger line already read, or `none`.\nAnswer: open.\n",
  ),
  (
    "buffer.md",
    "# Buffer\n\nThe advisor's. One block each, the most urgent first, brought to the author one at a time.\n\n## <short name>\nPriority: why it comes before the next.\nDecision: a pointer into decisions.md, or the question itself.\nBrought: not yet.\n",
  ),
  (
    "ledger.md",
    "# Ledger\n\nOne line each: time in UTC, layer, what was chosen, why it may be undone.\n",
  ),
  (
    "status.md",
    "# Status\n\nAs of: time in UTC.\nStep: where the thread stands on its path.\nTarget test: its last result, and when.\nRunning: `mise run //:job list`'s ids that matter.\nWaiting on: who, for what.\n",
  ),
]

let valid = name => /^[a-z][a-z0-9-]*$/->RegExp.test(name)

let start = (name, ~dry) =>
  if !valid(name) {
    Console.error(`${name} is no thread name, which is lowercase words joined by hyphens`)
    2
  } else {
    let directory = Node.join([root(), name])
    if Node.existsSync(directory) {
      Console.error(`${directory} exists already`)
      1
    } else if dry {
      shape->Array.forEach(((file, _)) =>
        Console.log(`would write ${Node.join([directory, file])}`)
      )
      0
    } else {
      Node.mkdirAll(directory)
      shape->Array.forEach(((file, text)) => Node.writeFileSync(Node.join([directory, file]), text))
      Console.log(directory)
      0
    }
  }

let list = () => {
  if Node.existsSync(root()) {
    Node.readdir(root())->Array.forEach(name => Console.log(Node.join([root(), name])))
  }
  0
}

/** The charter and the commit list alone, what an auditor is given, docs/agents/auditor.md. */
let audit = name => {
  let charter = Node.join([Figures.directory(name), "charter.md"])
  if !Node.existsSync(charter) {
    Console.error(`${name} has no charter`)
    2
  } else {
    Console.log(Node.readFileSync(charter))
    Console.log("# Commits\n")
    Figures.records(name)->Array.forEach(one =>
      switch one {
      | Landed({repository, commit, subject}) => Console.log(`${repository} ${commit} ${subject}`)
      | _ => ()
      }
    )
    Console.log(
      "\nWhat is this team doing, and which of it does not serve the goal? Ask questions, decide nothing.",
    )
    0
  }
}

let at = () => JSON.Number(Date.now())

let main = (argv: array<string>) =>
  switch argv {
  | ["green", name, step] =>
    Figures.add(name, [("kind", JSON.String("green")), ("step", JSON.String(step)), ("at", at())])
    0
  | ["seat", name, seat] | ["seat", name, seat, "--tooling"] =>
    Figures.add(
      name,
      [
        ("kind", JSON.String("seat")),
        ("name", JSON.String(seat)),
        ("tooling", JSON.Boolean(argv->Array.includes("--tooling"))),
        ("at", at()),
      ],
    )
    0
  | ["seated", name, seat] =>
    Figures.add(name, [("kind", JSON.String("seated")), ("name", JSON.String(seat)), ("at", at())])
    0
  | ["landed", name, repository, commit, subject] =>
    Figures.add(
      name,
      [
        ("kind", JSON.String("landed")),
        ("repository", JSON.String(repository)),
        ("commit", JSON.String(commit)),
        ("subject", JSON.String(subject)),
        ("at", at()),
      ],
    )
    0
  | ["audit", name] => audit(name)
  | ["new", name] => start(name, ~dry=false)
  | ["new", name, "--dry-run" | "-n"] => start(name, ~dry=true)
  | ["where", name] =>
    Console.log(Node.join([root(), name]))
    0
  | ["list"] => list()
  | _ =>
    Console.error(
      "usage: mise run //:thread new <name> [--dry-run] | where <name> | list | audit <name>\n       mise run //:thread green <name> <step> | seat <name> <seat> [--tooling] | seated <name> <seat> | landed <name> <repository> <commit> <subject>",
    )
    2
  }

if Node.isMain {
  Node.exit(main(Node.args()))
}
