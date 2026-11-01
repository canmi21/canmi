/** Refuses a jj commit onto a repository's main checkout while the form layer finds something. */
/** Whether `repo` is a main checkout, whose `.jj/repo` is a directory and not a lane's pointer. */
let mainCheckout = repo =>
  Node.stat(Node.join([repo, ".jj", "repo"]))->Option.mapOr(false, Node.statsIsDirectory)

/** The repositories the workspace owns, the workspace itself and each one below `repos/`. */
let ours = repo => repo == Registry.root || repo->String.startsWith(Registry.repos ++ "/")

/** The words of a commit that name files, past the flags and the values they take. */
let valued = ["-m", "--message", "--author", "-T", "--template", "--config", "--config-file"]
let filesets = (arguments: array<string>) => {
  let kept = []
  let at = ref(0)
  while at.contents < arguments->Array.length {
    let word = arguments->Array.getUnsafe(at.contents)
    if valued->Array.includes(word) {
      at := at.contents + 2
    } else {
      word->String.startsWith("-") ? () : kept->Array.push(word)
      at := at.contents + 1
    }
  }
  kept
}

/** The lines of the child's log that state a finding. */
let findings = (log: string) =>
  log
  ->String.split("\n")
  ->Array.filter(line =>
    line->String.startsWith("error:") ||
    line->String.startsWith("  x ") ||
    line->String.startsWith("refused:")
  )

/** The program that judges the tree, built beside the hooks. */
let program = Node.join([Registry.root, "model", "checks", "form", "commit_tree.res.mjs"])

/** The exit status the harness reads, 2 refusing the command with the reason on stderr. */
let handle = (payload: Payload.t, ~owned=ours): int => {
  let command = Payload.command(payload)
  let places = Jj_command.placed(command, ~cwd=Payload.cwd(payload), Commits.committing)
  if places == [] || Jj_command.skipped(command)->Array.includes("form") {
    0
  } else {
    let arguments =
      Jj_command.invocations(command)
      ->Array.filter(((subcommand, _)) => Commits.committing->Array.includes(subcommand))
      ->Array.map(((_, rest)) => filesets(rest))
    let refused = places->Array.filterMapWithIndex((place, index) => {
      let repo = Payload.jj(~cwd=place, ["workspace", "root"])->String.trim
      let paused =
        repo->String.startsWith(Registry.repos ++ "/") &&
          Waiting.skipped(Registry.label(repo))->Option.isSome
      if repo == "" || !owned(repo) || !mainCheckout(repo) || paused {
        None
      } else {
        let answer = Node.spawnSync(
          "node",
          [program, repo, place, ...arguments[index]->Option.getOr([])],
          {encoding: "utf8", maxBuffer: 268435456, timeout: 90000},
        )
        answer.status->Nullable.toOption == Some(1)
          ? Some((repo, findings(answer.stdout->Nullable.getOr(""))))
          : None
      }
    })
    switch refused[0] {
    | None => 0
    | Some((repo, found)) =>
      Console.error(
        `Commit refused by hooks/gates/form.res: the form layer finds this in ${Registry.label(
            repo,
          )}, which a commit onto its main line may not carry.\n`,
      )
      found->Array.forEach(line => Console.error(`  ${line->String.trim}`))
      Console.error(
        `\nTake the change back to its lane and fix it there, then land it again. ` ++ `To commit anyway, name the gate: \`SKIP=form jj commit ...\`. See docs/agents/checking.md.`,
      )
      2
    }
  }
}
