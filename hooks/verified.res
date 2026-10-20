/** Before a jj command making a commit: refuse it until verify passed at this working copy. */
let label = repo =>
  repo == Registry.root
    ? "mise run check"
    : repo->String.startsWith(Registry.repos ++ "/")
    ? `mise run check ${Registry.label(repo)}`
    : "the repository's verify"

/** The exit status the harness reads: 2 refuses the command, with the reason on stderr. */
let handle = (payload: Payload.t): int => {
  let command = Payload.command(payload)
  let committing =
    Jj_command.invocations(command)->Array.some(((subcommand, _)) =>
      Commits.committing->Array.includes(subcommand)
    )
  if !committing || Jj_command.skipped(command)->Array.includes("verify") {
    0
  } else {
    let cwd = Payload.cwd(payload)
    let at = Jj_command.repository(command)->Option.mapOr(cwd, named => Node.resolve([cwd, named]))
    let repo = Payload.jj(~cwd=at, ["workspace", "root"])->String.trim
    if repo == "" || Stamp.holds(repo) {
      0
    } else {
      Console.error(
        `Commit refused by hooks/verified.res: ${repo} has not passed verify at this working ` ++
        `copy.\n\nRun \`${label(
            repo,
          )}\` from the workspace, then commit again. To commit ` ++ `without it, name the gate: \`SKIP=verify jj commit ...\`. See docs/commits.md.`,
      )
      2
    }
  }
}
